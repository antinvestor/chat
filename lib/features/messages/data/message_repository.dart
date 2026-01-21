import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../domain/room_event.dart' as domain;

/// Repository for message and room event operations
///
/// Provides database access for messages including:
/// - Fetching messages for a room with pagination
/// - Inserting and updating messages
/// - Watching message streams for reactive UI updates
/// - Managing message status (sent, delivered, read)
///
/// Example:
/// ```dart
/// final repo = MessageRepository(database);
/// final messages = await repo.getMessagesForRoom('room-123');
/// await repo.insertMessage(newMessage);
/// ```
class MessageRepository {
  MessageRepository(this._database);
  final AppDatabase _database;

  Future<List<domain.RoomEvent>> getMessagesForRoom(
    String roomId, {
    int limit = 50,
  }) async {
    final query = _database.select(_database.roomEvents)
      ..where((t) => t.roomId.equals(roomId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);

    final results = await query.get();
    return results.map(_toRoomEvent).toList().reversed.toList();
  }

  /// Get messages for a room before a specific timestamp (for pagination)
  /// Returns messages ordered from oldest to newest
  Future<List<domain.RoomEvent>> getMessagesBeforeTimestamp(
    String roomId, {
    required int beforeTimestamp,
    int limit = 50,
  }) async {
    final query = _database.select(_database.roomEvents)
      ..where(
        (t) =>
            t.roomId.equals(roomId) &
            t.createdAt.isSmallerThanValue(beforeTimestamp),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);

    final results = await query.get();
    return results.map(_toRoomEvent).toList().reversed.toList();
  }

  /// Get the oldest message timestamp for a room (for pagination cursor)
  Future<int?> getOldestMessageTimestamp(String roomId) async {
    final query = _database.select(_database.roomEvents)
      ..where((t) => t.roomId.equals(roomId))
      ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
      ..limit(1);

    final result = await query.getSingleOrNull();
    return result?.createdAt;
  }

  /// Get total message count for a room
  Future<int> getMessageCount(String roomId) async {
    final query = _database.select(_database.roomEvents)
      ..where((t) => t.roomId.equals(roomId));
    final results = await query.get();
    return results.length;
  }

  /// Watch messages for a room - provides reactive updates for instant UI refresh
  Stream<List<domain.RoomEvent>> watchMessagesForRoom(
    String roomId, {
    int limit = 50,
  }) {
    final query = _database.select(_database.roomEvents)
      ..where((t) => t.roomId.equals(roomId))
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(limit);

    return query.watch().map(
      (results) => results.map(_toRoomEvent).toList().reversed.toList(),
    );
  }

  Future<void> insertMessage(domain.RoomEvent event) async {
    await _database
        .into(_database.roomEvents)
        .insertOnConflictUpdate(
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
            editedAt: Value(event.editedAt),
            redacted: Value(event.redacted),
            redactedAt: Value(event.redactedAt),
            redactedBy: Value(event.redactedBy),
          ),
        );
  }

  Future<void> updateMessageStatus(
    String messageId,
    domain.EventStatus status,
  ) async {
    await (_database.update(_database.roomEvents)
          ..where((t) => t.id.equals(messageId)))
        .write(RoomEventsCompanion(status: Value(status.index)));
  }

  Future<void> updateMessagesStatus(
    List<String> messageIds,
    domain.EventStatus status,
  ) async {
    if (messageIds.isEmpty) return;
    await (_database.update(_database.roomEvents)
          ..where((t) => t.id.isIn(messageIds)))
        .write(RoomEventsCompanion(status: Value(status.index)));
  }

  /// Update the content of an existing message (for editing)
  ///
  /// Stores the original content if this is the first edit,
  /// and updates the editedAt timestamp.
  Future<void> updateMessageContent(
    String messageId,
    Map<String, dynamic> newContent, {
    String? originalContent,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_database.update(
      _database.roomEvents,
    )..where((t) => t.id.equals(messageId))).write(
      RoomEventsCompanion(
        content: Value(jsonEncode(newContent)),
        editedAt: Value(now),
        originalContent: originalContent != null
            ? Value(originalContent)
            : const Value.absent(),
      ),
    );
  }

  /// Check if a message can be edited (within time window and is text type)
  Future<bool> canEditMessage(
    String messageId,
    String currentUserId, {
    Duration editWindow = const Duration(minutes: 15),
  }) async {
    final event = await getEventById(messageId);
    if (event == null) return false;

    // Must be own message
    if (event.senderId != currentUserId) return false;

    // Must be text type
    if (event.type != domain.RoomEventType.text) return false;

    // Must be within edit window
    final messageAge = DateTime.now().millisecondsSinceEpoch - event.createdAt;
    if (messageAge > editWindow.inMilliseconds) return false;

    // Must not be failed or pending
    if (event.status == domain.EventStatus.failed ||
        event.status == domain.EventStatus.pending) {
      return false;
    }

    return true;
  }

  Future<domain.RoomEvent?> getEventById(String eventId) async {
    final query = _database.select(_database.roomEvents)
      ..where((t) => t.id.equals(eventId));

    final result = await query.getSingleOrNull();
    return result != null ? _toRoomEvent(result) : null;
  }

  Future<List<domain.RoomEvent>> getReactionsForEvent(String eventId) async {
    final query = _database.select(_database.roomEvents)
      ..where(
        (t) =>
            t.parentId.equals(eventId) &
            t.type.equals(domain.RoomEventType.reaction.index),
      );

    final results = await query.get();
    return results.map(_toRoomEvent).toList();
  }

  /// Delete a message for everyone (marks as redacted)
  ///
  /// Sets the redacted flag and timestamp. The message content
  /// is preserved locally for history but hidden in UI.
  Future<void> deleteMessage(String messageId, {String? deletedBy}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_database.update(
      _database.roomEvents,
    )..where((t) => t.id.equals(messageId))).write(
      RoomEventsCompanion(
        redacted: const Value(true),
        redactedAt: Value(now),
        redactedBy: deletedBy != null ? Value(deletedBy) : const Value.absent(),
      ),
    );
  }

  /// Delete a message locally only (removes from local database)
  ///
  /// This is for "delete for me" functionality where the message
  /// is only removed from the current user's device.
  Future<void> deleteMessageForMe(String messageId) async {
    await (_database.delete(
      _database.roomEvents,
    )..where((t) => t.id.equals(messageId))).go();
  }

  /// Check if a message can be deleted by the current user
  ///
  /// Users can delete their own messages within a time window,
  /// or admins can delete any message.
  Future<bool> canDeleteMessage(
    String messageId,
    String currentUserId, {
    Duration deleteWindow = const Duration(hours: 24),
    bool isAdmin = false,
  }) async {
    final event = await getEventById(messageId);
    if (event == null) return false;

    // Already deleted
    if (event.isDeleted) return false;

    // Admins can delete any message
    if (isAdmin) return true;

    // Must be own message
    if (event.senderId != currentUserId) return false;

    // Must be within delete window
    final messageAge = DateTime.now().millisecondsSinceEpoch - event.createdAt;
    if (messageAge > deleteWindow.inMilliseconds) return false;

    // Cannot delete pending or failed messages (use cancel instead)
    if (event.status == domain.EventStatus.pending ||
        event.status == domain.EventStatus.failed) {
      return false;
    }

    return true;
  }

  domain.RoomEvent _toRoomEvent(RoomEvent row) => domain.RoomEvent(
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
    editedAt: row.editedAt,
    redacted: row.redacted,
    redactedAt: row.redactedAt,
    redactedBy: row.redactedBy,
  );
}
