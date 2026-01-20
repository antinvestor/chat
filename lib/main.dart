import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app/router.dart';
import 'core/error/error_tracking_service.dart';
import 'core/logging/app_logger.dart';
import 'core/networking/connectivity_service.dart';
import 'core/sync/background_sync_task.dart';
import 'core/sync/sync_engine.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/notifications/notification_service.dart';

/// Sentry DSN - should be configured via environment variable in production
const String _sentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue: '',
);

/// Type-safe wrapper for user info from OIDC token
class _UserInfo {
  final String id;
  final String? email;
  final String? username;

  _UserInfo({required this.id, this.email, this.username});

  /// Parse user info from OIDC token claims
  factory _UserInfo.fromOidcClaims(Map<String, dynamic> claims) {
    return _UserInfo(
      id: claims['sub'] as String? ?? 'unknown',
      email: claims['email'] as String?,
      username: claims['preferred_username'] as String?,
    );
  }
}

/// Background task callback - must be top-level function
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    AppLogger.info('Workmanager executing task', data: {'task': task});

    try {
      // Run background sync
      final success = await BackgroundSyncTask.run();
      AppLogger.info(
        'Workmanager task completed',
        data: {'task': task, 'success': success},
      );
      return success;
    } catch (e, stackTrace) {
      AppLogger.error(
        'Workmanager task failed',
        error: e,
        stackTrace: stackTrace,
        data: {'task': task},
      );
      return false;
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize error tracking with Sentry
  if (_sentryDsn.isNotEmpty) {
    await ErrorTrackingService.initialize(
      dsn: _sentryDsn,
      tracesSampleRate: kReleaseMode ? 0.2 : 1.0,
      appRunner: () => _initializeAndRun(),
    );
  } else {
    // Run without Sentry if DSN not configured
    AppLogger.warning('Sentry DSN not configured, error tracking disabled');
    await _initializeAndRun();
  }
}

/// Initialize app services and run the app
Future<void> _initializeAndRun() async {
  // Database is initialized lazily by Drift

  // Initialize Firebase (required for push notifications)
  final isMobile = Platform.isAndroid || Platform.isIOS;
  if (isMobile) {
    await Firebase.initializeApp();

    // Register background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    AppLogger.info('Firebase initialized');
  }

  // Initialize workmanager (only supported on Android and iOS)
  if (isMobile) {
    await Workmanager().initialize(callbackDispatcher);

    // Register periodic background sync (15 minutes)
    await Workmanager().registerPeriodicTask(
      'background-sync',
      'backgroundSync',
      frequency: const Duration(minutes: 15),
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  AppLogger.info(
    'Application starting',
    data: {
      'backgroundSyncRegistered': isMobile,
      'firebaseInitialized': isMobile,
      'errorTrackingEnabled': ErrorTrackingService.isInitialized,
    },
  );

  // Add breadcrumb for app start
  if (ErrorTrackingService.isInitialized) {
    await ErrorTrackingService.addBreadcrumb(
      message: 'App started',
      category: 'lifecycle',
      data: {'platform': Platform.operatingSystem},
    );
  }

  runApp(const ProviderScope(child: ChatApp()));
}

class ChatApp extends ConsumerStatefulWidget {
  const ChatApp({super.key});

  @override
  ConsumerState<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends ConsumerState<ChatApp> {
  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  /// Initialize app and check authentication
  Future<void> _initializeApp() async {
    final authRepo = ref.read(authRepositoryProvider);
    final isLoggedIn = await authRepo.isLoggedIn();

    if (isLoggedIn) {
      AppLogger.info('User is logged in, ensuring valid access token');

      // Ensure we have a valid access token (will refresh if expired)
      final token = await authRepo.ensureValidAccessToken();

      if (token == null) {
        // Token refresh failed, user needs to re-login
        AppLogger.warning(
          'Token refresh failed on app start, user needs to re-login',
        );
        return;
      }

      AppLogger.info(
        'Valid access token obtained, starting background services',
      );

      // Set user context for error tracking
      if (ErrorTrackingService.isInitialized) {
        final userInfoMap = await authRepo.getUserInfo();
        if (userInfoMap != null) {
          final userInfo = _UserInfo.fromOidcClaims(userInfoMap);
          await ErrorTrackingService.setUser(
            id: userInfo.id,
            email: userInfo.email,
            username: userInfo.username,
          );
          await ErrorTrackingService.addBreadcrumb(
            message: 'User authenticated',
            category: 'auth',
          );
        }
      }

      // Token refresh is now handled reactively by TokenManager on 401

      // Wait for network to be available before starting sync
      await _waitForNetwork();

      // Start sync engine (async)
      final syncEngine = await ref.read(syncEngineProvider.future);
      syncEngine.start();

      // Start connectivity monitoring for auto-sync on reconnection (async)
      final connectivityService = await ref.read(
        connectivityServiceProvider.future,
      );
      connectivityService.start();

      // Initialize push notifications (after auth is confirmed)
      if (NotificationService.isSupported) {
        final notificationService = ref.read(notificationServiceProvider);
        await notificationService.initialize();
      }
    } else {
      AppLogger.debug('Profile not logged in, skipping service initialization');
    }
  }

  /// Wait for network connectivity before proceeding
  Future<void> _waitForNetwork() async {
    final connectivity = Connectivity();
    var results = await connectivity.checkConnectivity();

    // Check if we have a connection
    bool hasConnection = results.any(
      (r) =>
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.ethernet,
    );

    if (!hasConnection) {
      AppLogger.info('Waiting for network connectivity...');
      // Wait for connectivity change
      await for (final results in connectivity.onConnectivityChanged) {
        hasConnection = results.any(
          (r) =>
              r == ConnectivityResult.wifi ||
              r == ConnectivityResult.mobile ||
              r == ConnectivityResult.ethernet,
        );
        if (hasConnection) {
          AppLogger.info('Network connectivity established');
          break;
        }
      }
    }

    // Small delay to ensure DNS is ready
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'AntInvestor Chat',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system, // Follow system theme
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
