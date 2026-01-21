import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/room_with_last_message.dart';

/// Chat list item following design specifications
class ChatListItem extends StatelessWidget {

  const ChatListItem({
    required this.room, required this.onTap, super.key,
    this.isSelected = false,
    this.isMultiSelectMode = false,
    this.onLongPress,
    this.onSelectionChanged,
  });
  final RoomWithLastMessage room;
  final VoidCallback onTap;
  final bool isSelected;
  final bool isMultiSelectMode;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RepaintBoundary(
      key: ValueKey(room.id),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isMultiSelectMode
              ? () {
                  onSelectionChanged?.call(!isSelected);
                }
              : onTap,
          onLongPress: () {
            if (isMultiSelectMode) {
              onSelectionChanged?.call(!isSelected);
            } else {
              onLongPress?.call();
            }
          },
          borderRadius: BorderRadius.circular(8),
          splashColor: AppTheme.getSubtleColor(context, AppTheme.primaryGreen),
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.standardMargin),
            child: Row(
              children: [
                // Avatar with online indicator and selection checkbox
                Stack(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        color: AppTheme.primaryGreen,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          room.name.isNotEmpty
                              ? room.name[0].toUpperCase()
                              : '?',
                          style: AppTheme.headerText.copyWith(
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    // Online status indicator
                    if (room.lastMessageTimestamp != null)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppTheme.brightGreen,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppTheme.surfaceLight,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    // Selection checkbox for multi-select mode
                    if (isMultiSelectMode)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppTheme.primaryGreen
                                : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.primaryGreen
                                  : Colors.grey,
                              width: 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 14,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),

                const SizedBox(width: AppTheme.elementGap),

                // Content area
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name and timestamp row
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              room.name,
                              style: AppTheme.bodyText.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppTheme.getTextColor(context),
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
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),

                      // Last message or typing indicator
                      if (room.isTyping ?? false)
                        Text(
                          'Typing...',
                          style: AppTheme.bodyText.copyWith(
                            color: AppTheme.brightGreen,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      else if (room.lastMessageText != null)
                        Text(
                          room.lastMessageText!,
                          style: AppTheme.bodyText.copyWith(
                            fontSize: 14,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                // Right side: Unread badge
                if (room.unreadCount > 0)
                  Column(
                    children: [
                      // Unread count badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.elementGap,
                          vertical: 4,
                        ),
                        decoration: const BoxDecoration(
                          color: AppTheme.brightGreen,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        child: Text(
                          room.unreadCount > 99
                              ? '99+'
                              : room.unreadCount.toString(),
                          style: AppTheme.metadataText.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: AppTheme.elementGap),
                    ],
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
