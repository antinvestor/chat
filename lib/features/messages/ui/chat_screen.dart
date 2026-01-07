import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../advanced/ui/motion_bubble.dart';
import '../../advanced/ui/transaction_bubble.dart';
import '../../auth/data/auth_repository.dart';
import '../../calls/services/call_manager.dart';
import '../../calls/ui/call_screen.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/sync/sync_engine.dart';
import '../data/message_providers.dart';
import '../data/message_sending_service.dart';
import '../data/typing_provider.dart';
import '../domain/room_event.dart';
import 'message_bubble.dart';
import 'typing_indicator.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String roomId;
  final String roomName;

  const ChatScreen({super.key, required this.roomId, required this.roomName});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  Timer? _typingDebounce;
  Timer? _readReceiptDebounce;
  bool _isEncryptionEnabled = false;
  bool _isUploading = false;
  double _uploadProgress = 0;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _typingDebounce?.cancel();
    _readReceiptDebounce?.cancel();
    super.dispose();
  }

  void _sendReadReceipts(List<RoomEvent> messages) {
    // Cancel previous debounce
    _readReceiptDebounce?.cancel();

    _readReceiptDebounce = Timer(const Duration(milliseconds: 500), () async {
      try {
        final currentProfileIdAsync = ref.read(currentProfileIdProvider);
        final currentProfileId = currentProfileIdAsync.value ?? '';
        if (currentProfileId.isEmpty) return;

        final unreadIds = messages
            .where(
              (m) =>
                  m.senderId != currentProfileId &&
                  m.status != EventStatus.read,
            )
            .map((m) => m.id)
            .toList();

        if (unreadIds.isNotEmpty) {
          final syncEngine = await ref.read(syncEngineProvider.future);
          await syncEngine.sendReadReceipts(widget.roomId, unreadIds);
        }
      } catch (e) {
        // Silently fail for read receipts - they're not critical
        AppLogger.error('Failed to send read receipts', error: e);
      }
    });
  }

  void _onTextChanged(String text) {
    if (_typingDebounce?.isActive ?? false) _typingDebounce!.cancel();

    // Send typing event when user starts typing
    if (text.isNotEmpty) {
      ref.read(typingProvider(widget.roomId).notifier).sendTyping(true);
    }

    _typingDebounce = Timer(const Duration(seconds: 2), () {
      // Send typing stopped event
      ref.read(typingProvider(widget.roomId).notifier).sendTyping(false);
    });
  }

  Future<void> _sendMessage() async {
    if (_controller.text.trim().isEmpty) return;

    final messagingService = ref.read(messageSendingServiceProvider);
    await messagingService.sendTextMessage(
      roomId: widget.roomId,
      text: _controller.text.trim(),
      encrypt: _isEncryptionEnabled,
    );
    _controller.clear();
  }

  Future<void> _pickAndSendImage() async {
    final XFile? image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (image != null) {
      await _sendMediaFile(File(image.path), RoomEventType.image);
    }
  }

  Future<void> _takeAndSendPhoto() async {
    final XFile? photo = await _imagePicker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (photo != null) {
      await _sendMediaFile(File(photo.path), RoomEventType.image);
    }
  }

  Future<void> _pickAndSendVideo() async {
    final XFile? video = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (video != null) {
      await _sendMediaFile(File(video.path), RoomEventType.video);
    }
  }

  Future<void> _pickAndSendFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      await _sendMediaFile(File(result.files.single.path!), RoomEventType.file);
    }
  }

  Future<void> _sendMediaFile(File file, RoomEventType type) async {
    setState(() {
      _isUploading = true;
      _uploadProgress = 0;
    });

    try {
      final messagingService = ref.read(messageSendingServiceProvider);

      switch (type) {
        case RoomEventType.image:
          await messagingService.sendImageMessage(
            roomId: widget.roomId,
            imageFile: file,
            encrypt: _isEncryptionEnabled,
            onProgress: (progress) {
              setState(() => _uploadProgress = progress);
            },
          );
          break;
        case RoomEventType.video:
          await messagingService.sendVideoMessage(
            roomId: widget.roomId,
            videoFile: file,
            encrypt: _isEncryptionEnabled,
            onProgress: (progress) {
              setState(() => _uploadProgress = progress);
            },
          );
          break;
        case RoomEventType.file:
          await messagingService.sendFileMessage(
            roomId: widget.roomId,
            file: file,
            encrypt: _isEncryptionEnabled,
            onProgress: (progress) {
              setState(() => _uploadProgress = progress);
            },
          );
          break;
        default:
          break;
      }

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File sent successfully')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to send file: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Photo from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendImage();
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _takeAndSendPhoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendVideo();
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('File'),
              onTap: () {
                Navigator.pop(context);
                _pickAndSendFile();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messageListProvider(widget.roomId));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.roomName),
            if (_isEncryptionEnabled)
              const Row(
                children: [
                  Icon(Icons.lock, size: 12, color: Colors.green),
                  SizedBox(width: 4),
                  Text(
                    'Encrypted',
                    style: TextStyle(fontSize: 12, color: Colors.green),
                  ),
                ],
              ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // Navigate back to room list
            context.go('/');
          },
          tooltip: 'Back to rooms',
        ),
        actions: [
          IconButton(
            icon: Icon(
              _isEncryptionEnabled ? Icons.lock : Icons.lock_open,
              color: _isEncryptionEnabled ? Colors.green : null,
            ),
            onPressed: () {
              setState(() => _isEncryptionEnabled = !_isEncryptionEnabled);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _isEncryptionEnabled
                        ? 'End-to-end encryption enabled'
                        : 'End-to-end encryption disabled',
                  ),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            tooltip: 'Toggle encryption',
          ),
          IconButton(
            icon: const Icon(Icons.video_call),
            onPressed: () async {
              final callManager = await ref.read(callManagerProvider.future);
              await callManager.startCall(widget.roomId);
              if (context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CallScreen(
                      roomId: widget.roomId,
                      roomName: widget.roomName,
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              data: (messages) {
                if (messages.isEmpty) {
                  return const Center(child: Text('No messages yet'));
                }

                // Send read receipts for messages being viewed
                _sendReadReceipts(messages);

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true, // Start from bottom
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    // Reverse index since we're using reverse: true
                    final reversedIndex = messages.length - 1 - index;
                    final message = messages[reversedIndex];

                    // Get current profile ID for proper message positioning
                    final currentProfileId = ref.watch(
                      currentProfileIdProvider,
                    );
                    final isMe = message.senderId == currentProfileId.value;

                    // Show avatar only for first message in a group
                    final showAvatar =
                        reversedIndex == messages.length - 1 ||
                        messages[reversedIndex + 1].senderId !=
                            message.senderId;

                    return _buildMessageWidget(message, isMe, showAvatar);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stack) => Center(child: Text('Error: $error')),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Upload progress indicator
                if (_isUploading)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: LinearProgressIndicator(
                            value: _uploadProgress > 0 ? _uploadProgress : null,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _uploadProgress > 0
                              ? '${(_uploadProgress * 100).toInt()}%'
                              : 'Uploading...',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                TypingIndicator(roomId: widget.roomId),
                Row(
                  children: [
                    // Attachment button
                    IconButton(
                      icon: const Icon(Icons.attach_file),
                      onPressed: _isUploading ? null : _showAttachmentOptions,
                      tooltip: 'Attach file',
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: _isEncryptionEnabled
                              ? 'Type an encrypted message...'
                              : 'Type a message...',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          prefixIcon: _isEncryptionEnabled
                              ? const Icon(
                                  Icons.lock,
                                  size: 18,
                                  color: Colors.green,
                                )
                              : null,
                        ),
                        onChanged: _onTextChanged,
                        onSubmitted: (_) => _sendMessage(),
                        enabled: !_isUploading,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: const Icon(Icons.send),
                      onPressed: _isUploading ? null : _sendMessage,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageWidget(RoomEvent message, bool isMe, bool showAvatar) {
    switch (message.type) {
      case RoomEventType.motion:
        return MotionBubble(event: message, isMe: isMe);

      case RoomEventType.transaction:
        return TransactionBubble(event: message, isMe: isMe);

      default:
        return MessageBubble(
          message: message,
          isMe: isMe,
          showAvatar: showAvatar,
        );
    }
  }
}
