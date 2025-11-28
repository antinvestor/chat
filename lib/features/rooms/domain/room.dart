import 'package:freezed_annotation/freezed_annotation.dart';

part 'room.freezed.dart';
part 'room.g.dart';

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
  }) = _Room;

  factory Room.fromJson(Map<String, dynamic> json) => _$RoomFromJson(json);
}
