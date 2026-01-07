import 'dart:async';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/db/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/sync/sync_engine.dart';

part 'typing_provider.g.dart';

@riverpod
class Typing extends _$Typing {
  StreamSubscription? _subscription;
  final Map<String, Timer> _typingTimers = {};
  late String _roomId;

  @override
  Set<String> build(String roomId) {
    _roomId = roomId; // Store room ID for later use
    _init(roomId);
    ref.onDispose(() {
      _subscription?.cancel();
      for (final timer in _typingTimers.values) {
        timer.cancel();
      }
    });
    return {};
  }

  Future<void> _init(String roomId) async {
    final syncEngine = await ref.read(syncEngineProvider.future);
    _subscription = syncEngine.typingEvents.listen((event) {
      if (event.roomId == roomId) {
        // Use subscription ID to identify the user
        final subscriptionId = event.hasSubscriptionId()
            ? event.subscriptionId
            : '';
        if (subscriptionId.isNotEmpty) {
          // Get profile ID for this subscription
          _getProfileIdFromSubscription(roomId, subscriptionId).then((
            profileId,
          ) {
            if (profileId != null && profileId.isNotEmpty) {
              if (event.typing) {
                _addTypingUser(profileId);
              } else {
                _removeTypingUser(profileId);
              }
            }
          });
        }
      }
    });
  }

  /// Helper method to get profile ID from subscription ID
  Future<String?> _getProfileIdFromSubscription(
    String roomId,
    String subscriptionId,
  ) async {
    try {
      final db = AppDatabase.instance;
      final query = db.select(db.roomMembers)
        ..where(
          (t) =>
              t.roomId.equals(roomId) & t.subscriptionId.equals(subscriptionId),
        );
      final member = await query.getSingleOrNull();
      return member?.profileId;
    } catch (e) {
      // If we can't find the member, return null
      return null;
    }
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
    try {
      final syncEngine = await ref.read(syncEngineProvider.future);
      await syncEngine.sendTyping(_roomId, isTyping);
    } catch (e) {
      // Silently fail for typing events - they're not critical
      AppLogger.error('Failed to send typing event', error: e);
    }
  }
}
