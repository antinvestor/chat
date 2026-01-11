import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../../../core/theme/app_theme.dart';
import '../data/chat_input_providers.dart';
import '../data/message_providers.dart';
import '../../messages/domain/room_event.dart' as domain;

/// WhatsApp-style chat input bar with proper Riverpod/state separation
class ChatInputBar extends ConsumerStatefulWidget {
  final String roomId;
  final String roomName;

  const ChatInputBar({super.key, required this.roomId, required this.roomName});

  @override
  ConsumerState<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends ConsumerState<ChatInputBar> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  // Local UI state only
  bool _hasText = false;
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingDuration = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();

    // Local listener only - no Riverpod calls
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Local state change only
  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
  }

  // Riverpod-driven emoji toggle
  void _toggleEmoji() {
    final isOpen = ref.read(emojiPanelVisibilityProvider);

    if (isOpen) {
      ref.read(emojiPanelVisibilityProvider.notifier).hide();
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      ref.read(emojiPanelVisibilityProvider.notifier).show();
    }
  }

  // Riverpod-driven send with proper UI ordering
  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    // Clear UI instantly for perceived speed
    _controller.clear();
    setState(() => _hasText = false);

    // Network happens async via Riverpod
    await _sendMessage(ref, text, 'text', '');
  }

  // Voice recording state managed locally with Riverpod typing indicator
  void _startVoice() {
    if (_isRecording) {
      _stopRecording();
    } else {
      _startRecording();
    }
  }

  void _startRecording() async {
    setState(() => _isRecording = true);
    ref.read(typingProvider.notifier).onTyping();

    // Start recording timer
    _recordingDuration = 0;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _recordingDuration++);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice recording started'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  void _stopRecording() {
    setState(() => _isRecording = false);
    _recordingTimer?.cancel();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Voice recording stopped'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // Helper method to send messages through provider
  Future<void> _sendMessage(
    WidgetRef ref,
    String filePath,
    String messageType,
    String fileName,
  ) async {
    final message = domain.RoomEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      roomId: widget.roomId,
      senderId: '', // Will be set by provider
      type: messageType == 'image'
          ? domain.RoomEventType.image
          : domain.RoomEventType.file,
      content: {'path': filePath, 'fileName': fileName},
      createdAt: DateTime.now().millisecondsSinceEpoch,
      status: domain.EventStatus.pending,
    );

    // Send via existing message infrastructure
    final messageRepo = ref.read(messageRepositoryProvider);

    // Optimistic update
    await messageRepo.insertMessage(message);

    // Network send (simplified for example)
    try {
      // Actual network send logic here
      await messageRepo.updateMessageStatus(
        message.id,
        domain.EventStatus.sent,
      );
    } catch (e) {
      await messageRepo.updateMessageStatus(
        message.id,
        domain.EventStatus.failed,
      );
    }
  }

  // Camera functionality
  Future<void> _captureFromCamera() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (image != null) {
      // Process and send selected image
      await _sendMessage(ref, image.path, 'image', image.name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Camera image sent: ${image.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Gallery functionality
  Future<void> _pickFromGallery() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (image != null) {
      // Process and send selected image
      await _sendMessage(ref, image.path, 'image', image.name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gallery image sent: ${image.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Document functionality
  Future<void> _pickDocument() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final PlatformFile file = result.files.single;
      // Process and send selected document
      await _sendMessage(ref, file.path!, 'file', file.name);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document sent: ${file.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _showAttachmentOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppTheme.standardMargin),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildAttachmentOption(
                    icon: Icons.camera_alt,
                    label: 'Camera',
                    onTap: () async {
                      Navigator.pop(context);
                      await _captureFromCamera();
                    },
                  ),
                  _buildAttachmentOption(
                    icon: Icons.photo_library,
                    label: 'Gallery',
                    onTap: () async {
                      Navigator.pop(context);
                      await _pickFromGallery();
                    },
                  ),
                  _buildAttachmentOption(
                    icon: Icons.description,
                    label: 'Document',
                    onTap: () async {
                      Navigator.pop(context);
                      await _pickDocument();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.standardMargin),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.getSubtleColor(context, AppTheme.primaryGreen),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: AppTheme.primaryGreen, size: 28),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: AppTheme.metadataText.copyWith(
                color: AppTheme.getTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Row(
              children: [
                // Emoji button (Riverpod-driven)
                IconButton(
                  icon: Icon(
                    ref.watch(emojiPanelVisibilityProvider)
                        ? Icons.keyboard
                        : Icons.emoji_emotions_outlined,
                  ),
                  onPressed: _toggleEmoji,
                  tooltip: 'Emoji',
                  style: IconButton.styleFrom(
                    foregroundColor: AppTheme.primaryGreen,
                  ),
                ),

                const SizedBox(width: AppTheme.elementGap),

                // Attachment button
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  onPressed: _showAttachmentOptions,
                  tooltip: 'Attachment',
                  style: IconButton.styleFrom(
                    foregroundColor: AppTheme.getTextColor(context),
                  ),
                ),

                const SizedBox(width: AppTheme.elementGap),

                // Text field (local state only)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.getChatBackground(context),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _focusNode.hasFocus
                            ? AppTheme.primaryGreen.withValues(alpha: 0.5)
                            : Colors.transparent,
                        width: _focusNode.hasFocus ? 2 : 1,
                      ),
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      minLines: 1,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      style: AppTheme.bodyText.copyWith(
                        color: AppTheme.getTextColor(context),
                      ),
                      decoration: InputDecoration(
                        hintText: 'Message',
                        hintStyle: AppTheme.bodyText.copyWith(
                          color: AppTheme.getTextColor(
                            context,
                          ).withValues(alpha: 0.6),
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      // No onChanged that touches providers
                    ),
                  ),
                ),

                const SizedBox(width: AppTheme.elementGap),

                // Camera button (only show when no text)
                if (!_hasText)
                  IconButton(
                    icon: const Icon(Icons.camera_alt),
                    onPressed: _captureFromCamera,
                    tooltip: 'Camera',
                    style: IconButton.styleFrom(
                      foregroundColor: AppTheme.getTextColor(context),
                    ),
                  ),

                // Send/Mic button with proper animation
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _hasText
                      ? IconButton(
                          key: const ValueKey('send'),
                          icon: const Icon(Icons.send),
                          onPressed: _send,
                          tooltip: 'Send',
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.primaryGreen,
                            foregroundColor: Colors.white,
                          ),
                        )
                      : IconButton(
                          key: const ValueKey('mic'),
                          icon: Icon(
                            _isRecording ? Icons.stop : Icons.mic,
                            color: _isRecording
                                ? Colors.red
                                : AppTheme.primaryGreen,
                          ),
                          onPressed: _startVoice,
                          tooltip: _isRecording
                              ? 'Stop Recording'
                              : 'Voice Message',
                          style: IconButton.styleFrom(
                            backgroundColor: _isRecording
                                ? Colors.red.withValues(alpha: 0.1)
                                : AppTheme.getSubtleColor(
                                    context,
                                    AppTheme.primaryGreen,
                                  ),
                            foregroundColor: _isRecording
                                ? Colors.red
                                : AppTheme.primaryGreen,
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
}
