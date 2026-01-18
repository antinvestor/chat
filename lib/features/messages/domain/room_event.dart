import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_event.freezed.dart';
part 'room_event.g.dart';

enum RoomEventType {
  text,
  image,
  video,
  audio,
  file,
  reaction,
  callOffer,
  callAnswer,
  callIce,
  callEnd,
  motion,
  vote,
  transaction,
}

enum EventStatus { pending, sent, delivered, read, failed }

@freezed
abstract class RoomEvent with _$RoomEvent {
  const factory RoomEvent({
    required String id,
    required String roomId,
    required String senderId, // Profile ID (from ContactLink.profileId)
    String? senderContactId, // Contact ID (from ContactLink.contactId)
    required RoomEventType type,
    required Map<String, dynamic> content,
    String? parentId,
    @Default(EventStatus.pending) EventStatus status,
    required int createdAt,
    int? serverTs,
    String? localId,
  }) = _RoomEvent;

  factory RoomEvent.fromJson(Map<String, dynamic> json) =>
      _$RoomEventFromJson(json);
}
