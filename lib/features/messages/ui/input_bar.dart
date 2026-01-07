import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../data/typing_provider.dart';

class InputBar extends ConsumerStatefulWidget {
  final String roomId;
  final Function(String text, {String? replyToMessageId}) onSendMessage;
  final VoidCallback onAttachment;
  final VoidCallback onCamera;
  final VoidCallback onVoiceRecord;
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
    required this.onVoiceRecord,
    this.isEncryptionEnabled = false,
    this.replyingToMessageId,
    this.replyingToText,
    required this.onCancelReply,
  });

  @override
  ConsumerState<InputBar> createState() => _InputBarState();
}

class _InputBarState extends ConsumerState<InputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _typingDebounce;
  Timer? _voiceRecordingTimer;
  bool _isVoiceRecording = false;
  int _maxLines = 1;
  int _recordingDuration = 0;
  Timer? _recordingTimer;
  double _voiceButtonScale = 1.0;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _typingDebounce?.cancel();
    _voiceRecordingTimer?.cancel();
    _recordingTimer?.cancel();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      setState(() {});
    }
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

    // Adjust text field height based on content
    final newLines = (text.length / 40).ceil().clamp(1, 5);
    if (newLines != _maxLines) {
      setState(() {
        _maxLines = newLines;
      });
    }
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    // Add haptic feedback
    HapticFeedback.lightImpact();

    widget.onSendMessage(
      _controller.text.trim(),
      replyToMessageId: widget.replyingToMessageId,
    );
    _controller.clear();
    setState(() {
      _maxLines = 1;
    });
    _focusNode.requestFocus();
  }

  void _startVoiceRecording() {
    HapticFeedback.heavyImpact();
    setState(() {
      _isVoiceRecording = true;
      _recordingDuration = 0;
      _voiceButtonScale = 1.2;
    });

    // Start recording timer
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration++;
      });
    });

    // Auto-stop after 30 seconds
    _voiceRecordingTimer = Timer(const Duration(seconds: 30), () {
      _stopVoiceRecording();
    });

    widget.onVoiceRecord();
  }

  void _stopVoiceRecording() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isVoiceRecording = false;
      _recordingDuration = 0;
      _voiceButtonScale = 1.0;
    });

    _recordingTimer?.cancel();
    _voiceRecordingTimer?.cancel();
  }

  void _cancelVoiceRecording() {
    HapticFeedback.lightImpact();
    setState(() {
      _isVoiceRecording = false;
      _recordingDuration = 0;
      _voiceButtonScale = 1.0;
    });

    _recordingTimer?.cancel();
    _voiceRecordingTimer?.cancel();
  }

  bool get _hasText => _controller.text.trim().isNotEmpty;

  String _formatRecordingDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: 8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Reply preview with enhanced design
            if (widget.replyingToMessageId != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.1),
                      theme.colorScheme.primary.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.reply,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Replying to message',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.replyingToText ?? '',
                            style: TextStyle(
                              fontSize: 14,
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w400,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: widget.onCancelReply,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),

            // Voice recording interface
            if (_isVoiceRecording)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 500),
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.4),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Recording',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatRecordingDuration(_recordingDuration),
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: (_recordingDuration % 5) / 5,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: _cancelVoiceRecording,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.red,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _stopVoiceRecording,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Main input area
            Row(
              children: [
                // Attachment button
                Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainer,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.add_circle_outline,
                      color: theme.colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                    onPressed: widget.onAttachment,
                    tooltip: 'Attach file',
                  ),
                ),

                const SizedBox(width: 8),

                // Text field with pill shape
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: _focusNode.hasFocus
                            ? theme.colorScheme.primary.withValues(alpha: 0.5)
                            : theme.colorScheme.outline.withValues(alpha: 0.2),
                        width: _focusNode.hasFocus ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Encryption indicator
                        if (widget.isEncryptionEnabled)
                          Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Icon(
                              Icons.lock,
                              size: 16,
                              color: Colors.green,
                            ),
                          ),

                        // Text input
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            maxLines: _maxLines,
                            minLines: 1,
                            style: TextStyle(
                              fontSize: 16,
                              color: theme.colorScheme.onSurface,
                            ),
                            decoration: InputDecoration(
                              hintText: widget.isEncryptionEnabled
                                  ? 'Type an encrypted message...'
                                  : 'Type a message...',
                              hintStyle: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.7),
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            onChanged: _onTextChanged,
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),

                        // Camera button (inside text field)
                        if (!_hasText)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: IconButton(
                              icon: Icon(
                                Icons.camera_alt_outlined,
                                color: theme.colorScheme.onSurfaceVariant,
                                size: 20,
                              ),
                              onPressed: widget.onCamera,
                              tooltip: 'Take photo',
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Mic/Send button with enhanced design
                AnimatedScale(
                  scale: _voiceButtonScale,
                  duration: const Duration(milliseconds: 200),
                  child: GestureDetector(
                    onTap: _hasText ? _sendMessage : null,
                    onLongPressStart: !_hasText
                        ? (details) {
                            _startVoiceRecording();
                          }
                        : null,
                    onLongPressEnd: !_hasText
                        ? (details) {
                            _stopVoiceRecording();
                          }
                        : null,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: _hasText
                            ? LinearGradient(
                                colors: [
                                  theme.colorScheme.primary,
                                  theme.colorScheme.primary.withValues(
                                    alpha: 0.8,
                                  ),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : LinearGradient(
                                colors: [
                                  theme.colorScheme.surfaceContainer,
                                  theme.colorScheme.surfaceContainer.withValues(
                                    alpha: 0.8,
                                  ),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          if (_hasText)
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.3,
                              ),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(
                        _hasText ? Icons.send : Icons.mic,
                        color: _hasText
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
