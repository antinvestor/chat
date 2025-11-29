import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_with_last_message.freezed.dart';

@freezed
abstract class RoomWithLastMessage with _$RoomWithLastMessage {
  const factory RoomWithLastMessage({
    required String id,
    required String name,
    required String type,
    required int unreadCount,
    String? lastMessageText,
    int? lastMessageTimestamp,
    String? lastMessageSenderId,
  }) = _RoomWithLastMessage;
}
