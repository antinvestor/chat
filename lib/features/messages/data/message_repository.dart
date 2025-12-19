import 'dart:convert';
import 'package:drift/drift.dart';
import '../../../core/db/database.dart';
import '../domain/room_event.dart' as domain;

class MessageRepository {
  final AppDatabase _database;

  MessageRepository(this._database);

  Future<List<domain.RoomEvent>> getMessagesForRoom(String roomId, {int limit = 50}) async {
    final query = _database.select(_database.roomEvents)
      ..where((t) => t.roomId.equals(roomId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);
    
    final results = await query.get();
    return results.map((row) => _toRoomEvent(row)).toList().reversed.toList();
  }

  Future<void> insertMessage(domain.RoomEvent event) async {
    await _database.into(_database.roomEvents).insertOnConflictUpdate(
      RoomEventsCompanion.insert(
        id: event.id,
        roomId: event.roomId,
        senderId: event.senderId,
        type: event.type.index,
        content: Value(jsonEncode(event.content)),
        parentId: Value(event.parentId),
        status: Value(event.status.index),
        createdAt: Value(event.createdAt),
        serverTs: Value(event.serverTs),
        localId: Value(event.localId),
      ),
    );
  }

  Future<void> updateMessageStatus(String messageId, domain.EventStatus status) async {
    await (_database.update(_database.roomEvents)
      ..where((t) => t.id.equals(messageId)))
      .write(RoomEventsCompanion(status: Value(status.index)));
  }

  Future<void> updateMessagesStatus(List<String> messageIds, domain.EventStatus status) async {
    if (messageIds.isEmpty) return;
    await (_database.update(_database.roomEvents)
      ..where((t) => t.id.isIn(messageIds)))
      .write(RoomEventsCompanion(status: Value(status.index)));
  }

  Future<List<domain.RoomEvent>> getReactionsForEvent(String eventId) async {
    final query = _database.select(_database.roomEvents)
      ..where((t) => t.parentId.equals(eventId) & t.type.equals(domain.RoomEventType.reaction.index));
    
    final results = await query.get();
    return results.map((row) => _toRoomEvent(row)).toList();
  }

  domain.RoomEvent _toRoomEvent(RoomEvent row) {
    return domain.RoomEvent(
      id: row.id,
      roomId: row.roomId,
      senderId: row.senderId,
      type: domain.RoomEventType.values[row.type],
      content: row.content != null ? jsonDecode(row.content!) : {},
      parentId: row.parentId,
      status: domain.EventStatus.values[row.status],
      createdAt: row.createdAt ?? 0,
      serverTs: row.serverTs,
      localId: row.localId,
    );
  }
}
