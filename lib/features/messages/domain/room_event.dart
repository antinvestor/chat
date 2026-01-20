import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_event.freezed.dart';
part 'room_event.g.dart';

/// Types of events that can occur in a chat room
///
/// Includes message types (text, media, files), reactions,
/// call signaling, and group-specific events (motions, votes, transactions).
///
/// Example:
/// ```dart
/// final type = RoomEventType.text;
/// if (type == RoomEventType.image) {
///   // Handle image message
/// }
/// ```
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

/// Status of a message/event in its delivery lifecycle
///
/// Tracks message progression from creation to delivery:
/// - pending: Message created locally, not yet sent
/// - sent: Message sent to server
/// - delivered: Message delivered to recipient
/// - read: Message read by recipient
/// - failed: Message failed to send
///
/// Example:
/// ```dart
/// if (message.status == EventStatus.failed) {
///   showRetryButton();
/// }
/// ```
enum EventStatus { pending, sent, delivered, read, failed }

/// Room event domain model representing messages and events
///
/// A RoomEvent can be a text message, media attachment, reaction,
/// call signal, or other event type. Events are immutable and
/// identified by their ID.
///
/// Example:
/// ```dart
/// final message = RoomEvent(
///   id: 'event-123',
///   roomId: 'room-456',
///   senderId: 'profile-789',
///   type: RoomEventType.text,
///   content: {'text': 'Hello world'},
///   createdAt: DateTime.now().millisecondsSinceEpoch,
/// );
/// ```
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
