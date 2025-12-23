import 'package:flutter/material.dart';

import '../domain/room_with_last_message.dart';

class RoomListTile extends StatelessWidget {
  final RoomWithLastMessage room;
  final VoidCallback onTap;

  const RoomListTile({
    super.key,
    required this.room,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Semantics(
      label: 'Chat with ${room.name}',
      value: room.unreadCount > 0 ? '${room.unreadCount} unread messages' : null,
      button: true,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            room.name[0].toUpperCase(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                room.name,
                style: TextStyle(
                  fontWeight: room.unreadCount > 0 ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 16,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (room.lastMessageTimestamp != null)
              Text(
                _formatTimestamp(room.lastMessageTimestamp!),
                style: TextStyle(
                  fontSize: 12,
                  color: room.unreadCount > 0
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        subtitle: room.lastMessageText != null
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  room.lastMessageText!,
                  style: TextStyle(
                    fontSize: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: room.unreadCount > 0 ? FontWeight.w500 : FontWeight.normal,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              )
            : null,
        trailing: room.unreadCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                child: Text(
                  room.unreadCount > 99 ? '99+' : room.unreadCount.toString(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
              )
            : null,
        onTap: onTap,
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);

    // Today - show time
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }

    // Yesterday
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.day == yesterday.day && date.month == yesterday.month && date.year == yesterday.year) {
      return 'Yesterday';
    }

    // This week - show day name
    if (difference.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[date.weekday - 1];
    }

    // This year - show date without year
    if (date.year == now.year) {
      return '${date.day}/${date.month}';
    }

    // Older - show full date
    return '${date.day}/${date.month}/${date.year}';
  }
}
