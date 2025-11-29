import 'dart:convert';
import '../../../core/db/database.dart';
import '../domain/room.dart';
import '../domain/room_with_last_message.dart';

class RoomRepository {
  final AppDatabase _database;

  RoomRepository(this._database);

  Future<List<Room>> getAllRooms() async {
    final db = await _database.database;
    final results = db.select('SELECT * FROM rooms ORDER BY last_event_index DESC');
    
    return results.map((row) {
      return Room(
        id: row['id'] as String,
        name: row['name'] as String,
        type: row['type'] as String,
        lastEventId: row['last_event_id'] as String?,
        lastEventIndex: row['last_event_index'] as int? ?? 0,
        unreadCount: row['unread_count'] as int? ?? 0,
        metadata: row['metadata'] != null 
          ? jsonDecode(row['metadata'] as String) 
          : null,
      );
    }).toList();
  }

  Future<List<RoomWithLastMessage>> getRoomsWithLastMessage() async {
    final db = await _database.database;
    
    // Join rooms with their last message
    final results = db.select('''
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
    ''');
    
    return results.map((row) {
      String? lastMessageText;
      if (row['last_message_content'] != null) {
        final content = jsonDecode(row['last_message_content'] as String) as Map<String, dynamic>;
        lastMessageText = content['text'] as String?;
      }
      
      return RoomWithLastMessage(
        id: row['id'] as String,
        name: row['name'] as String,
        type: row['type'] as String,
        unreadCount: row['unread_count'] as int? ?? 0,
        lastMessageText: lastMessageText,
        lastMessageTimestamp: row['last_message_timestamp'] as int?,
        lastMessageSenderId: row['last_message_sender_id'] as String?,
      );
    }).toList();
  }

  Future<Room?> getRoomById(String roomId) async {
    final db = await _database.database;
    final results = db.select('SELECT * FROM rooms WHERE id = ?', [roomId]);
    
    if (results.isEmpty) return null;
    
    final row = results.first;
    return Room(
      id: row['id'] as String,
      name: row['name'] as String,
      type: row['type'] as String,
      lastEventId: row['last_event_id'] as String?,
      lastEventIndex: row['last_event_index'] as int? ?? 0,
      unreadCount: row['unread_count'] as int? ?? 0,
      metadata: row['metadata'] != null 
        ? jsonDecode(row['metadata'] as String) 
        : null,
    );
  }

  Future<void> insertRoom(Room room) async {
    final db = await _database.database;
    db.execute(
      '''INSERT OR REPLACE INTO rooms (id, name, type, last_event_id, last_event_index, unread_count, metadata)
         VALUES (?, ?, ?, ?, ?, ?, ?)''',
      [
        room.id,
        room.name,
        room.type,
        room.lastEventId,
        room.lastEventIndex,
        room.unreadCount,
        room.metadata != null ? jsonEncode(room.metadata) : null,
      ],
    );
  }

  Future<void> updateUnreadCount(String roomId, int count) async {
    final db = await _database.database;
    db.execute('UPDATE rooms SET unread_count = ? WHERE id = ?', [count, roomId]);
  }
}
