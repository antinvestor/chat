// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'room_event.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$RoomEvent {

 String get id; String get roomId; String get senderId; RoomEventType get type; Map<String, dynamic> get content; String? get parentId; EventStatus get status; int get createdAt; int? get serverTs; String? get localId;
/// Create a copy of RoomEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RoomEventCopyWith<RoomEvent> get copyWith => _$RoomEventCopyWithImpl<RoomEvent>(this as RoomEvent, _$identity);

  /// Serializes this RoomEvent to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RoomEvent&&(identical(other.id, id) || other.id == id)&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.senderId, senderId) || other.senderId == senderId)&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other.content, content)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.serverTs, serverTs) || other.serverTs == serverTs)&&(identical(other.localId, localId) || other.localId == localId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,roomId,senderId,type,const DeepCollectionEquality().hash(content),parentId,status,createdAt,serverTs,localId);

@override
String toString() {
  return 'RoomEvent(id: $id, roomId: $roomId, senderId: $senderId, type: $type, content: $content, parentId: $parentId, status: $status, createdAt: $createdAt, serverTs: $serverTs, localId: $localId)';
}


}

/// @nodoc
abstract mixin class $RoomEventCopyWith<$Res>  {
  factory $RoomEventCopyWith(RoomEvent value, $Res Function(RoomEvent) _then) = _$RoomEventCopyWithImpl;
@useResult
$Res call({
 String id, String roomId, String senderId, RoomEventType type, Map<String, dynamic> content, String? parentId, EventStatus status, int createdAt, int? serverTs, String? localId
});




}
/// @nodoc
class _$RoomEventCopyWithImpl<$Res>
    implements $RoomEventCopyWith<$Res> {
  _$RoomEventCopyWithImpl(this._self, this._then);

  final RoomEvent _self;
  final $Res Function(RoomEvent) _then;

/// Create a copy of RoomEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? roomId = null,Object? senderId = null,Object? type = null,Object? content = null,Object? parentId = freezed,Object? status = null,Object? createdAt = null,Object? serverTs = freezed,Object? localId = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,senderId: null == senderId ? _self.senderId : senderId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as RoomEventType,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as EventStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,serverTs: freezed == serverTs ? _self.serverTs : serverTs // ignore: cast_nullable_to_non_nullable
as int?,localId: freezed == localId ? _self.localId : localId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [RoomEvent].
extension RoomEventPatterns on RoomEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RoomEvent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RoomEvent() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RoomEvent value)  $default,){
final _that = this;
switch (_that) {
case _RoomEvent():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RoomEvent value)?  $default,){
final _that = this;
switch (_that) {
case _RoomEvent() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String roomId,  String senderId,  RoomEventType type,  Map<String, dynamic> content,  String? parentId,  EventStatus status,  int createdAt,  int? serverTs,  String? localId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RoomEvent() when $default != null:
return $default(_that.id,_that.roomId,_that.senderId,_that.type,_that.content,_that.parentId,_that.status,_that.createdAt,_that.serverTs,_that.localId);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String roomId,  String senderId,  RoomEventType type,  Map<String, dynamic> content,  String? parentId,  EventStatus status,  int createdAt,  int? serverTs,  String? localId)  $default,) {final _that = this;
switch (_that) {
case _RoomEvent():
return $default(_that.id,_that.roomId,_that.senderId,_that.type,_that.content,_that.parentId,_that.status,_that.createdAt,_that.serverTs,_that.localId);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String roomId,  String senderId,  RoomEventType type,  Map<String, dynamic> content,  String? parentId,  EventStatus status,  int createdAt,  int? serverTs,  String? localId)?  $default,) {final _that = this;
switch (_that) {
case _RoomEvent() when $default != null:
return $default(_that.id,_that.roomId,_that.senderId,_that.type,_that.content,_that.parentId,_that.status,_that.createdAt,_that.serverTs,_that.localId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _RoomEvent implements RoomEvent {
  const _RoomEvent({required this.id, required this.roomId, required this.senderId, required this.type, required final  Map<String, dynamic> content, this.parentId, this.status = EventStatus.pending, required this.createdAt, this.serverTs, this.localId}): _content = content;
  factory _RoomEvent.fromJson(Map<String, dynamic> json) => _$RoomEventFromJson(json);

@override final  String id;
@override final  String roomId;
@override final  String senderId;
@override final  RoomEventType type;
 final  Map<String, dynamic> _content;
@override Map<String, dynamic> get content {
  if (_content is EqualUnmodifiableMapView) return _content;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_content);
}

@override final  String? parentId;
@override@JsonKey() final  EventStatus status;
@override final  int createdAt;
@override final  int? serverTs;
@override final  String? localId;

/// Create a copy of RoomEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RoomEventCopyWith<_RoomEvent> get copyWith => __$RoomEventCopyWithImpl<_RoomEvent>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$RoomEventToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _RoomEvent&&(identical(other.id, id) || other.id == id)&&(identical(other.roomId, roomId) || other.roomId == roomId)&&(identical(other.senderId, senderId) || other.senderId == senderId)&&(identical(other.type, type) || other.type == type)&&const DeepCollectionEquality().equals(other._content, _content)&&(identical(other.parentId, parentId) || other.parentId == parentId)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.serverTs, serverTs) || other.serverTs == serverTs)&&(identical(other.localId, localId) || other.localId == localId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,roomId,senderId,type,const DeepCollectionEquality().hash(_content),parentId,status,createdAt,serverTs,localId);

@override
String toString() {
  return 'RoomEvent(id: $id, roomId: $roomId, senderId: $senderId, type: $type, content: $content, parentId: $parentId, status: $status, createdAt: $createdAt, serverTs: $serverTs, localId: $localId)';
}


}

/// @nodoc
abstract mixin class _$RoomEventCopyWith<$Res> implements $RoomEventCopyWith<$Res> {
  factory _$RoomEventCopyWith(_RoomEvent value, $Res Function(_RoomEvent) _then) = __$RoomEventCopyWithImpl;
@override @useResult
$Res call({
 String id, String roomId, String senderId, RoomEventType type, Map<String, dynamic> content, String? parentId, EventStatus status, int createdAt, int? serverTs, String? localId
});




}
/// @nodoc
class __$RoomEventCopyWithImpl<$Res>
    implements _$RoomEventCopyWith<$Res> {
  __$RoomEventCopyWithImpl(this._self, this._then);

  final _RoomEvent _self;
  final $Res Function(_RoomEvent) _then;

/// Create a copy of RoomEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? roomId = null,Object? senderId = null,Object? type = null,Object? content = null,Object? parentId = freezed,Object? status = null,Object? createdAt = null,Object? serverTs = freezed,Object? localId = freezed,}) {
  return _then(_RoomEvent(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,roomId: null == roomId ? _self.roomId : roomId // ignore: cast_nullable_to_non_nullable
as String,senderId: null == senderId ? _self.senderId : senderId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as RoomEventType,content: null == content ? _self._content : content // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>,parentId: freezed == parentId ? _self.parentId : parentId // ignore: cast_nullable_to_non_nullable
as String?,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as EventStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,serverTs: freezed == serverTs ? _self.serverTs : serverTs // ignore: cast_nullable_to_non_nullable
as int?,localId: freezed == localId ? _self.localId : localId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
