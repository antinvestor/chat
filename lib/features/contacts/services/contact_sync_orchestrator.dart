import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/settings/settings_service.dart';
import '../data/roster_repository.dart';
import '../ui/contact_permission_dialog.dart';

part 'contact_sync_orchestrator.g.dart';

/// Settings keys for contact sync orchestration
class ContactSyncOrchestratorKeys {
  /// Whether the user has completed the initial contact sync
  /// (either granted permission and synced, or explicitly declined)
  static const contactSyncInitialized = 'contact_sync_initialized';

  /// Whether the user has denied contact permission
  /// Used to track if we should show "Open Settings" vs "Continue"
  static const contactPermissionDenied = 'contact_permission_denied';
}

/// Orchestrates lazy contact synchronization on group creation.
///
/// Contact sync only happens when the user first tries to create a group:
/// 1. If already initialized: check hash for changes, trigger silent background sync if needed
/// 2. If not initialized: show explanation dialog, request permission, perform initial sync
///
/// On web/desktop, contact sync is skipped entirely (no native contacts).
class ContactSyncOrchestrator {
  ContactSyncOrchestrator({
    required RosterRepository rosterRepository,
    required SettingsService settingsService,
  }) : _rosterRepository = rosterRepository,
       _settingsService = settingsService;

  final RosterRepository _rosterRepository;
  final SettingsService _settingsService;

  /// Whether we're on a mobile platform with native contacts
  bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Whether contact sync has been initialized
  bool get isInitialized => _settingsService.getBool(
    ContactSyncOrchestratorKeys.contactSyncInitialized,
  );

  /// Whether the user previously denied permission
  bool get wasPermissionDenied => _settingsService.getBool(
    ContactSyncOrchestratorKeys.contactPermissionDenied,
  );

  /// Mark contact sync as initialized
  Future<void> _markInitialized() async {
    await _settingsService.setBool(
      ContactSyncOrchestratorKeys.contactSyncInitialized,
      true,
    );
  }

  /// Mark that the user denied permission
  Future<void> _markPermissionDenied(bool denied) async {
    await _settingsService.setBool(
      ContactSyncOrchestratorKeys.contactPermissionDenied,
      denied,
    );
  }

  /// Ensure contacts are synced before allowing group creation.
  ///
  /// Call this when the user tries to create a group chat.
  ///
  /// Behavior by platform:
  /// - **Web/Desktop**: Returns true immediately (no native contacts)
  /// - **Mobile (initialized)**: Triggers silent background sync if needed, returns true
  /// - **Mobile (not initialized)**: Shows explanation dialog, requests permission,
  ///   performs initial sync, returns true on success or false if declined
  ///
  /// Returns `true` if contacts are ready for use, `false` if the user declined
  /// permission or an error occurred.
  Future<bool> ensureContactsSynced({required BuildContext context}) async {
    AppLogger.info('[ContactSyncOrchestrator] ensureContactsSynced called');

    // Skip on web/desktop - no native contacts
    if (!_isMobile) {
      AppLogger.debug(
        '[ContactSyncOrchestrator] Not mobile platform, skipping',
      );
      return true;
    }

    // Check if already initialized
    if (isInitialized) {
      AppLogger.debug(
        '[ContactSyncOrchestrator] Already initialized, checking for changes',
      );
      return _handleInitializedSync();
    }

    // Not initialized - show dialog and perform initial sync
    AppLogger.info(
      '[ContactSyncOrchestrator] First time - showing permission dialog',
    );
    return _handleFirstTimeSync(context);
  }

  /// Handle sync when already initialized
  ///
  /// Checks if contacts have changed and triggers silent background sync if needed.
  Future<bool> _handleInitializedSync() async {
    try {
      // Check if permission is still granted
      final status = await Permission.contacts.status;
      if (!status.isGranted) {
        AppLogger.debug(
          '[ContactSyncOrchestrator] Permission revoked since initialization',
        );
        // Permission was revoked - don't reset initialized state,
        // just return true and let the UI show cached contacts
        return true;
      }

      // Check if sync is needed using hash-based change detection
      final needsSync = await _rosterRepository.needsSync();
      if (needsSync) {
        AppLogger.info(
          '[ContactSyncOrchestrator] Changes detected, triggering background sync',
        );
        // Fire-and-forget background sync - don't block the UI
        unawaited(_triggerBackgroundSync());
      } else {
        AppLogger.debug(
          '[ContactSyncOrchestrator] No changes detected, using cached contacts',
        );
      }

      return true;
    } catch (e, stackTrace) {
      AppLogger.error(
        '[ContactSyncOrchestrator] Error checking sync state',
        error: e,
        stackTrace: stackTrace,
      );
      // Return true anyway - let the user proceed with cached data
      return true;
    }
  }

  /// Handle first-time sync with permission dialog
  Future<bool> _handleFirstTimeSync(BuildContext context) async {
    if (!context.mounted) return false;

    // Show the beautiful explanation dialog
    final result = await ContactPermissionDialog.show(context);

    switch (result) {
      case ContactPermissionResult.granted:
        AppLogger.info(
          '[ContactSyncOrchestrator] Permission granted, performing initial sync',
        );
        await _markPermissionDenied(false);
        await _performInitialSync();
        await _markInitialized();
        return true;

      case ContactPermissionResult.declined:
        AppLogger.info('[ContactSyncOrchestrator] User declined permission');
        // Don't mark as initialized - we'll ask again next time
        return false;

      case ContactPermissionResult.openSettings:
        AppLogger.info(
          '[ContactSyncOrchestrator] Opening settings for permission',
        );
        await _markPermissionDenied(true);
        await openAppSettings();

        // After returning from settings, check if permission was granted
        if (!context.mounted) return false;

        final newStatus = await Permission.contacts.status;
        if (newStatus.isGranted) {
          AppLogger.info(
            '[ContactSyncOrchestrator] Permission granted from settings',
          );
          await _markPermissionDenied(false);
          await _performInitialSync();
          await _markInitialized();
          return true;
        } else {
          AppLogger.debug(
            '[ContactSyncOrchestrator] Permission still denied after settings',
          );
          return false;
        }
    }
  }

  /// Perform the initial contact sync
  ///
  /// Phase 1: Local sync (immediate, for UI display)
  /// Phase 2: Server sync (background, silent)
  Future<void> _performInitialSync() async {
    try {
      AppLogger.info(
        '[ContactSyncOrchestrator] Starting initial two-phase sync',
      );

      // Phase 1: Local sync (immediate) - reads device contacts and stores locally
      final localContacts = await _rosterRepository.syncContactsLocal();
      AppLogger.info(
        '[ContactSyncOrchestrator] Phase 1 complete: ${localContacts.length} contacts loaded locally',
      );

      // Phase 2: Server sync (background, fire-and-forget)
      // This links contacts with platform profiles
      unawaited(_triggerBackgroundSync());
    } catch (e, stackTrace) {
      AppLogger.error(
        '[ContactSyncOrchestrator] Initial sync failed',
        error: e,
        stackTrace: stackTrace,
      );
      // Don't rethrow - partial sync is still useful
    }
  }

  /// Trigger a silent background sync
  ///
  /// This runs without any UI indication and handles errors silently.
  Future<void> _triggerBackgroundSync() async {
    try {
      AppLogger.debug(
        '[ContactSyncOrchestrator] Starting silent background sync',
      );
      await _rosterRepository.syncContactsToServer();
      AppLogger.debug('[ContactSyncOrchestrator] Background sync completed');
    } catch (e) {
      AppLogger.debug(
        '[ContactSyncOrchestrator] Background sync failed (will retry later)',
        data: {'error': e.toString()},
      );
      // Silent failure - don't disturb user
    }
  }

  /// Reset the initialized state (for testing or after logout)
  Future<void> reset() async {
    await _settingsService.setBool(
      ContactSyncOrchestratorKeys.contactSyncInitialized,
      false,
    );
    await _settingsService.setBool(
      ContactSyncOrchestratorKeys.contactPermissionDenied,
      false,
    );
    AppLogger.debug('[ContactSyncOrchestrator] State reset');
  }
}

// ============================================================================
// Providers
// ============================================================================

/// Provider for ContactSyncOrchestrator
@riverpod
Future<ContactSyncOrchestrator> contactSyncOrchestrator(Ref ref) async {
  final rosterRepository = await ref.watch(rosterRepositoryProvider.future);
  final settingsService = ref.watch(settingsServiceProvider);

  return ContactSyncOrchestrator(
    rosterRepository: rosterRepository,
    settingsService: settingsService,
  );
}

/// Provider to check if contact sync is initialized
@riverpod
bool contactSyncInitialized(Ref ref) {
  final settingsService = ref.watch(settingsServiceProvider);
  return settingsService.getBool(
    ContactSyncOrchestratorKeys.contactSyncInitialized,
  );
}
