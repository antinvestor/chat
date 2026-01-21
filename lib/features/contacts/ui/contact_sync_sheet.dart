import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';

import '../../../core/logging/app_logger.dart';
import '../data/roster_repository.dart';

/// Shows a bottom sheet with sync progress that auto-dismisses on completion
Future<void> showContactSyncSheet({
  required BuildContext context,
  required RosterRepository repository,
  Duration autoDismissDelay = const Duration(seconds: 2),
  VoidCallback? onComplete,
  VoidCallback? onDismiss,
}) async {
  final completer = Completer<void>();

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _ContactSyncSheet(
      repository: repository,
      autoDismissDelay: autoDismissDelay,
      onComplete: () {
        Navigator.of(sheetContext).pop();
        onComplete?.call();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onDismiss: () {
        Navigator.of(sheetContext).pop();
        onDismiss?.call();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    ),
  ).then((_) {
    if (!completer.isCompleted) {
      completer.complete();
    }
  });

  return completer.future;
}

class _ContactSyncSheet extends StatefulWidget {
  const _ContactSyncSheet({
    required this.repository,
    required this.autoDismissDelay,
    required this.onComplete,
    required this.onDismiss,
  });
  final RosterRepository repository;
  final Duration autoDismissDelay;
  final VoidCallback onComplete;
  final VoidCallback onDismiss;

  @override
  State<_ContactSyncSheet> createState() => _ContactSyncSheetState();
}

class _ContactSyncSheetState extends State<_ContactSyncSheet> {
  SyncProgress _progress = const SyncProgress(state: SyncState.idle);
  bool _isComplete = false;
  bool _permissionPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    AppLogger.info('[ContactSyncSheet] Bottom sheet opened, starting sync');
    _startSync();
  }

  Future<void> _startSync() async {
    AppLogger.debug('[ContactSyncSheet] Starting two-phase sync');

    // Phase 1: Local sync (immediate)
    AppLogger.info(
      '[ContactSyncSheet] ========== PHASE 1: LOCAL SYNC ==========',
    );
    await widget.repository.syncContactsLocal(
      progressCallback: (progress) {
        if (mounted) {
          setState(() => _progress = progress);

          if (progress.state == SyncState.permissionDenied) {
            AppLogger.warning(
              '[ContactSyncSheet] Permission denied, checking if permanent',
            );
            _checkIfPermanentlyDenied();
          }
        }
      },
    );

    // Phase 2: Server sync (background)
    if (mounted && _progress.state != SyncState.permissionDenied) {
      AppLogger.info(
        '[ContactSyncSheet] ========== PHASE 2: SERVER SYNC ==========',
      );
      await widget.repository.syncContactsToServer(
        progressCallback: (progress) {
          if (mounted) {
            setState(() => _progress = progress);

            if (progress.state == SyncState.completed) {
              _isComplete = true;
              AppLogger.info(
                '[ContactSyncSheet] Sync completed, auto-dismissing in ${widget.autoDismissDelay.inSeconds}s',
              );
              Future.delayed(widget.autoDismissDelay, () {
                if (mounted) {
                  AppLogger.debug('[ContactSyncSheet] Auto-dismiss triggered');
                  widget.onComplete();
                }
              });
            }
          }
        },
      );
    }
  }

  Future<void> _checkIfPermanentlyDenied() async {
    final status = await Permission.contacts.status;
    AppLogger.debug(
      '[ContactSyncSheet] Permission status check',
      data: {
        'isGranted': status.isGranted,
        'isDenied': status.isDenied,
        'isPermanentlyDenied': status.isPermanentlyDenied,
        'isRestricted': status.isRestricted,
      },
    );
    if (mounted) {
      setState(() {
        // On Android, after denying twice the permission becomes permanently denied
        // On iOS, after denying once it's permanently denied
        _permissionPermanentlyDenied =
            status.isPermanentlyDenied || status.isRestricted;
      });
      AppLogger.debug(
        '[ContactSyncSheet] Permission permanently denied: $_permissionPermanentlyDenied',
      );
    }
  }

  Future<void> _requestPermissionAgain() async {
    AppLogger.info('[ContactSyncSheet] User tapped "Grant Permission" button');
    setState(() {
      _progress = const SyncProgress(
        state: SyncState.requestingPermission,
        message: 'Requesting permission...',
      );
    });

    final status = await Permission.contacts.request();
    AppLogger.debug(
      '[ContactSyncSheet] Permission request result',
      data: {
        'isGranted': status.isGranted,
        'isDenied': status.isDenied,
        'isPermanentlyDenied': status.isPermanentlyDenied,
      },
    );

    if (status.isGranted) {
      // Permission granted, restart sync
      AppLogger.info(
        '[ContactSyncSheet] Permission granted on retry, restarting sync',
      );
      await _startSync();
    } else if (status.isPermanentlyDenied) {
      AppLogger.warning('[ContactSyncSheet] Permission permanently denied');
      if (mounted) {
        setState(() {
          _permissionPermanentlyDenied = true;
          _progress = const SyncProgress(
            state: SyncState.permissionDenied,
            message: 'Permission denied. Please enable in Settings.',
          );
        });
      }
    } else {
      AppLogger.warning('[ContactSyncSheet] Permission denied again');
      if (mounted) {
        setState(() {
          _progress = const SyncProgress(
            state: SyncState.permissionDenied,
            message: 'Contact permission is required to sync.',
          );
        });
      }
    }
  }

  Future<void> _openSettings() async {
    AppLogger.info('[ContactSyncSheet] User tapped "Open Settings" button');
    await openAppSettings();
  }

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: theme.colorScheme.outline.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Icon
            _buildIcon(theme),
            const SizedBox(height: 16),

            // Title
            Text(
              _getTitle(),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),

            // Message
            Text(
              _progress.message ?? '',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),

            // Progress bar (only during upload)
            if (_progress.state == SyncState.uploading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress.progress,
                  minHeight: 8,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 12),
              // Batch and contact progress info
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _progress.totalBatches > 0
                        ? 'Batch ${_progress.currentBatch}/${_progress.totalBatches}'
                        : 'Processing...',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  Text(
                    '${_progress.processedContacts}/${_progress.totalContacts} contacts',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
              // Show found contacts count with animation
              if (_progress.foundOnPlatform > 0) ...[
                const SizedBox(height: 12),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.7,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_add,
                        size: 16,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${_progress.foundOnPlatform} contacts found',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            // Loading indicator for non-upload states
            if (_progress.state == SyncState.requestingPermission ||
                _progress.state == SyncState.readingContacts) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],

            // Completed count
            if (_isComplete && _progress.foundOnPlatform > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_progress.foundOnPlatform} contacts ready to chat!',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ),
            ],

            // Action buttons for permission denied or error
            if (_progress.state == SyncState.permissionDenied ||
                _progress.state == SyncState.error) ...[
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Open Settings button (for permanently denied)
                  if (_permissionPermanentlyDenied && _isMobile) ...[
                    FilledButton.icon(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.settings, size: 18),
                      label: const Text('Open Settings'),
                    ),
                    const SizedBox(width: 12),
                  ] else if (_progress.state == SyncState.permissionDenied) ...[
                    // Re-request permission button
                    FilledButton.icon(
                      onPressed: _requestPermissionAgain,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Grant Permission'),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // Retry button for errors
                  if (_progress.state == SyncState.error) ...[
                    FilledButton.icon(
                      onPressed: _startSync,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // Skip/Dismiss button
                  TextButton(
                    onPressed: widget.onDismiss,
                    child: const Text('Skip'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(ThemeData theme) {
    IconData icon;
    Color color;
    var showSpinner = false;

    switch (_progress.state) {
      case SyncState.idle:
      case SyncState.requestingPermission:
        icon = Icons.contacts;
        color = theme.colorScheme.primary;
        showSpinner = true;
        break;
      case SyncState.readingContacts:
        icon = Icons.contact_page;
        color = theme.colorScheme.primary;
        showSpinner = true;
        break;
      case SyncState.uploading:
        icon = Icons.cloud_upload;
        color = theme.colorScheme.primary;
        showSpinner = true;
        break;
      case SyncState.completed:
        icon = Icons.check_circle;
        color = Colors.green;
        break;
      case SyncState.permissionDenied:
        icon = Icons.no_accounts;
        color = theme.colorScheme.error;
        break;
      case SyncState.error:
        icon = Icons.error_outline;
        color = theme.colorScheme.error;
        break;
    }

    if (showSpinner) {
      return Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: color.withValues(alpha: 0.3),
            ),
          ),
          Icon(icon, size: 32, color: color),
        ],
      );
    }

    return Icon(icon, size: 48, color: color);
  }

  String _getTitle() {
    switch (_progress.state) {
      case SyncState.idle:
        return 'Starting Sync';
      case SyncState.requestingPermission:
        return 'Requesting Permission';
      case SyncState.readingContacts:
        return 'Reading Contacts';
      case SyncState.uploading:
        return 'Syncing Contacts';
      case SyncState.completed:
        return 'Sync Complete!';
      case SyncState.permissionDenied:
        return 'Permission Required';
      case SyncState.error:
        return 'Sync Failed';
    }
  }
}
