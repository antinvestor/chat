import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:xid/xid.dart';

import '../../advanced/ui/motion_bubble.dart';
import '../services/voice_recording_service.dart';
import '../../advanced/ui/transaction_bubble.dart';
import '../../auth/data/auth_repository.dart';
import '../../calls/services/call_manager.dart';
import '../../calls/ui/call_screen.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/theme/app_theme.dart';
import '../data/message_providers.dart';
import '../data/typing_provider.dart';
import '../data/message_sending_service.dart';
import '../domain/room_event.dart';
import 'message_bubble.dart';
import 'input_bar.dart';
import 'date_header.dart';
import '../../../core/navigation/navigation_helper.dart';

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
  bool _showScrollToBottom = false;
  int _newMessageCount = 0;
  final bool _shouldAutoScroll = true;

  @override
  void initState() {
    super.initState();
    // Add scroll listener for scroll-to-bottom FAB
    _scrollController.addListener(_onScroll);
    // Preload chat background patterns for better performance
    WidgetsBinding.instance.addPostFrameCallback((_) {
      precacheImage(const AssetImage('assets/chat_pattern.webp'), context);
      precacheImage(
        const AssetImage('assets/chat_pattern_black.webp'),
        context,
      );
    });
  }

  void _onScroll() {
    // Show scroll-to-bottom FAB when scrolled up more than 200 pixels
    final showButton = _scrollController.offset > 200;
    if (showButton != _showScrollToBottom) {
      setState(() {
        _showScrollToBottom = showButton;
        // Reset new message count when scrolling to bottom
        if (!showButton) {
          _newMessageCount = 0;
        }
      });
    }
  }

  void _scrollToBottom() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    setState(() {
      _newMessageCount = 0;
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
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

  void _sendMessage(String text, {String? replyToMessageId}) async {
    if (text.trim().isEmpty) return;

    final messagingService = ref.read(messageSendingServiceProvider);

    // Send message - the service handles optimistic updates internally
    // by inserting into the local DB which triggers the stream update
    messagingService.sendTextMessage(
      roomId: widget.roomId,
      text: text.trim(),
      encrypt: _isEncryptionEnabled,
    );

    // Clear reply state immediately for better UX
    if (replyToMessageId != null) {
      setState(() {
        _replyingToMessageId = null;
        _replyingToText = null;
      });
    }

    // Scroll to bottom to see the new message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onReplyToMessage(String messageId, String messageText) {
    setState(() {
      _replyingToMessageId = messageId;
      _replyingToText = messageText;
    });
  }

  Future<void> _retryMessage(RoomEvent message) async {
    try {
      final messagingService = ref.read(messageSendingServiceProvider);
      await messagingService.retryMessage(message.localId ?? message.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Retrying message...'),
            duration: Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to retry: $e')));
      }
    }
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
    final messagesAsync = ref.watch(messagesStreamProvider(widget.roomId));

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: _buildAppBar(context),
      body: SafeArea(
        child: Column(
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
                          opacity:
                              Theme.of(context).brightness == Brightness.dark
                              ? 0.08 // 8% for dark theme (6-10% range)
                              : 0.05, // 5% for light theme
                        ),
                ),
                child: Stack(
                  children: [
                    messagesAsync.when(
                      data: (messages) => _buildMessageList(messages),
                      loading: () => _buildLoadingState(),
                      error: (error, stack) => _buildErrorState(error, stack),
                    ),
                    // Enhanced typing indicator overlay
                    Consumer(
                      builder: (context, ref, child) {
                        final typingUsers = ref.watch(
                          typingProvider(widget.roomId),
                        );
                        final isAnyoneTyping = typingUsers.isNotEmpty;

                        return isAnyoneTyping
                            ? Positioned(
                                bottom: 80,
                                left: 16,
                                right: 16,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surface,
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.1,
                                        ),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color?>(
                                                AppTheme.primaryGreen,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          'Someone is typing...',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : const SizedBox.shrink();
                      },
                    ),
                    // Scroll-to-bottom FAB with new message count
                    if (_showScrollToBottom)
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: _buildScrollToBottomButton(),
                      ),
                  ],
                ),
              ),
            ),
            InputBar(
              roomId: widget.roomId,
              onSendMessage: _sendMessage,
              onAttachment: _showAttachmentOptions,
              onCamera: _takeAndSendPhoto,
              onVoiceRecordingComplete: _onVoiceRecordingComplete,
              isEncryptionEnabled: _isEncryptionEnabled,
              replyingToMessageId: _replyingToMessageId,
              replyingToText: _replyingToText,
              onCancelReply: _cancelReply,
            ),
          ],
        ),
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
        // Enhanced auto-scroll with better performance
        if (scrollInfo is ScrollEndNotification &&
            scrollInfo.metrics.extentAfter == 0) {
          // User is at bottom, keep them there
        } else if (scrollInfo is ScrollUpdateNotification) {
          // Auto-scroll to bottom when new messages arrive
          if (_shouldAutoScroll) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: messages.length,
        // Performance optimizations for smooth scrolling
        cacheExtent: MediaQuery.of(context).size.height * 2, // Cache 2 screens
        addAutomaticKeepAlives: false, // Reduce memory for off-screen items
        addRepaintBoundaries: true, // Isolate repaints
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        itemBuilder: (context, index) {
          final reversedIndex = messages.length - 1 - index;
          final message = messages[reversedIndex];
          final currentProfileId = ref.watch(currentProfileIdProvider);
          final isMe = message.senderId == currentProfileId.value;

          // Enhanced message grouping with better performance
          bool showDateHeader = false;
          bool shouldGroupWithPrevious = false;
          bool removeTail = false;

          if (reversedIndex < messages.length - 1) {
            final nextMessage = messages[reversedIndex + 1];
            final timeDiff = message.createdAt - nextMessage.createdAt;
            shouldGroupWithPrevious =
                nextMessage.senderId == message.senderId &&
                timeDiff < 120000; // 2 minutes
            removeTail = shouldGroupWithPrevious;
          } else {
            showDateHeader = true;
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
    // Navigate to room details screen with fluid animation
    context.navigateToRoomDetails(
      roomId: widget.roomId,
      roomName: widget.roomName,
    );
  }

  void _onVoiceRecordingComplete(VoiceRecordingResult result) {
    // Voice recording completed, send as audio message
    _sendAudioMessage(result);
  }

  Future<void> _sendAudioMessage(VoiceRecordingResult recording) async {
    try {
      // Create audio message event
      final event = RoomEvent(
        id: Xid().toString(),
        roomId: widget.roomId,
        senderId: '', // Will be set by the provider
        type: RoomEventType.audio,
        content: {
          'path': recording.path,
          'duration': recording.duration.inSeconds,
          'size': recording.sizeBytes,
          'mimeType': recording.mimeType,
          'fileName': recording.fileName,
        },
        status: EventStatus.pending,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        localId: Xid().toString(),
      );

      // Send the message through the provider
      // Note: The actual file upload will be handled by the file upload service
      await ref
          .read(messageListProvider(widget.roomId).notifier)
          .sendMessage(event);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Voice message sent (${recording.formattedDuration})',
            ),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send voice message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
          onRetry: message.status == EventStatus.failed
              ? () => _retryMessage(message)
              : null,
        );
    }
  }

  Widget _buildScrollToBottomButton() {
    return GestureDetector(
      onTap: _scrollToBottom,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.keyboard_arrow_down,
              color: Theme.of(context).colorScheme.onSurface,
              size: 28,
            ),
            if (_newMessageCount > 0)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryGreen,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Text(
                    _newMessageCount > 99 ? '99+' : '$_newMessageCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
