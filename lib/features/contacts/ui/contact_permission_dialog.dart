import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';

/// Result of the contact permission dialog
enum ContactPermissionResult {
  /// User tapped "Not Now" - declined to grant permission
  declined,

  /// User granted permission (or it was already granted)
  granted,

  /// User needs to go to settings (permission permanently denied)
  openSettings,
}

/// A beautiful dialog explaining why contact access is needed for group creation.
///
/// Shows:
/// - Groups icon in a circular container
/// - Clear title: "Create Group Chats"
/// - Explanation text
/// - Three benefits with icons
/// - Privacy reassurance note
/// - Warning for permanently denied state
/// - "Not Now" and "Continue"/"Open Settings" buttons
class ContactPermissionDialog extends StatelessWidget {
  const ContactPermissionDialog({required this.isPermanentlyDenied, super.key});

  /// Whether the permission was permanently denied by the user
  final bool isPermanentlyDenied;

  /// Show the contact permission dialog
  ///
  /// Returns [ContactPermissionResult] indicating the user's choice.
  static Future<ContactPermissionResult> show(BuildContext context) async {
    // Check current permission status
    final status = await Permission.contacts.status;

    // Already granted - no need to show dialog
    if (status.isGranted) {
      return ContactPermissionResult.granted;
    }

    // Check if permanently denied
    final isPermanentlyDenied = status.isPermanentlyDenied;

    if (!context.mounted) return ContactPermissionResult.declined;

    final result = await showDialog<ContactPermissionResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          ContactPermissionDialog(isPermanentlyDenied: isPermanentlyDenied),
    );

    return result ?? ContactPermissionResult.declined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Groups icon in circular container
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.groups_rounded,
              size: 40,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 20),

          // Title
          Text(
            'Create Group Chats',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // Explanation text
          Text(
            'To create group chats with your friends, we need access to your contacts.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // Benefits container
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _BenefitRow(
                  icon: Icons.person_search_rounded,
                  text: 'Find friends already on the app',
                  theme: theme,
                ),
                const SizedBox(height: 12),
                _BenefitRow(
                  icon: Icons.group_add_rounded,
                  text: 'Quickly add members to groups',
                  theme: theme,
                ),
                const SizedBox(height: 12),
                _BenefitRow(
                  icon: Icons.sync_rounded,
                  text: 'Stay connected as contacts join',
                  theme: theme,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Privacy reassurance
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline_rounded,
                size: 16,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(width: 6),
              Text(
                'Your contacts stay private on your device',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),

          // Warning for permanently denied
          if (isPermanentlyDenied) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Permission was previously denied. Please enable it in Settings.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        // Not Now button
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(ContactPermissionResult.declined);
          },
          child: Text(
            'Not Now',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),

        // Continue / Open Settings button
        FilledButton(
          onPressed: () async {
            if (isPermanentlyDenied) {
              // Open settings and return result
              Navigator.of(context).pop(ContactPermissionResult.openSettings);
            } else {
              // Request permission
              final status = await Permission.contacts.request();
              if (!context.mounted) return;

              if (status.isGranted) {
                Navigator.of(context).pop(ContactPermissionResult.granted);
              } else if (status.isPermanentlyDenied) {
                Navigator.of(context).pop(ContactPermissionResult.openSettings);
              } else {
                // User denied - close dialog
                Navigator.of(context).pop(ContactPermissionResult.declined);
              }
            }
          },
          child: Text(isPermanentlyDenied ? 'Open Settings' : 'Continue'),
        ),
      ],
    );
  }
}

/// A row displaying a benefit with an icon
class _BenefitRow extends StatelessWidget {
  const _BenefitRow({
    required this.icon,
    required this.text,
    required this.theme,
  });

  final IconData icon;
  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 18, color: theme.colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
