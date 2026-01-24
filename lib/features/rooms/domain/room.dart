import 'package:freezed_annotation/freezed_annotation.dart';

part 'room.freezed.dart';
part 'room.g.dart';

/// Chat room domain model
///
/// Represents a chat room which can be either a direct message (1:1)
/// or a group conversation. Rooms track their last message for
/// ordering and display purposes.
///
/// Example:
/// ```dart
/// final room = Room(
///   id: 'room-123',
///   name: 'Team Chat',
///   type: 'group',
///   unreadCount: 5,
/// );
/// ```
@freezed
abstract class Room with _$Room {
  const factory Room({
    required String id,
    required String name,
    required String type, // 'direct' or 'group'
    String? lastEventId,
    @Default(0) int lastEventIndex,
    @Default(0) int unreadCount,
    Map<String, dynamic>? metadata,

    /// Disappearing messages timeout in seconds (null = disabled)
    /// Supported values: null (off), 86400 (24h), 604800 (7d), 7776000 (90d)
    int? disappearingTimeout,
  }) = _Room;

  factory Room.fromJson(Map<String, dynamic> json) => _$RoomFromJson(json);
}
