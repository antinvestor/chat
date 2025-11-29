import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import '../../../core/db/database.dart';
import '../domain/room_event.dart';

class MessageRepository {
  final AppDatabase _database;

  MessageRepository(this._database);

  Future<List<RoomEvent>> getMessagesForRoom(String roomId, {int limit = 50}) async {
    final db = await _database.database;
    final results = db.select(
      'SELECT * FROM room_events WHERE room_id = ? ORDER BY created_at DESC LIMIT ?',
      [roomId, limit],
    );
    
    return results.map((row) => _rowToRoomEvent(row)).toList().reversed.toList();
  }

  Future<void> insertMessage(RoomEvent event) async {
    final db = await _database.database;
    db.execute(
      '''INSERT OR REPLACE INTO room_events 
         (id, room_id, sender_id, type, content, parent_id, status, created_at, server_ts, local_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        event.id,
        event.roomId,
        event.senderId,
        event.type.index,
        jsonEncode(event.content),
        event.parentId,
        event.status.index,
        event.createdAt,
        event.serverTs,
        event.localId,
      ],
    );
  }

  Future<void> updateMessageStatus(String messageId, EventStatus status) async {
    final db = await _database.database;
    db.execute('UPDATE room_events SET status = ? WHERE id = ?', [status.index, messageId]);
  }

  Future<void> updateMessagesStatus(List<String> messageIds, EventStatus status) async {
    if (messageIds.isEmpty) return;
    final db = await _database.database;
    final placeholders = List.filled(messageIds.length, '?').join(',');
    db.execute(
      'UPDATE room_events SET status = ? WHERE id IN ($placeholders)',
      [status.index, ...messageIds],
    );
  }

  Future<List<RoomEvent>> getReactionsForEvent(String eventId) async {
    final db = await _database.database;
    final results = db.select(
      'SELECT * FROM room_events WHERE parent_id = ? AND type = ?',
      [eventId, RoomEventType.reaction.index],
    );
    
    return results.map((row) => _rowToRoomEvent(row)).toList();
  }

  RoomEvent _rowToRoomEvent(Row row) {
    return RoomEvent(
      id: row['id'] as String,
      roomId: row['room_id'] as String,
      senderId: row['sender_id'] as String,
      type: RoomEventType.values[row['type'] as int],
      content: jsonDecode(row['content'] as String),
      parentId: row['parent_id'] as String?,
      status: EventStatus.values[row['status'] as int],
      createdAt: row['created_at'] as int,
      serverTs: row['server_ts'] as int?,
      localId: row['local_id'] as String?,
    );
  }
}
