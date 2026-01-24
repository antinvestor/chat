import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/logging/app_logger.dart';
import '../../contacts/data/roster_repository.dart';
import '../data/onboarding_repository.dart';

/// Screen shown after login to sync contacts
class ContactSyncScreen extends ConsumerStatefulWidget {
  const ContactSyncScreen({super.key});

  @override
  ConsumerState<ContactSyncScreen> createState() => _ContactSyncScreenState();
}

class _ContactSyncScreenState extends ConsumerState<ContactSyncScreen> {
  ContactSyncState _state = ContactSyncState.initial;
  String _statusMessage = 'Sync your contacts to find friends on the app';
  double _progress = 0;
  int _syncedCount = 0;
  bool _permissionPermanentlyDenied = false;

  /// Check if running on mobile platform
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  void initState() {
    super.initState();
    // Check if we should auto-start sync
    _checkAndStartSync();
  }

  Future<void> _checkAndStartSync() async {
    // Small delay to let the UI settle
    await Future.delayed(const Duration(milliseconds: 300));
    if (mounted) {
      await _requestPermissionAndSync();
    }
  }

  Future<void> _requestPermissionAndSync() async {
    setState(() {
      _state = ContactSyncState.requestingPermission;
      _statusMessage = 'Requesting contacts permission...';
      _permissionPermanentlyDenied = false;
    });

    try {
      if (_isMobile) {
        // Use permission_handler for more control on mobile
        final status = await Permission.contacts.request();

        if (status.isGranted) {
          await _syncContacts();
        } else if (status.isPermanentlyDenied) {
          if (mounted) {
            setState(() {
              _state = ContactSyncState.permissionDenied;
              _permissionPermanentlyDenied = true;
              _statusMessage =
                  'Permission was denied. Please enable contacts access in Settings.';
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _state = ContactSyncState.permissionDenied;
              _statusMessage =
                  'Contacts permission is required to find friends';
            });
          }
        }
      } else {
        // Use flutter_contacts for desktop/web
        final hasPermission = await FlutterContacts.requestPermission();

        if (!hasPermission) {
          if (mounted) {
            setState(() {
              _state = ContactSyncState.permissionDenied;
              _statusMessage =
                  'Contacts permission is required to find friends';
            });
          }
          return;
        }

        await _syncContacts();
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Permission request failed',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() {
          _state = ContactSyncState.error;
          _statusMessage = 'Failed to request permission';
        });
      }
    }
  }

  Future<void> _openAppSettings() async {
    await openAppSettings();
    // After returning from settings, check permission status again
    if (mounted) {
      final status = await Permission.contacts.status;
      if (status.isGranted) {
        await _syncContacts();
      }
    }
  }

  Future<void> _syncContacts() async {
    setState(() {
      _state = ContactSyncState.syncing;
      _statusMessage = 'Reading contacts...';
      _progress = 0.1;
    });

    try {
      // Get device contacts
      final deviceContacts = await FlutterContacts.getContacts(
        withProperties: true,
      );

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Found ${deviceContacts.length} contacts';
        _progress = 0.3;
      });

      await Future.delayed(const Duration(milliseconds: 500));

      if (!mounted) return;

      setState(() {
        _statusMessage = 'Syncing with server...';
        _progress = 0.5;
      });

      // Sync contacts
      final repo = await ref.read(contactSyncRepositoryProvider.future);
      final syncedContacts = await repo.syncContacts();

      if (!mounted) return;

      setState(() {
        _syncedCount = syncedContacts.length;
        _progress = 1.0;
        _state = ContactSyncState.completed;
        _statusMessage = syncedContacts.isEmpty
            ? 'No contacts found on the app yet'
            : 'Found $_syncedCount contacts on the app!';
      });

      // Mark contacts as synced
      await ref.read(onboardingRepositoryProvider).markContactsSynced();

      // Wait a moment to show completion
      await Future.delayed(const Duration(seconds: 1));

      // Navigate to main screen
      if (mounted) {
        context.go('/');
      }
    } catch (e, stackTrace) {
      AppLogger.error('Contact sync failed', error: e, stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _state = ContactSyncState.error;
          _statusMessage = 'Sync failed. Please try again.';
        });
      }
    }
  }

  Future<void> _skipSync() async {
    // Mark as skipped so we don't show this screen again
    await ref.read(onboardingRepositoryProvider).markContactsSynced();
    if (mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),

              // Icon
              Icon(_getIcon(), size: 80, color: _getIconColor(theme)),
              const SizedBox(height: 32),

              // Title
              Text(
                _getTitle(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Status message
              Text(
                _statusMessage,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Progress indicator
              if (_state == ContactSyncState.syncing ||
                  _state == ContactSyncState.requestingPermission) ...[
                LinearProgressIndicator(
                  value: _state == ContactSyncState.syncing ? _progress : null,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 16),
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: theme.textTheme.bodySmall,
                ),
              ],

              // Completed state
              if (_state == ContactSyncState.completed && _syncedCount > 0)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '$_syncedCount contacts ready to chat!',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              const Spacer(),

              // Action buttons
              if (_state == ContactSyncState.permissionDenied ||
                  _state == ContactSyncState.error) ...[
                // Show "Open Settings" button if permission permanently denied on mobile
                if (_permissionPermanentlyDenied && _isMobile) ...[
                  FilledButton.icon(
                    onPressed: _openAppSettings,
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Settings'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _requestPermissionAndSync,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Check Again'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: _requestPermissionAndSync,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try Again'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
              ],

              // Skip button (always visible except when syncing)
              if (_state != ContactSyncState.syncing &&
                  _state != ContactSyncState.completed)
                TextButton(
                  onPressed: _skipSync,
                  child: const Text('Skip for now'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIcon() {
    switch (_state) {
      case ContactSyncState.initial:
      case ContactSyncState.requestingPermission:
        return Icons.contacts;
      case ContactSyncState.syncing:
        return Icons.sync;
      case ContactSyncState.completed:
        return Icons.check_circle_outline;
      case ContactSyncState.permissionDenied:
        return Icons.no_accounts;
      case ContactSyncState.error:
        return Icons.error_outline;
    }
  }

  Color _getIconColor(ThemeData theme) {
    switch (_state) {
      case ContactSyncState.completed:
        return Colors.green;
      case ContactSyncState.permissionDenied:
      case ContactSyncState.error:
        return theme.colorScheme.error;
      default:
        return theme.colorScheme.primary;
    }
  }

  String _getTitle() {
    switch (_state) {
      case ContactSyncState.initial:
        return 'Find Your Friends';
      case ContactSyncState.requestingPermission:
        return 'Requesting Permission';
      case ContactSyncState.syncing:
        return 'Syncing Contacts';
      case ContactSyncState.completed:
        return 'Sync Complete!';
      case ContactSyncState.permissionDenied:
        return 'Permission Required';
      case ContactSyncState.error:
        return 'Sync Failed';
    }
  }
}

enum ContactSyncState {
  initial,
  requestingPermission,
  syncing,
  completed,
  permissionDenied,
  error,
}
