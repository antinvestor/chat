import 'dart:async';

import 'package:antinvestor_api_chat/antinvestor_api_chat.dart' as pb;
import 'package:antinvestor_api_chat/antinvestor_api_chat.dart';
import 'package:antinvestor_api_common/antinvestor_api_common.dart' as common;
import 'package:antinvestor_api_common/antinvestor_api_common.dart' show TokenManager;
import 'package:fixnum/fixnum.dart' as fixnum;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/messages/data/message_providers.dart';
import '../../features/messages/data/message_repository.dart';
import '../../features/messages/domain/room_event.dart' as domain;
import '../crypto/key_manager.dart';
import '../db/database.dart';
import '../logging/app_logger.dart';
import '../networking/client.dart';
import 'pending_job.dart' as domain_job;
import 'pending_job_repository.dart';

final pendingJobRepositoryProvider = Provider<PendingJobRepository>((ref) {
  return PendingJobRepository(AppDatabase.instance);
});

/// Async provider for SyncEngine since it depends on async client providers
final syncEngineProvider = FutureProvider<SyncEngine>((ref) async {
  final gatewayClient = await ref.watch(gatewayServiceClientProvider.future);
  final chatClient = await ref.watch(chatServiceClientProvider.future);
  final tokenManager = ref.watch(tokenManagerProvider);
  final authRepo = ref.watch(authRepositoryProvider);
  
  return SyncEngine(
    gatewayClient,
    chatClient,
    ref.watch(messageRepositoryProvider),
    ref.watch(pendingJobRepositoryProvider),
    KeyManager(const FlutterSecureStorage()),
    tokenManager,
    onTokenRefresh: () async {
      AppLogger.debug('SyncEngine: Starting token refresh via authRepo');
      try {
        // Use the robust token refresh with retry logic
        final result = await authRepo.ensureValidAccessTokenWithStatus();
        final newToken = result.token;
        AppLogger.debug('SyncEngine: Token refresh result', data: {
          'hasToken': newToken != null,
          'needsRelogin': result.needsRelogin,
        });
        // Update TokenManager's in-memory cache so subsequent requests use the new token
        if (newToken != null) {
          await tokenManager.setAccessToken(newToken);
          AppLogger.debug('SyncEngine: TokenManager updated with new token');
        }
        return newToken;
      } catch (e, st) {
        AppLogger.error('SyncEngine: Token refresh failed with exception', 
            error: e, stackTrace: st);
        rethrow;
      }
    },
  );
});

enum SyncConnectionState { disconnected, connecting, connected }

final connectionStateProvider = StreamProvider<SyncConnectionState>((ref) async* {
  final syncEngine = await ref.watch(syncEngineProvider.future);
  yield* syncEngine.connectionState;
});

/// Callback type for token refresh operations
typedef TokenRefreshCallback = Future<String?> Function();

class SyncEngine {
  final GatewayServiceClient _gatewayClient;
  final ChatServiceClient _chatClient;
  final MessageRepository _messageRepo;
  final PendingJobRepository _jobRepo;
  final KeyManager _keyManager;
  final TokenManager _tokenManager; // Keep for potential future use
  final TokenRefreshCallback? _onTokenRefresh;

  StreamSubscription? _connectSubscription;
  Timer? _uploadTimer;
  bool _isUploading = false;
  bool _isConnected = false;
  int _reconnectAttempts = 0;
  int _authErrorCount = 0; // Track consecutive auth errors
  final Set<String> _processedEventIds = {}; // For event deduplication
  
  // Configuration
  static const _maxAuthErrors = 3; // Max auth errors before giving up

  final _typingEventsController = StreamController<pb.TypingEvent>.broadcast();
  Stream<pb.TypingEvent> get typingEvents => _typingEventsController.stream;

  final _signalingEventsController = StreamController<domain.RoomEvent>.broadcast();
  Stream<domain.RoomEvent> get signalingEvents => _signalingEventsController.stream;

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
    this._tokenManager, {
    TokenRefreshCallback? onTokenRefresh,
  }) : _onTokenRefresh = onTokenRefresh;

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
      // Don't pass manual headers - let the interceptor handle authorization
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

  Future<void> sendSignal(domain.RoomEvent event) async {
    // Insert into DB first (optional for signals, but good for history)
    await _messageRepo.insertMessage(event);

    // Create pending job
    await _jobRepo.addJob(domain_job.JobType.sendMessage, {
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
        final request = pb.StreamRequest(deviceId: deviceId);

        // Don't pass manual headers - let the interceptor handle authorization
        // This ensures token refresh works correctly on 401
        final stream = _gatewayClient.stream(Stream.value(request));
        _isConnected = true;
        _reconnectAttempts = 0;
        _authErrorCount = 0; // Reset auth error count on successful connection
        _connectionStateController.add(SyncConnectionState.connected);

        await for (final response in stream) {
          await _handleConnectResponse(response);
        }
      } catch (e, stackTrace) {
        final errorStr = e.toString().toLowerCase();
        final isAuthError = _isAuthenticationError(errorStr);
        final isNormalDisconnect = _isNormalDisconnect(errorStr);
        
        // Log appropriately based on error type
        if (isNormalDisconnect) {
          // Normal server disconnection - just log as debug, will auto-reconnect
          AppLogger.debug('Sync connection closed by server, will reconnect');
        } else {
          AppLogger.error(
            'Sync connection error',
            error: e,
            stackTrace: stackTrace,
            data: {
              'reconnectAttempts': _reconnectAttempts,
              'isAuthError': isAuthError,
              'authErrorCount': _authErrorCount,
            },
          );
        }
        
        // If it's an auth error, try to refresh token before reconnecting
        if (isAuthError) {
          _authErrorCount++;
          
          if (_authErrorCount > _maxAuthErrors) {
            AppLogger.error('Max auth errors reached, stopping sync until re-login');
            _connectionStateController.add(SyncConnectionState.disconnected);
            return; // Exit the loop - user needs to re-login
          }
          
          final refreshCallback = _onTokenRefresh;
          if (refreshCallback != null) {
            AppLogger.info('Authentication error detected, attempting token refresh', 
                data: {'attempt': _authErrorCount, 'maxAttempts': _maxAuthErrors});
            try {
              final newToken = await refreshCallback();
              if (newToken != null) {
                AppLogger.info('Token refreshed after auth error, will retry connection');
                _reconnectAttempts = 0; // Reset reconnect attempts on successful refresh
                // Small delay to prevent tight loop if refresh succeeds but connection still fails
                await Future.delayed(const Duration(milliseconds: 500));
                continue; // Retry with the new token
              } else {
                // Refresh returned null - either failed or in progress
                // Wait before retrying to avoid busy loop
                AppLogger.debug('Token refresh returned null, waiting before retry');
                await Future.delayed(const Duration(seconds: 2));
              }
            } catch (refreshError) {
              AppLogger.warning('Token refresh failed after auth error', 
                  data: {'error': refreshError.toString()});
              // Don't immediately retry on refresh failure - let the backoff handle it
            }
          }
        } else {
          // Not an auth error, reset auth error count
          _authErrorCount = 0;
        }
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
  
  /// Check if this is a normal/expected disconnection (not a real error)
  bool _isNormalDisconnect(String errorStr) {
    return errorStr.contains('connection closed') ||
        errorStr.contains('stream was reset') ||
        errorStr.contains('connection reset') ||
        errorStr.contains('eof') ||
        errorStr.contains('cancelled');
  }

  /// Check if an error is an authentication/authorization error
  bool _isAuthenticationError(String errorStr) {
    // Exclude database errors - these are NOT auth errors
    if (errorStr.contains('sqliteexception') ||
        errorStr.contains('foreign key') ||
        errorStr.contains('constraint failed') ||
        errorStr.contains('database') ||
        errorStr.contains('sqlite')) {
      return false;
    }
    
    return errorStr.contains('unauthenticated') ||
        errorStr.contains('unauthorized') ||
        errorStr.contains('invalid authorization') ||
        errorStr.contains('invalid token') ||
        errorStr.contains('token expired') ||
        errorStr.contains('jwt expired') ||
        errorStr.contains('401') ||
        errorStr.contains('403');
  }

  Duration _getBackoffDelay() {
    int delay = _initialBackoffMs * (1 << _reconnectAttempts);
    if (delay > _maxBackoffMs) {
      delay = _maxBackoffMs;
    }
    return Duration(milliseconds: delay);
  }

  Future<void> _handleConnectResponse(pb.StreamResponse response) async {
    // Handle different event types
    if (response.hasMessage()) {
      await _processPbRoomEvent(response.message);
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

  Future<void> _processPbRoomEvent(pb.RoomEvent event) async {
    // Skip events with missing required fields
    if (event.id.isEmpty) {
      AppLogger.warning('Skipping event with empty id');
      return;
    }
    if (event.roomId.isEmpty) {
      AppLogger.debug('Skipping system event with no room', data: {
        'eventId': event.id,
        'type': event.type.toString(),
      });
      return;
    }

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

    final roomEvent = domain.RoomEvent(
      id: event.id,
      roomId: event.roomId,
      senderId: event.senderId,
      type: _mapProtoEventType(event.type),
      content: content,
      parentId: event.hasParentId() ? event.parentId : null,
      status: domain.EventStatus.delivered,
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

  bool _isCallEvent(domain.RoomEventType type) {
    return type == domain.RoomEventType.callOffer ||
        type == domain.RoomEventType.callAnswer ||
        type == domain.RoomEventType.callIce ||
        type == domain.RoomEventType.callEnd;
  }

  Future<void> _processReceiptEvent(pb.ReceiptEvent event) async {
    // Update status for received read receipts
    // Skip if it's from ourselves (already marked as read locally)
    // TODO: Get actual current user ID from auth
    if (event.profileId == 'current_user_id') return;

    // Mark messages as delivered (other user received them)
    await _messageRepo.updateMessagesStatus(
      event.eventId.toList(),
      domain.EventStatus.delivered,
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

  Future<void> _processJob(domain_job.PendingJob job) async {
    // Skip jobs that have exceeded retry limit
    if (job.retryCount >= 5) {
      await _jobRepo.deleteJob(job.id);
      return;
    }

    try {
      switch (job.type) {
        case domain_job.JobType.sendMessage:
        case domain_job.JobType.sendMediaMessage:
          await _processSendMessage(job);
          break;
        case domain_job.JobType.uploadFile:
          // File uploads are handled by FileUploadService before queuing
          break;
        case domain_job.JobType.createRoom:
          await _processCreateRoom(job);
          break;
        case domain_job.JobType.updateRoom:
          await _processUpdateRoom(job);
          break;
        case domain_job.JobType.deleteRoom:
          await _processDeleteRoom(job);
          break;
        case domain_job.JobType.addRoomMembers:
          await _processAddRoomMembers(job);
          break;
        case domain_job.JobType.removeRoomMembers:
          await _processRemoveRoomMembers(job);
          break;
        case domain_job.JobType.vote:
          // TODO: Implement voting
          break;
        case domain_job.JobType.syncContacts:
          // Contact sync is handled by ContactSyncRepository
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

  Future<void> _processCreateRoom(domain_job.PendingJob job) async {
    final payload = job.payload;

    final request = pb.CreateRoomRequest(
      id: payload['id'] as String,
      name: payload['name'] as String? ?? '',
      description: payload['description'] as String? ?? '',
      isPrivate: payload['isPrivate'] as bool? ?? false,
      members: (payload['members'] as List<dynamic>?)?.cast<String>() ?? [],
    );

    if (payload['metadata'] != null) {
      request.metadata = _mapToStruct(
        payload['metadata'] as Map<String, dynamic>,
      );
    }

    final response = await _chatClient.createRoom(request);

    if (response.hasRoom()) {
      AppLogger.info('Room created on server', data: {
        'localId': payload['id'],
        'serverId': response.room.id,
      });
      // Room is already saved locally, server confirmed creation
    } else if (response.hasError()) {
      AppLogger.error('Server rejected room creation', data: {
        'error': response.error.message,
      });
      throw Exception('Room creation failed: ${response.error.message}');
    }
  }

  Future<void> _processUpdateRoom(domain_job.PendingJob job) async {
    final payload = job.payload;

    final request = pb.UpdateRoomRequest(
      roomId: payload['id'] as String,
      name: payload['name'] as String? ?? '',
      topic: payload['description'] as String? ?? '',
    );

    if (payload['metadata'] != null) {
      request.metadata = _mapToStruct(
        payload['metadata'] as Map<String, dynamic>,
      );
    }

    await _chatClient.updateRoom(request);
    AppLogger.info('Room updated on server', data: {'roomId': payload['id']});
  }

  Future<void> _processDeleteRoom(domain_job.PendingJob job) async {
    final payload = job.payload;

    final request = pb.DeleteRoomRequest(
      roomId: payload['id'] as String,
    );

    await _chatClient.deleteRoom(request);
    AppLogger.info('Room deleted on server', data: {'roomId': payload['id']});
  }

  Future<void> _processAddRoomMembers(domain_job.PendingJob job) async {
    final payload = job.payload;
    final roomId = payload['roomId'] as String;
    final profileIds = (payload['profileIds'] as List<dynamic>).cast<String>();

    // Convert profileIds to RoomSubscription objects
    final members = profileIds.map((profileId) => pb.RoomSubscription(
      roomId: roomId,
      profileId: profileId,
    )).toList();

    final request = pb.AddRoomSubscriptionsRequest(
      roomId: roomId,
      members: members,
    );

    await _chatClient.addRoomSubscriptions(request);
    AppLogger.info('Members added to room on server', data: {
      'roomId': roomId,
      'memberCount': profileIds.length,
    });
  }

  Future<void> _processRemoveRoomMembers(domain_job.PendingJob job) async {
    final payload = job.payload;

    final request = pb.RemoveRoomSubscriptionsRequest(
      roomId: payload['roomId'] as String,
      profileIds: (payload['profileIds'] as List<dynamic>).cast<String>(),
    );

    await _chatClient.removeRoomSubscriptions(request);
    AppLogger.info('Members removed from room on server', data: {
      'roomId': payload['roomId'],
      'memberCount': (payload['profileIds'] as List).length,
    });
  }

  Future<void> _processSendMessage(domain_job.PendingJob job) async {
    final payload = job.payload;

    // Convert content Map to Struct
    final contentStruct = _mapToStruct(
      payload['content'] as Map<String, dynamic>,
    );

    // Create timestamp
    final now = DateTime.now();
    final timestamp = common.Timestamp(
      seconds: fixnum.Int64(now.millisecondsSinceEpoch ~/ 1000),
      nanos: (now.millisecondsSinceEpoch % 1000) * 1000000,
    );

    final event = pb.RoomEvent(
      id: payload['localId'] as String? ?? '',
      roomId: payload['roomId'] as String,
      senderId: 'current_user_id', // TODO: Get from auth service
      type: _mapLocalEventTypeToProto(
        domain.RoomEventType.values.firstWhere(
          (t) => t.toString() == payload['type'],
          orElse: () => domain.RoomEventType.text,
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
      final updatedEvent = domain.RoomEvent(
        id: ackEventId,
        roomId: payload['roomId'] as String,
        senderId: 'current_user_id',
        type: domain.RoomEventType.values.firstWhere(
          (t) => t.toString() == payload['type'],
          orElse: () => domain.RoomEventType.text,
        ),
        content: payload['content'] as Map<String, dynamic>,
        status: domain.EventStatus.sent,
        createdAt: now.millisecondsSinceEpoch,
        localId: payload['localId'] as String?,
      );
      await _messageRepo.insertMessage(updatedEvent);
    }
  }

  // ignore: unused_element
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

  // Helper methods for type conversion

  // ignore: unused_element - kept for future use in reconnection logic
  domain.RoomEventType _mapProtoEventType(pb.RoomEventType type) {
    switch (type) {
      case pb.RoomEventType.ROOM_EVENT_TYPE_TEXT:
        return domain.RoomEventType.text;
      case pb.RoomEventType.ROOM_EVENT_TYPE_ATTACHMENT:
        // Map ATTACHMENT to image for now, could detect type from content
        return domain.RoomEventType.image;
      case pb.RoomEventType.ROOM_EVENT_TYPE_REACTION:
        return domain.RoomEventType.reaction;
      case pb.RoomEventType.ROOM_EVENT_TYPE_CALL_OFFER:
        return domain.RoomEventType.callOffer;
      case pb.RoomEventType.ROOM_EVENT_TYPE_CALL_ANSWER:
        return domain.RoomEventType.callAnswer;
      case pb.RoomEventType.ROOM_EVENT_TYPE_CALL_ICE:
        return domain.RoomEventType.callIce;
      case pb.RoomEventType.ROOM_EVENT_TYPE_CALL_END:
        return domain.RoomEventType.callEnd;
      default:
        return domain.RoomEventType.text;
    }
  }

  pb.RoomEventType _mapLocalEventTypeToProto(domain.RoomEventType type) {
    switch (type) {
      case domain.RoomEventType.text:
        return pb.RoomEventType.ROOM_EVENT_TYPE_TEXT;
      case domain.RoomEventType.image:
      case domain.RoomEventType.video:
      case domain.RoomEventType.audio:
      case domain.RoomEventType.file:
        // All media types map to ATTACHMENT
        return pb.RoomEventType.ROOM_EVENT_TYPE_ATTACHMENT;
      case domain.RoomEventType.reaction:
        return pb.RoomEventType.ROOM_EVENT_TYPE_REACTION;
      case domain.RoomEventType.callOffer:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_OFFER;
      case domain.RoomEventType.callAnswer:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_ANSWER;
      case domain.RoomEventType.callIce:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_ICE;
      case domain.RoomEventType.callEnd:
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL_END;
      case domain.RoomEventType.motion:
      case domain.RoomEventType.vote:
      case domain.RoomEventType.transaction:
        // These might not be in protobuf yet, map to TEXT for now
        return pb.RoomEventType.ROOM_EVENT_TYPE_TEXT;
    }
  }

  // Convert protobuf Struct to Dart Map
  Map<String, dynamic> _structToMap(common.Struct struct) {
    final result = <String, dynamic>{};
    for (final entry in struct.fields.entries) {
      result[entry.key] = _valueToObject(entry.value);
    }
    return result;
  }

  dynamic _valueToObject(common.Value value) {
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
  common.Struct _mapToStruct(Map<String, dynamic> map) {
    final struct = common.Struct();
    for (final entry in map.entries) {
      struct.fields[entry.key] = _objectToValue(entry.value);
    }
    return struct;
  }

  common.Value _objectToValue(dynamic obj) {
    final value = common.Value();
    if (obj == null) {
      value.nullValue = common.NullValue.NULL_VALUE;
    } else if (obj is String) {
      value.stringValue = obj;
    } else if (obj is num) {
      value.numberValue = obj.toDouble();
    } else if (obj is bool) {
      value.boolValue = obj;
    } else if (obj is List) {
      final listValue = common.ListValue();
      listValue.values.addAll(obj.map(_objectToValue));
      value.listValue = listValue;
    } else if (obj is Map) {
      value.structValue = _mapToStruct(obj.cast<String, dynamic>());
    }
    return value;
  }
}
