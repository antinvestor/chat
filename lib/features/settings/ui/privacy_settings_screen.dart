import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/navigation_helper.dart';
import '../../../core/theme/app_theme.dart';

class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
      appBar: AppBar(
        title: const Text('Privacy'),
        backgroundColor: AppTheme.primaryGreen,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.navigateBack('/settings'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _buildSettingsSection(
            context,
            title: 'Blocking',
            items: [
              _buildSettingsItem(
                context,
                title: 'Blocked contacts',
                subtitle: 'Manage contacts you have blocked',
                onTap: () {
                  _showBlockedContactsScreen(context);
                },
              ),
            ],
          ),
          _buildSettingsSection(
            context,
            title: 'Disappearing messages',
            items: [
              _buildSettingsItem(
                context,
                title: 'Default message timer',
                subtitle: '24 hours',
                onTap: () {
                  _showMessageTimerOptions(context);
                },
              ),
            ],
          ),
          _buildSettingsSection(
            context,
            title: 'Read receipts',
            items: [
              _buildSwitchItem(
                context,
                title: 'Read receipts',
                subtitle:
                    'If turned off, you won\'t send or receive read receipts',
                value: true,
                onChanged: (value) {
                  _toggleReadReceipts(context, value);
                },
              ),
            ],
          ),
        ],
      ),
    );

  void _showBlockedContactsScreen(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Blocked Contacts'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Blocked contacts functionality coming soon:'),
            SizedBox(height: 8),
            Text('• View blocked contacts list'),
            Text('• Unblock contacts'),
            Text('• Block new contacts'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showMessageTimerOptions(BuildContext context) {
    final timers = ['Off', '5 seconds', '10 seconds', '30 seconds', '1 minute'];
    var selectedTimer = '10 seconds'; // Default value

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Message Timer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Choose how long messages should disappear after being read:',
            ),
            const SizedBox(height: 16),
            ...timers.map((timer) => ListTile(
                title: Text(timer),
                trailing: selectedTimer == timer
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  selectedTimer = timer;
                },
              )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Message timer set to $selectedTimer'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _toggleReadReceipts(BuildContext context, bool value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Read receipts ${value ? 'enabled' : 'disabled'}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Widget _buildSettingsSection(
    BuildContext context, {
    required String title,
    required List<Widget> items,
  }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.primaryGreen,
            ),
          ),
        ),
        ...items,
      ],
    );

  Widget _buildSettingsItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          size: 20,
        ),
        onTap: onTap,
      ),
    );

  Widget _buildSwitchItem(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppTheme.primaryGreen,
        ),
      ),
    );
}
