import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../domain/room.dart' as domain;
import '../domain/room_with_last_message.dart';
import '../../../core/db/database.dart';
import 'room_repository.dart';

part 'room_providers.g.dart';

@riverpod
RoomRepository roomRepository(Ref ref) {
  return RoomRepository(AppDatabase.instance);
}

@riverpod
class RoomList extends _$RoomList {
  @override
  Future<List<domain.Room>> build() async {
    final repo = ref.watch(roomRepositoryProvider);
    return repo.getAllRooms();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(roomRepositoryProvider);
      return repo.getAllRooms();
    });
  }

  Future<void> createRoom(domain.Room room) async {
    final repo = ref.read(roomRepositoryProvider);
    await repo.insertRoom(room);
    refresh();
  }
}

@riverpod
class RoomListWithMessages extends _$RoomListWithMessages {
  @override
  Future<List<RoomWithLastMessage>> build() async {
    final repo = ref.watch(roomRepositoryProvider);
    return repo.getRoomsWithLastMessage();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(roomRepositoryProvider);
      return repo.getRoomsWithLastMessage();
    });
  }
}
