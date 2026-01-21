import 'package:flutter/material.dart';

import '../../../core/navigation/navigation_helper.dart';
import '../../../core/theme/app_theme.dart';
import '../domain/room_with_last_message.dart';

class RoomListTile extends StatelessWidget {

  const RoomListTile({required this.room, required this.onTap, super.key});
  final RoomWithLastMessage room;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      label: 'Chat with ${room.name}',
      value: room.unreadCount > 0
          ? '${room.unreadCount} unread messages'
          : null,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          splashColor: AppTheme.getSubtleColor(context, AppTheme.primaryGreen),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.standardMargin),
            child: Row(
              children: [
                // Avatar
                GestureDetector(
                  onTap: () {
                    // Navigate to room details when avatar is tapped with smooth animation
                    context.navigateToRoomDetails(
                      roomId: room.id,
                      roomName: room.name,
                    );
                  },
                  child: Container(
                    width: AppTheme.minTouchTarget,
                    height: AppTheme.minTouchTarget,
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryGreen,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        room.name[0].toUpperCase(),
                        style: AppTheme.headerText.copyWith(
                          fontSize: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: AppTheme.elementGap),

                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Room name and timestamp
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              room.name,
                              style: AppTheme.bodyText.copyWith(
                                fontWeight: room.unreadCount > 0
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: theme.colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (room.lastMessageTimestamp != null)
                            const SizedBox(width: AppTheme.elementGap),
                          if (room.lastMessageTimestamp != null)
                            Text(
                              _formatTimestamp(room.lastMessageTimestamp!),
                              style: AppTheme.metadataText.copyWith(
                                color: room.unreadCount > 0
                                    ? AppTheme.primaryGreen
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),

                      // Last message
                      if (room.lastMessageText != null)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: AppTheme.elementGap,
                          ),
                          child: Text(
                            room.lastMessageText!,
                            style: AppTheme.bodyText.copyWith(
                              fontSize: 14,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: room.unreadCount > 0
                                  ? FontWeight.w500
                                  : FontWeight.normal,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ),

                // Unread count badge
                if (room.unreadCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: AppTheme.elementGap),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.elementGap,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreen,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: AppTheme.minTouchTarget / 2,
                        minHeight: AppTheme.minTouchTarget / 2,
                      ),
                      child: Text(
                        room.unreadCount > 99
                            ? '99+'
                            : room.unreadCount.toString(),
                        style: AppTheme.metadataText.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);

    // Today - show time
    if (date.day == now.day &&
        date.month == now.month &&
        date.year == now.year) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }

    // Yesterday
    final yesterday = now.subtract(const Duration(days: 1));
    if (date.day == yesterday.day &&
        date.month == yesterday.month &&
        date.year == yesterday.year) {
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
