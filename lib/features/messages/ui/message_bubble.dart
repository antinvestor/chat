import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../features/contacts/data/roster_repository.dart';
import '../../../features/rooms/data/room_subscription_service.dart';
import '../data/upload_progress_provider.dart';
import '../domain/room_event.dart';
import '../domain/upload_progress.dart';
import 'read_receipt_indicator.dart';
import 'widgets/upload_progress_indicator.dart';
import 'widgets/voice_message_player.dart';

class MessageBubble extends ConsumerWidget {
  const MessageBubble({
    required this.message,
    required this.isMe,
    super.key,
    this.shouldGroupWithPrevious = false,
    this.removeTail = false,
    this.isGroupChat = false,
    this.onReply,
    this.onRetry,
    this.onEdit,
    this.canEdit = false,
    this.onDelete,
    this.canDelete = false,
    this.onForward,
    this.canForward = false,
    this.onCancelUpload,
    this.onRetryUpload,
  });
  final RoomEvent message;
  final bool isMe;
  final bool shouldGroupWithPrevious;
  final bool removeTail;
  final bool isGroupChat;
  final Function(String messageId, String messageText)? onReply;
  final VoidCallback? onRetry;
  final Function(String messageId, String currentText)? onEdit;
  final bool canEdit;
  final Function(String messageId, {required bool forEveryone})? onDelete;
  final bool canDelete;
  final Function(RoomEvent message)? onForward;
  final bool canForward;
  final Function(String localId)? onCancelUpload;
  final Function(String localId)? onRetryUpload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final timestamp = _formatTimestamp(message.createdAt);
    final text = message.content['text'] as String? ?? '';
    final isDarkMode = theme.brightness == Brightness.dark;

    // Handle deleted messages
    if (message.isDeleted) {
      return _buildDeletedMessage(context, timestamp, isDarkMode);
    }

    return RepaintBoundary(
      key: ValueKey(
        message.id,
      ), // Performance: Only rebuild when message changes
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
          child: Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Avatar for received messages (performance: only build when needed)
              if (!isMe && !shouldGroupWithPrevious) ...[
                _buildAvatar(context, ref),
                const SizedBox(width: 8),
              ] else if (!isMe)
                const SizedBox(width: 48), // Space for avatar
              // Message bubble with enhanced performance
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _showMessageMenu(context, text),
                  child: Dismissible(
                    key: ValueKey(
                      message.id,
                    ), // Performance: Stable key for ListView
                    direction: DismissDirection.startToEnd,
                    dismissThresholds: const {DismissDirection.startToEnd: 0.3},
                    // Use confirmDismiss instead of onDismissed to prevent actual dismissal
                    // We just want to trigger the reply action, not remove the message
                    confirmDismiss: (direction) async {
                      onReply?.call(message.id, text);
                      return false; // Never actually dismiss - just trigger reply
                    },
                    background: Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 20),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: _getBubbleRadius(isMe, removeTail),
                      ),
                      child: const Icon(Icons.reply, color: Colors.blue),
                    ),
                    child: Container(
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
                          // Sender name for group messages (performance: conditional)
                          if (!isMe && !shouldGroupWithPrevious)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
                              child: Text(
                                _getSenderName(ref),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _getSenderNameColor(isMe, isDarkMode),
                                ),
                              ),
                            ),
                          // Forwarded indicator
                          if (message.isForwarded)
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                12,
                                (!isMe && !shouldGroupWithPrevious) ? 2 : 8,
                                12,
                                4,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.shortcut,
                                    size: 14,
                                    color: isDarkMode
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Forwarded',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: isDarkMode
                                          ? Colors.grey.shade400
                                          : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Message content with inline timestamp (WhatsApp style)
                          Stack(
                            children: [
                              Padding(
                                padding: EdgeInsets.fromLTRB(
                                  12,
                                  (message.isForwarded ||
                                          (!isMe && !shouldGroupWithPrevious))
                                      ? 0
                                      : 8,
                                  12,
                                  6,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _buildMessageContent(context, ref),
                                    // Spacer for timestamp+status
                                    const SizedBox(height: 16),
                                  ],
                                ),
                              ),
                              // WhatsApp-style inline timestamp and status at bottom-right
                              Positioned(
                                bottom: 4,
                                right: 8,
                                child: _buildTimestampAndStatus(
                                  context,
                                  timestamp,
                                ),
                              ),
                            ],
                          ),
                          // Failed message retry button
                          if (isMe && message.status == EventStatus.failed)
                            _buildRetryButton(context),
                        ],
                      ),
                    ),
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

  /// Build placeholder for deleted messages
  Widget _buildDeletedMessage(
    BuildContext context,
    String timestamp,
    bool isDarkMode,
  ) => Align(
    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.grey.shade800.withValues(alpha: 0.5)
            : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.block,
            size: 16,
            color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
          const SizedBox(width: 8),
          Text(
            isMe ? 'You deleted this message' : 'This message was deleted',
            style: TextStyle(
              fontSize: 14,
              fontStyle: FontStyle.italic,
              color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            timestamp,
            style: TextStyle(
              fontSize: 11,
              color: isDarkMode ? Colors.grey.shade500 : Colors.grey.shade500,
            ),
          ),
        ],
      ),
    ),
  );

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
      return const BorderRadius.only(
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

  Widget _buildMessageContent(BuildContext context, WidgetRef ref) {
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
        return _buildImageContent(context, ref);
      case RoomEventType.video:
        return _buildVideoContent(context, ref);
      case RoomEventType.audio:
        return _buildAudioContent(context, ref);
      case RoomEventType.file:
        return _buildFileContent(context, ref);
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

  Widget _buildImageContent(BuildContext context, WidgetRef ref) {
    final url = message.content['url'] as String?;
    final localPath = message.content['localPath'] as String?;
    final caption = message.content['caption'] as String?;
    final isUploading = message.content['uploading'] == true;
    final localId = message.localId;

    // Get upload progress if available
    final uploadProgress = localId != null
        ? ref.watch(singleUploadProgressProvider(localId))
        : null;
    final hasActiveUpload =
        uploadProgress != null &&
        (uploadProgress.isInProgress ||
            uploadProgress.state == UploadState.pending);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 200, maxWidth: 250),
            child: (isUploading || hasActiveUpload) && localPath != null
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.file(
                        File(localPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _buildMediaPlaceholder(Icons.image),
                      ),
                      // Use progressive upload indicator
                      if (localId != null && uploadProgress != null)
                        UploadProgressIndicator(
                          localId: localId,
                          size: 56,
                          onCancel: onCancelUpload != null
                              ? () => onCancelUpload!(localId)
                              : null,
                          onRetry: onRetryUpload != null
                              ? () => onRetryUpload!(localId)
                              : null,
                        )
                      else
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
        // Show progress bar below image during upload
        if (localId != null && hasActiveUpload) ...[
          const SizedBox(height: 4),
          UploadProgressBar(
            localId: localId,
            height: 3,
            onCancel: onCancelUpload != null
                ? () => onCancelUpload!(localId)
                : null,
            onRetry: onRetryUpload != null
                ? () => onRetryUpload!(localId)
                : null,
          ),
        ],
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

  Widget _buildVideoContent(BuildContext context, WidgetRef ref) {
    final url = message.content['url'] as String?;
    final thumbnailUrl = message.content['thumbnailUrl'] as String?;
    final localThumbnailPath = message.content['localThumbnailPath'] as String?;
    final caption = message.content['caption'] as String?;
    final isUploading = message.content['uploading'] == true;
    final localId = message.localId;

    // Get upload progress if available
    final uploadProgress = localId != null
        ? ref.watch(singleUploadProgressProvider(localId))
        : null;
    final hasActiveUpload =
        uploadProgress != null &&
        (uploadProgress.isInProgress ||
            uploadProgress.state == UploadState.pending);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: url != null && !isUploading && !hasActiveUpload
              ? () => _openUrl(url)
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Container(
              constraints: const BoxConstraints(maxHeight: 200, maxWidth: 250),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Show thumbnail (local or remote)
                  if (localThumbnailPath != null &&
                      (isUploading || hasActiveUpload))
                    Image.file(
                      File(localThumbnailPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _buildMediaPlaceholder(Icons.videocam),
                    )
                  else if (thumbnailUrl != null)
                    Image.network(
                      thumbnailUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _buildMediaPlaceholder(Icons.videocam),
                    )
                  else
                    _buildMediaPlaceholder(Icons.videocam),
                  // Upload progress or play button
                  if (isUploading || hasActiveUpload)
                    if (localId != null && uploadProgress != null)
                      UploadProgressIndicator(
                        localId: localId,
                        size: 56,
                        onCancel: onCancelUpload != null
                            ? () => onCancelUpload!(localId)
                            : null,
                        onRetry: onRetryUpload != null
                            ? () => onRetryUpload!(localId)
                            : null,
                      )
                    else
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
        // Show progress bar below video during upload
        if (localId != null && hasActiveUpload) ...[
          const SizedBox(height: 4),
          UploadProgressBar(
            localId: localId,
            height: 3,
            onCancel: onCancelUpload != null
                ? () => onCancelUpload!(localId)
                : null,
            onRetry: onRetryUpload != null
                ? () => onRetryUpload!(localId)
                : null,
          ),
        ],
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

  Widget _buildAudioContent(BuildContext context, WidgetRef ref) {
    final url = message.content['url'] as String? ?? '';
    final localPath = message.content['localPath'] as String?;
    final duration = message.content['duration'] as int? ?? 0;
    final isUploading = message.content['uploading'] == true;
    final localId = message.localId;

    // Get upload progress if available
    final uploadProgress = localId != null
        ? ref.watch(singleUploadProgressProvider(localId))
        : null;
    final hasActiveUpload =
        uploadProgress != null &&
        (uploadProgress.isInProgress ||
            uploadProgress.state == UploadState.pending);

    // Show uploading state with progress
    if (isUploading || hasActiveUpload) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Progress indicator
              if (localId != null && uploadProgress != null)
                SizedBox(
                  width: 40,
                  height: 40,
                  child: UploadProgressIndicator(
                    localId: localId,
                    size: 40,
                    showPercentage: false,
                    onCancel: onCancelUpload != null
                        ? () => onCancelUpload!(localId)
                        : null,
                    onRetry: onRetryUpload != null
                        ? () => onRetryUpload!(localId)
                        : null,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      uploadProgress?.progressText ??
                          'Sending voice message...',
                      style: const TextStyle(fontSize: 14),
                    ),
                    Text(
                      _formatDuration(duration),
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
          // Progress bar
          if (localId != null && hasActiveUpload) ...[
            const SizedBox(height: 8),
            UploadProgressBar(localId: localId, height: 3, showText: false),
          ],
        ],
      );
    }

    // Use polished VoiceMessagePlayer for playback
    return VoiceMessagePlayer(
      audioUrl: url,
      localPath: localPath,
      durationMs: duration,
      isOwnMessage: isMe,
    );
  }

  Widget _buildFileContent(BuildContext context, WidgetRef ref) {
    final fileName = message.content['fileName'] as String? ?? 'File';
    final fileSize = message.content['fileSize'] as int?;
    final url = message.content['url'] as String?;
    final isUploading = message.content['uploading'] == true;
    final localId = message.localId;

    // Get upload progress if available
    final uploadProgress = localId != null
        ? ref.watch(singleUploadProgressProvider(localId))
        : null;
    final hasActiveUpload =
        uploadProgress != null &&
        (uploadProgress.isInProgress ||
            uploadProgress.state == UploadState.pending);

    return GestureDetector(
      onTap: url != null && !isUploading && !hasActiveUpload
          ? () => _openUrl(url)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // File icon or upload progress
              if ((isUploading || hasActiveUpload) &&
                  localId != null &&
                  uploadProgress != null)
                SizedBox(
                  width: 44,
                  height: 44,
                  child: UploadProgressIndicator(
                    localId: localId,
                    size: 44,
                    onCancel: onCancelUpload != null
                        ? () => onCancelUpload!(localId)
                        : null,
                    onRetry: onRetryUpload != null
                        ? () => onRetryUpload!(localId)
                        : null,
                  ),
                )
              else
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
                      Builder(
                        builder: (context) {
                          final uploadedBytes =
                              uploadProgress?.uploadedBytes ?? 0;
                          return Text(
                            hasActiveUpload
                                ? '${_formatFileSize(uploadedBytes)} / ${_formatFileSize(fileSize)}'
                                : _formatFileSize(fileSize),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
          // Progress bar for file uploads
          if (localId != null && hasActiveUpload) ...[
            const SizedBox(height: 8),
            UploadProgressBar(
              localId: localId,
              height: 3,
              onCancel: onCancelUpload != null
                  ? () => onCancelUpload!(localId)
                  : null,
              onRetry: onRetryUpload != null
                  ? () => onRetryUpload!(localId)
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReactionContent(BuildContext context) {
    final emoji = message.content['emoji'] as String? ?? '👍';
    return Text(emoji, style: const TextStyle(fontSize: 24));
  }

  Widget _buildMediaPlaceholder(IconData icon) => Container(
    width: 150,
    height: 100,
    color: Colors.grey.shade300,
    child: Icon(icon, size: 40, color: Colors.grey.shade600),
  );

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

  /// WhatsApp-style timestamp and status row
  Widget _buildTimestampAndStatus(BuildContext context, String timestamp) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isMe
        ? Colors.black.withValues(alpha: 0.5)
        : (isDarkMode ? Colors.white60 : Colors.black54);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Show "edited" indicator if message was edited
          if (message.isEdited) ...[
            Text(
              'edited',
              style: TextStyle(
                fontSize: 10,
                fontStyle: FontStyle.italic,
                color: textColor,
              ),
            ),
            const SizedBox(width: 4),
          ],
          Text(timestamp, style: TextStyle(fontSize: 11, color: textColor)),
          if (isMe) ...[
            const SizedBox(width: 3),
            _buildStatusIndicator(context),
          ],
        ],
      ),
    );
  }

  /// Retry button for failed messages with retry count and error info
  Widget _buildRetryButton(BuildContext context) {
    final retryCount = message.retryCount;
    final errorMsg = message.errorMessage;
    final requiresManual = message.requiresManualRetry;

    return GestureDetector(
      onTap: () => _showRetryOptions(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: const BorderRadius.only(
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 14, color: Colors.red.shade600),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    requiresManual
                        ? 'Failed after $retryCount attempts. Tap for options'
                        : 'Not sent${retryCount > 0 ? " ($retryCount/$maxAutoRetries)" : ""}. Tap for options',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            // Show error message if available
            if (errorMsg != null && errorMsg.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                errorMsg,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade400,
                  fontStyle: FontStyle.italic,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Show retry/delete options for failed messages
  void _showRetryOptions(BuildContext context) {
    final theme = Theme.of(context);
    final retryCount = message.retryCount;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with retry count
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade600),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Message not sent',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (retryCount > 0)
                            Text(
                              'Attempted $retryCount time${retryCount > 1 ? "s" : ""}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Retry option
              ListTile(
                leading: Icon(Icons.refresh, color: theme.colorScheme.primary),
                title: const Text('Retry sending'),
                subtitle: const Text('Try to send the message again'),
                onTap: () {
                  Navigator.pop(context);
                  onRetry?.call();
                },
              ),
              // Delete option
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete message'),
                subtitle: const Text('Remove this unsent message'),
                onTap: () {
                  Navigator.pop(context);
                  onDelete?.call(message.id, forEveryone: false);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show context menu for message actions (reply, forward, edit, copy)
  void _showMessageMenu(BuildContext context, String text) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reply option
              if (onReply != null)
                ListTile(
                  leading: Icon(Icons.reply, color: theme.colorScheme.primary),
                  title: const Text('Reply'),
                  onTap: () {
                    Navigator.pop(context);
                    onReply?.call(message.id, text);
                  },
                ),
              // Forward option
              if (canForward && onForward != null)
                ListTile(
                  leading: Icon(
                    Icons.shortcut,
                    color: theme.colorScheme.primary,
                  ),
                  title: const Text('Forward'),
                  onTap: () {
                    Navigator.pop(context);
                    onForward?.call(message);
                  },
                ),
              // Edit option (only for own text messages within edit window)
              if (isMe && canEdit && message.type == RoomEventType.text)
                ListTile(
                  leading: Icon(Icons.edit, color: theme.colorScheme.primary),
                  title: const Text('Edit'),
                  onTap: () {
                    Navigator.pop(context);
                    onEdit?.call(message.id, text);
                  },
                ),
              // Copy option (for text messages)
              if (message.type == RoomEventType.text && text.isNotEmpty)
                ListTile(
                  leading: Icon(Icons.copy, color: theme.colorScheme.primary),
                  title: const Text('Copy'),
                  onTap: () {
                    Navigator.pop(context);
                    // Copy to clipboard
                    _copyToClipboard(context, text);
                  },
                ),
              // Delete for me option (available for all messages)
              if (onDelete != null)
                ListTile(
                  leading: const Icon(
                    Icons.delete_outline,
                    color: Colors.orange,
                  ),
                  title: const Text('Delete for me'),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(context, forEveryone: false);
                  },
                ),
              // Delete for everyone option (only for own messages within window)
              if (isMe && canDelete && onDelete != null)
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: const Text('Delete for everyone'),
                  onTap: () {
                    Navigator.pop(context);
                    _showDeleteConfirmation(context, forEveryone: true);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Copy text to clipboard with feedback
  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  /// Show delete confirmation dialog
  void _showDeleteConfirmation(
    BuildContext context, {
    required bool forEveryone,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(forEveryone ? 'Delete for everyone?' : 'Delete for me?'),
        content: Text(
          forEveryone
              ? 'This message will be deleted for everyone in this chat. '
                    'Others will see that a message was deleted.'
              : 'This message will be removed from your device only. '
                    'Others will still see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onDelete?.call(message.id, forEveryone: forEveryone);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// WhatsApp-style status indicator with ticks
  ///
  /// Uses ReadReceiptIndicator widget which supports:
  /// - Pending: clock icon
  /// - Sent: single grey check
  /// - Delivered: double grey check
  /// - Read: double blue check (tappable in group chats to show readers)
  /// - Failed: error icon
  Widget _buildStatusIndicator(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Use ReadReceiptIndicator for tappable read receipts in groups
    return ReadReceiptIndicator(
      event: message,
      isGroupChat: isGroupChat,
      sentColor: isMe
          ? Colors.black.withValues(alpha: 0.5)
          : (isDarkMode ? Colors.white54 : Colors.black54),
      readColor: const Color(0xFF53BDEB), // WhatsApp blue
    );
  }

  String _getSenderName(WidgetRef ref) {
    // message.senderId is a subscription ID, need to look up the profile
    // First, get the profile ID from the subscription
    final profileIdAsync = ref.watch(
      profileIdFromSubscriptionProvider(message.senderId),
    );
    final profilesAsync = ref.watch(profilesWithContactsProvider);

    // Get the profile ID (or use senderId as fallback if lookup fails)
    final profileId = profileIdAsync.when(
      data: (id) => id,
      loading: () => null,
      error: (_, _) => null,
    );

    return profilesAsync.when(
      data: (profiles) {
        if (profileId != null) {
          // Find profile matching the looked-up profile ID
          final senderProfile = profiles
              .where((p) => p.profile.id == profileId)
              .firstOrNull;
          if (senderProfile != null) {
            return senderProfile.displayName;
          }
        }
        // Fallback to sender ID (subscription ID) if profile not found
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
