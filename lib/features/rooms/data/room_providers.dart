import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../messages/data/draft_repository.dart';
import '../domain/room.dart' as domain;
import '../domain/room_with_last_message.dart';
import 'room_service.dart';

part 'room_providers.g.dart';

/// Provider for getting a room by ID
@riverpod
Future<domain.Room?> roomById(Ref ref, String roomId) async {
  final service = await ref.watch(roomServiceProvider.future);
  return service.getRoomById(roomId);
}

@riverpod
class RoomList extends _$RoomList {
  @override
  Future<List<domain.Room>> build() async {
    final service = await ref.watch(roomServiceProvider.future);
    return service.getAllRooms();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = await ref.read(roomServiceProvider.future);
      return service.getAllRooms();
    });
  }

  /// Create a new room (offline-first)
  /// Saves locally first, then syncs when online
  /// Server handles routing to on/off-platform members
  Future<domain.Room> createRoom({
    required String name,
    required String type,
    String? description,
    bool isPrivate = false,
    List<String> contactIds = const [], // Server determines routing
    Map<String, dynamic>? metadata,
  }) async {
    final service = await ref.read(roomServiceProvider.future);
    final room = await service.createRoom(
      name: name,
      type: type,
      description: description,
      isPrivate: isPrivate,
      contactIds: contactIds,
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
    final service = await ref.read(roomServiceProvider.future);
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
    final service = await ref.read(roomServiceProvider.future);
    await service.deleteRoom(roomId);
    await refresh();
  }

  /// Add members to a room (offline-first)
  Future<void> addMembers({
    required String roomId,
    required List<String> profileIds,
  }) async {
    final service = await ref.read(roomServiceProvider.future);
    await service.addMembers(roomId: roomId, profileIds: profileIds);
  }

  /// Remove members from a room (offline-first)
  Future<void> removeMembers({
    required String roomId,
    required List<String> profileIds,
  }) async {
    final service = await ref.read(roomServiceProvider.future);
    await service.removeMembers(roomId: roomId, profileIds: profileIds);
  }
}

@riverpod
class RoomListWithMessages extends _$RoomListWithMessages {
  @override
  Future<List<RoomWithLastMessage>> build() async {
    final repo = ref.watch(roomRepositoryProvider);
    final draftRepo = ref.watch(draftRepositoryProvider);

    // Get rooms and drafts
    final rooms = await repo.getRoomsWithLastMessage();
    final draftsMap = await draftRepo.getDraftsMap();

    // Merge draft info into rooms
    return rooms.map((room) {
      final draft = draftsMap[room.id];
      return room.copyWith(draftText: draft);
    }).toList();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(roomRepositoryProvider);
      final draftRepo = ref.read(draftRepositoryProvider);

      final rooms = await repo.getRoomsWithLastMessage();
      final draftsMap = await draftRepo.getDraftsMap();

      return rooms.map((room) {
        final draft = draftsMap[room.id];
        return room.copyWith(draftText: draft);
      }).toList();
    });
  }
}
