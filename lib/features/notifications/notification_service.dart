import 'dart:io' show Platform;

import 'package:antinvestor_api_common/antinvestor_api_common.dart'
    as common_pb;
import 'package:antinvestor_api_device/antinvestor_api_device.dart' as pb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../core/networking/client.dart';
import '../../core/storage/key_manager.dart';

/// Background message handler - must be top-level function
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Initialize Firebase if not already initialized
  await Firebase.initializeApp();

  AppLogger.info(
    'Background message received',
    data: {'messageId': message.messageId, 'data': message.data},
  );

  // Background handling is limited - just log for now
  // Full handling happens when app is opened
}

/// Provider for NotificationService
final notificationServiceProvider = Provider<NotificationService>(NotificationService.new);

/// Service for handling push notifications via Firebase Cloud Messaging
///
/// Manages:
/// - Firebase initialization
/// - FCM token retrieval and registration with backend
/// - Foreground notification handling
/// - Background notification handling
/// - Deep linking from notification taps
class NotificationService {

  NotificationService(this._ref);
  final Ref _ref;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _fcmToken;
  bool _initialized = false;

  /// Whether the notification service has been initialized
  bool get isInitialized => _initialized;

  /// Current FCM token (null if not yet retrieved)
  String? get fcmToken => _fcmToken;

  /// Initialize the notification service
  ///
  /// Should be called after Firebase.initializeApp() and user authentication.
  Future<void> initialize() async {
    if (_initialized) {
      AppLogger.debug('NotificationService already initialized');
      return;
    }

    try {
      // Request notification permissions
      final settings = await _requestPermissions();
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        AppLogger.warning('Notification permissions denied');
        return;
      }

      // Get and register FCM token
      await _retrieveAndRegisterToken();

      // Listen for token refresh
      _messaging.onTokenRefresh.listen(_onTokenRefresh);

      // Setup message handlers
      _setupMessageHandlers();

      _initialized = true;
      AppLogger.info('NotificationService initialized successfully');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to initialize NotificationService',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Request notification permissions from the user
  Future<NotificationSettings> _requestPermissions() async {
    final settings = await _messaging.requestPermission(
      
    );

    AppLogger.info(
      'Notification permission status',
      data: {'status': settings.authorizationStatus.name},
    );

    return settings;
  }

  /// Retrieve FCM token and register it with the backend
  Future<void> _retrieveAndRegisterToken() async {
    try {
      _fcmToken = await _messaging.getToken();

      if (_fcmToken == null) {
        AppLogger.warning('Failed to retrieve FCM token');
        return;
      }

      AppLogger.debug(
        'FCM token retrieved',
        data: {'tokenPrefix': _fcmToken!.substring(0, 20)},
      );

      await _registerTokenWithBackend(_fcmToken!);
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to retrieve/register FCM token',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Handle FCM token refresh
  Future<void> _onTokenRefresh(String newToken) async {
    AppLogger.info('FCM token refreshed');
    _fcmToken = newToken;
    await _registerTokenWithBackend(newToken);
  }

  /// Register the FCM token with the backend Device API
  Future<void> _registerTokenWithBackend(String token) async {
    try {
      final keyManager = _ref.read(keyManagerProvider);
      final deviceId = await keyManager.getDeviceId();
      final deviceClient = await _ref.read(deviceServiceClientProvider.future);

      // Create extras struct with the FCM token
      final extras = common_pb.Struct();
      extras.fields['token'] = common_pb.Value(stringValue: token);

      final request = pb.RegisterKeyRequest(
        deviceId: deviceId,
        keyType: pb.KeyType.FCM_TOKEN,
        extras: extras,
      );

      await deviceClient.registerKey(request);

      AppLogger.info(
        'FCM token registered with backend',
        data: {'deviceId': deviceId},
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to register FCM token with backend',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Setup message handlers for foreground and background
  void _setupMessageHandlers() {
    // Handle messages when app is in foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check for initial message (app opened from terminated state)
    _checkInitialMessage();
  }

  /// Check if app was opened from a notification when terminated
  Future<void> _checkInitialMessage() async {
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      AppLogger.info('App opened from terminated state via notification');
      _handleNotificationTap(initialMessage);
    }
  }

  /// Handle foreground message - show as local notification or update UI
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    AppLogger.info(
      'Foreground message received',
      data: {
        'messageId': message.messageId,
        'title': message.notification?.title,
        'body': message.notification?.body,
        'data': message.data,
      },
    );

    // For now, foreground messages are logged
    // TODO(antinvestor): Show as local notification using flutter_local_notifications
    // or update UI directly via state management
  }

  /// Handle notification tap - navigate to relevant screen
  void _handleNotificationTap(RemoteMessage message) {
    AppLogger.info(
      'Notification tapped',
      data: {'messageId': message.messageId, 'data': message.data},
    );

    // Extract room ID from notification data
    final roomId = message.data['roomId'] as String?;
    final roomName = message.data['roomName'] as String?;

    if (roomId != null) {
      _navigateToChat(roomId, roomName);
    }
  }

  /// Navigate to chat screen for a specific room
  void _navigateToChat(String roomId, String? roomName) {
    // Get the router from the provider
    // Note: This requires a navigation context, which we'll handle via a global key
    AppLogger.info(
      'Navigating to chat from notification',
      data: {'roomId': roomId, 'roomName': roomName},
    );

    // Deep link navigation will be handled by the app's navigation system
    // The route path is: /chat/:roomId?name=:roomName
  }

  /// Unregister FCM token from backend (call on logout)
  Future<void> unregisterToken() async {
    try {
      final keyManager = _ref.read(keyManagerProvider);
      final deviceId = await keyManager.getDeviceId();

      final deviceClient = await _ref.read(deviceServiceClientProvider.future);

      // Search for existing FCM key
      final searchRequest = pb.SearchKeyRequest(
        deviceId: deviceId,
        keyTypes: [pb.KeyType.FCM_TOKEN],
      );

      final searchResponse = await deviceClient.searchKey(searchRequest);

      // Deregister if found
      for (final key in searchResponse.data) {
        final deregisterRequest = pb.DeRegisterKeyRequest(id: key.id);
        await deviceClient.deRegisterKey(deregisterRequest);
      }

      _fcmToken = null;
      AppLogger.info('FCM token unregistered from backend');
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to unregister FCM token',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Check if notifications are supported on the current platform
  static bool get isSupported => Platform.isAndroid || Platform.isIOS;
}
