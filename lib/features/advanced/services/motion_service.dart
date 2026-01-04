import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xid/xid.dart';

import '../../../core/db/database.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../features/auth/data/auth_repository.dart';
import '../../messages/data/message_providers.dart';
import '../../messages/data/message_repository.dart';
import '../../messages/domain/room_event.dart' as domain;

final motionServiceProvider = FutureProvider<MotionService>((ref) async {
  final syncEngine = await ref.watch(syncEngineProvider.future);
  final authRepo = ref.watch(authRepositoryProvider);
  final messageRepo = ref.watch(messageRepositoryProvider);
  final db = AppDatabase.instance;
  return MotionService(syncEngine, authRepo, messageRepo, db);
});

class ValidationException implements Exception {
  final String message;
  ValidationException(this.message);

  @override
  String toString() => message;
}

class PermissionDeniedException implements Exception {
  final String message;
  PermissionDeniedException(this.message);

  @override
  String toString() => message;
}

class MotionService {
  final SyncEngine _syncEngine;
  final AuthRepository _authRepository;
  final MessageRepository _messageRepository;
  final AppDatabase _database;

  MotionService(this._syncEngine, this._authRepository, this._messageRepository, this._database);

  /// Helper method to check if user has admin/owner role in room
  Future<String?> _getRoomRole(String roomId, String userId) async {
    final query = _database.select(_database.roomMembers)
      ..where((t) => t.roomId.equals(roomId) & t.profileId.equals(userId));

    final member = await query.getSingleOrNull();
    return member?.role;
  }

  Future<void> createMotion({
    required String roomId,
    required String title,
    required String description,
    required List<String> options,
    required DateTime deadline,
  }) async {
    // Input validation
    if (title.trim().isEmpty) {
      throw ValidationException('Motion title cannot be empty');
    }
    if (title.trim().length < 5) {
      throw ValidationException('Motion title must be at least 5 characters');
    }
    if (title.trim().length > 100) {
      throw ValidationException('Motion title must be less than 100 characters');
    }
    if (options.length < 2) {
      throw ValidationException('Motion must have at least 2 options');
    }
    if (deadline.isBefore(DateTime.now())) {
      throw ValidationException('Deadline must be in the future');
    }

    // Admin role enforcement
    final currentUserId = await _authRepository.getCurrentUserId();
    if (currentUserId == null) {
      throw ValidationException('User not authenticated');
    }

    final role = await _getRoomRole(roomId, currentUserId);
    if (role != 'admin' && role != 'owner') {
      throw PermissionDeniedException('Only room admins can create motions');
    }

    final content = {
      'title': title.trim(),
      'description': description.trim(),
      'options': options,
      'deadline': deadline.millisecondsSinceEpoch,
      'votes': <String, String>{}, // userId -> option
      'status': 'active',
    };

    final event = domain.RoomEvent(
      id: Xid().toString(),
      roomId: roomId,
      senderId: currentUserId,
      type: domain.RoomEventType.motion,
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
    // 1. Fetch motion event
    final motionEvent = await _messageRepository.getEventById(motionId);
    if (motionEvent == null) {
      throw ValidationException('Motion not found');
    }

    // 2. Validate motion type
    if (motionEvent.type != domain.RoomEventType.motion) {
      throw ValidationException('Event is not a motion');
    }

    // 3. Check deadline
    final deadline = DateTime.fromMillisecondsSinceEpoch(
      motionEvent.content['deadline'] as int,
    );
    if (DateTime.now().isAfter(deadline)) {
      throw ValidationException('Voting has closed for this motion');
    }

    // 4. Validate option
    final options = (motionEvent.content['options'] as List<dynamic>).cast<String>();
    if (!options.contains(option)) {
      throw ValidationException('Invalid voting option');
    }

    // 5. Check for existing vote (deduplication & change logic)
    final currentUserId = await _authRepository.getCurrentUserId();
    if (currentUserId == null) {
      throw ValidationException('User not authenticated');
    }

    final votes = (motionEvent.content['votes'] as Map<String, dynamic>?) ?? {};
    final existingVote = votes[currentUserId];

    // If same vote, no-op (deduplication)
    if (existingVote == option) {
      return;
    }

    // 6. Create vote event (with previousOption if changing vote)
    final content = {
      'motionId': motionId,
      'option': option,
      if (existingVote != null) 'previousOption': existingVote,
    };

    final event = domain.RoomEvent(
      id: Xid().toString(),
      roomId: roomId,
      senderId: currentUserId,
      type: domain.RoomEventType.vote,
      content: content,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      localId: Xid().toString(),
    );

    await _syncEngine.sendSignal(event);
  }
}
