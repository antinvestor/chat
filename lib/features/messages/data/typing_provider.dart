import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/sync/sync_engine.dart';

part 'typing_provider.g.dart';

@riverpod
class Typing extends _$Typing {
  StreamSubscription? _subscription;
  final Map<String, Timer> _typingTimers = {};

  @override
  Set<String> build(String roomId) {
    _init(roomId);
    ref.onDispose(() {
      _subscription?.cancel();
      for (final timer in _typingTimers.values) {
        timer.cancel();
      }
    });
    return {};
  }

  void _init(String roomId) {
    final syncEngine = ref.read(syncEngineProvider);
    _subscription = syncEngine.typingEvents.listen((event) {
      if (event.roomId == roomId) {
        if (event.typing) {
          _addTypingUser(event.profileId);
        } else {
          _removeTypingUser(event.profileId);
        }
      }
    });
  }

  void _addTypingUser(String userId) {
    if (state.contains(userId)) {
      // Reset timer
      _typingTimers[userId]?.cancel();
    } else {
      state = {...state, userId};
    }

    // Auto-remove after 5 seconds of no updates
    _typingTimers[userId] = Timer(const Duration(seconds: 5), () {
      _removeTypingUser(userId);
    });
  }

  void _removeTypingUser(String userId) {
    _typingTimers[userId]?.cancel();
    _typingTimers.remove(userId);
    if (state.contains(userId)) {
      state = state.where((id) => id != userId).toSet();
    }
  }

  Future<void> sendTyping(bool isTyping) async {
    // TODO: Re-implement through Connect stream
    // final syncEngine = ref.read(syncEngineProvider);
    // await syncEngine.sendTyping(roomId, isTyping);
  }
}
