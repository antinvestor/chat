import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:antinvestor_api_chat/antinvestor_api_chat.dart' as pb;
import 'package:antinvestor_api_common/antinvestor_api_common.dart'
    as common_types;
import 'package:fixnum/fixnum.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/messages/data/message_providers.dart';
import '../../features/messages/data/message_repository.dart';
import '../../features/messages/data/read_receipt_repository.dart';
import '../../features/messages/domain/room_event.dart' as domain;
import '../../features/rooms/data/room_member_repository.dart';
import '../../features/rooms/data/room_subscription_service.dart';
import '../auth/token_refresh_coordinator.dart';
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
  final authRepo = ref.watch(authRepositoryProvider);
  final encryptionService = ref.watch(e2eEncryptionServiceProvider);
  final coordinator = ref.watch(tokenRefreshCoordinatorProvider);

  // Initialize encryption service
  await encryptionService.initialize();

  final engine = SyncEngine(
    gatewayClient,
    chatClient,
    ref.watch(messageRepositoryProvider),
    ref.watch(pendingJobRepositoryProvider),
    authRepo,
    ref.watch(roomMemberRepositoryProvider),
    ref.watch(roomSubscriptionServiceProvider),
    encryptionService,
    ref.watch(readReceiptRepositoryProvider),
    onTokenRefresh: () async {
      // Delegate ALL token refresh logic to the coordinator
      // This ensures consistent behavior across TokenManager, SyncEngine,
      // and TokenRefreshService
      AppLogger.debug(
        'SyncEngine: Token refresh requested, delegating to coordinator',
      );

      final result = await coordinator.refresh(source: 'SyncEngine');

      if (!result.success) {
        if (result.result == common_types.TokenRefreshResult.permanentError) {
          throw TokenRefreshPermanentError(
            result.error ?? 'User must re-authenticate',
          );
        }
        // Transient error - return null to signal retry later
        AppLogger.warning(
          'SyncEngine: Token refresh failed (transient)',
          data: {'error': result.error},
        );
        return null;
      }

      AppLogger.debug('SyncEngine: Token refresh successful via coordinator');
      return result.accessToken;
    },
  );

  // Register lifecycle observer
  engine._registerLifecycleObserver();

  // Cleanup on dispose
  ref.onDispose(engine.dispose);

  return engine;
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
/// - Pausing on app background and resuming on foreground
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
class SyncEngine with WidgetsBindingObserver {
  SyncEngine(
    this._gatewayClient,
    this._chatClient,
    this._messageRepo,
    this._jobRepo,
    this._authRepository,
    this._roomMemberRepository,
    this._subscriptionService,
    this._encryptionService,
    this._readReceiptRepo, {
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
  final ReadReceiptRepository _readReceiptRepo;
  final TokenRefreshCallback? _onTokenRefresh;

  StreamSubscription? _connectSubscription;
  StreamSubscription<List<domain_job.PendingJob>>? _jobWatchSubscription;
  bool _isUploading = false;
  bool _isConnected = false;
  bool _shouldStop = false; // Flag to stop the download loop
  bool _isPaused = false; // Flag to track if paused due to app lifecycle
  int _reconnectAttempts = 0;
  int _authErrorCount = 0; // Track consecutive auth errors

  // Lock to prevent multiple concurrent connection attempts
  Completer<void>? _connectionLock;

  // Random for jitter in reconnection backoff
  final _random = Random();

  // Controller for bidirectional stream requests
  // This keeps the stream open so we can send multiple messages (hello, typing, receipts, etc.)
  StreamController<pb.StreamRequest>? _requestController;

  // Completer for graceful stop/start coordination
  Completer<void>? _stopCompleter;
  bool _isLifecycleObserverRegistered = false;

  // Configuration
  static const _maxAuthErrors = 3; // Max auth errors before giving up
  static const _streamReadTimeout = Duration(seconds: 60); // Read timeout

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

  /// Get current connection state synchronously
  SyncConnectionState get currentConnectionState => _isConnected
      ? SyncConnectionState.connected
      : SyncConnectionState.disconnected;

  // Exponential backoff configuration
  static const _initialBackoffMs = 1000; // 1 second
  static const _maxBackoffMs = 30000; // 30 seconds
  static const _maxReconnectAttempts = 5;

  // Room member sync cache to avoid redundant syncs
  final Map<String, DateTime> _roomMemberSyncCache = {};
  static const _roomMemberSyncCacheDuration = Duration(minutes: 5);

  /// Register the lifecycle observer
  void _registerLifecycleObserver() {
    if (!_isLifecycleObserverRegistered) {
      WidgetsBinding.instance.addObserver(this);
      _isLifecycleObserverRegistered = true;
      AppLogger.debug('SyncEngine: Lifecycle observer registered');
    }
  }

  /// Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _onAppResumed();
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _onAppBackgrounded();
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        // App is being destroyed or hidden
        break;
    }
  }

  /// Called when app comes to foreground
  void _onAppResumed() {
    if (_isPaused) {
      AppLogger.info('SyncEngine: App resumed, restarting sync');
      _isPaused = false;
      start();
    }
  }

  /// Called when app goes to background
  void _onAppBackgrounded() {
    // Stop sync if connected OR if currently attempting to connect
    // This prevents wasting resources on connection attempts while backgrounded
    if (!_isPaused && (_isConnected || _connectionLock != null)) {
      AppLogger.info('SyncEngine: App backgrounded, pausing sync');
      _isPaused = true;
      stop();
    }
  }

  void start() {
    // Don't start if paused due to app lifecycle
    if (_isPaused) {
      AppLogger.debug('SyncEngine: Ignoring start() while paused');
      return;
    }

    _shouldStop = false;
    _startDownloadLoop();
    _startUploadLoop();
  }

  /// Stop the sync engine and wait for it to fully stop
  Future<void> stopAsync() async {
    if (_stopCompleter != null) {
      // Already stopping, wait for completion
      await _stopCompleter!.future;
      return;
    }

    _stopCompleter = Completer<void>();
    _shouldStop = true;

    _connectSubscription?.cancel();
    _connectSubscription = null;
    _jobWatchSubscription?.cancel();
    _jobWatchSubscription = null;
    _isConnected = false;

    // Small delay to ensure loops have exited
    await Future.delayed(const Duration(milliseconds: 100));

    _stopCompleter?.complete();
    _stopCompleter = null;
  }

  void stop() {
    _shouldStop = true; // Signal download loop to stop
    _connectSubscription?.cancel();
    _connectSubscription = null;
    _jobWatchSubscription?.cancel();
    _jobWatchSubscription = null;
    _isConnected = false;

    // Close the request controller to end the bidirectional stream gracefully
    _requestController?.close();
    _requestController = null;

    // Release connection lock if held
    if (_connectionLock != null && !_connectionLock!.isCompleted) {
      _connectionLock!.complete();
    }
    _connectionLock = null;

    // Note: Don't close broadcast stream controllers here as they may be reused
    // They will be closed when the engine is disposed
  }

  /// Permanently dispose of the sync engine (call only when no longer needed)
  void dispose() {
    // Unregister lifecycle observer
    if (_isLifecycleObserverRegistered) {
      WidgetsBinding.instance.removeObserver(this);
      _isLifecycleObserverRegistered = false;
    }

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
    // Prevent multiple concurrent connection attempts
    if (_connectionLock != null) {
      AppLogger.debug('Connection attempt already in progress, skipping');
      return;
    }
    if (_isConnected || _shouldStop) return;

    // Acquire connection lock
    _connectionLock = Completer<void>();

    _connectionStateController.add(SyncConnectionState.connecting);

    // Run connection loop in a way that doesn't block the main thread
    while (!_shouldStop) {
      try {
        // Create a StreamController for bidirectional communication
        // This stays open so we can send multiple requests (hello, typing, receipts, etc.)
        _requestController = StreamController<pb.StreamRequest>();

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
        final helloRequest = pb.StreamRequest(hello: hello);

        // Send hello as the first message
        _requestController!.add(helloRequest);

        // Don't pass manual headers - let the interceptor handle authorization
        // This ensures token refresh works correctly on 401
        // Use the controller's stream which stays open for bidirectional communication
        final stream = _gatewayClient.stream(_requestController!.stream);
        _isConnected = true;
        _reconnectAttempts = 0;
        _authErrorCount = 0; // Reset auth error count on successful connection
        _connectionStateController.add(SyncConnectionState.connected);

        // Process stream events with timeout to detect stalled connections
        await _processStreamWithTimeout(stream);
      } catch (e, stackTrace) {
        final errorStr = e.toString().toLowerCase();
        final isAuthError = _isAuthenticationError(errorStr);
        final isNormalDisconnect = _isNormalDisconnect(errorStr);
        final isTimeout = e is TimeoutException;

        // Log appropriately based on error type
        if (isNormalDisconnect) {
          // Normal server disconnection - just log as debug, will auto-reconnect
          AppLogger.debug('Sync connection closed by server, will reconnect');
        } else if (isTimeout) {
          AppLogger.warning(
            'Sync connection timed out (no data for ${_streamReadTimeout.inSeconds}s), reconnecting',
          );
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
                _reconnectAttempts = 0;
                _authErrorCount = 0; // Reset on successful refresh
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
          // Not an auth error, reset auth error count after successful backoff
          _authErrorCount = 0;
        }
      } finally {
        _isConnected = false;
        _connectionStateController.add(SyncConnectionState.disconnected);

        // Close the request controller to clean up resources
        await _requestController?.close();
        _requestController = null;
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

    // Release connection lock when loop exits
    _connectionLock?.complete();
    _connectionLock = null;
  }

  /// Process stream events with a timeout to detect stalled connections
  ///
  /// Uses Stream.timeout() for proper timeout detection - this triggers
  /// even when no messages arrive (unlike manual checks which only run
  /// when messages are received).
  Future<void> _processStreamWithTimeout(
    Stream<pb.StreamResponse> stream,
  ) async {
    // Use Stream.timeout() for proper timeout detection
    // This will throw TimeoutException if no data arrives within the timeout
    final timedStream = stream.timeout(
      _streamReadTimeout,
      onTimeout: (sink) {
        sink.addError(
          TimeoutException(
            'No data received for ${_streamReadTimeout.inSeconds} seconds',
          ),
        );
        sink.close();
      },
    );

    // Process messages sequentially to maintain order and prevent queue overflow
    // Using await for ensures backpressure - we won't accept new messages
    // until the current one is processed
    await for (final response in timedStream) {
      // Check if we should stop
      if (_shouldStop) {
        AppLogger.debug('Stop requested during stream processing');
        break;
      }

      // Reset auth error count on successful data receipt
      _authErrorCount = 0;

      // Process synchronously to maintain message order
      // This also provides natural backpressure
      try {
        await _handleConnectResponse(response);
      } catch (e, stackTrace) {
        AppLogger.error(
          'Error handling stream response',
          error: e,
          stackTrace: stackTrace,
        );
        // Continue processing other messages even if one fails
      }
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
    // Add jitter (0-25% of delay) to prevent thundering herd
    final jitter = (_random.nextDouble() * 0.25 * delay).toInt();
    return Duration(milliseconds: delay + jitter);
  }

  /// Send a request through the bidirectional stream
  ///
  /// Returns true if the request was sent, false if not connected
  bool _sendRequest(pb.StreamRequest request) {
    final controller = _requestController;
    if (controller == null || controller.isClosed) {
      AppLogger.warning(
        'Cannot send request: stream not connected',
        data: {'hasController': controller != null},
      );
      return false;
    }

    try {
      controller.add(request);
      return true;
    } catch (e) {
      AppLogger.error('Failed to send request through stream', error: e);
      return false;
    }
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

    // Note: Deduplication is handled by the database's unique constraint on event ID
    // XIDs provide natural ordering, so we rely on the DB for both ordering and uniqueness

    // Extract content from typed payload fields
    var content = <String, dynamic>{};
    var isRoomKeyEvent = false;
    if (event.hasPayload()) {
      final payload = event.payload;
      if (payload.hasText()) {
        final textBody = payload.text.body;
        // Check if this is a roomKey event (session key sharing for E2EE)
        if (textBody.startsWith('{"type":"roomKey"') ||
            textBody.contains('"algorithm":"megolm')) {
          try {
            final keyData = jsonDecode(textBody) as Map<String, dynamic>;
            if (keyData['type'] == 'roomKey' ||
                keyData['algorithm'] == 'megolm.v1') {
              // Process the session key
              await _processRoomKeyEvent(keyData, event.roomId);
              isRoomKeyEvent = true;
              content = {
                'type': 'roomKey',
                'processed': true,
                'sessionId': keyData['sessionId'],
              };
            }
          } catch (e) {
            // Not a valid JSON roomKey, treat as regular text
            AppLogger.debug('Text is not a roomKey event: $e');
          }
        }
        if (!isRoomKeyEvent) {
          content = {'text': textBody};
        }
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
          // Convert ciphertext bytes to base64 string for decryption
          final ciphertext = base64Encode(encrypted.ciphertext);
          final sessionId = encrypted.sessionId;
          // Use sender's subscription ID as sender key for session lookup
          final senderKey = event.hasSubscriptionId()
              ? event.subscriptionId
              : '';

          // senderKey is required for E2EE decryption
          if (senderKey.isEmpty) {
            AppLogger.warning(
              'Encrypted message missing sender info',
              data: {'roomId': event.roomId, 'sessionId': sessionId},
            );
            content = {
              'text': '[Unable to decrypt - unknown sender]',
              'encrypted': true,
              'decrypted': false,
              'error': 'missing_sender_key',
            };
          } else if (_encryptionService.hasInboundSession(
            event.roomId,
            senderKey,
          )) {
            // Try to get the inbound session for this room/sender
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
            AppLogger.debug(
              'Message decrypted',
              data: {'roomId': event.roomId, 'sessionId': sessionId},
            );
          } else {
            // Need to request session key from sender
            AppLogger.warning(
              'Missing session key for decryption',
              data: {
                'roomId': event.roomId,
                'sessionId': sessionId,
                'senderKey': senderKey,
              },
            );
            content = {
              'text': '[Unable to decrypt - missing session key]',
              'encrypted': true,
              'decrypted': false,
              'sessionId': sessionId,
              'senderKey': senderKey,
            };
          }
        } catch (e, stackTrace) {
          AppLogger.error(
            'Decryption failed',
            error: e,
            stackTrace: stackTrace,
          );
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

    // Extract sender subscription ID directly from server event
    // senderId stores the subscription ID, not profile ID
    // Profile ID can be looked up via RoomMembers when needed for display
    final subscriptionId = event.hasSubscriptionId()
        ? event.subscriptionId
        : '';

    // Optionally get contact ID for the sender (for additional context)
    String? senderContactId;
    if (subscriptionId.isNotEmpty) {
      final member = await _roomMemberRepository.getSubscription(
        subscriptionId,
      );
      senderContactId = member?.contactId;
    }

    final roomEvent = domain.RoomEvent(
      id: event.id,
      roomId: event.roomId,
      senderId: subscriptionId, // Store subscription ID directly
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
    final eventIds = event.eventId.toList();
    if (eventIds.isEmpty) return;

    // Get the subscription ID of the reader
    final subscriptionId = event.hasSubscriptionId()
        ? event.subscriptionId
        : null;

    // Get the room ID from one of the events (for storing receipts)
    String? roomId;
    String? readerProfileId;

    if (subscriptionId != null) {
      // Look up the profile ID from the subscription
      final member = await _roomMemberRepository.getSubscription(
        subscriptionId,
      );
      if (member != null) {
        roomId = member.roomId;
        readerProfileId = member.profileId;
      }
    }

    // If we have reader info, store read receipts
    if (roomId != null && readerProfileId != null) {
      final readAt = DateTime.now().millisecondsSinceEpoch;
      for (final eventId in eventIds) {
        await _readReceiptRepo.saveReadReceipt(
          eventId: eventId,
          roomId: roomId,
          profileId: readerProfileId,
          readAt: readAt,
        );
      }

      // Mark messages as read (since someone read them)
      await _messageRepo.updateMessagesStatus(
        eventIds,
        domain.EventStatus.read,
      );

      AppLogger.debug(
        'Processed read receipts',
        data: {
          'eventCount': eventIds.length,
          'reader': readerProfileId.substring(0, 8),
        },
      );
    } else {
      // Fall back to delivered status if we can't identify the reader
      await _messageRepo.updateMessagesStatus(
        eventIds,
        domain.EventStatus.delivered,
      );
    }
  }

  /// Process a roomKey event containing E2EE session key data
  ///
  /// When another user shares their Megolm session key with us, we need to
  /// add it as an inbound session so we can decrypt their messages.
  Future<void> _processRoomKeyEvent(
    Map<String, dynamic> keyData,
    String eventRoomId,
  ) async {
    try {
      final roomId = keyData['roomId'] as String? ?? eventRoomId;
      final sessionId = keyData['sessionId'] as String?;
      final sessionKey = keyData['sessionKey'] as String?;
      final senderKey = keyData['senderKey'] as String?;

      if (sessionId == null || sessionKey == null || senderKey == null) {
        AppLogger.warning(
          'Invalid roomKey event: missing required fields',
          data: {
            'hasSessionId': sessionId != null,
            'hasSessionKey': sessionKey != null,
            'hasSenderKey': senderKey != null,
          },
        );
        return;
      }

      // Add the session key as an inbound group session
      await _encryptionService.addInboundGroupSession(
        roomId,
        sessionId,
        sessionKey,
        senderKey: senderKey,
      );

      AppLogger.info(
        'Received and stored session key',
        data: {
          'roomId': roomId,
          'sessionId': sessionId,
          'senderKey': senderKey.substring(0, 8),
        },
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to process roomKey event',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _startUploadLoop() {
    // Cancel existing subscription to prevent multiple watchers
    _jobWatchSubscription?.cancel();

    if (_shouldStop) return;

    // Use reactive database watching instead of polling
    _jobWatchSubscription = _jobRepo.watchPendingJobs().listen(
      (jobs) async {
        // Only process if connected and not already uploading
        if (_isUploading || !_isConnected || _shouldStop) return;
        if (jobs.isEmpty) return;

        _isUploading = true;
        AppLogger.debug(
          'Processing pending jobs',
          data: {'count': jobs.length},
        );

        try {
          // Process jobs sequentially to avoid overwhelming the server
          for (final job in jobs) {
            if (_shouldStop || !_isConnected) break;

            try {
              await _processJob(job);
            } catch (e, stackTrace) {
              AppLogger.error(
                'Error processing job',
                error: e,
                stackTrace: stackTrace,
                data: {'jobId': job.id, 'jobType': job.type.toString()},
              );
            }
          }
        } catch (e, stackTrace) {
          // Log but don't crash
          AppLogger.error(
            'Upload loop error',
            error: e,
            stackTrace: stackTrace,
          );
        } finally {
          _isUploading = false;
        }
      },
      onError: (Object e, StackTrace stackTrace) {
        AppLogger.error(
          'Job watch stream error',
          error: e,
          stackTrace: stackTrace,
        );
      },
    );
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
        case domain_job.JobType.updateRoomAvatar:
          // Avatar updates are included in updateRoom job
          await _processUpdateRoom(job);
          break;
        case domain_job.JobType.updateRoomPermissions:
          // Permission updates are included in updateRoom job
          await _processUpdateRoom(job);
          break;
        case domain_job.JobType.changeMemberRole:
          await _processChangeMemberRole(job);
          break;
        case domain_job.JobType.forwardMessage:
          await _processForwardMessage(job);
          break;
        case domain_job.JobType.custom:
          // Custom jobs are handled by their respective services
          break;
        case domain_job.JobType.createInviteLink:
        case domain_job.JobType.revokeInviteLink:
        case domain_job.JobType.useInviteLink:
        case domain_job.JobType.approveJoinRequest:
        case domain_job.JobType.rejectJoinRequest:
          // Invite link jobs are handled by InviteLinkService
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
    final roomId = payload['id'] as String;

    final request = pb.UpdateRoomRequest(
      roomId: roomId,
      name: payload['name'] as String? ?? '',
      topic: payload['description'] as String? ?? '',
    );

    // Build metadata including avatar and permissions if present
    final metadataMap = <String, dynamic>{};
    if (payload['metadata'] != null) {
      metadataMap.addAll(payload['metadata'] as Map<String, dynamic>);
    }
    if (payload['avatarUrl'] != null) {
      metadataMap['avatarUrl'] = payload['avatarUrl'];
    }
    if (payload['editInfoPermission'] != null) {
      metadataMap['editInfoPermission'] = payload['editInfoPermission'];
    }
    if (payload['sendMessagesPermission'] != null) {
      metadataMap['sendMessagesPermission'] = payload['sendMessagesPermission'];
    }
    if (payload['addMembersPermission'] != null) {
      metadataMap['addMembersPermission'] = payload['addMembersPermission'];
    }

    if (metadataMap.isNotEmpty) {
      request.metadata = _mapToStruct(metadataMap);
    }

    await _chatClient.updateRoom(request);
    AppLogger.info('Room updated on server', data: {'roomId': roomId});
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

  Future<void> _processChangeMemberRole(domain_job.PendingJob job) async {
    final payload = job.payload;
    final roomId = payload['roomId'] as String?;
    final subscriptionId = payload['subscriptionId'] as String?;
    final newRole = payload['role'] as String?;

    if (roomId == null || subscriptionId == null || newRole == null) {
      AppLogger.error(
        'Invalid payload for changeMemberRole job',
        data: {'jobId': job.id},
      );
      return;
    }

    // Update the role locally (already done in RoomService.changeMemberRole)
    // The server sync can be handled via UpdateRoomSubscription API when available
    // For now, log the role change request
    AppLogger.info(
      'Member role change queued for sync',
      data: {
        'roomId': roomId,
        'subscriptionId': subscriptionId,
        'newRole': newRole,
      },
    );

    // TODO: Add server API call when backend supports role changes
    // Example: await _chatClient.updateRoomSubscription(request);
  }

  Future<void> _processLeaveRoom(domain_job.PendingJob job) async {
    final payload = job.payload;
    final roomId = payload['id'] as String;

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
    } else if (localType == domain.RoomEventType.roomKey) {
      // Room key events are sent as JSON-encoded text for key sharing
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

  Future<void> _processForwardMessage(domain_job.PendingJob job) async {
    final payload = job.payload;
    final originalMessageId = payload['originalMessageId'] as String;
    final destinationRoomId = payload['destinationRoomId'] as String;
    final localId = payload['localId'] as String?;
    final currentProfileId = await _authRepository.getCurrentProfileId();

    // Get original message content
    final content = payload['content'] as Map<String, dynamic>;
    final localType = domain.RoomEventType.values.firstWhere(
      (t) => t.toString() == payload['type'],
      orElse: () => domain.RoomEventType.text,
    );
    final protoType = _mapLocalEventTypeToProto(localType);

    // Build event with forwarded content
    final timestamp = common_types.Timestamp.fromDateTime(DateTime.now());
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
      id: localId ?? '',
      roomId: destinationRoomId,
      type: protoType,
      sentAt: timestamp,
      payload: pbPayload,
    );

    final request = pb.SendEventRequest(event: [event]);
    final response = await _chatClient.sendEvent(request);

    // Update local message with server ID
    if (localId != null && response.ack.isNotEmpty) {
      final ackEventId = response.ack.first.eventId;
      final updatedEvent = domain.RoomEvent(
        id: ackEventId.first,
        roomId: destinationRoomId,
        senderId: currentProfileId ?? 'unknown',
        type: localType,
        content: content,
        status: domain.EventStatus.sent,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        localId: localId,
        forwardedFromEvent: originalMessageId,
      );
      await _messageRepo.insertMessage(updatedEvent);
    }

    AppLogger.info(
      'Forward message synced',
      data: {
        'originalMessageId': originalMessageId,
        'destinationRoomId': destinationRoomId,
      },
    );
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
      case domain.RoomEventType.roomKey:
        // Room key events are sent as encrypted messages for key exchange
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
  ///
  /// @param roomId The room to get subscription for
  /// @param syncIfMissing If true, sync room members when subscription not found
  /// @param maxRetries Number of sync attempts before giving up (only used if syncIfMissing)
  Future<String?> getCurrentSubscriptionId(
    String roomId, {
    bool syncIfMissing = false,
    int maxRetries = 2,
  }) async {
    final currentProfileId = await _authRepository.getCurrentProfileId();
    final currentContactId = await _authRepository.getCurrentContactId();
    if (currentContactId == null) return null;

    // First attempt - check local database
    var subscriptionId = await _roomMemberRepository.getCurrentSubscriptionId(
      roomId,
      currentProfileId ?? '', // Empty string for anonymous subscriptions
      currentContactId,
    );

    if (subscriptionId != null) {
      return subscriptionId;
    }

    // Subscription not found - try syncing if enabled
    if (!syncIfMissing) {
      return null;
    }

    AppLogger.debug(
      'Subscription not found locally, attempting sync',
      data: {'roomId': roomId, 'maxRetries': maxRetries},
    );

    // Sync and retry
    for (var retry = 0; retry < maxRetries; retry++) {
      try {
        await _syncRoomMembersIfNeeded(roomId, forceSync: retry > 0);

        subscriptionId = await _roomMemberRepository.getCurrentSubscriptionId(
          roomId,
          currentProfileId ?? '',
          currentContactId,
        );

        if (subscriptionId != null) {
          AppLogger.info(
            'Subscription found after sync',
            data: {'roomId': roomId, 'attempt': retry + 1},
          );
          return subscriptionId;
        }
      } catch (e, stackTrace) {
        AppLogger.warning(
          'Room member sync failed',
          data: {'roomId': roomId, 'attempt': retry + 1, 'error': e.toString()},
        );
        if (retry == maxRetries - 1) {
          AppLogger.error(
            'All sync attempts failed',
            error: e,
            stackTrace: stackTrace,
            data: {'roomId': roomId},
          );
        }
      }
    }

    return null;
  }

  /// Sync room members from server if not recently synced
  ///
  /// @param roomId The room to sync members for
  /// @param forceSync If true, sync even if recently synced
  Future<void> _syncRoomMembersIfNeeded(
    String roomId, {
    bool forceSync = false,
  }) async {
    // Check cache
    if (!forceSync) {
      final lastSync = _roomMemberSyncCache[roomId];
      if (lastSync != null) {
        final elapsed = DateTime.now().difference(lastSync);
        if (elapsed < _roomMemberSyncCacheDuration) {
          AppLogger.debug(
            'Skipping room member sync - recently synced',
            data: {
              'roomId': roomId,
              'elapsedSeconds': elapsed.inSeconds,
              'cacheSeconds': _roomMemberSyncCacheDuration.inSeconds,
            },
          );
          return;
        }
      }
    }

    // Perform sync
    await _syncRoomMembers(roomId);

    // Update cache
    _roomMemberSyncCache[roomId] = DateTime.now();
  }

  /// Sync room members from server
  ///
  /// @param roomId The room to sync members for
  Future<void> _syncRoomMembers(String roomId) async {
    try {
      // Create request to search room subscriptions
      final request = pb.SearchRoomSubscriptionsRequest(roomId: roomId);

      // Fetch subscriptions from API
      final response = await _chatClient.searchRoomSubscriptions(request);

      var memberCount = 0;

      // Process each subscription from the response
      for (final subscription in response.members) {
        // Extract subscription ID from API response
        final subscriptionId = subscription.id;

        // Extract profileId and contactId from ContactLink
        final profileId =
            subscription.hasMember() && subscription.member.hasProfileId()
            ? subscription.member.profileId
            : null;
        final contactId =
            subscription.hasMember() && subscription.member.hasContactId()
            ? subscription.member.contactId
            : null;

        // Extract role (use first role if multiple, or null)
        final role = subscription.roles.isNotEmpty
            ? subscription.roles.first
            : null;

        // Note: joinedAt is available via subscription.joinedAt but
        // createSubscription uses current timestamp for simplicity

        // Insert or update room member using repository
        await _roomMemberRepository.createSubscription(
          subscriptionId: subscriptionId,
          roomId: subscription.roomId,
          profileId: profileId,
          contactId: contactId,
          role: role,
        );

        memberCount++;
      }

      AppLogger.info(
        'Room members synced via SyncEngine',
        data: {'roomId': roomId, 'memberCount': memberCount},
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to sync room members',
        error: e,
        stackTrace: stackTrace,
        data: {'roomId': roomId},
      );
      rethrow;
    }
  }

  /// Public method to sync room members for a specific room
  /// Can be called by external services when needed
  Future<void> syncRoomMembers(String roomId, {bool forceSync = false}) async {
    await _syncRoomMembersIfNeeded(roomId, forceSync: forceSync);
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
  ///
  /// If subscription is not found locally, attempts to sync room members
  /// and retry before giving up.
  Future<void> sendTyping(String roomId, bool isTyping) async {
    try {
      // Get current profile's subscription ID with sync fallback
      final subscriptionId = await getCurrentSubscriptionId(
        roomId,
        syncIfMissing: true,
        maxRetries: 1, // Single retry for typing (low priority)
      );

      if (subscriptionId == null) {
        // Even after sync, subscription not found - user may not be in room
        AppLogger.debug(
          'Cannot send typing event: subscription not found after sync',
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

      // Send via existing bidirectional stream
      final request = pb.StreamRequest(command: command);
      if (_sendRequest(request)) {
        AppLogger.debug(
          'Typing event sent',
          data: {'roomId': roomId, 'typing': isTyping},
        );
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to send typing event',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Send read receipts for messages
  ///
  /// If subscription is not found locally, attempts to sync room members
  /// and retry before giving up.
  Future<void> sendReadReceipts(String roomId, List<String> messageIds) async {
    try {
      // Get current profile's subscription ID with sync fallback
      final subscriptionId = await getCurrentSubscriptionId(
        roomId,
        syncIfMissing: true,
        maxRetries: 1, // Single retry for read receipts (low priority)
      );

      if (subscriptionId == null) {
        // Even after sync, subscription not found - user may not be in room
        AppLogger.debug(
          'Cannot send read receipts: subscription not found after sync',
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

      // Send via existing bidirectional stream
      final request = pb.StreamRequest(command: command);
      if (_sendRequest(request)) {
        AppLogger.debug(
          'Read receipt sent',
          data: {'roomId': roomId, 'upToEventId': latestMessageId},
        );
      }
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
  ///
  /// If subscription is not found locally, attempts to sync room members
  /// and retry before failing.
  Future<void> sendMessageDirect(domain.RoomEvent event) async {
    if (!_isConnected) {
      throw Exception('Not connected to server');
    }

    try {
      // Get current profile's subscription ID with sync fallback
      final subscriptionId = await getCurrentSubscriptionId(
        event.roomId,
        syncIfMissing: true,
      );

      if (subscriptionId == null) {
        throw Exception('Subscription not found for room ${event.roomId}');
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

      // Send via existing bidirectional stream
      final request = pb.StreamRequest(command: command);
      if (!_sendRequest(request)) {
        throw Exception('Failed to send message: stream not connected');
      }

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
