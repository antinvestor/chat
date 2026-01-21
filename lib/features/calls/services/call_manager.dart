import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/logging/app_logger.dart';
import '../../../features/auth/data/auth_repository.dart';
import '../../messages/domain/room_event.dart';
import 'signaling_service.dart';
import 'turn_credentials_service.dart';

final callManagerProvider = FutureProvider<CallManager>((ref) async {
  final signalingService = await ref.watch(signalingServiceProvider.future);
  final authRepo = ref.watch(authRepositoryProvider);
  final turnService = await ref.watch(turnCredentialsServiceProvider.future);
  return CallManager(signalingService, authRepo, turnService);
});

enum CallState {
  idle,
  calling, // Outgoing call
  incoming, // Incoming call
  connected,
  ended,
}

class CallManager {
  CallManager(
    this._signalingService,
    this._authRepository,
    this._turnCredentialsService,
  ) {
    _signalingService.onSignal.listen(_handleSignal);
  }
  final SignalingService _signalingService;
  final AuthRepository _authRepository;
  final TurnCredentialsService _turnCredentialsService;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _currentRoomId;

  final _callStateController = StreamController<CallState>.broadcast();
  Stream<CallState> get callStateStream => _callStateController.stream;
  CallState _state = CallState.idle;
  CallState get state => _state;

  final _localStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get localStreamStream => _localStreamController.stream;

  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get remoteStreamStream => _remoteStreamController.stream;

  void _setState(CallState newState) {
    _state = newState;
    _callStateController.add(newState);
  }

  Future<void> startCall(String roomId) async {
    if (_state != CallState.idle) return;

    _currentRoomId = roomId;
    _setState(CallState.calling);

    try {
      await _initPeerConnection();
      final offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);

      await _signalingService.sendOffer(roomId, {
        'sdp': offer.sdp,
        'type': offer.type,
      });
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to start call',
        error: e,
        stackTrace: stackTrace,
        data: {'roomId': roomId},
      );
      endCall();
    }
  }

  Future<void> answerCall() async {
    if (_state != CallState.incoming ||
        _peerConnection == null ||
        _currentRoomId == null) {
      return;
    }

    try {
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      await _signalingService.sendAnswer(_currentRoomId!, {
        'sdp': answer.sdp,
        'type': answer.type,
      });

      _setState(CallState.connected);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to answer call',
        error: e,
        stackTrace: stackTrace,
        data: {'roomId': _currentRoomId},
      );
      endCall();
    }
  }

  Future<void> endCall() async {
    if (_currentRoomId != null) {
      await _signalingService.sendHangup(_currentRoomId!);
    }
    _close();
  }

  void _close() {
    _peerConnection?.close();
    _peerConnection = null;
    _localStream?.dispose();
    _localStream = null;
    _localStreamController.add(null);
    _remoteStream =
        null; // Remote stream is disposed by peer connection usually
    _remoteStreamController.add(null);
    _currentRoomId = null;
    _setState(CallState.idle);
  }

  Future<void> _initPeerConnection() async {
    // Request permissions
    await [Permission.camera, Permission.microphone].request();

    // Get ICE server configuration with TURN credentials
    final config = await _turnCredentialsService.getIceServers();

    AppLogger.info(
      'Initializing peer connection',
      data: {'iceServerCount': (config['iceServers'] as List).length},
    );

    _peerConnection = await createPeerConnection(config);

    // Get local stream
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': true,
    });
    _localStreamController.add(_localStream);

    _localStream!.getTracks().forEach((track) {
      _peerConnection!.addTrack(track, _localStream!);
    });

    // Handle remote stream
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        _remoteStreamController.add(_remoteStream);
      }
    };

    // Handle ICE candidates
    _peerConnection!.onIceCandidate = (candidate) {
      if (_currentRoomId != null) {
        _signalingService.sendCandidate(_currentRoomId!, {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setState(CallState.connected);
      } else if (state ==
              RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        endCall();
      }
    };
  }

  Future<void> _handleSignal(RoomEvent event) async {
    // Ignore own signals
    final currentProfileId = await _authRepository.getCurrentProfileId();
    if (currentProfileId != null && event.senderId == currentProfileId) return;

    switch (event.type) {
      case RoomEventType.callOffer:
        await _handleOffer(event);
        break;
      case RoomEventType.callAnswer:
        await _handleAnswer(event);
        break;
      case RoomEventType.callIce:
        await _handleCandidate(event);
        break;
      case RoomEventType.callEnd:
        _close();
        break;
      default:
        break;
    }
  }

  Future<void> _handleOffer(RoomEvent event) async {
    if (_state != CallState.idle) {
      // Busy
      // Implementation note: Send busy signal when receiving call offer while already in a call
      return;
    }

    _currentRoomId = event.roomId;
    _setState(CallState.incoming);

    await _initPeerConnection();

    final sdp = event.content['sdp'];
    final type = event.content['type'];
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, type),
    );
  }

  Future<void> _handleAnswer(RoomEvent event) async {
    if (_state != CallState.calling) return;

    final sdp = event.content['sdp'];
    final type = event.content['type'];
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, type),
    );
  }

  Future<void> _handleCandidate(RoomEvent event) async {
    if (_peerConnection == null) return;

    final candidate = RTCIceCandidate(
      event.content['candidate'],
      event.content['sdpMid'],
      event.content['sdpMLineIndex'],
    );
    await _peerConnection!.addCandidate(candidate);
  }
}
