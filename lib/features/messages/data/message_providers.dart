import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/db/database.dart';
import '../../../core/sync/pending_job.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/room_event.dart' as domain;
import 'message_repository.dart';

part 'message_providers.g.dart';

@riverpod
MessageRepository messageRepository(Ref ref) {
  return MessageRepository(AppDatabase.instance);
}

@riverpod
class MessageList extends _$MessageList {
  @override
  Future<List<domain.RoomEvent>> build(String roomId) async {
    final repo = ref.watch(messageRepositoryProvider);
    return repo.getMessagesForRoom(roomId);
  }

  Future<void> sendMessage(domain.RoomEvent event) async {
    final messageRepo = ref.read(messageRepositoryProvider);
    final jobRepo = ref.read(pendingJobRepositoryProvider);

    // 1. Optimistic update: Insert into local DB
    await messageRepo.insertMessage(event);

    // 2. Queue job for sync
    await jobRepo.addJob(JobType.sendMessage, {
      'roomId': event.roomId,
      'localId': event.localId,
      'content': event.content,
    });
    
    // Refresh the list
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return messageRepo.getMessagesForRoom(event.roomId);
    });
  }

  /// Fetch historical messages from server
  Future<void> fetchHistory(String roomId, {String? cursor}) async {
    final messageRepo = ref.read(messageRepositoryProvider);
    
    // Fetch from server (wait for sync engine to be ready)
    final syncEngine = await ref.read(syncEngineProvider.future);
    await syncEngine.getHistory(roomId, cursor: cursor);
    
    // Refresh local messages
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return messageRepo.getMessagesForRoom(roomId);
    });
  }
}
