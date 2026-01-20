// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RoomEvent _$RoomEventFromJson(Map<String, dynamic> json) => _RoomEvent(
  id: json['id'] as String,
  roomId: json['roomId'] as String,
  senderId: json['senderId'] as String,
  senderContactId: json['senderContactId'] as String?,
  type: $enumDecode(_$RoomEventTypeEnumMap, json['type']),
  content: json['content'] as Map<String, dynamic>,
  parentId: json['parentId'] as String?,
  status:
      $enumDecodeNullable(_$EventStatusEnumMap, json['status']) ??
      EventStatus.pending,
  createdAt: (json['createdAt'] as num).toInt(),
  serverTs: (json['serverTs'] as num?)?.toInt(),
  localId: json['localId'] as String?,
  editedAt: (json['editedAt'] as num?)?.toInt(),
);

Map<String, dynamic> _$RoomEventToJson(_RoomEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'roomId': instance.roomId,
      'senderId': instance.senderId,
      'senderContactId': instance.senderContactId,
      'type': _$RoomEventTypeEnumMap[instance.type]!,
      'content': instance.content,
      'parentId': instance.parentId,
      'status': _$EventStatusEnumMap[instance.status]!,
      'createdAt': instance.createdAt,
      'serverTs': instance.serverTs,
      'localId': instance.localId,
      'editedAt': instance.editedAt,
    };

const _$RoomEventTypeEnumMap = {
  RoomEventType.text: 'text',
  RoomEventType.image: 'image',
  RoomEventType.video: 'video',
  RoomEventType.audio: 'audio',
  RoomEventType.file: 'file',
  RoomEventType.reaction: 'reaction',
  RoomEventType.callOffer: 'callOffer',
  RoomEventType.callAnswer: 'callAnswer',
  RoomEventType.callIce: 'callIce',
  RoomEventType.callEnd: 'callEnd',
  RoomEventType.motion: 'motion',
  RoomEventType.vote: 'vote',
  RoomEventType.transaction: 'transaction',
};

const _$EventStatusEnumMap = {
  EventStatus.pending: 'pending',
  EventStatus.sent: 'sent',
  EventStatus.delivered: 'delivered',
  EventStatus.read: 'read',
  EventStatus.failed: 'failed',
};
