import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/typing_provider.dart';
import '../services/voice_recording_service.dart';

/// Callback for when a voice recording is completed
typedef OnVoiceRecordingComplete = void Function(VoiceRecordingResult result);

/// Professional WhatsApp-style input bar with clean design
class InputBar extends ConsumerStatefulWidget {
  final String roomId;
  final Function(String text, {String? replyToMessageId}) onSendMessage;
  final VoidCallback onAttachment;
  final VoidCallback onCamera;
  final OnVoiceRecordingComplete? onVoiceRecordingComplete;
  final bool isEncryptionEnabled;
  final String? replyingToMessageId;
  final String? replyingToText;
  final VoidCallback onCancelReply;

  const InputBar({
    super.key,
    required this.roomId,
    required this.onSendMessage,
    required this.onAttachment,
    required this.onCamera,
    this.onVoiceRecordingComplete,
    this.isEncryptionEnabled = false,
    this.replyingToMessageId,
    this.replyingToText,
    required this.onCancelReply,
  });

  @override
  ConsumerState<InputBar> createState() => _InputBarState();
}

class _InputBarState extends ConsumerState<InputBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _typingDebounce;
  bool _isVoiceRecording = false;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  late AnimationController _sendButtonController;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);

    // Send button animation
    _sendButtonController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _focusNode.dispose();
    _typingDebounce?.cancel();
    _recordingTimer?.cancel();
    _durationSubscription?.cancel();
    _sendButtonController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _controller.text.trim().isNotEmpty;

    // Animate send button
    if (hasText) {
      _sendButtonController.forward();
    } else {
      _sendButtonController.reverse();
    }

    // Typing indicator logic
    if (_typingDebounce?.isActive ?? false) _typingDebounce!.cancel();

    if (hasText) {
      ref.read(typingProvider(widget.roomId).notifier).sendTyping(true);
    }

    _typingDebounce = Timer(const Duration(seconds: 2), () {
      ref.read(typingProvider(widget.roomId).notifier).sendTyping(false);
    });

    setState(() {});
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    HapticFeedback.lightImpact();

    widget.onSendMessage(
      _controller.text.trim(),
      replyToMessageId: widget.replyingToMessageId,
    );
    _controller.clear();
    _focusNode.requestFocus();
  }

  static const int _maxRecordingDuration = 300; // 5 minutes max
  StreamSubscription<Duration>? _durationSubscription;

  Future<void> _startVoiceRecording() async {
    HapticFeedback.heavyImpact();

    final voiceService = ref.read(voiceRecordingServiceProvider);

    // Start actual recording
    final path = await voiceService.startRecording();
    if (path == null) {
      // Failed to start recording (permission denied or error)
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not start recording. Please check microphone permissions.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    setState(() {
      _isVoiceRecording = true;
      _recordingDuration = 0;
    });

    // Listen to duration updates from the service
    _durationSubscription?.cancel();
    _durationSubscription = voiceService.durationStream.listen((duration) {
      if (mounted) {
        setState(() {
          _recordingDuration = duration.inSeconds;
        });
      }
    });

    // Also keep the timer for UI updates (backup)
    _recordingTimer?.cancel();
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      // Auto-stop at max duration to prevent infinite recording
      if (_recordingDuration >= _maxRecordingDuration) {
        _stopVoiceRecording();
      }
    });
  }

  Future<void> _stopVoiceRecording() async {
    HapticFeedback.mediumImpact();
    _recordingTimer?.cancel();
    _durationSubscription?.cancel();

    final voiceService = ref.read(voiceRecordingServiceProvider);
    final result = await voiceService.stopRecording();

    setState(() {
      _isVoiceRecording = false;
      _recordingDuration = 0;
    });

    // If we got a valid recording, notify the parent
    if (result != null && widget.onVoiceRecordingComplete != null) {
      widget.onVoiceRecordingComplete!(result);
    }
  }

  Future<void> _cancelVoiceRecording() async {
    HapticFeedback.lightImpact();
    _recordingTimer?.cancel();
    _durationSubscription?.cancel();

    final voiceService = ref.read(voiceRecordingServiceProvider);
    await voiceService.cancelRecording();

    setState(() {
      _isVoiceRecording = false;
      _recordingDuration = 0;
    });
  }

  bool get _hasText => _controller.text.trim().isNotEmpty;

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F1F) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reply preview
            if (widget.replyingToMessageId != null) _buildReplyPreview(theme),

            // Voice recording UI
            if (_isVoiceRecording)
              _buildVoiceRecordingUI(theme)
            else
              // Main input row
              _buildInputRow(theme, isDark, primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyPreview(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 3),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Reply',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.replyingToText ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.close,
                size: 18,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              onPressed: widget.onCancelReply,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceRecordingUI(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // Recording indicator
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withValues(alpha: 0.5),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _formatDuration(_recordingDuration),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const Spacer(),
          // Cancel button
          TextButton(
            onPressed: _cancelVoiceRecording,
            child: Text('Cancel', style: TextStyle(color: Colors.red.shade600)),
          ),
          const SizedBox(width: 8),
          // Send button
          _buildSendButton(theme, isRecording: true),
        ],
      ),
    );
  }

  Widget _buildInputRow(ThemeData theme, bool isDark, Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Input field container
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2A2A2A)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Attachment button
                  _buildIconButton(
                    icon: Icons.attach_file,
                    onTap: widget.onAttachment,
                    theme: theme,
                  ),
                  // Text field
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      maxLines: 5,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.colorScheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.isEncryptionEnabled
                            ? 'Encrypted message'
                            : 'Message',
                        hintStyle: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.5,
                          ),
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 12,
                        ),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  // Encryption indicator
                  if (widget.isEncryptionEnabled)
                    Padding(
                      padding: const EdgeInsets.only(right: 4, bottom: 10),
                      child: Icon(
                        Icons.lock,
                        size: 16,
                        color: Colors.green.shade600,
                      ),
                    ),
                  // Camera button (only when no text)
                  if (!_hasText)
                    _buildIconButton(
                      icon: Icons.camera_alt,
                      onTap: widget.onCamera,
                      theme: theme,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Send/Mic button
          _buildSendButton(theme),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required ThemeData theme,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 22,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }

  Widget _buildSendButton(ThemeData theme, {bool isRecording = false}) {
    final primaryColor = theme.colorScheme.primary;
    final showSend = _hasText || isRecording;

    return GestureDetector(
      onTap: showSend
          ? (isRecording ? _stopVoiceRecording : _sendMessage)
          : null,
      onLongPressStart: !showSend ? (_) => _startVoiceRecording() : null,
      onLongPressEnd: !showSend ? (_) => _stopVoiceRecording() : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: showSend ? primaryColor : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: showSend
              ? Icon(
                  isRecording ? Icons.send : Icons.send,
                  key: const ValueKey('send'),
                  size: 20,
                  color: Colors.white,
                )
              : Icon(
                  Icons.mic,
                  key: const ValueKey('mic'),
                  size: 22,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
        ),
      ),
    );
  }
}
