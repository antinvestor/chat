import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../logging/app_logger.dart';
import '../../apis/chat/v1/chat.connect.client.dart';
import '../../apis/chat/v1/chat.pb.dart' as pb;
import '../../apis/google/protobuf/struct.pb.dart' as google_struct;
import '../../apis/google/protobuf/timestamp.pb.dart' as google_timestamp;
import 'package:fixnum/fixnum.dart' as fixnum;
import '../../features/messages/data/message_providers.dart';
import '../../features/messages/data/message_repository.dart';
import '../../features/messages/domain/room_event.dart';
import '../crypto/key_manager.dart';
import '../db/database.dart';
import '../networking/client.dart';

import 'pending_job.dart';
import 'pending_job_repository.dart';

final pendingJobRepositoryProvider = Provider<PendingJobRepository>((ref) {
  return PendingJobRepository(AppDatabase.instance);
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    ref.watch(gatewayServiceClientProvider),
    ref.watch(chatServiceClientProvider),
    ref.watch(messageRepositoryProvider),
    ref.watch(pendingJobRepositoryProvider),
    KeyManager(const FlutterSecureStorage()),
  );
});

enum SyncConnectionState { disconnected, connecting, connected }

final connectionStateProvider = StreamProvider<SyncConnectionState>((ref) {
  return ref.watch(syncEngineProvider).connectionState;
});

class SyncEngine {
  final GatewayServiceClient _gatewayClient;
  final ChatServiceClient _chatClient;
  final MessageRepository _messageRepo;
  final PendingJobRepository _jobRepo;
  final KeyManager _keyManager;

  StreamSubscription? _connectSubscription;
  Timer? _uploadTimer;
  bool _isUploading = false;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  final Set<String> _processedEventIds = {}; // For event deduplication

  final _typingEventsController = StreamController<pb.TypingEvent>.broadcast();
  Stream<pb.TypingEvent> get typingEvents => _typingEventsController.stream;

  final _signalingEventsController = StreamController<RoomEvent>.broadcast();
  Stream<RoomEvent> get signalingEvents => _signalingEventsController.stream;

  final _connectionStateController =
      StreamController<SyncConnectionState>.broadcast();
  Stream<SyncConnectionState> get connectionState =>
      _connectionStateController.stream;

  // Exponential backoff configuration
  static const _initialBackoffMs = 1000; // 1 second
  static const _maxBackoffMs = 30000; // 30 seconds
  static const _maxReconnectAttempts = 5;

  SyncEngine(
    this._gatewayClient,
    this._chatClient,
    this._messageRepo,
    this._jobRepo,
    this._keyManager,
  );

  void start() {
    _startDownloadLoop();
    _startUploadLoop();
  }

  void stop() {
    _connectSubscription?.cancel();
    _uploadTimer?.cancel();
    _connectSubscription?.cancel();
    _uploadTimer?.cancel();
    _typingEventsController.close();
    _signalingEventsController.close();
    _isConnected = false;
  }

  /// Fetch historical messages for a room
  /// Returns number of events fetched (0 if none available)
  Future<int> getHistory(
    String roomId, {
    String? cursor,
    int limit = 50,
  }) async {
    try {
      final request = pb.GetHistoryRequest(
        roomId: roomId,
        cursor: cursor,
        limit: limit,
        forward: false, // Get newer->older by default
      );

      final response = await _chatClient.getHistory(request);

      // Process each event in the response
      for (final connectResponse in response.events) {
        await _handleConnectResponse(connectResponse);
      }

      return response.events.length;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to get history',
        error: e,
        stackTrace: stackTrace,
        data: {'roomId': roomId, 'limit': limit},
      );
      return 0;
    }
  }

  Future<void> sendSignal(RoomEvent event) async {
    // Insert into DB first (optional for signals, but good for history)
    await _messageRepo.insertMessage(event);

    // Create pending job
    await _jobRepo.addJob(JobType.sendMessage, {
      'roomId': event.roomId,
      'type': event.type.toString(),
      'content': event.content,
      'localId': event.localId,
    });

    // Trigger immediate upload if connected
    if (_isConnected) {
      _startUploadLoop();
    }
  }

  Future<void> _startDownloadLoop() async {
    if (_isConnected) return;

    _connectionStateController.add(SyncConnectionState.connecting);

    while (true) {
      try {
        final deviceId = await _keyManager.getDeviceId();
        final request = pb.ConnectRequest(deviceId: deviceId);

        // Wrap request in a Stream as expected by the client
        final stream = _gatewayClient.connect(Stream.value(request));
        _isConnected = true;
        _reconnectAttempts = 0;
        _connectionStateController.add(SyncConnectionState.connected);

        await for (final response in stream) {
          await _handleConnectResponse(response);
        }
      } catch (e, stackTrace) {
        AppLogger.error(
          'Sync connection error',
          error: e,
          stackTrace: stackTrace,
          data: {'reconnectAttempts': _reconnectAttempts},
        );
      } finally {
        _isConnected = false;
        _connectionStateController.add(SyncConnectionState.disconnected);

        // Exponential backoff
        final delay = _getBackoffDelay();
        AppLogger.info(
          'Reconnecting to sync',
          data: {
            'delaySeconds': delay.inSeconds,
            'attempt': _reconnectAttempts + 1,
          },
        );
        await Future.delayed(delay);
        _reconnectAttempts++;
      }
    }
  }

  Duration _getBackoffDelay() {
    int delay = _initialBackoffMs * (1 << _reconnectAttempts);
    if (delay > _maxBackoffMs) {
      delay = _maxBackoffMs;
    }
    return Duration(milliseconds: delay);
  }

  Future<void> _handleConnectResponse(pb.ConnectResponse response) async {
    // Handle different event types
    if (response.hasMessage()) {
      await _processRoomEvent(response.message);
    } else if (response.hasTypingEvent()) {
      _typingEventsController.add(response.typingEvent);
    } else if (response.hasPresenceEvent()) {
      // TODO: Handle presence events
    } else if (response.hasReceiptEvent()) {
      await _processReceiptEvent(response.receiptEvent);
    } else if (response.hasReadEvent()) {
      // TODO: Handle read marker events
    }
  }

  Future<void> _processRoomEvent(pb.RoomEvent event) async {
    // Deduplicate events
    if (_processedEventIds.contains(event.id)) {
      return;
    }
    _processedEventIds.add(event.id);

    // Keep deduplication set bounded (last 1000 events)
    if (_processedEventIds.length > 1000) {
      final toRemove = _processedEventIds.take(100).toList();
      _processedEventIds.removeAll(toRemove);
    }

    // Decrypt if needed
    Map<String, dynamic> content = {};
    if (event.type == pb.RoomEventType.ROOM_EVENT_TYPE_ENCRYPTED) {
      // TODO: Decrypt using vodozemac
      // content = await _keyManager.decrypt(event.payload);
      content = {'text': '[Encrypted message]'};
    } else if (event.hasPayload()) {
      content = _structToMap(event.payload);
    }

    final roomEvent = RoomEvent(
      id: event.id,
      roomId: event.roomId,
      senderId: event.senderId,
      type: _mapProtoEventType(event.type),
      content: content,
      parentId: event.hasParentId() ? event.parentId : null,
      status: EventStatus.delivered,
      createdAt: event.hasSentAt()
          ? event.sentAt.seconds.toInt() * 1000 + event.sentAt.nanos ~/ 1000000
          : DateTime.now().millisecondsSinceEpoch,
      serverTs: event.hasSentAt()
          ? event.sentAt.seconds.toInt() * 1000 + event.sentAt.nanos ~/ 1000000
          : null,
    );

    await _messageRepo.insertMessage(roomEvent);

    // Emit signaling events for real-time handling
    if (_isCallEvent(roomEvent.type)) {
      _signalingEventsController.add(roomEvent);
    }
  }

  bool _isCallEvent(RoomEventType type) {
    return type == RoomEventType.callOffer ||
        type == RoomEventType.callAnswer ||
        type == RoomEventType.callIce ||
        type == RoomEventType.callEnd;
  }

  Future<void> _processReceiptEvent(pb.ReceiptEvent event) async {
    // Update status for received read receipts
    // Skip if it's from ourselves (already marked as read locally)
    // TODO: Get actual current user ID from auth
    if (event.profileId == 'current_user_id') return;

    // Mark messages as delivered (other user received them)
    await _messageRepo.updateMessagesStatus(
      event.eventId.toList(),
      EventStatus.delivered,
    );
  }

  void _startUploadLoop() {
    _uploadTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_isUploading || !_isConnected) return;
      _isUploading = true;

      try {
        final jobs = await _jobRepo.getPendingJobs();
        for (final job in jobs) {
          await _processJob(job);
        }
      } catch (e, stackTrace) {
        // Log but don't crash
        AppLogger.error('Upload loop error', error: e, stackTrace: stackTrace);
      } finally {
        _isUploading = false;
      }
    });
  }

  Future<void> _processJob(PendingJob job) async {
    // Skip jobs that have exceeded retry limit
    if (job.retryCount >= 5) {
      await _jobRepo.deleteJob(job.id);
      return;
    }

    try {
      switch (job.type) {
        case JobType.sendMessage:
          await _processSendMessage(job);
          break;
        case JobType.updateRoom:
          // TODO: Implement room update
          break;
        case JobType.vote:
          // TODO: Implement voting
          break;
      }
      await _jobRepo.deleteJob(job.id);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Job processing failed',
        error: e,
        stackTrace: stackTrace,
        data: {
          'jobId': job.id,
          'jobType': job.type.toString(),
          'retryCount': job.retryCount,
        },
      );
      await _jobRepo.incrementRetry(job.id);
    }
  }

  Future<void> _processSendMessage(PendingJob job) async {
    final payload = job.payload;

    // Convert content Map to Struct
    final contentStruct = _mapToStruct(
      payload['content'] as Map<String, dynamic>,
    );

    // Create timestamp
    final now = DateTime.now();
    final timestamp = google_timestamp.Timestamp(
      seconds: fixnum.Int64(now.millisecondsSinceEpoch ~/ 1000),
      nanos: (now.millisecondsSinceEpoch % 1000) * 1000000,
    );

    final event = pb.RoomEvent(
      id: payload['localId'] as String? ?? '',
      roomId: payload['roomId'] as String,
      senderId: 'current_user_id', // TODO: Get from auth service
      type: _mapLocalEventTypeToProto(
        RoomEventType.values.firstWhere(
          (t) => t.toString() == payload['type'],
          orElse: () => RoomEventType.text,
        ),
      ),
      payload: contentStruct,
      sentAt: timestamp,
    );

    final request = pb.SendEventRequest(event: [event]);
    final response = await _chatClient.sendEvent(request);

    // Update local message status to sent
    if (payload['localId'] != null && response.ack.isNotEmpty) {
      final ackEventId = response.ack.first.eventId;
      // Update the message with server ID
      final updatedEvent = RoomEvent(
        id: ackEventId,
        roomId: payload['roomId'] as String,
        senderId: 'current_user_id',
        type: RoomEventType.values.firstWhere(
          (t) => t.toString() == payload['type'],
          orElse: () => RoomEventType.text,
        ),
        content: payload['content'] as Map<String, dynamic>,
        status: EventStatus.sent,
        createdAt: now.millisecondsSinceEpoch,
        localId: payload['localId'] as String?,
      );
      await _messageRepo.insertMessage(updatedEvent);
    }
  }

  void _handleConnectionError(dynamic error) {
    AppLogger.error('Sync connection error', error: error);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      AppLogger.warning(
        'Max reconnect attempts reached, stopping reconnection',
        data: {'maxAttempts': _maxReconnectAttempts},
      );
      return;
    }

    // Calculate backoff delay with exponential increase
    final backoffMs = (_initialBackoffMs * (1 << _reconnectAttempts)).clamp(
      _initialBackoffMs,
      _maxBackoffMs,
    );

    _reconnectAttempts++;

    AppLogger.info(
      'Scheduling reconnect',
      data: {'backoffMs': backoffMs, 'attempt': _reconnectAttempts},
    );

    Future.delayed(Duration(milliseconds: backoffMs), () {
      if (!_isConnected) {
        _startDownloadLoop();
      }
    });
  }

  Future<String> _getAuthToken() async {
    const storage = FlutterSecureStorage();
    return await storage.read(key: 'access_token') ?? '';
  }

  // Helper methods for type conversion

  RoomEventType _mapProtoEventType(pb.RoomEventType type) {
    switch (type) {
      case pb.RoomEventType.ROOM_EVENT_TYPE_TEXT:
        return RoomEventType.text;
      case pb.RoomEventType.ROOM_EVENT_TYPE_ATTACHMENT:
        // Map ATTACHMENT to image for now, could detect type from content
        return RoomEventType.image;
      case pb.RoomEventType.ROOM_EVENT_TYPE_REACTION:
        return RoomEventType.reaction;
      case pb.RoomEventType.ROOM_EVENT_TYPE_CALL_OFFER:
        return RoomEventType.callOffer;
      case pb.RoomEventType.ROOM_EVENT_TYPE_CALL_ANSWER:
        return RoomEventType.callAnswer;
      case pb.RoomEventType.ROOM_EVENT_TYPE_CALL_ICE:
        return RoomEventType.callIce;
      case pb.RoomEventType.ROOM_EVENT_TYPE_CALL_END:
        return RoomEventType.callEnd;
      default:
        return RoomEventType.text;
    }
  }

  pb.RoomEventType _mapLocalEventTypeToProto(RoomEventType type) {
    switch (type) {
      case RoomEventType.text:
        return pb.RoomEventType.ROOM_EVENT_TYPE_TEXT;
      case RoomEventType.image:
      case RoomEventType.video:
      case RoomEventType.audio:
      case RoomEventType.file:
        // All media types map to ATTACHMENT
        return pb.RoomEventType.ROOM_EVENT_TYPE_ATTACHMENT;
      case RoomEventType.reaction:
        return pb.RoomEventType.ROOM_EVENT_TYPE_REACTION;
      case RoomEventType.callOffer:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_OFFER;
      case RoomEventType.callAnswer:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_ANSWER;
      case RoomEventType.callIce:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_ICE;
      case RoomEventType.callEnd:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_END;
      case RoomEventType.motion:
      case RoomEventType.vote:
      case RoomEventType.transaction:
        // These might not be in protobuf yet, map to TEXT for now
        return pb.RoomEventType.ROOM_EVENT_TYPE_TEXT;
    }
  }

  // Convert protobuf Struct to Dart Map
  Map<String, dynamic> _structToMap(google_struct.Struct struct) {
    final result = <String, dynamic>{};
    for (final entry in struct.fields.entries) {
      result[entry.key] = _valueToObject(entry.value);
    }
    return result;
  }

  dynamic _valueToObject(google_struct.Value value) {
    if (value.hasStringValue()) return value.stringValue;
    if (value.hasNumberValue()) return value.numberValue;
    if (value.hasBoolValue()) return value.boolValue;
    if (value.hasNullValue()) return null;
    if (value.hasListValue()) {
      return value.listValue.values.map(_valueToObject).toList();
    }
    if (value.hasStructValue()) {
      return _structToMap(value.structValue);
    }
    return null;
  }

  // Convert Dart Map to protobuf Struct
  google_struct.Struct _mapToStruct(Map<String, dynamic> map) {
    final struct = google_struct.Struct();
    for (final entry in map.entries) {
      struct.fields[entry.key] = _objectToValue(entry.value);
    }
    return struct;
  }

  google_struct.Value _objectToValue(dynamic obj) {
    final value = google_struct.Value();
    if (obj == null) {
      value.nullValue = google_struct.NullValue.NULL_VALUE;
    } else if (obj is String) {
      value.stringValue = obj;
    } else if (obj is num) {
      value.numberValue = obj.toDouble();
    } else if (obj is bool) {
      value.boolValue = obj;
    } else if (obj is List) {
      final listValue = google_struct.ListValue();
      listValue.values.addAll(obj.map(_objectToValue));
      value.listValue = listValue;
    } else if (obj is Map) {
      value.structValue = _mapToStruct(obj.cast<String, dynamic>());
    }
    return value;
  }
}
