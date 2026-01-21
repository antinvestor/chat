import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/navigation/navigation_helper.dart';
import '../../../core/theme/app_theme.dart';
import '../data/settings_providers.dart';

class StorageSettingsScreen extends ConsumerStatefulWidget {
  const StorageSettingsScreen({super.key});

  @override
  ConsumerState<StorageSettingsScreen> createState() =>
      _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends ConsumerState<StorageSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);
    final cacheAsync = ref.watch(cacheManagerProvider);

    return settingsAsync.when(
      data: (settings) => cacheAsync.when(
        data: (cacheSize) => Scaffold(
          appBar: AppBar(
            title: const Text('Storage'),
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
                title: 'Network usage',
                items: [
                  _buildSettingsItem(
                    context,
                    title: 'Media auto-download',
                    subtitle: settings['media_auto_download'] ?? 'Wi-Fi only',
                    onTap: () => _showMediaDownloadOptions(
                      settings['media_auto_download'] ?? 'Wi-Fi only',
                    ),
                  ),
                  _buildSettingsItem(
                    context,
                    title: 'Call data usage',
                    subtitle: settings['call_data_usage'] ?? 'Low data usage',
                    onTap: () => _showCallDataUsageOptions(
                      settings['call_data_usage'] ?? 'Low data usage',
                    ),
                  ),
                ],
              ),
              _buildSettingsSection(
                context,
                title: 'Storage management',
                items: [
                  _buildSettingsItem(
                    context,
                    title: 'Manage storage',
                    subtitle: 'Free up space by clearing cache and old files',
                    onTap: _showStorageManagementDialog,
                  ),
                  _buildSettingsItem(
                    context,
                    title: 'Clear cache',
                    subtitle:
                        'Clear temporary files (${_formatBytes(cacheSize)})',
                    onTap: _clearCache,
                  ),
                ],
              ),
            ],
          ),
        ),
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (error, stack) => Scaffold(
          body: Center(child: Text('Error loading cache info: $error')),
        ),
      ),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stack) =>
          Scaffold(body: Center(child: Text('Error loading settings: $error'))),
    );
  }

  void _showMediaDownloadOptions(String currentOption) {
    final options = ['Never', 'Wi-Fi only', 'Wi-Fi and mobile data'];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Media Auto-Download'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              ListTile(
                title: Text(option),
                trailing: currentOption == option
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  ref
                      .read(settingsProvider.notifier)
                      .updateMediaAutoDownload(option);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showCallDataUsageOptions(String currentOption) {
    final options = [
      'Low data usage',
      'Standard data usage',
      'High data usage',
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call Data Usage'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              ListTile(
                title: Text(option),
                trailing: currentOption == option
                    ? const Icon(Icons.check, color: Colors.blue)
                    : null,
                onTap: () {
                  ref
                      .read(settingsProvider.notifier)
                      .updateCallDataUsage(option);
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showStorageManagementDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Storage Management'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Storage management features coming soon:'),
            SizedBox(height: 16),
            Text('• Clear old media files'),
            Text('• Delete old conversations'),
            Text('• Optimize database'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _clearCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
          'Are you sure you want to clear all temporary files?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await ref.read(cacheManagerProvider.notifier).clearCache();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cache cleared successfully')),
        );
      }
    }
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
}
