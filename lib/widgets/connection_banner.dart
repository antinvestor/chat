import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/sync/sync_engine.dart';

class ConnectionBanner extends ConsumerWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionStateProvider);

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      child: connectionState.when(
        data: (state) {
          if (state == SyncConnectionState.connected) {
            return const SizedBox.shrink();
          }

          final isConnecting = state == SyncConnectionState.connecting;
          final color = isConnecting ? Colors.orange : Colors.red;
          final message = isConnecting ? 'Connecting...' : 'Offline';
          final icon = isConnecting ? Icons.sync : Icons.wifi_off;

          return Container(
            width: double.infinity,
            color: color,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const SizedBox.shrink(),
        error: (_, __) => const SizedBox.shrink(),
      ),
    );
  }
}
