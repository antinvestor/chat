import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/db/database.dart';
import '../../messages/domain/room_event.dart' as domain;

part 'detail_panel_providers.g.dart';

/// Provider for active motions in a room
/// Returns motions that haven't expired yet
@riverpod
Stream<List<domain.RoomEvent>> activeMotions(Ref ref, String roomId) {
  final db = AppDatabase.instance;

  // Watch room events and filter for active motions
  return (db.select(db.roomEvents)
    ..where((t) => t.roomId.equals(roomId))
    ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
      .watch()
      .map((events) {
    final now = DateTime.now();

    return events.where((event) {
      if (event.type != domain.RoomEventType.motion.index) return false;

      // Parse content to check deadline
      try {
        final content = event.content != null
            ? (jsonDecode(event.content!) as Map<String, dynamic>)
            : <String, dynamic>{};

        final deadlineMs = content['deadline'] as int?;
        if (deadlineMs == null) return false;

        final deadline = DateTime.fromMillisecondsSinceEpoch(deadlineMs);
        final status = content['status'] as String? ?? 'active';

        // Include if not expired and status is active
        return now.isBefore(deadline) && status == 'active';
      } catch (e) {
        return false;
      }
    }).map((event) => _toRoomEvent(event)).toList();
  });
}

/// Provider for room members
/// Returns list of members in a room with their profile info
@riverpod
Future<List<RoomMemberInfo>> roomMembers(Ref ref, String roomId) async {
  final db = AppDatabase.instance;

  final query = db.select(db.roomMembers)
    ..where((t) => t.roomId.equals(roomId));

  final members = await query.get();

  // Fetch profile info for each member
  final memberInfoList = <RoomMemberInfo>[];

  for (final member in members) {
    String? name;
    String? avatarUrl;

    // Try to get profile info if profileId is set
    if (member.profileId != null) {
      final profileQuery = db.select(db.profiles)
        ..where((t) => t.id.equals(member.profileId!));

      final profile = await profileQuery.getSingleOrNull();
      if (profile != null) {
        name = profile.name;
        avatarUrl = profile.avatarUrl;
      }
    }

    // Fallback to contact info
    if (name == null && member.contactId != null) {
      final rosterQuery = db.select(db.roster)
        ..where((t) => t.contactId.equals(member.contactId!));

      final contact = await rosterQuery.getSingleOrNull();
      if (contact != null) {
        name = contact.displayName ?? contact.contactDetail;
      }
    }

    memberInfoList.add(RoomMemberInfo(
      subscriptionId: member.subscriptionId,
      profileId: member.profileId,
      contactId: member.contactId,
      name: name ?? 'Unknown',
      avatarUrl: avatarUrl,
      role: member.role ?? 'member',
      joinedAt: member.joinedAt,
    ));
  }

  return memberInfoList;
}

/// Provider for shared media in a room (images and videos)
@riverpod
Stream<List<domain.RoomEvent>> roomMedia(Ref ref, String roomId) {
  final db = AppDatabase.instance;

  return (db.select(db.roomEvents)
        ..where((t) => t.roomId.equals(roomId))
        ..where((t) =>
            t.type.equals(domain.RoomEventType.image.index) |
            t.type.equals(domain.RoomEventType.video.index))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(50))
      .watch()
      .map((events) {
    return events.map((event) => _toRoomEvent(event)).toList();
  });
}

/// Provider for recent transactions in a room
@riverpod
Stream<List<domain.RoomEvent>> roomTransactions(Ref ref, String roomId) {
  final db = AppDatabase.instance;

  return (db.select(db.roomEvents)
        ..where((t) => t.roomId.equals(roomId))
        ..where((t) => t.type.equals(domain.RoomEventType.transaction.index))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(50))
      .watch()
      .map((events) {
    return events.map((event) => _toRoomEvent(event)).toList();
  });
}

// Helper to convert database row to domain model
domain.RoomEvent _toRoomEvent(RoomEvent row) {
  return domain.RoomEvent(
    id: row.id,
    roomId: row.roomId,
    senderId: row.senderId,
    senderContactId: row.senderContactId,
    type: domain.RoomEventType.values[row.type],
    content: row.content != null
        ? (jsonDecode(row.content!) as Map<String, dynamic>)
        : {},
    parentId: row.parentId,
    status: domain.EventStatus.values[row.status],
    createdAt: row.createdAt ?? 0,
    serverTs: row.serverTs,
    localId: row.localId,
  );
}

/// Room member information for display
class RoomMemberInfo {
  final String subscriptionId;
  final String? profileId;
  final String? contactId;
  final String name;
  final String? avatarUrl;
  final String role;
  final int? joinedAt;

  RoomMemberInfo({
    required this.subscriptionId,
    required this.profileId,
    required this.contactId,
    required this.name,
    required this.avatarUrl,
    required this.role,
    required this.joinedAt,
  });
}
