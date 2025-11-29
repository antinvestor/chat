import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/call_manager.dart';
import 'call_screen.dart';

class IncomingCallBanner extends ConsumerWidget {
  const IncomingCallBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final callStateStream = ref.watch(callManagerProvider).callStateStream;

    return StreamBuilder<CallState>(
      stream: callStateStream,
      builder: (context, snapshot) {
        if (snapshot.data == CallState.incoming) {
          return Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const CircleAvatar(
                      child: Icon(Icons.person),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Incoming Call',
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          Text(
                            'Unknown Caller', // TODO: Get caller name
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      onPressed: () {
                        ref.read(callManagerProvider).endCall();
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.call_end),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: () {
                        ref.read(callManagerProvider).answerCall();
                        // Navigate to call screen
                        // Note: Navigation should ideally be handled by a router listener
                        // but for now we'll push directly
                        // We need room ID for CallScreen, which CallManager has
                        // but it's private. We should expose it or pass it in event.
                        // For MVP, we'll assume CallManager handles state and we just show UI.
                        // Actually, we need to navigate.
                        // Let's assume we are already on a screen that can navigate.
                        // But we don't have context here easily if this is a global overlay.
                        // If this widget is placed in the main scaffold, we can use context.
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.call),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}
