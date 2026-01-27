import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../domain/room.dart' as domain;
import '../domain/room_with_last_message.dart';

/// Repository for chat room operations
///
/// Provides database access for room management including:
/// - Fetching all rooms with optional filtering
/// - Getting rooms with their last message for display
/// - Creating, updating, and deleting rooms
/// - Managing unread message counts
///
/// Example:
/// ```dart
/// final repo = RoomRepository(database);
/// final rooms = await repo.getRoomsWithLastMessage();
/// final room = await repo.getRoomById('room-123');
/// ```
class RoomRepository {
  RoomRepository(this._database);
  final AppDatabase _database;

  Future<List<domain.Room>> getAllRooms() async {
    final query = _database.select(_database.rooms)
      ..orderBy([(t) => OrderingTerm.desc(t.lastEventIndex)]);
    final results = await query.get();

    return results.map(_toRoom).toList();
  }

  Future<List<RoomWithLastMessage>> getRoomsWithLastMessage() async {
    final query = _database.customSelect(
      '''
      SELECT 
        r.id,
        r.name,
        r.type,
        r.unread_count,
        e.content as last_message_content,
        e.created_at as last_message_timestamp,
        e.sender_id as last_message_sender_id
      FROM rooms r
      LEFT JOIN room_events e ON r.last_event_id = e.id
      ORDER BY COALESCE(e.created_at, 0) DESC
    ''',
      readsFrom: {_database.rooms, _database.roomEvents},
    );

    final results = await query.get();

    return results.map((row) {
      String? lastMessageText;
      final content = row.read<String?>('last_message_content');
      if (content != null) {
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        lastMessageText = decoded['text'] as String?;
      }

      return RoomWithLastMessage(
        id: row.read<String>('id'),
        name: row.read<String?>('name') ?? '',
        type: row.read<String?>('type') ?? '',
        unreadCount: row.read<int?>('unread_count') ?? 0,
        lastMessageText: lastMessageText,
        lastMessageTimestamp: row.read<int?>('last_message_timestamp'),
        lastMessageSenderId: row.read<String?>('last_message_sender_id'),
      );
    }).toList();
  }

  Future<domain.Room?> getRoomById(String roomId) async {
    final query = _database.select(_database.rooms)
      ..where((t) => t.id.equals(roomId));
    final result = await query.getSingleOrNull();

    if (result == null) return null;
    return _toRoom(result);
  }

  Future<void> insertRoom(domain.Room room) async {
    await _database
        .into(_database.rooms)
        .insertOnConflictUpdate(
          RoomsCompanion.insert(
            id: room.id,
            name: Value(room.name),
            type: Value(room.type),
            lastEventId: Value(room.lastEventId),
            lastEventIndex: Value(room.lastEventIndex),
            unreadCount: Value(room.unreadCount),
            metadata: Value(
              room.metadata != null ? jsonEncode(room.metadata) : null,
            ),
            disappearingTimeout: Value(room.disappearingTimeout),
          ),
        );
  }

  /// Update disappearing messages timeout for a room
  Future<void> updateDisappearingTimeout(String roomId, int? timeout) async {
    await (_database.update(_database.rooms)..where((t) => t.id.equals(roomId)))
        .write(RoomsCompanion(disappearingTimeout: Value(timeout)));
  }

  Future<void> updateUnreadCount(String roomId, int count) async {
    await (_database.update(_database.rooms)..where((t) => t.id.equals(roomId)))
        .write(RoomsCompanion(unreadCount: Value(count)));
  }

  /// Update room name from server-pushed change
  Future<void> updateRoomName(String roomId, String name) async {
    await (_database.update(_database.rooms)..where((t) => t.id.equals(roomId)))
        .write(RoomsCompanion(name: Value(name)));
  }

  /// Update room metadata from server-pushed change (merges with existing)
  Future<void> updateRoomMetadata(
    String roomId,
    Map<String, dynamic> newMetadata,
  ) async {
    final existing = await getRoomById(roomId);
    if (existing == null) return;

    final merged = {...?existing.metadata, ...newMetadata};

    await (_database.update(_database.rooms)..where((t) => t.id.equals(roomId)))
        .write(RoomsCompanion(metadata: Value(jsonEncode(merged))));
  }

  /// Mark room as deleted from server-pushed change
  Future<void> markRoomDeleted(String roomId) async {
    final existing = await getRoomById(roomId);
    if (existing == null) return;

    final metadata = {...?existing.metadata, 'deleted': true};

    await (_database.update(_database.rooms)..where((t) => t.id.equals(roomId)))
        .write(RoomsCompanion(metadata: Value(jsonEncode(metadata))));
  }

  domain.Room _toRoom(Room row) => domain.Room(
    id: row.id,
    name: row.name ?? '',
    type: row.type ?? '',
    lastEventId: row.lastEventId,
    lastEventIndex: row.lastEventIndex ?? 0,
    unreadCount: row.unreadCount,
    metadata: row.metadata != null ? jsonDecode(row.metadata!) : null,
    disappearingTimeout: row.disappearingTimeout,
  );
}
