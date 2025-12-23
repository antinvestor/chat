import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../messages/domain/room_event.dart';
import '../services/motion_service.dart';

class MotionBubble extends ConsumerWidget {
  final RoomEvent event;
  final bool isMe;

  const MotionBubble({
    super.key,
    required this.event,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final content = event.content;
    final title = content['title'] as String? ?? 'Motion';
    final description = content['description'] as String? ?? '';
    final options = (content['options'] as List<dynamic>?)?.cast<String>() ?? [];
    final votes = (content['votes'] as Map<String, dynamic>?) ?? {};
    final deadline = DateTime.fromMillisecondsSinceEpoch(content['deadline'] as int? ?? 0);
    final isExpired = DateTime.now().isAfter(deadline);

    // Calculate votes
    final voteCounts = <String, int>{};
    for (final option in options) {
      voteCounts[option] = 0;
    }
    for (final vote in votes.values) {
      if (voteCounts.containsKey(vote)) {
        voteCounts[vote] = (voteCounts[vote] ?? 0) + 1;
      }
    }
    final totalVotes = votes.length;

    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.how_to_vote, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(description, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          ...options.map((option) {
            final count = voteCounts[option] ?? 0;
            final percentage = totalVotes > 0 ? count / totalVotes : 0.0;
            final isSelected = false; // TODO: Check if current user voted for this

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: isExpired
                    ? null
                    : () {
                        ref.read(motionServiceProvider).castVote(
                              roomId: event.roomId,
                              motionId: event.id,
                              option: option,
                            );
                      },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isSelected ? theme.colorScheme.primary : theme.colorScheme.outline,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: isSelected ? theme.colorScheme.primaryContainer : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(option),
                          Text('$count votes'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: percentage,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
          Text(
            isExpired ? 'Voting Closed' : 'Voting ends: ${_formatDate(deadline)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: isExpired ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }
}
