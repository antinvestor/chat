import 'dart:io' as io;

import 'package:antinvestor_api_profile/antinvestor_api_profile.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:connectrpc/io.dart' as connect_io;
import 'package:connectrpc/protobuf.dart' as connect_protobuf;
import 'package:connectrpc/protocol/connect.dart' as connect_protocol;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/db/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/networking/api_config.dart';
import '../../../core/settings/settings_service.dart';
import '../data/roster_repository.dart';
import 'contact_sync_service.dart';

/// Unique task name for contact sync background task
const contactSyncTaskName = 'contact-sync';

/// Unique task identifier for contact sync background task
const contactSyncTaskIdentifier = 'contactSync';

/// Contact sync background task
///
/// This task runs periodically (every 24 hours by default) to sync contacts.
/// It uses workmanager for scheduling and runs even when the app is closed.
class ContactBackgroundSyncTask {
  /// Main entry point for background contact sync
  ///
  /// Returns true if sync completed successfully, false otherwise.
  /// This is called by the Workmanager callback dispatcher.
  static Future<bool> run() async {
    try {
      AppLogger.info('[ContactBackgroundSync] Starting background sync task');
      final stopwatch = Stopwatch()..start();

      // Initialize database
      final database = AppDatabase.instance;
      final settingsService = SettingsService(database);
      await settingsService.initialize();

      // Check if auto sync is enabled
      final autoSyncEnabled = settingsService.getBool(
        ContactSyncSettings.autoSyncEnabled,
        defaultValue: ContactSyncDefaults.autoSyncEnabled,
      );

      if (!autoSyncEnabled) {
        AppLogger.debug('[ContactBackgroundSync] Auto sync disabled, skipping');
        return true; // Not a failure, just disabled
      }

      // Check if sync is due
      final lastSyncTimestamp = settingsService.getInt(
        ContactSyncSettings.lastSyncTime,
      );
      final syncIntervalHours = settingsService.getInt(
        ContactSyncSettings.syncIntervalHours,
        defaultValue: ContactSyncDefaults.syncIntervalHours,
      );

      if (lastSyncTimestamp > 0) {
        final lastSync = DateTime.fromMillisecondsSinceEpoch(lastSyncTimestamp);
        final nextSyncTime = lastSync.add(Duration(hours: syncIntervalHours));
        if (DateTime.now().isBefore(nextSyncTime)) {
          AppLogger.debug(
            '[ContactBackgroundSync] Sync not due yet',
            data: {
              'lastSync': lastSync.toIso8601String(),
              'nextSyncTime': nextSyncTime.toIso8601String(),
            },
          );
          return true; // Not a failure, just not due
        }
      }

      // Check Wi-Fi only setting
      final syncOnlyOnWifi = settingsService.getBool(
        ContactSyncSettings.syncOnlyOnWifi,
      );

      if (syncOnlyOnWifi) {
        final connectivity = Connectivity();
        final results = await connectivity.checkConnectivity();
        final hasWifi = results.any((r) => r == ConnectivityResult.wifi);

        if (!hasWifi) {
          AppLogger.debug(
            '[ContactBackgroundSync] Wi-Fi only enabled but not connected to Wi-Fi',
          );
          return true; // Not a failure, just waiting for Wi-Fi
        }
      }

      // Get auth token
      const storage = FlutterSecureStorage();
      final accessToken = await storage.read(key: 'access_token');

      if (accessToken == null) {
        AppLogger.debug(
          '[ContactBackgroundSync] No access token, skipping sync',
        );
        return true; // Not a failure, just not logged in
      }

      // Create profile client
      final httpClient = io.HttpClient();
      httpClient.connectionTimeout = ApiConfig.connectionTimeout;
      httpClient.idleTimeout = ApiConfig.idleTimeout;
      httpClient.maxConnectionsPerHost = 2; // Limit for background tasks

      final transport = connect_protocol.Transport(
        baseUrl: ApiConfig.profileBaseUrl,
        codec: const connect_protobuf.ProtoCodec(),
        httpClient: connect_io.createHttpClient(httpClient),
      );
      final profileClient = ProfileServiceClient(transport);

      // Create roster repository
      final rosterRepository = RosterRepository(profileClient, database);

      // Check if contacts have changed (hash-based)
      final needsSync = await rosterRepository.needsSync();

      if (!needsSync) {
        AppLogger.info('[ContactBackgroundSync] No contact changes detected');

        // Update last sync time
        await settingsService.setInt(
          ContactSyncSettings.lastSyncTime,
          DateTime.now().millisecondsSinceEpoch,
        );

        stopwatch.stop();
        AppLogger.info(
          '[ContactBackgroundSync] Completed (no changes)',
          data: {'durationMs': stopwatch.elapsedMilliseconds},
        );
        return true;
      }

      // Perform incremental sync
      AppLogger.info('[ContactBackgroundSync] Changes detected, syncing...');

      final syncedEntries = await rosterRepository.syncContacts();
      final foundOnPlatform = syncedEntries
          .where((e) => e.profileId != null)
          .length;

      // Update last sync time
      await settingsService.setInt(
        ContactSyncSettings.lastSyncTime,
        DateTime.now().millisecondsSinceEpoch,
      );

      stopwatch.stop();
      AppLogger.info(
        '[ContactBackgroundSync] Completed successfully',
        data: {
          'syncedCount': syncedEntries.length,
          'foundOnPlatform': foundOnPlatform,
          'durationMs': stopwatch.elapsedMilliseconds,
        },
      );

      return true;
    } catch (e, stackTrace) {
      AppLogger.error(
        '[ContactBackgroundSync] Failed',
        error: e,
        stackTrace: stackTrace,
      );
      return false; // Signal failure so workmanager can retry
    }
  }
}
