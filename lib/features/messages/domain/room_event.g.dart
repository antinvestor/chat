// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'room_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_RoomEvent _$RoomEventFromJson(Map<String, dynamic> json) => _RoomEvent(
  id: json['id'] as String,
  roomId: json['roomId'] as String,
  senderId: json['senderId'] as String,
  type: $enumDecode(_$RoomEventTypeEnumMap, json['type']),
  content: json['content'] as Map<String, dynamic>,
  createdAt: (json['createdAt'] as num).toInt(),
  senderContactId: json['senderContactId'] as String?,
  parentId: json['parentId'] as String?,
  status:
      $enumDecodeNullable(_$EventStatusEnumMap, json['status']) ??
      EventStatus.pending,
  serverTs: (json['serverTs'] as num?)?.toInt(),
  localId: json['localId'] as String?,
  editedAt: (json['editedAt'] as num?)?.toInt(),
  redacted: json['redacted'] as bool? ?? false,
  redactedAt: (json['redactedAt'] as num?)?.toInt(),
  redactedBy: json['redactedBy'] as String?,
);

Map<String, dynamic> _$RoomEventToJson(_RoomEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'roomId': instance.roomId,
      'senderId': instance.senderId,
      'type': _$RoomEventTypeEnumMap[instance.type]!,
      'content': instance.content,
      'createdAt': instance.createdAt,
      'senderContactId': instance.senderContactId,
      'parentId': instance.parentId,
      'status': _$EventStatusEnumMap[instance.status]!,
      'serverTs': instance.serverTs,
      'localId': instance.localId,
      'editedAt': instance.editedAt,
      'redacted': instance.redacted,
      'redactedAt': instance.redactedAt,
      'redactedBy': instance.redactedBy,
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
