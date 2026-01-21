import 'package:flutter/material.dart';

class DateHeader extends StatelessWidget {
  const DateHeader({required this.timestamp, super.key});
  final int timestamp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(date.year, date.month, date.day);

    String dateText;

    if (messageDate == today) {
      dateText = 'Today';
    } else {
      final yesterday = today.subtract(const Duration(days: 1));
      if (messageDate == yesterday) {
        dateText = 'Yesterday';
      } else {
        // This week - show day name
        final difference = today.difference(messageDate);
        if (difference.inDays < 7) {
          const days = [
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
            'Sunday',
          ];
          dateText = days[date.weekday - 1];
        } else {
          // Older - show date
          dateText = '${date.day}/${date.month}/${date.year}';
        }
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              dateText,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}
