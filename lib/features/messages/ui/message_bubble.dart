import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../features/contacts/data/contact_sync_repository.dart';
import '../domain/room_event.dart';

class MessageBubble extends ConsumerWidget {
  final RoomEvent message;
  final bool isMe;
  final bool shouldGroupWithPrevious;
  final bool removeTail;
  final Function(String messageId, String messageText)? onReply;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.shouldGroupWithPrevious = false,
    this.removeTail = false,
    this.onReply,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final senderName = isMe ? 'Me' : _getSenderName(ref);
    final timestamp = _formatTimestamp(message.createdAt);
    final text = message.content['text'] as String? ?? '';
    final isDarkMode = theme.brightness == Brightness.dark;

    return RepaintBoundary(
      child: Semantics(
        label: 'Message from $senderName at $timestamp',
        value: text,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: shouldGroupWithPrevious ? 1 : 4,
          ),
          child: Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar for received messages
              if (!isMe && !shouldGroupWithPrevious) ...[
                _buildAvatar(context, ref),
                const SizedBox(width: 8),
              ] else if (!isMe)
                const SizedBox(width: 48), // Space for avatar
              // Message bubble
              Flexible(
                child: Dismissible(
                  key: ValueKey(message.id),
                  direction: DismissDirection.startToEnd,
                  dismissThresholds: const {DismissDirection.startToEnd: 0.3},
                  onDismissed: (direction) {
                    onReply?.call(message.id, text);
                  },
                  background: Container(
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 20),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.reply, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('Reply', style: TextStyle(color: Colors.blue)),
                      ],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.8,
                        ),
                        decoration: BoxDecoration(
                          color: _getBubbleColor(isMe, isDarkMode),
                          borderRadius: _getBubbleRadius(isMe, removeTail),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Sender name for group messages
                            if (!isMe && !shouldGroupWithPrevious)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  4,
                                ),
                                child: Text(
                                  _getSenderName(ref),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: _getSenderNameColor(
                                      isMe,
                                      isDarkMode,
                                    ),
                                  ),
                                ),
                              ),

                            // Message content
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                16,
                                (!isMe && !shouldGroupWithPrevious) ? 0 : 12,
                                16,
                                (!isMe && !shouldGroupWithPrevious) ? 12 : 8,
                              ),
                              child: _buildMessageContent(context),
                            ),
                          ],
                        ),
                      ),

                      // Timestamp and status
                      if (!shouldGroupWithPrevious)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                timestamp,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                              ),
                              if (isMe) ...[
                                const SizedBox(width: 4),
                                _buildStatusIndicator(context),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Avatar for sent messages
              if (isMe && !shouldGroupWithPrevious) ...[
                const SizedBox(width: 8),
                _buildAvatar(context, ref),
              ] else if (isMe)
                const SizedBox(width: 48), // Space for avatar
            ],
          ),
        ),
      ),
    );
  }

  Color _getBubbleColor(bool isMe, bool isDarkMode) {
    if (isMe) {
      return const Color(0xFFDCF8C6); // Pale Green for sent messages
    } else {
      return isDarkMode
          ? const Color(0xFF2C2C2C) // Dark grey for received in dark mode
          : Colors.white; // White for received in light mode
    }
  }

  Color _getSenderNameColor(bool isMe, bool isDarkMode) {
    if (isMe) {
      return isDarkMode ? Colors.white70 : Colors.black54;
    } else {
      return isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700;
    }
  }

  BorderRadius _getBubbleRadius(bool isMe, bool removeTail) {
    const radius = Radius.circular(12);
    const tailRadius = Radius.circular(4);

    if (removeTail) {
      return BorderRadius.only(
        topLeft: radius,
        topRight: radius,
        bottomLeft: radius,
        bottomRight: radius,
      );
    }

    return BorderRadius.only(
      topLeft: isMe ? radius : tailRadius,
      topRight: isMe ? tailRadius : radius,
      bottomLeft: isMe ? radius : tailRadius,
      bottomRight: isMe ? tailRadius : radius,
    );
  }

  Widget _buildAvatar(BuildContext context, WidgetRef ref) {
    final senderName = _getSenderName(ref);
    return CircleAvatar(
      radius: 16,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Text(
        senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 14,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildMessageContent(BuildContext context) {
    final theme = Theme.of(context);
    final isEncrypted = message.content['encrypted'] == true;

    // Show encryption indicator
    if (isEncrypted) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock, size: 14, color: Colors.green.shade700),
              const SizedBox(width: 4),
              Text(
                'Encrypted message',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.green.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message.content['text'] as String? ?? '[Encrypted]',
            style: TextStyle(
              fontSize: 15,
              height: 1.4,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      );
    }

    // Handle different message types
    switch (message.type) {
      case RoomEventType.image:
        return _buildImageContent(context);
      case RoomEventType.video:
        return _buildVideoContent(context);
      case RoomEventType.audio:
        return _buildAudioContent(context);
      case RoomEventType.file:
        return _buildFileContent(context);
      case RoomEventType.reaction:
        return _buildReactionContent(context);
      default:
        return _buildTextContent(context);
    }
  }

  Widget _buildTextContent(BuildContext context) {
    final text = message.content['text'] as String? ?? '';
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Text(
      text,
      style: TextStyle(
        fontSize: 16,
        height: 1.5,
        color: _getTextColor(isMe, isDarkMode),
        fontWeight: FontWeight.w400,
      ),
    );
  }

  Color _getTextColor(bool isMe, bool isDarkMode) {
    if (isMe) {
      return Colors.black87; // Dark text on light green background
    } else {
      return isDarkMode ? Colors.white : Colors.black87;
    }
  }

  Widget _buildImageContent(BuildContext context) {
    final url = message.content['url'] as String?;
    final localPath = message.content['localPath'] as String?;
    final caption = message.content['caption'] as String?;
    final isUploading = message.content['uploading'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 250),
            child: isUploading && localPath != null
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.file(
                        File(localPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _buildMediaPlaceholder(Icons.image),
                      ),
                      Container(
                        color: Colors.black45,
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  )
                : url != null
                ? Image.network(
                    url,
                    fit: BoxFit.cover,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return _buildMediaPlaceholder(Icons.image);
                    },
                    errorBuilder: (_, _, _) =>
                        _buildMediaPlaceholder(Icons.broken_image),
                  )
                : localPath != null
                ? Image.file(
                    File(localPath),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        _buildMediaPlaceholder(Icons.image),
                  )
                : _buildMediaPlaceholder(Icons.image),
          ),
        ),
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            caption,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildVideoContent(BuildContext context) {
    final url = message.content['url'] as String?;
    final thumbnailUrl = message.content['thumbnailUrl'] as String?;
    final caption = message.content['caption'] as String?;
    final isUploading = message.content['uploading'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: url != null ? () => _openUrl(url) : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 250),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (thumbnailUrl != null)
                    Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _buildMediaPlaceholder(Icons.videocam),
                    )
                  else
                    _buildMediaPlaceholder(Icons.videocam),
                  if (isUploading)
                    Container(
                      color: Colors.black45,
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            caption,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAudioContent(BuildContext context) {
    final duration = message.content['duration'] as int?;
    final isUploading = message.content['uploading'] == true;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: isUploading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.play_arrow,
                  color: Theme.of(context).colorScheme.primary,
                ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Voice message', style: TextStyle(fontSize: 14)),
            if (duration != null)
              Text(
                _formatDuration(duration),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildFileContent(BuildContext context) {
    final fileName = message.content['fileName'] as String? ?? 'File';
    final fileSize = message.content['fileSize'] as int?;
    final url = message.content['url'] as String?;
    final isUploading = message.content['uploading'] == true;

    return GestureDetector(
      onTap: url != null ? () => _openUrl(url) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: isUploading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.insert_drive_file,
                    color: Theme.of(context).colorScheme.primary,
                  ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (fileSize != null)
                  Text(
                    _formatFileSize(fileSize),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionContent(BuildContext context) {
    final emoji = message.content['emoji'] as String? ?? '👍';
    return Text(emoji, style: const TextStyle(fontSize: 24));
  }

  Widget _buildMediaPlaceholder(IconData icon) {
    return Container(
      width: 150,
      height: 100,
      color: Colors.grey.shade300,
      child: Icon(icon, size: 40, color: Colors.grey.shade600),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  String _formatDuration(int milliseconds) {
    final seconds = (milliseconds / 1000).round();
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
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

    return Icon(iconData, size: 14, color: iconColor);
  }

  String _getSenderName(WidgetRef ref) {
    // Try to get sender name from profiles
    final profilesAsync = ref.watch(profilesWithContactsProvider);

    return profilesAsync.when(
      data: (profiles) {
        // Find profile matching sender ID
        final senderProfile = profiles
            .where((p) => p.profile.id == message.senderId)
            .firstOrNull;
        if (senderProfile != null) {
          return senderProfile.displayName;
        }
        // Fallback to sender ID if profile not found
        return message.senderId;
      },
      loading: () => message.senderId,
      error: (_, _) => message.senderId,
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();

    if (date.day == now.day &&
        date.month == now.month &&
        date.year == now.year) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }

    return '${date.day}/${date.month} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
