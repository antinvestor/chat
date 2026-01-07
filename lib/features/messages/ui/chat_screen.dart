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
import '../../../core/theme/app_theme.dart';
import '../data/message_providers.dart';
import '../data/message_sending_service.dart';
import '../domain/room_event.dart';
import 'message_bubble.dart';
import 'input_bar.dart';
import 'date_header.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String roomId;
  final String roomName;

  const ChatScreen({super.key, required this.roomId, required this.roomName});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  Timer? _readReceiptDebounce;
  bool _isEncryptionEnabled = false;
  String? _replyingToMessageId;
  String? _replyingToText;
  bool _isVoiceRecording = false;
  Timer? _voiceRecordingTimer;

  @override
  void initState() {
    super.initState();
    // Preload chat background patterns for better performance
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/chat_pattern.webp'), context);
      precacheImage(
        const AssetImage('assets/chat_pattern_black.webp'),
        context,
      );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _readReceiptDebounce?.cancel();
    _voiceRecordingTimer?.cancel();
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

  void _sendMessage(String text, {String? replyToMessageId}) async {
    if (text.trim().isEmpty) return;

    final messagingService = ref.read(messageSendingServiceProvider);
    await messagingService.sendTextMessage(
      roomId: widget.roomId,
      text: text.trim(),
      encrypt: _isEncryptionEnabled,
    );

    // Clear reply state after sending
    if (replyToMessageId != null) {
      setState(() {
        _replyingToMessageId = null;
        _replyingToText = null;
      });
    }
  }

  void _onReplyToMessage(String messageId, String messageText) {
    setState(() {
      _replyingToMessageId = messageId;
      _replyingToText = messageText;
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingToMessageId = null;
      _replyingToText = null;
    });
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
    try {
      final messagingService = ref.read(messageSendingServiceProvider);

      switch (type) {
        case RoomEventType.image:
          await messagingService.sendImageMessage(
            roomId: widget.roomId,
            imageFile: file,
            encrypt: _isEncryptionEnabled,
          );
          break;
        case RoomEventType.video:
          await messagingService.sendVideoMessage(
            roomId: widget.roomId,
            videoFile: file,
            encrypt: _isEncryptionEnabled,
          );
          break;
        case RoomEventType.file:
          await messagingService.sendFileMessage(
            roomId: widget.roomId,
            file: file,
            encrypt: _isEncryptionEnabled,
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF121212) // Optimized dark background
                    : Theme.of(context).colorScheme.surface,
                image: _isEncryptionEnabled
                    ? null
                    : DecorationImage(
                        image: AssetImage(
                          Theme.of(context).brightness == Brightness.dark
                              ? 'assets/chat_pattern_black.webp'
                              : 'assets/chat_pattern.webp',
                        ),
                        repeat: ImageRepeat.repeat,
                        fit: BoxFit.none,
                        opacity: Theme.of(context).brightness == Brightness.dark
                            ? 0.08 // 8% for dark theme (6-10% range)
                            : 0.05, // 5% for light theme
                      ),
              ),
              child: messagesAsync.when(
                data: (messages) => _buildMessageList(messages),
                loading: () => _buildLoadingState(),
                error: (error, stack) => _buildErrorState(error, stack),
              ),
            ),
          ),
          SafeArea(
            child: InputBar(
              roomId: widget.roomId,
              onSendMessage: _sendMessage,
              onAttachment: _showAttachmentOptions,
              onCamera: _takeAndSendPhoto,
              onVoiceRecord: _onVoiceRecord,
              isEncryptionEnabled: _isEncryptionEnabled,
              replyingToMessageId: _replyingToMessageId,
              replyingToText: _replyingToText,
              onCancelReply: _cancelReply,
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      title: GestureDetector(
        onTap: () => _openContactInfo(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppTheme.primaryGreen,
                  child: Text(
                    widget.roomName.isNotEmpty
                        ? widget.roomName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.roomName,
                        style: AppTheme.bodyText.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).appBarTheme.foregroundColor,
                        ),
                      ),
                      Text(
                        'Last seen recently',
                        style: AppTheme.metadataText.copyWith(
                          color: Theme.of(
                            context,
                          ).appBarTheme.foregroundColor?.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/'),
      ),
      actions: [
        IconButton(
          icon: Icon(
            _isEncryptionEnabled ? Icons.lock : Icons.lock_open,
            color: _isEncryptionEnabled ? Colors.green : null,
          ),
          onPressed: _toggleEncryption,
        ),
        IconButton(icon: const Icon(Icons.video_call), onPressed: _startCall),
      ],
    );
  }

  Widget _buildMessageList(List<RoomEvent> messages) {
    if (messages.isEmpty) {
      return _buildEmptyState();
    }

    // Send read receipts for messages being viewed
    _sendReadReceipts(messages);

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollInfo) {
        // Auto-scroll to bottom when new messages arrive
        if (scrollInfo is ScrollEndNotification &&
            scrollInfo.metrics.extentAfter == 0) {
          // User is at the bottom, keep them there
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: messages.length,
        // Performance optimization: cache extent
        cacheExtent: 500,
        itemBuilder: (context, index) {
          final reversedIndex = messages.length - 1 - index;
          final message = messages[reversedIndex];
          final currentProfileId = ref.watch(currentProfileIdProvider);
          final isMe = message.senderId == currentProfileId.value;

          // Check if we should show date header
          bool showDateHeader = false;
          if (reversedIndex < messages.length - 1) {
            final nextMessage = messages[reversedIndex + 1];
            final currentDate = DateTime.fromMillisecondsSinceEpoch(
              message.createdAt,
            );
            final nextDate = DateTime.fromMillisecondsSinceEpoch(
              nextMessage.createdAt,
            );
            showDateHeader = !_isSameDay(currentDate, nextDate);
          } else {
            showDateHeader = true;
          }

          // Check message grouping for bubble styling
          bool shouldGroupWithPrevious = false;
          bool removeTail = false;

          if (reversedIndex < messages.length - 1) {
            final nextMessage = messages[reversedIndex + 1];
            final timeDiff = message.createdAt - nextMessage.createdAt;
            shouldGroupWithPrevious =
                nextMessage.senderId == message.senderId &&
                timeDiff < 120000; // 2 minutes
            removeTail = shouldGroupWithPrevious;
          }

          return Column(
            children: [
              if (showDateHeader) DateHeader(timestamp: message.createdAt),
              _buildMessageWidget(
                message,
                isMe,
                shouldGroupWithPrevious,
                removeTail,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Start the conversation',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Send a message to begin chatting with ${widget.roomName}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).colorScheme.primary,
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Text(
              'Say Hello!',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: CircularProgressIndicator(
              color: Theme.of(context).colorScheme.primary,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Loading messages...',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Please wait while we fetch your conversation',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(Object error, StackTrace stack) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline, size: 64, color: Colors.red),
          ),
          const SizedBox(height: 24),
          Text(
            'Something went wrong',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Unable to load messages. Please try again.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => ref.refresh(messageListProvider(widget.roomId)),
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.day == date2.day &&
        date1.month == date2.month &&
        date1.year == date2.year;
  }

  void _toggleEncryption() {
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
  }

  void _startCall() async {
    final callManager = await ref.read(callManagerProvider.future);
    await callManager.startCall(widget.roomId);
    if (mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              CallScreen(roomId: widget.roomId, roomName: widget.roomName),
        ),
      );
    }
  }

  void _openContactInfo() {
    // Navigate to contact info screen
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Contact info coming soon')));
  }

  void _onVoiceRecord() {
    setState(() {
      _isVoiceRecording = !_isVoiceRecording;
    });

    if (_isVoiceRecording) {
      _voiceRecordingTimer = Timer(const Duration(seconds: 30), () {
        if (mounted) {
          setState(() {
            _isVoiceRecording = false;
          });
        }
      });
    } else {
      _voiceRecordingTimer?.cancel();
    }
  }

  Widget _buildMessageWidget(
    RoomEvent message,
    bool isMe,
    bool shouldGroupWithPrevious,
    bool removeTail,
  ) {
    switch (message.type) {
      case RoomEventType.motion:
        return MotionBubble(event: message, isMe: isMe);
      case RoomEventType.transaction:
        return TransactionBubble(event: message, isMe: isMe);
      default:
        return MessageBubble(
          message: message,
          isMe: isMe,
          shouldGroupWithPrevious: shouldGroupWithPrevious,
          removeTail: removeTail,
          onReply: _onReplyToMessage,
        );
    }
  }
}
