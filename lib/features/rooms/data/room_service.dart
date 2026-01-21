import 'package:antinvestor_api_chat/antinvestor_api_chat.dart' as pb_chat;
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xid/xid.dart';

import '../../../core/db/database.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/networking/client.dart';
import '../../../core/sync/pending_job.dart';
import '../../../core/sync/pending_job_repository.dart';
import '../../../core/sync/sync_engine.dart';
import '../domain/room.dart' as domain;
import 'room_repository.dart';

/// Service for managing rooms with offline-first support
/// All operations are saved locally first, then queued for server sync
/// Supports universal messaging: server handles routing to on/off-platform members
class RoomService {
  RoomService(this._roomRepo, this._jobRepo, this._chatClient, this._database);
  final RoomRepository _roomRepo;
  final PendingJobRepository _jobRepo;
  final pb_chat.ChatServiceClient _chatClient;
  final AppDatabase _database;

  /// Create a new room (group or direct chat)
  /// Saves locally first, then queues for server sync
  ///
  /// Universal messaging: Pass all contact IDs regardless of platform status.
  /// The server will determine which members are on-platform vs off-platform,
  /// handle credit checks, and forward messages via notification service as needed.
  Future<domain.Room> createRoom({
    required String name,
    required String type,
    String? description,
    bool isPrivate = false,
    List<String> contactIds =
        const [], // All member contact IDs - server handles routing
    Map<String, dynamic>? metadata,
  }) async {
    final roomId = Xid().toString();

    final room = domain.Room(
      id: roomId,
      name: name,
      type: type,
      metadata: {
        ...?metadata,
        'description': description ?? '',
        'isPrivate': isPrivate,
        'pendingSync': true,
      },
    );

    // Save locally first
    await _roomRepo.insertRoom(room);

    // Queue for server sync - server handles all member types
    await _jobRepo.addJob(JobType.createRoom, {
      'id': roomId,
      'name': name,
      'description': description ?? '',
      'isPrivate': isPrivate,
      'contactIds': contactIds, // Server determines platform status and routing
      'metadata': metadata,
    });

    AppLogger.info(
      'Room created locally and queued for sync',
      data: {
        'roomId': roomId,
        'name': name,
        'type': type,
        'memberCount': contactIds.length,
      },
    );

    return room;
  }

  /// Update an existing room
  /// Saves locally first, then queues for server sync
  Future<domain.Room> updateRoom({
    required String roomId,
    String? name,
    String? description,
    Map<String, dynamic>? metadata,
  }) async {
    // Get existing room
    final existingRoom = await _roomRepo.getRoomById(roomId);
    if (existingRoom == null) {
      throw Exception('Room not found: $roomId');
    }

    // Merge metadata
    final updatedMetadata = {
      ...?existingRoom.metadata,
      ...?metadata,
      if (description != null) 'description': description,
      'pendingSync': true,
    };

    final updatedRoom = existingRoom.copyWith(
      name: name ?? existingRoom.name,
      metadata: updatedMetadata,
    );

    // Save locally first
    await _roomRepo.insertRoom(updatedRoom);

    // Queue for server sync
    await _jobRepo.addJob(JobType.updateRoom, {
      'id': roomId,
      'name': name ?? existingRoom.name,
      'description': description ?? updatedMetadata['description'] ?? '',
      'metadata': metadata,
    });

    AppLogger.info(
      'Room updated locally and queued for sync',
      data: {'roomId': roomId},
    );

    return updatedRoom;
  }

  /// Delete a room
  /// Marks as deleted locally, then queues for server sync
  Future<void> deleteRoom(String roomId) async {
    // Mark as deleted in metadata (soft delete)
    final existingRoom = await _roomRepo.getRoomById(roomId);
    if (existingRoom != null) {
      final updatedRoom = existingRoom.copyWith(
        metadata: {
          ...?existingRoom.metadata,
          'deleted': true,
          'pendingSync': true,
        },
      );
      await _roomRepo.insertRoom(updatedRoom);
    }

    // Queue for server sync
    await _jobRepo.addJob(JobType.deleteRoom, {'id': roomId});

    AppLogger.info('Room deletion queued for sync', data: {'roomId': roomId});
  }

  /// Add members to a room
  /// Saves locally first, then queues for server sync
  Future<void> addMembers({
    required String roomId,
    required List<String> profileIds,
  }) async {
    // Queue for server sync
    await _jobRepo.addJob(JobType.addRoomMembers, {
      'roomId': roomId,
      'profileIds': profileIds,
    });

    AppLogger.info(
      'Add members queued for sync',
      data: {'roomId': roomId, 'memberCount': profileIds.length},
    );
  }

  /// Remove members from a room
  /// Queues for server sync
  Future<void> removeMembers({
    required String roomId,
    required List<String> profileIds,
  }) async {
    // Queue for server sync
    await _jobRepo.addJob(JobType.removeRoomMembers, {
      'roomId': roomId,
      'profileIds': profileIds,
    });

    AppLogger.info(
      'Remove members queued for sync',
      data: {'roomId': roomId, 'memberCount': profileIds.length},
    );
  }

  /// Get all rooms (from local database)
  Future<List<domain.Room>> getAllRooms() async {
    final rooms = await _roomRepo.getAllRooms();
    // Filter out deleted rooms
    return rooms.where((room) {
      final metadata = room.metadata;
      if (metadata == null) return true;
      return metadata['deleted'] != true;
    }).toList();
  }

  /// Get a specific room by ID
  Future<domain.Room?> getRoomById(String roomId) async =>
      _roomRepo.getRoomById(roomId);

  /// Check if a room has pending sync
  bool hasPendingSync(domain.Room room) =>
      room.metadata?['pendingSync'] == true;

  /// Leave a room (current user exits the group)
  /// Marks as left locally, then queues for server sync
  Future<void> leaveRoom(String roomId) async {
    // Mark room as left in metadata (soft delete for user)
    final existingRoom = await _roomRepo.getRoomById(roomId);
    if (existingRoom != null) {
      final updatedRoom = existingRoom.copyWith(
        metadata: {
          ...?existingRoom.metadata,
          'left': true,
          'pendingSync': true,
        },
      );
      await _roomRepo.insertRoom(updatedRoom);
    }

    // Queue for server sync
    await _jobRepo.addJob(JobType.leaveRoom, {'roomId': roomId});

    AppLogger.info('Leave room queued for sync', data: {'roomId': roomId});
  }

  /// Sync room members from server
  /// Fetches room member subscriptions and stores them locally using the searchRoomSubscriptions API
  Future<void> syncRoomMembers(String roomId) async {
    try {
      // Create request to search room subscriptions
      final request = pb_chat.SearchRoomSubscriptionsRequest(roomId: roomId);

      // Fetch subscriptions from API (unary call returns single response)
      final response = await _chatClient.searchRoomSubscriptions(request);

      var memberCount = 0;

      // Process each subscription from the response
      for (final subscription in response.members) {
        // Extract subscription ID from API response
        final subscriptionId = subscription.id;

        // Extract profileId and contactId from ContactLink
        final profileId =
            subscription.hasMember() && subscription.member.hasProfileId()
            ? subscription.member.profileId
            : null;
        final contactId =
            subscription.hasMember() && subscription.member.hasContactId()
            ? subscription.member.contactId
            : null;

        // Extract role (use first role if multiple, or null)
        final role = subscription.roles.isNotEmpty
            ? subscription.roles.first
            : null;

        // Extract joined timestamp
        final joinedAt = subscription.hasJoinedAt()
            ? subscription.joinedAt.seconds.toInt() * 1000 +
                  subscription.joinedAt.nanos ~/ 1000000
            : null;

        // Insert or update room member
        await _database
            .into(_database.roomMembers)
            .insertOnConflictUpdate(
              RoomMembersCompanion.insert(
                subscriptionId: subscriptionId,
                roomId: subscription.roomId,
                profileId: Value(profileId),
                contactId: Value(contactId),
                role: Value(role),
                joinedAt: Value(joinedAt),
              ),
            );

        memberCount++;
      }

      AppLogger.info(
        'Room members synced',
        data: {'roomId': roomId, 'memberCount': memberCount},
      );
    } catch (e, stackTrace) {
      AppLogger.error(
        'Failed to sync room members',
        error: e,
        stackTrace: stackTrace,
        data: {'roomId': roomId},
      );
      rethrow;
    }
  }
}

/// Provider for RoomService
final roomServiceProvider = FutureProvider<RoomService>((ref) async {
  final roomRepo = ref.watch(roomRepositoryProvider);
  final jobRepo = ref.watch(pendingJobRepositoryProvider);
  final chatClient = await ref.watch(chatServiceClientProvider.future);
  final database = AppDatabase.instance;
  return RoomService(roomRepo, jobRepo, chatClient, database);
});

/// Provider for RoomRepository
final roomRepositoryProvider = Provider<RoomRepository>(
  (ref) => RoomRepository(AppDatabase.instance),
);
