import 'dart:async';

import 'package:antinvestor_api_chat/antinvestor_api_chat.dart' as pb;
import 'package:antinvestor_api_common/antinvestor_api_common.dart'
    as common_types;
import 'package:fixnum/fixnum.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/messages/data/message_providers.dart';
import '../../features/messages/data/message_repository.dart';
import '../../features/messages/domain/room_event.dart' as domain;
import '../../features/rooms/data/room_member_repository.dart';
import '../../features/rooms/data/room_subscription_service.dart';
import '../crypto/e2e_encryption_service.dart';
import '../db/database.dart';
import '../logging/app_logger.dart';
import '../networking/client.dart';
import 'pending_job.dart' as domain_job;
import 'pending_job_repository.dart';

final pendingJobRepositoryProvider = Provider<PendingJobRepository>(
  (ref) => PendingJobRepository(AppDatabase.instance),
);

/// Exception thrown when token refresh fails permanently and user must re-authenticate
class TokenRefreshPermanentError implements Exception {
  TokenRefreshPermanentError(this.message);
  final String message;

  @override
  String toString() => 'TokenRefreshPermanentError: $message';
}

/// Async provider for SyncEngine since it depends on async client providers
final syncEngineProvider = FutureProvider<SyncEngine>((ref) async {
  final gatewayClient = await ref.watch(gatewayServiceClientProvider.future);
  final chatClient = await ref.watch(chatServiceClientProvider.future);
  final tokenManager = ref.watch(tokenManagerProvider);
  final authRepo = ref.watch(authRepositoryProvider);
  final encryptionService = ref.watch(e2eEncryptionServiceProvider);

  // Initialize encryption service
  await encryptionService.initialize();

  return SyncEngine(
    gatewayClient,
    chatClient,
    ref.watch(messageRepositoryProvider),
    ref.watch(pendingJobRepositoryProvider),
    authRepo,
    ref.watch(roomMemberRepositoryProvider),
    ref.watch(roomSubscriptionServiceProvider),
    encryptionService,
    onTokenRefresh: () async {
      AppLogger.debug('SyncEngine: Starting token refresh via authRepo');
      try {
        // Use the robust token refresh with retry logic
        final result = await authRepo.ensureValidAccessTokenWithStatus();
        final newToken = result.token;
        AppLogger.debug(
          'SyncEngine: Token refresh result',
          data: {
            'hasToken': newToken != null,
            'needsRelogin': result.needsRelogin,
          },
        );

        // If re-login is required, throw a specific exception to signal permanent failure
        if (result.needsRelogin) {
          AppLogger.warning('SyncEngine: Token refresh requires re-login');
          throw TokenRefreshPermanentError('User must re-authenticate');
        }

        // Update TokenManager's in-memory cache so subsequent requests use the new token
        if (newToken != null) {
          await tokenManager.setAccessToken(newToken);
          AppLogger.debug('SyncEngine: TokenManager updated with new token');
        }
        return newToken;
      } on Exception catch (e, st) {
        AppLogger.error(
          'SyncEngine: Token refresh failed with exception',
          error: e,
          stackTrace: st,
        );
        rethrow;
      }
    },
  );
});

/// Connection state for the real-time sync engine
///
/// Example:
/// ```dart
/// final state = ref.watch(connectionStateProvider);
/// if (state == SyncConnectionState.connected) {
///   print('Connected to server');
/// }
/// ```
enum SyncConnectionState { disconnected, connecting, connected }

/// Stream provider for monitoring sync connection state
final connectionStateProvider = StreamProvider<SyncConnectionState>((
  ref,
) async* {
  final syncEngine = await ref.watch(syncEngineProvider.future);
  yield* syncEngine.connectionState;
});

/// Callback type for token refresh operations
typedef TokenRefreshCallback = Future<String?> Function();

/// Real-time synchronization engine for bidirectional message streaming
///
/// Manages the WebSocket-like connection to the gateway service for:
/// - Receiving incoming messages and events
/// - Uploading pending messages from the offline queue
/// - Handling typing indicators and read receipts
/// - Managing connection state with automatic reconnection
///
/// Example:
/// ```dart
/// final syncEngine = await ref.watch(syncEngineProvider.future);
/// syncEngine.start();
///
/// // Monitor connection state
/// syncEngine.connectionState.listen((state) {
///   print('Connection: $state');
/// });
///
/// // Send a message
/// await syncEngine.sendSignal(event);
/// ```
class SyncEngine {
  SyncEngine(
    this._gatewayClient,
    this._chatClient,
    this._messageRepo,
    this._jobRepo,
    this._authRepository,
    this._roomMemberRepository,
    this._subscriptionService, {
    TokenRefreshCallback? onTokenRefresh,
  }) : _onTokenRefresh = onTokenRefresh;
  final pb.GatewayServiceClient _gatewayClient;
  final pb.ChatServiceClient _chatClient;
  final MessageRepository _messageRepo;
  final PendingJobRepository _jobRepo;
  final AuthRepository _authRepository;
  final RoomMemberRepository _roomMemberRepository;
  final RoomSubscriptionService _subscriptionService;
  final E2EEncryptionService _encryptionService;
  final TokenRefreshCallback? _onTokenRefresh;

  StreamSubscription? _connectSubscription;
  Timer? _uploadTimer;
  bool _isUploading = false;
  bool _isConnected = false;
  bool _shouldStop = false; // Flag to stop the download loop
  int _reconnectAttempts = 0;
  int _authErrorCount = 0; // Track consecutive auth errors
  final Set<String> _processedEventIds = {}; // For event deduplication

  // Configuration
  static const _maxAuthErrors = 3; // Max auth errors before giving up

  final _typingEventsController = StreamController<pb.TypingEvent>.broadcast();
  Stream<pb.TypingEvent> get typingEvents => _typingEventsController.stream;

  final _signalingEventsController =
      StreamController<domain.RoomEvent>.broadcast();
  Stream<domain.RoomEvent> get signalingEvents =>
      _signalingEventsController.stream;

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
    this._authRepository,
    this._roomMemberRepository,
    this._subscriptionService,
    this._encryptionService, {
    TokenRefreshCallback? onTokenRefresh,
  }) : _onTokenRefresh = onTokenRefresh;

  void start() {
    _shouldStop = false;
    _startDownloadLoop();
    _startUploadLoop();
  }

  void stop() {
    _shouldStop = true; // Signal download loop to stop
    _connectSubscription?.cancel();
    _connectSubscription = null;
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _isConnected = false;
    // Note: Don't close stream controllers here as they may be reused
    // They will be closed when the engine is disposed
  }

  /// Permanently dispose of the sync engine (call only when no longer needed)
  void dispose() {
    stop();
    _typingEventsController.close();
    _signalingEventsController.close();
    _connectionStateController.close();
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
      final pageCursor = common_types.PageCursor(limit: limit, page: cursor);

      final request = pb.GetHistoryRequest(
        roomId: roomId,
        cursor: pageCursor,
        forward: false, // Get newer->older by default
      );

      final response = await _chatClient.getHistory(request);

      // Process each event in the response
      for (final roomEvent in response.events) {
        await _processPbRoomEvent(roomEvent);
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
    if (_isConnected || _shouldStop) return;

    _connectionStateController.add(SyncConnectionState.connecting);

    // Run connection loop in a way that doesn't block the main thread
    while (!_shouldStop) {
      try {
        // Add client capabilities for server-side feature detection
        final hello = pb.StreamHello(
          capabilities: {
            'version': '1.0.0',
            'platform': 'flutter',
            'e2ee': 'vodozemac-0.4',
            'calls': 'webrtc',
            'offline': 'true',
          },
          clientTime: common_types.Timestamp.fromDateTime(DateTime.now()),
        );
        final request = pb.StreamRequest(hello: hello);

        // Don't pass manual headers - let the interceptor handle authorization
        // This ensures token refresh works correctly on 401
        final stream = _gatewayClient.stream(Stream.value(request));
        _isConnected = true;
        _reconnectAttempts = 0;
        _authErrorCount = 0; // Reset auth error count on successful connection
        _connectionStateController.add(SyncConnectionState.connected);

        // Process stream events with yield to prevent blocking
        await for (final response in stream) {
          // Use microtask to ensure UI responsiveness
          Future.microtask(() async {
            try {
              await _handleConnectResponse(response);
            } catch (e, stackTrace) {
              AppLogger.error(
                'Error handling stream response in microtask',
                error: e,
                stackTrace: stackTrace,
              );
            }
          });
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
            AppLogger.error(
              'Max auth errors reached, stopping sync until re-login',
            );
            _connectionStateController.add(SyncConnectionState.disconnected);
            return; // Exit the loop - user needs to re-login
          }

          final refreshCallback = _onTokenRefresh;
          if (refreshCallback != null) {
            AppLogger.info(
              'Authentication error detected, attempting token refresh',
              data: {'attempt': _authErrorCount, 'maxAttempts': _maxAuthErrors},
            );

            try {
              final newToken = await refreshCallback();
              if (newToken != null) {
                AppLogger.info(
                  'Token refreshed after auth error, will retry connection',
                );
                _reconnectAttempts =
                    0; // Reset reconnect attempts on successful refresh
                // Small delay to prevent tight loop if refresh succeeds but connection still fails
                await Future.delayed(const Duration(milliseconds: 500));
              } else {
                // Refresh returned null - transient error, wait before retrying
                AppLogger.debug(
                  'Token refresh returned null (transient), waiting before retry',
                );
                await Future.delayed(const Duration(seconds: 2));
              }
            } on TokenRefreshPermanentError catch (e) {
              // Permanent token failure - user must re-authenticate
              // Stop the sync engine entirely
              AppLogger.error(
                'Permanent token refresh failure, stopping sync engine',
                data: {'error': e.message},
              );
              _connectionStateController.add(SyncConnectionState.disconnected);
              return; // Exit the loop - user needs to re-login
            } catch (refreshError) {
              AppLogger.warning(
                'Token refresh failed with transient error',
                data: {'error': refreshError.toString()},
              );
              // Transient error - continue with backoff and retry
            }

            // Continue with reconnection attempt
            continue;
          }
        } else {
          // Not an auth error, reset auth error count
          _authErrorCount = 0;
        }
      } finally {
        _isConnected = false;
        _connectionStateController.add(SyncConnectionState.disconnected);
      }

      // Check if we should stop before waiting
      if (_shouldStop) {
        AppLogger.debug('Sync engine stopped, exiting download loop');
        break;
      }

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

      // Check again after delay in case stop was called during wait
      if (_shouldStop) {
        AppLogger.debug('Sync engine stopped during backoff, exiting');
        break;
      }

      _reconnectAttempts++;
    }
  }

  /// Check if this is a normal/expected disconnection (not a real error)
  bool _isNormalDisconnect(String errorStr) =>
      errorStr.contains('connection closed') ||
      errorStr.contains('stream was reset') ||
      errorStr.contains('connection reset') ||
      errorStr.contains('eof') ||
      errorStr.contains('cancelled');

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
    var delay = _initialBackoffMs * (1 << _reconnectAttempts);
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
      // Note: Presence events will be handled when needed
    } else if (response.hasReceiptEvent()) {
      await _processReceiptEvent(response.receiptEvent);
    } else if (response.hasReadEvent()) {
      // Note: Read marker events will be handled when needed
    }
  }

  Future<void> _processPbRoomEvent(pb.RoomEvent event) async {
    // Skip events with missing required fields
    if (event.id.isEmpty) {
      AppLogger.warning('Skipping event with empty id');
      return;
    }

    // Handle system events that don't have roomId
    if (event.roomId.isEmpty) {
      AppLogger.debug(
        'Processing system event with no room',
        data: {'eventId': event.id, 'type': event.type.toString()},
      );

      // Process system events (like token refresh, auth status, etc.)
      await _processSystemEvent(event);
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

    // Extract content from typed payload fields
    var content = <String, dynamic>{};
    if (event.hasPayload()) {
      final payload = event.payload;
      if (payload.hasText()) {
        content = {'text': payload.text.body};
      } else if (payload.hasAttachment()) {
        content = {
          'attachmentId': payload.attachment.attachmentId,
          'fileName': payload.attachment.filename,
          'mimeType': payload.attachment.mimeType,
          'size': payload.attachment.sizeBytes.toInt(),
        };
      } else if (payload.hasEncrypted()) {
        // Decrypt the message using E2EE service
        try {
          final encrypted = payload.encrypted;
          final ciphertext = encrypted.ciphertext;
          final sessionId = encrypted.sessionId;
          final senderKey = encrypted.hasSenderKey() ? encrypted.senderKey : null;

          // Try to get the inbound session for this room/sender
          if (_encryptionService.hasInboundSession(event.roomId, senderKey)) {
            final plaintext = await _encryptionService.decryptGroup(
              event.roomId,
              ciphertext,
              senderKey: senderKey,
            );
            content = {
              'text': plaintext,
              'encrypted': true, // Mark as was encrypted for UI indicator
              'decrypted': true,
            };
            AppLogger.debug('Message decrypted', data: {
              'roomId': event.roomId,
              'sessionId': sessionId,
            });
          } else {
            // Need to request session key from sender
            AppLogger.warning('Missing session key for decryption', data: {
              'roomId': event.roomId,
              'sessionId': sessionId,
              'senderKey': senderKey,
            });
            content = {
              'text': '[Unable to decrypt - missing session key]',
              'encrypted': true,
              'decrypted': false,
              'sessionId': sessionId,
              'senderKey': senderKey,
            };
          }
        } catch (e, stackTrace) {
          AppLogger.error('Decryption failed', error: e, stackTrace: stackTrace);
          content = {
            'text': '[Unable to decrypt message]',
            'encrypted': true,
            'decrypted': false,
            'error': e.toString(),
          };
        }
      } else if (payload.hasCall()) {
        // Extract call data
        content = {
          'callId': payload.call.callId,
          'callType': payload.call.action.toString(),
        };
      }
    }

    // Extract sender info using subscription ID
    final subscriptionId = event.hasSubscriptionId()
        ? event.subscriptionId
        : '';

    // Get profile info for the subscription
    String? senderId;
    String? senderContactId;
    if (subscriptionId.isNotEmpty) {
      final member = await _roomMemberRepository.getSubscription(
        subscriptionId,
      );
      senderId = member?.profileId;
      senderContactId = member?.contactId;
    }

    final roomEvent = domain.RoomEvent(
      id: event.id,
      roomId: event.roomId,
      senderId: senderId ?? '',
      senderContactId: senderContactId,
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

    // Note: Server handles message forwarding to off-platform members
    // No client-side forwarding needed - server determines routing based on
    // member platform status, credit balance, and handles billing

    // Emit signaling events for real-time handling
    if (_isCallEvent(roomEvent.type)) {
      _signalingEventsController.add(roomEvent);
    }
  }

  bool _isCallEvent(domain.RoomEventType type) =>
      type == domain.RoomEventType.callOffer ||
      type == domain.RoomEventType.callAnswer ||
      type == domain.RoomEventType.callIce ||
      type == domain.RoomEventType.callEnd;

  /// Process system events that don't have roomId (like auth events, token refresh, etc.)
  Future<void> _processSystemEvent(pb.RoomEvent event) async {
    try {
      AppLogger.debug(
        'Processing system event',
        data: {
          'eventId': event.id,
          'type': event.type.toString(),
          'hasPayload': event.hasPayload(),
        },
      );

      // Handle different types of system events
      switch (event.type) {
        case pb.RoomEventType.ROOM_EVENT_TYPE_EVENT:
          // Generic system event - extract and handle payload
          if (event.hasPayload()) {
            final payload = event.payload;
            AppLogger.debug(
              'System event payload',
              data: {
                'hasText': payload.hasText(),
                'hasAttachment': payload.hasAttachment(),
                'hasCall': payload.hasCall(),
              },
            );
          }
          break;

        default:
          AppLogger.debug(
            'Unhandled system event type',
            data: {'type': event.type.toString()},
          );
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Error processing system event',
        error: e,
        stackTrace: stackTrace,
        data: {'eventId': event.id, 'type': event.type.toString()},
      );
    }
  }

  Future<void> _processReceiptEvent(pb.ReceiptEvent event) async {
    // Update status for received read receipts
    // New API doesn't include source information, so we can't filter out self-receipts
    // Note: Filtering through subscription context will be implemented if needed

    // Mark messages as delivered (other user received them)
    await _messageRepo.updateMessagesStatus(
      event.eventId.toList(),
      domain.EventStatus.delivered,
    );
  }

  void _startUploadLoop() {
    // Cancel existing timer to prevent multiple timers running
    _uploadTimer?.cancel();

    if (_shouldStop) return;

    _uploadTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_isUploading || !_isConnected || _shouldStop) return;
      _isUploading = true;

      try {
        final jobs = await _jobRepo.getPendingJobs();

        // Process each job in a microtask to prevent blocking
        for (final job in jobs) {
          Future.microtask(() async {
            try {
              await _processJob(job);
            } catch (e, stackTrace) {
              AppLogger.error(
                'Error processing job in microtask',
                error: e,
                stackTrace: stackTrace,
                data: {'jobId': job.id, 'jobType': job.type.toString()},
              );
            }
          });
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
        case domain_job.JobType.leaveRoom:
          await _processLeaveRoom(job);
          break;
        case domain_job.JobType.vote:
          await _processVote(job);
          break;
        case domain_job.JobType.syncContacts:
          // Contact sync is handled by ContactSyncRepository
          break;
        case domain_job.JobType.editMessage:
          await _processEditMessage(job);
          break;
        case domain_job.JobType.deleteMessage:
          await _processDeleteMessage(job);
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

    // Convert member profile IDs to ContactLink objects
    final memberIds =
        (payload['members'] as List<dynamic>?)?.cast<String>() ?? [];
    final memberLinks = memberIds
        .map((id) => common_types.ContactLink(profileId: id))
        .toList();

    final request = pb.CreateRoomRequest(
      id: payload['id'] as String,
      name: payload['name'] as String? ?? '',
      description: payload['description'] as String? ?? '',
      isPrivate: payload['isPrivate'] as bool? ?? false,
      members: memberLinks,
    );

    if (payload['metadata'] != null) {
      request.metadata = _mapToStruct(
        payload['metadata'] as Map<String, dynamic>,
      );
    }

    final response = await _chatClient.createRoom(request);

    if (response.hasRoom()) {
      AppLogger.info(
        'Room created on server',
        data: {'localId': payload['id'], 'serverId': response.room.id},
      );
      // Room is already saved locally, server confirmed creation
    } else if (response.hasError()) {
      AppLogger.error(
        'Server rejected room creation',
        data: {'error': response.error.message},
      );
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

    final request = pb.DeleteRoomRequest(roomId: payload['id'] as String);

    await _chatClient.deleteRoom(request);
    AppLogger.info('Room deleted on server', data: {'roomId': payload['id']});
  }

  Future<void> _processAddRoomMembers(domain_job.PendingJob job) async {
    final payload = job.payload;
    final roomId = payload['roomId'] as String;
    final profileIds = (payload['profileIds'] as List<dynamic>).cast<String>();

    // Convert profileIds to RoomSubscription objects with ContactLink
    final members = profileIds
        .map(
          (profileId) => pb.RoomSubscription(
            roomId: roomId,
            member: common_types.ContactLink(profileId: profileId),
          ),
        )
        .toList();

    final request = pb.AddRoomSubscriptionsRequest(
      roomId: roomId,
      members: members,
    );

    await _chatClient.addRoomSubscriptions(request);
    AppLogger.info(
      'Members added to room on server',
      data: {'roomId': roomId, 'memberCount': profileIds.length},
    );
  }

  Future<void> _processRemoveRoomMembers(domain_job.PendingJob job) async {
    final payload = job.payload;

    // Note: The API now expects subscription_id instead of profileIds
    // For now, we'll use profileIds as subscription IDs (they should match)
    final subscriptionIds = (payload['profileIds'] as List<dynamic>)
        .cast<String>();

    final request = pb.RemoveRoomSubscriptionsRequest(
      roomId: payload['roomId'] as String,
      subscriptionId: subscriptionIds,
    );

    await _chatClient.removeRoomSubscriptions(request);
    AppLogger.info(
      'Members removed from room on server',
      data: {
        'roomId': payload['roomId'],
        'memberCount': subscriptionIds.length,
      },
    );
  }

  Future<void> _processLeaveRoom(domain_job.PendingJob job) async {
    final payload = job.payload;
    final roomId = payload['roomId'] as String;

    // Get current profile's profile ID to remove their subscription
    final currentProfileId = await _authRepository.getCurrentProfileId();
    if (currentProfileId == null) {
      throw Exception('Cannot leave room: Profile not authenticated');
    }

    final request = pb.RemoveRoomSubscriptionsRequest(
      roomId: roomId,
      subscriptionId: [
        currentProfileId,
      ], // Remove current profile's subscription
    );

    await _chatClient.removeRoomSubscriptions(request);
    AppLogger.info('Left room on server', data: {'roomId': roomId});
  }

  Future<void> _processSendMessage(domain_job.PendingJob job) async {
    final payload = job.payload;
    final currentProfileId = await _authRepository.getCurrentProfileId();

    // Create timestamp
    final now = DateTime.now();
    final timestamp = common_types.Timestamp.fromDateTime(now);
    // Source is no longer used in new API

    // Extract content and type
    final content = payload['content'] as Map<String, dynamic>;
    final localType = domain.RoomEventType.values.firstWhere(
      (t) => t.toString() == payload['type'],
      orElse: () => domain.RoomEventType.text,
    );
    final protoType = _mapLocalEventTypeToProto(localType);

    // Build event with payload-based content
    final pbPayload = pb.Payload();
    if (localType == domain.RoomEventType.text) {
      pbPayload.text = pb.TextContent(body: content['text'] as String? ?? '');
    } else if (localType == domain.RoomEventType.image ||
        localType == domain.RoomEventType.video ||
        localType == domain.RoomEventType.audio ||
        localType == domain.RoomEventType.file) {
      pbPayload.attachment = pb.AttachmentContent(
        attachmentId: content['attachmentId'] as String? ?? '',
        filename: content['fileName'] as String? ?? '',
        mimeType: content['mimeType'] as String? ?? '',
        sizeBytes: Int64(content['size'] as int? ?? 0),
      );
    }

    final event = pb.RoomEvent(
      id: payload['localId'] as String? ?? '',
      roomId: payload['roomId'] as String,
      type: protoType,
      sentAt: timestamp,
      payload: pbPayload,
    );

    final request = pb.SendEventRequest(event: [event]);
    final response = await _chatClient.sendEvent(request);

    // Update local message status to sent
    if (payload['localId'] != null && response.ack.isNotEmpty) {
      final ackEventId = response.ack.first.eventId;
      // Update the message with server ID
      final updatedEvent = domain.RoomEvent(
        id: ackEventId.first,
        roomId: payload['roomId'] as String,
        senderId: currentProfileId ?? 'unknown',
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

  Future<void> _processVote(domain_job.PendingJob job) async {
    final payload = job.payload;
    final currentProfileId = await _authRepository.getCurrentProfileId();

    // Create timestamp
    final now = DateTime.now();
    final timestamp = common_types.Timestamp.fromDateTime(now);
    // Source is no longer used in new API

    // Build vote payload - use text content since VoteContent doesn't exist yet
    final pbPayload = pb.Payload();
    final voteData = {
      'motionId': payload['motionId'],
      'option': payload['option'],
      'type': 'vote',
    };
    pbPayload.text = pb.TextContent(body: voteData.toString());

    final event = pb.RoomEvent(
      id: payload['localId'] as String? ?? '',
      roomId: payload['roomId'] as String,
      type:
          pb.RoomEventType.ROOM_EVENT_TYPE_MESSAGE, // Vote not in protobuf yet
      sentAt: timestamp,
      payload: pbPayload,
    );

    final request = pb.SendEventRequest(event: [event]);
    await _chatClient.sendEvent(request);

    // Update local motion event with the new vote
    await _updateMotionVote(
      payload['motionId'] as String,
      currentProfileId ?? 'unknown',
      payload['option'] as String,
    );
  }

  Future<void> _updateMotionVote(
    String motionId,
    String profileId,
    String option,
  ) async {
    final motionEvent = await _messageRepo.getEventById(motionId);
    if (motionEvent == null) return;

    final votes = Map<String, dynamic>.from(
      motionEvent.content['votes'] as Map<String, dynamic>? ?? {},
    );

    // Update or add the vote
    votes[profileId] = option;

    final updatedContent = Map<String, dynamic>.from(motionEvent.content);
    updatedContent['votes'] = votes;

    final updatedEvent = motionEvent.copyWith(content: updatedContent);
    await _messageRepo.insertMessage(updatedEvent);
  }

  Future<void> _processEditMessage(domain_job.PendingJob job) async {
    final payload = job.payload;
    final messageId = payload['messageId'] as String;
    final roomId = payload['roomId'] as String;
    final content = payload['content'] as Map<String, dynamic>;

    // Build the edit request
    final timestamp = common_types.Timestamp.fromDateTime(DateTime.now());

    final pbPayload = pb.Payload();
    pbPayload.text = pb.TextContent(body: content['text'] as String? ?? '');

    // Send as an edit event to the server
    // Note: Backend API for editing may need to be implemented
    // For now, we send as a regular message with edit metadata
    final event = pb.RoomEvent(
      id: messageId,
      roomId: roomId,
      type: pb.RoomEventType.ROOM_EVENT_TYPE_MESSAGE,
      sentAt: timestamp,
      payload: pbPayload,
    );

    final request = pb.SendEventRequest(event: [event]);
    await _chatClient.sendEvent(request);

    AppLogger.info('Edit message synced', data: {'messageId': messageId});
  }

  Future<void> _processDeleteMessage(domain_job.PendingJob job) async {
    final payload = job.payload;
    final messageId = payload['messageId'] as String;
    final roomId = payload['roomId'] as String;

    // Send a redacted event to mark the message as deleted
    final timestamp = common_types.Timestamp.fromDateTime(DateTime.now());

    final event = pb.RoomEvent(
      id: messageId,
      roomId: roomId,
      type: pb.RoomEventType.ROOM_EVENT_TYPE_MESSAGE,
      sentAt: timestamp,
      redacted: true,
    );

    final request = pb.SendEventRequest(event: [event]);
    await _chatClient.sendEvent(request);

    AppLogger.info('Delete message synced', data: {'messageId': messageId});
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
      case pb.RoomEventType.ROOM_EVENT_TYPE_MESSAGE:
        return domain.RoomEventType.text;
      case pb.RoomEventType.ROOM_EVENT_TYPE_REACTION:
        return domain.RoomEventType.reaction;
      case pb.RoomEventType.ROOM_EVENT_TYPE_CALL:
        // Map the unified CALL type to callOffer by default
        // The specific call action can be determined from the call content
        return domain.RoomEventType.callOffer;
      case pb.RoomEventType.ROOM_EVENT_TYPE_MOTION:
        return domain.RoomEventType.motion;
      case pb.RoomEventType.ROOM_EVENT_TYPE_EVENT:
        // System event - map to a special type or text for now
        return domain
            .RoomEventType
            .text; // Could create a new system event type
      default:
        return domain.RoomEventType.text;
    }
  }

  pb.RoomEventType _mapLocalEventTypeToProto(domain.RoomEventType type) {
    switch (type) {
      case domain.RoomEventType.text:
        return pb.RoomEventType.ROOM_EVENT_TYPE_MESSAGE;
      case domain.RoomEventType.image:
      case domain.RoomEventType.video:
      case domain.RoomEventType.audio:
      case domain.RoomEventType.file:
        // All media types map to MESSAGE with attachment payload
        return pb.RoomEventType.ROOM_EVENT_TYPE_MESSAGE;
      case domain.RoomEventType.reaction:
        return pb.RoomEventType.ROOM_EVENT_TYPE_REACTION;
      case domain.RoomEventType.callOffer:
      case domain.RoomEventType.callAnswer:
      case domain.RoomEventType.callIce:
      case domain.RoomEventType.callEnd:
        // All call types now map to a single ROOM_EVENT_TYPE_CALL
        return pb.RoomEventType.ROOM_EVENT_TYPE_CALL;
      case domain.RoomEventType.motion:
        return pb.RoomEventType.ROOM_EVENT_TYPE_MOTION;
      case domain.RoomEventType.vote:
      case domain.RoomEventType.transaction:
        // These might not be in protobuf yet, map to MESSAGE for now
        return pb.RoomEventType.ROOM_EVENT_TYPE_MESSAGE;
    }
  }

  // Convert protobuf Struct to Dart Map
  Map<String, dynamic> _structToMap(common_types.Struct struct) {
    final result = <String, dynamic>{};
    for (final entry in struct.fields.entries) {
      result[entry.key] = _valueToObject(entry.value);
    }
    return result;
  }

  dynamic _valueToObject(common_types.Value value) {
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
  common_types.Struct _mapToStruct(Map<String, dynamic> map) {
    final struct = common_types.Struct();
    for (final entry in map.entries) {
      struct.fields[entry.key] = _objectToValue(entry.value);
    }
    return struct;
  }

  common_types.Value _objectToValue(Object? obj) {
    final value = common_types.Value();
    if (obj == null) {
      value.nullValue = common_types.NullValue.NULL_VALUE;
    } else if (obj is String) {
      value.stringValue = obj;
    } else if (obj is num) {
      value.numberValue = obj.toDouble();
    } else if (obj is bool) {
      value.boolValue = obj;
    } else if (obj is List) {
      final listValue = common_types.ListValue();
      listValue.values.addAll(obj.map(_objectToValue));
      value.listValue = listValue;
    } else if (obj is Map) {
      value.structValue = _mapToStruct(obj.cast<String, dynamic>());
    }
    return value;
  }

  /// Get the current profile's SUBSCRIPTION ID for a specific room
  /// Returns null if the profile is not a member of the room
  ///
  /// IMPORTANT: This returns a SUBSCRIPTION ID (room-specific presence),
  /// not a PROFILE ID (global identity). Use this for room operations.
  ///
  /// Note: This method works for both authenticated and anonymous subscriptions
  /// The subscription ID is independent of profile ID.
  Future<String?> getCurrentSubscriptionId(String roomId) async {
    final currentProfileId = await _authRepository.getCurrentProfileId();
    final currentContactId = await _authRepository.getCurrentContactId();
    if (currentContactId == null) return null;

    // Use repository to find the subscription ID for the current profile
    // Pass empty string for profileId if null to handle anonymous subscriptions
    return _roomMemberRepository.getCurrentSubscriptionId(
      roomId,
      currentProfileId ?? '', // Empty string for anonymous subscriptions
      currentContactId,
    );
  }

  /// Check if a SUBSCRIPTION ID belongs to the current profile's contact
  /// Used to verify if incoming events are from the current profile
  ///
  /// @param roomId The room context
  /// @param subscriptionId The subscription ID to check (room-specific)
  /// @return true if this subscription belongs to current profile's contact
  ///
  /// Note: This method will return false for anonymous subscriptions (no contact ID)
  Future<bool> isCurrentUserSubscription(
    String roomId,
    String subscriptionId,
  ) async {
    final currentProfileId = await _authRepository.getCurrentProfileId();
    final currentContactId = await _authRepository.getCurrentContactId();
    if (currentContactId == null) return false;

    // Use repository to check if this subscription belongs to current profile's contact
    // Pass empty string for profileId if null to handle anonymous subscriptions
    return _roomMemberRepository.isCurrentUserSubscription(
      roomId,
      subscriptionId,
      currentProfileId ?? '', // Empty string for anonymous subscriptions
      currentContactId,
    );
  }

  /// Update profile ID for an existing subscription
  /// Used when a user authenticates and their profile ID becomes known
  ///
  /// @param subscriptionId The room subscription to update
  /// @param profileId The profile ID to associate with this subscription
  /// @param contactId Optional contact ID used for this subscription
  /// @return true if update was successful, false if subscription not found
  Future<bool> updateSubscriptionProfile({
    required String subscriptionId,
    required String profileId,
    String? contactId,
  }) async => _subscriptionService.updateSubscriptionProfile(
    subscriptionId: subscriptionId,
    profileId: profileId,
    contactId: contactId,
  );

  /// Get all subscriptions without a profile ID (anonymous subscriptions)
  /// Useful for finding subscriptions that need profile assignment
  ///
  /// @param roomId Optional room filter
  /// @return List of anonymous subscriptions
  Future<List<RoomMember>> getAnonymousSubscriptions({String? roomId}) async =>
      _subscriptionService.getAnonymousSubscriptions(roomId: roomId);

  /// Send typing event to server
  Future<void> sendTyping(String roomId, bool isTyping) async {
    try {
      // Get current profile's subscription ID for this room
      final subscriptionId = await getCurrentSubscriptionId(roomId);
      if (subscriptionId == null) {
        AppLogger.warning(
          'Cannot send typing event: profile not in room',
          data: {'roomId': roomId},
        );
        return;
      }

      // Create typing event
      final typingEvent = pb.TypingEvent(
        subscriptionId: subscriptionId,
        roomId: roomId,
        typing: isTyping,
        since: common_types.Timestamp.fromDateTime(DateTime.now()),
      );

      // Wrap in ClientCommand
      final command = pb.ClientCommand(typing: typingEvent);

      // Send via gateway stream (same connection as messages)
      final request = pb.StreamRequest(command: command);
      _gatewayClient.stream(Stream.value(request));

      AppLogger.debug(
        'Typing event sent',
        data: {'roomId': roomId, 'typing': isTyping},
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to send typing event',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Send read receipts for messages
  Future<void> sendReadReceipts(String roomId, List<String> messageIds) async {
    try {
      // Get current profile's subscription ID for this room
      final subscriptionId = await getCurrentSubscriptionId(roomId);
      if (subscriptionId == null) {
        AppLogger.warning(
          'Cannot send read receipts: profile not in room',
          data: {'roomId': roomId},
        );
        return;
      }

      // For read receipts, we send the latest message ID as upToEventId
      // This marks all messages up to and including this one as read
      if (messageIds.isEmpty) return;

      final latestMessageId = messageIds.last; // Assuming messages are ordered

      // Create read marker event
      final readEvent = pb.ReadMarker(
        subscriptionId: subscriptionId,
        roomId: roomId,
        upToEventId: latestMessageId,
      );

      // Wrap in ClientCommand
      final command = pb.ClientCommand(readMarker: readEvent);

      // Send via gateway stream (same connection as messages)
      final request = pb.StreamRequest(command: command);
      _gatewayClient.stream(Stream.value(request));

      AppLogger.debug(
        'Read receipt sent',
        data: {'roomId': roomId, 'upToEventId': latestMessageId},
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to send read receipts',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Send message immediately through live connection
  /// Falls back to job queue if connection is not available
  Future<void> sendMessageDirect(domain.RoomEvent event) async {
    if (!_isConnected) {
      throw Exception('Not connected to server');
    }

    try {
      // Get current profile's subscription ID for this room
      final subscriptionId = await getCurrentSubscriptionId(event.roomId);
      if (subscriptionId == null) {
        throw Exception('Profile not in room');
      }

      // Create timestamp
      final now = DateTime.now();
      final timestamp = common_types.Timestamp.fromDateTime(now);

      // Create payload based on event type
      final pbPayload = pb.Payload();
      switch (event.type) {
        case domain.RoomEventType.text:
          final textContent = event.content['text'] as String? ?? '';
          pbPayload.text = pb.TextContent(body: textContent);
          break;
        case domain.RoomEventType.image:
          final imageUrl = event.content['url'] as String? ?? '';
          final imageData = {'url': imageUrl, 'type': 'image'};
          pbPayload.text = pb.TextContent(body: imageData.toString());
          break;
        case domain.RoomEventType.file:
          final fileUrl = event.content['url'] as String? ?? '';
          final fileName = event.content['name'] as String? ?? '';
          final fileData = {'url': fileUrl, 'name': fileName, 'type': 'file'};
          pbPayload.text = pb.TextContent(body: fileData.toString());
          break;
        default:
          throw Exception('Unsupported event type: ${event.type}');
      }

      // Create room event
      final roomEvent = pb.RoomEvent(
        id: event.localId ?? event.id,
        roomId: event.roomId,
        subscriptionId: subscriptionId,
        type: _mapLocalEventTypeToProto(event.type),
        sentAt: timestamp,
        payload: pbPayload,
      );

      // Wrap in ClientCommand
      final command = pb.ClientCommand(event: roomEvent);

      // Send via gateway stream
      final request = pb.StreamRequest(command: command);
      _gatewayClient.stream(Stream.value(request));

      // Update local message status to sent
      await _messageRepo.updateMessageStatus(event.id, domain.EventStatus.sent);

      AppLogger.debug(
        'Message sent via live connection',
        data: {'eventId': event.id, 'roomId': event.roomId},
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to send message via live connection',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow; // Re-throw so caller can handle fallback
    }
  }
}
