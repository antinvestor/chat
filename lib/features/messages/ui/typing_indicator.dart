import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/typing_provider.dart';

class TypingIndicator extends ConsumerWidget {
  final String roomId;

  const TypingIndicator({super.key, required this.roomId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typingUsers = ref.watch(typingProvider(roomId));

    if (typingUsers.isEmpty) {
      return const SizedBox.shrink();
    }

    // Filter out current user if needed, but provider should handle logic
    // For now assuming provider gives us IDs of others typing

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildDots(context),
          const SizedBox(width: 8),
          Text(
            _getTypingText(typingUsers),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  String _getTypingText(Set<String> profileIds) {
    if (profileIds.length == 1) {
      return '${profileIds.first} is typing...';
    } else if (profileIds.length == 2) {
      return '${profileIds.first} and ${profileIds.last} are typing...';
    } else {
      return '${profileIds.length} people are typing...';
    }
  }

  Widget _buildDots(BuildContext context) {
    return SizedBox(width: 24, height: 12, child: _TypingDotsAnimation());
  }
}

class _TypingDotsAnimation extends StatefulWidget {
  @override
  State<_TypingDotsAnimation> createState() => _TypingDotsAnimationState();
}

class _TypingDotsAnimationState extends State<_TypingDotsAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(3, (index) {
            final offset = index * 0.2;
            final value = (_controller.value + offset) % 1.0;
            final opacity = (value < 0.5) ? value * 2 : (1.0 - value) * 2;

            return Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.6 + (opacity * 0.4)),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
