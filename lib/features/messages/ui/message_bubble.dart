import 'package:flutter/material.dart';
import '../domain/room_event.dart';

class MessageBubble extends StatelessWidget {
  final RoomEvent message;
  final bool isMe;
  final bool showAvatar;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.showAvatar = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final senderName = isMe ? 'Me' : _getSenderName();
    final timestamp = _formatTimestamp(message.createdAt);
    final status = isMe ? _getStatusLabel(message.status) : '';
    final text = message.content['text'] as String? ?? '';

    return Semantics(
      label: 'Message from $senderName at $timestamp',
      value: '$text. $status',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMe && showAvatar) ...[
              _buildAvatar(context),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.7,
                    ),
                    decoration: BoxDecoration(
                      color: isMe
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isMe)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              _getSenderName(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                        _buildMessageContent(context),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatTimestamp(message.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 4),
                        _buildStatusIndicator(context),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (isMe && showAvatar) ...[
              const SizedBox(width: 8),
              _buildAvatar(context),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        _getSenderName()[0].toUpperCase(),
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context) {
    final text = message.content['text'] as String? ?? '';
    
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        height: 1.4,
        color: Theme.of(context).colorScheme.onSecondaryContainer,
      ),
    );
  }

  Widget _buildStatusIndicator(BuildContext context) {
    final theme = Theme.of(context);
    IconData iconData;
    Color iconColor;

    switch (message.status) {
      case EventStatus.pending:
        iconData = Icons.schedule;
        iconColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4);
        break;
      case EventStatus.sent:
        iconData = Icons.check;
        iconColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
        break;
      case EventStatus.delivered:
        iconData = Icons.done_all;
        iconColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);
        break;
      case EventStatus.read:
        iconData = Icons.done_all;
        iconColor = theme.colorScheme.primary;
        break;
      case EventStatus.failed:
        iconData = Icons.error_outline;
        iconColor = theme.colorScheme.error;
        break;
    }

    return Icon(
      iconData,
      size: 14,
      color: iconColor,
    );
  }

  String _getSenderName() {
    // TODO: Get actual sender name from profile
    return message.senderId;
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    
    return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _getStatusLabel(EventStatus status) {
    switch (status) {
      case EventStatus.pending:
        return 'Sending';
      case EventStatus.sent:
        return 'Sent';
      case EventStatus.delivered:
        return 'Delivered';
      case EventStatus.read:
        return 'Read';
      case EventStatus.failed:
        return 'Failed to send';
    }
  }
}
