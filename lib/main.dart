import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app/router.dart';
import 'core/logging/app_logger.dart';
import 'core/networking/connectivity_service.dart';
import 'core/sync/background_sync_task.dart';
import 'core/sync/sync_engine.dart';
import 'features/auth/data/auth_repository.dart';

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

  // Database is initialized lazily by Drift

  // Initialize workmanager (only supported on Android and iOS)
  final isMobile = Platform.isAndroid || Platform.isIOS;
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
    data: {'backgroundSyncRegistered': isMobile},
  );

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
