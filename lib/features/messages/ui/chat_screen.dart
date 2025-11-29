import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xid/xid.dart';
import '../data/message_providers.dart';
import '../domain/room_event.dart';
import 'message_bubble.dart';
import 'typing_indicator.dart';
import '../../calls/services/call_manager.dart';
import '../../calls/ui/call_screen.dart';

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
  Timer? _typingDebounce;
  Timer? _readReceiptDebounce;

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

    // TODO: Re-implement receipts through Connect stream
    // Temporary disabled until Connect stream is available
    /*
    _readReceiptDebounce = Timer(const Duration(milliseconds: 500), () {
      final unreadIds = messages
          .where((m) => 
              m.senderId != 'current_user_id' && 
              m.status != EventStatus.read)
          .map((m) => m.id)
          .toList();
      
      if (unreadIds.isNotEmpty) {
        // Send through Connect stream
      }
    });
    */
  }

  void _onTextChanged(String text) {
    if (_typingDebounce?.isActive ?? false) _typingDebounce!.cancel();

    // TODO: Re-implement typing through Connect stream
    // ref.read(typingProvider(widget.roomId).notifier).sendTyping(true);

    _typingDebounce = Timer(const Duration(seconds: 2), () {
      // ref.read(typingProvider(widget.roomId).notifier).sendTyping(false);
    });
  }

  void _sendMessage() {
    if (_controller.text.trim().isEmpty) return;

    final message = RoomEvent(
      id: Xid().toString(),
      roomId: widget.roomId,
      senderId: 'current_user_id', // TODO: Get from auth
      type: RoomEventType.text,
      content: {'text': _controller.text.trim()},
      createdAt: DateTime.now().millisecondsSinceEpoch,
      localId: Xid().toString(),
    );

    ref.read(messageListProvider(widget.roomId).notifier).sendMessage(message);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final messagesAsync = ref.watch(messageListProvider(widget.roomId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomName),
        actions: [
          IconButton(
            icon: const Icon(Icons.video_call),
            onPressed: () {
              ref.read(callManagerProvider).startCall(widget.roomId);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => CallScreen(
                    roomId: widget.roomId,
                    roomName: widget.roomName,
                  ),
                ),
              );
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
                    final isMe =
                        message.senderId ==
                        'current_user_id'; // TODO: Check against real user

                    // Show avatar only for first message in a group
                    final showAvatar =
                        reversedIndex == messages.length - 1 ||
                        messages[reversedIndex + 1].senderId !=
                            message.senderId;

                    return MessageBubble(
                      message: message,
                      isMe: isMe,
                      showAvatar: showAvatar,
                    );
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
                TypingIndicator(roomId: widget.roomId),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onChanged: _onTextChanged,
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      icon: const Icon(Icons.send),
                      onPressed: _sendMessage,
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
}
