import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/sync/sync_engine.dart';

/// Banner that shows the connection status of the app
/// Displays when disconnected or connecting
class ConnectionStatusBanner extends ConsumerWidget {
  const ConnectionStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionStateAsync = ref.watch(connectionStateProvider);

    return connectionStateAsync.when(
      data: (state) {
        // Don't show banner when connected
        if (state == SyncConnectionState.connected) {
          return const SizedBox.shrink();
        }

        // Determine banner color and message
        Color backgroundColor;
        IconData icon;
        String message;
        Widget? trailing;

        if (state == SyncConnectionState.connecting) {
          backgroundColor = Colors.orange;
          icon = Icons.sync;
          message = 'Connecting...';
          trailing = const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          );
        } else {
          // Disconnected
          backgroundColor = Colors.red;
          icon = Icons.cloud_off;
          message = 'Offline - Messages will sync when online';
          trailing = null;
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          color: backgroundColor,
          child: Row(
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
