import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/room.dart' as domain;
import '../domain/room_with_last_message.dart';
import 'room_service.dart';

part 'room_providers.g.dart';

@riverpod
class RoomList extends _$RoomList {
  @override
  Future<List<domain.Room>> build() async {
    final service = ref.watch(roomServiceProvider);
    return service.getAllRooms();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(roomServiceProvider);
      return service.getAllRooms();
    });
  }

  /// Create a new room (offline-first)
  /// Saves locally first, then syncs when online
  Future<domain.Room> createRoom({
    required String name,
    required String type,
    String? description,
    bool isPrivate = false,
    List<String> members = const [],
    Map<String, dynamic>? metadata,
  }) async {
    final service = ref.read(roomServiceProvider);
    final room = await service.createRoom(
      name: name,
      type: type,
      description: description,
      isPrivate: isPrivate,
      members: members,
      metadata: metadata,
    );
    await refresh();
    return room;
  }

  /// Update an existing room (offline-first)
  Future<domain.Room> updateRoom({
    required String roomId,
    String? name,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    final service = ref.read(roomServiceProvider);
    final room = await service.updateRoom(
      roomId: roomId,
      name: name,
      description: description,
      metadata: metadata,
    );
    await refresh();
    return room;
  }

  /// Delete a room (offline-first)
  Future<void> deleteRoom(String roomId) async {
    final service = ref.read(roomServiceProvider);
    await service.deleteRoom(roomId);
    await refresh();
  }

  /// Add members to a room (offline-first)
  Future<void> addMembers({
    required String roomId,
    required List<String> profileIds,
  }) async {
    final service = ref.read(roomServiceProvider);
    await service.addMembers(roomId: roomId, profileIds: profileIds);
  }

  /// Remove members from a room (offline-first)
  Future<void> removeMembers({
    required String roomId,
    required List<String> profileIds,
  }) async {
    final service = ref.read(roomServiceProvider);
    await service.removeMembers(roomId: roomId, profileIds: profileIds);
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
