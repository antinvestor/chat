import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/room_event.dart' as domain;
import 'message_providers.dart';

part 'chat_input_providers.g.dart';

// Riverpod providers for WhatsApp-style chat input architecture

@riverpod
class EmojiPanelVisibility extends _$EmojiPanelVisibility {
  @override
  bool build() => false;

  void show() {
    state = true;
  }

  void hide() {
    state = false;
  }

  void toggle() {
    state = !state;
  }
}

@riverpod
bool typingState(Ref ref) => false;

@riverpod
class TypingNotifier extends _$TypingNotifier {
  Timer? _timer;

  @override
  bool build() => false;

  void onTyping() {
    if (!state) {
      state = true;
    }

    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      // Use ref.mounted to check if provider is still alive
      if (ref.mounted) {
        state = false;
      }
    });
  }
}

@riverpod
Future<void> Function(String) sendMessageProvider(Ref ref) {
  return (text) async {
    if (text.trim().isEmpty) return;

    // Create message event
    final message = domain.RoomEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      roomId: '', // Will be set by caller
      senderId: '', // Will be set by caller
      type: domain.RoomEventType.text,
      content: {'text': text.trim()},
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
  };
}
