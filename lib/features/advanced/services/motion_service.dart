import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xid/xid.dart';

import '../../../core/sync/sync_engine.dart';
import '../../../features/auth/data/auth_repository.dart';
import '../../messages/domain/room_event.dart';

final motionServiceProvider = FutureProvider<MotionService>((ref) async {
  final syncEngine = await ref.watch(syncEngineProvider.future);
  final authRepo = ref.watch(authRepositoryProvider);
  return MotionService(syncEngine, authRepo);
});

class MotionService {
  final SyncEngine _syncEngine;
  final AuthRepository _authRepository;

  MotionService(this._syncEngine, this._authRepository);

  Future<void> createMotion({
    required String roomId,
    required String title,
    required String description,
    required List<String> options,
    required DateTime deadline,
  }) async {
    final content = {
      'title': title,
      'description': description,
      'options': options,
      'deadline': deadline.millisecondsSinceEpoch,
      'votes': <String, String>{}, // userId -> option
    };

    final currentUserId = await _authRepository.getCurrentUserId();

    final event = RoomEvent(
      id: Xid().toString(),
      roomId: roomId,
      senderId: currentUserId ?? 'unknown',
      type: RoomEventType.motion,
      content: content,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      localId: Xid().toString(),
    );

    await _syncEngine.sendSignal(event);
  }

  Future<void> castVote({
    required String roomId,
    required String motionId,
    required String option,
  }) async {
    final content = {
      'motionId': motionId,
      'option': option,
    };

    final currentUserId = await _authRepository.getCurrentUserId();

    final event = RoomEvent(
      id: Xid().toString(),
      roomId: roomId,
      senderId: currentUserId ?? 'unknown',
      type: RoomEventType.vote,
      content: content,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      localId: Xid().toString(),
    );

    await _syncEngine.sendSignal(event);
  }
}
