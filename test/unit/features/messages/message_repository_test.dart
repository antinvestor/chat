import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:chat/core/db/database.dart' hide RoomEvent;
import 'package:chat/features/messages/data/message_repository.dart';
import 'package:chat/features/messages/domain/room_event.dart';

import '../../../test_helpers/test_database.dart';

void main() {
  late AppDatabase testDb;
  late MessageRepository repository;

  /// Helper to create a room in the database (required due to foreign key constraints)
  Future<void> createTestRoom(String roomId, {String? name}) async {
    await testDb.into(testDb.rooms).insertOnConflictUpdate(
      RoomsCompanion.insert(
        id: roomId,
        name: Value(name ?? 'Test Room'),
        type: const Value('group'),
      ),
    );
  }

  setUp(() async {
    testDb = createTestDatabase();
    repository = MessageRepository(testDb);
  });

  tearDown(() async {
    await testDb.close();
  });

  group('MessageRepository', () {
    group('insertMessage', () {
      test('inserts a text message successfully', () async {
        await createTestRoom('room-1');

        final event = RoomEvent(
          id: 'event-1',
          roomId: 'room-1',
          senderId: 'sender-1',
          type: RoomEventType.text,
          content: {'text': 'Hello, world!'},
          status: EventStatus.sent,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );

        await repository.insertMessage(event);

        final result = await repository.getEventById('event-1');
        expect(result, isNotNull);
        expect(result!.id, equals('event-1'));
        expect(result.roomId, equals('room-1'));
        expect(result.senderId, equals('sender-1'));
        expect(result.type, equals(RoomEventType.text));
        expect(result.content['text'], equals('Hello, world!'));
      });

      test('updates existing message on conflict', () async {
        await createTestRoom('room-1');

        final event1 = RoomEvent(
          id: 'event-1',
          roomId: 'room-1',
          senderId: 'sender-1',
          type: RoomEventType.text,
          content: {'text': 'Original'},
          status: EventStatus.pending,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );

        final event2 = RoomEvent(
          id: 'event-1',
          roomId: 'room-1',
          senderId: 'sender-1',
          type: RoomEventType.text,
          content: {'text': 'Updated'},
          status: EventStatus.sent,
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );

        await repository.insertMessage(event1);
        await repository.insertMessage(event2);

        final result = await repository.getEventById('event-1');
        expect(result!.content['text'], equals('Updated'));
        expect(result.status, equals(EventStatus.sent));
      });

      test('inserts message with all event types', () async {
        await createTestRoom('room-1');

        for (final type in RoomEventType.values) {
          final event = RoomEvent(
            id: 'event-${type.name}',
            roomId: 'room-1',
            senderId: 'sender-1',
            type: type,
            content: {'type': type.name},
            createdAt: DateTime.now().millisecondsSinceEpoch,
          );

          await repository.insertMessage(event);

          final result = await repository.getEventById('event-${type.name}');
          expect(result, isNotNull, reason: 'Failed for type: ${type.name}');
          expect(result!.type, equals(type));
        }
      });
    });

    group('getMessagesForRoom', () {
      test('returns empty list for room with no messages', () async {
        await createTestRoom('empty-room');

        final messages = await repository.getMessagesForRoom('empty-room');
        expect(messages, isEmpty);
      });

      test('returns messages for specific room', () async {
        await createTestRoom('room-1');
        await createTestRoom('room-2');

        for (var i = 1; i <= 5; i++) {
          await repository.insertMessage(
            RoomEvent(
              id: 'room1-event-$i',
              roomId: 'room-1',
              senderId: 'sender-1',
              type: RoomEventType.text,
              content: {'text': 'Message $i'},
              createdAt: DateTime.now().millisecondsSinceEpoch + i,
            ),
          );
        }

        for (var i = 1; i <= 3; i++) {
          await repository.insertMessage(
            RoomEvent(
              id: 'room2-event-$i',
              roomId: 'room-2',
              senderId: 'sender-1',
              type: RoomEventType.text,
              content: {'text': 'Message $i'},
              createdAt: DateTime.now().millisecondsSinceEpoch + i,
            ),
          );
        }

        final room1Messages = await repository.getMessagesForRoom('room-1');
        final room2Messages = await repository.getMessagesForRoom('room-2');

        expect(room1Messages.length, equals(5));
        expect(room2Messages.length, equals(3));
      });

      test('returns messages ordered by timestamp (oldest first)', () async {
        await createTestRoom('room-1');
        final now = DateTime.now().millisecondsSinceEpoch;

        await repository.insertMessage(
          RoomEvent(
            id: 'event-3',
            roomId: 'room-1',
            senderId: 'sender-1',
            type: RoomEventType.text,
            content: {'text': 'Third'},
            createdAt: now + 3000,
          ),
        );

        await repository.insertMessage(
          RoomEvent(
            id: 'event-1',
            roomId: 'room-1',
            senderId: 'sender-1',
            type: RoomEventType.text,
            content: {'text': 'First'},
            createdAt: now + 1000,
          ),
        );

        await repository.insertMessage(
          RoomEvent(
            id: 'event-2',
            roomId: 'room-1',
            senderId: 'sender-1',
            type: RoomEventType.text,
            content: {'text': 'Second'},
            createdAt: now + 2000,
          ),
        );

        final messages = await repository.getMessagesForRoom('room-1');

        expect(messages[0].content['text'], equals('First'));
        expect(messages[1].content['text'], equals('Second'));
        expect(messages[2].content['text'], equals('Third'));
      });

      test('respects limit parameter', () async {
        await createTestRoom('room-1');

        for (var i = 1; i <= 100; i++) {
          await repository.insertMessage(
            RoomEvent(
              id: 'event-$i',
              roomId: 'room-1',
              senderId: 'sender-1',
              type: RoomEventType.text,
              content: {'text': 'Message $i'},
              createdAt: DateTime.now().millisecondsSinceEpoch + i,
            ),
          );
        }

        final limitedMessages = await repository.getMessagesForRoom(
          'room-1',
          limit: 20,
        );

        expect(limitedMessages.length, equals(20));
      });
    });

    group('getMessagesBeforeTimestamp', () {
      test('returns messages before given timestamp', () async {
        await createTestRoom('room-1');
        final now = DateTime.now().millisecondsSinceEpoch;

        for (var i = 1; i <= 10; i++) {
          await repository.insertMessage(
            RoomEvent(
              id: 'event-$i',
              roomId: 'room-1',
              senderId: 'sender-1',
              type: RoomEventType.text,
              content: {'text': 'Message $i'},
              createdAt: now + (i * 1000),
            ),
          );
        }

        final messages = await repository.getMessagesBeforeTimestamp(
          'room-1',
          beforeTimestamp: now + 5500,
        );

        expect(messages.length, equals(5));
        expect(messages.last.content['text'], equals('Message 5'));
      });
    });

    group('getOldestMessageTimestamp', () {
      test('returns null for room with no messages', () async {
        await createTestRoom('empty-room');

        final timestamp = await repository.getOldestMessageTimestamp('empty-room');
        expect(timestamp, isNull);
      });

      test('returns oldest timestamp for room with messages', () async {
        await createTestRoom('room-1');
        final oldest = DateTime.now().millisecondsSinceEpoch;

        await repository.insertMessage(
          RoomEvent(
            id: 'event-2',
            roomId: 'room-1',
            senderId: 'sender-1',
            type: RoomEventType.text,
            content: {'text': 'Newer'},
            createdAt: oldest + 1000,
          ),
        );

        await repository.insertMessage(
          RoomEvent(
            id: 'event-1',
            roomId: 'room-1',
            senderId: 'sender-1',
            type: RoomEventType.text,
            content: {'text': 'Oldest'},
            createdAt: oldest,
          ),
        );

        final timestamp = await repository.getOldestMessageTimestamp('room-1');
        expect(timestamp, equals(oldest));
      });
    });

    group('getMessageCount', () {
      test('returns 0 for empty room', () async {
        await createTestRoom('empty-room');

        final count = await repository.getMessageCount('empty-room');
        expect(count, equals(0));
      });

      test('returns correct count for room with messages', () async {
        await createTestRoom('room-1');

        for (var i = 1; i <= 15; i++) {
          await repository.insertMessage(
            RoomEvent(
              id: 'event-$i',
              roomId: 'room-1',
              senderId: 'sender-1',
              type: RoomEventType.text,
              content: {'text': 'Message $i'},
              createdAt: DateTime.now().millisecondsSinceEpoch + i,
            ),
          );
        }

        final count = await repository.getMessageCount('room-1');
        expect(count, equals(15));
      });
    });

    group('updateMessageStatus', () {
      test('updates status of existing message', () async {
        await createTestRoom('room-1');

        await repository.insertMessage(
          RoomEvent(
            id: 'event-1',
            roomId: 'room-1',
            senderId: 'sender-1',
            type: RoomEventType.text,
            content: {'text': 'Test'},
            status: EventStatus.pending,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        await repository.updateMessageStatus('event-1', EventStatus.sent);

        final result = await repository.getEventById('event-1');
        expect(result!.status, equals(EventStatus.sent));
      });

      test('updates through all status transitions', () async {
        await createTestRoom('room-1');

        await repository.insertMessage(
          RoomEvent(
            id: 'event-1',
            roomId: 'room-1',
            senderId: 'sender-1',
            type: RoomEventType.text,
            content: {'text': 'Test'},
            status: EventStatus.pending,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        // Pending -> Sent
        await repository.updateMessageStatus('event-1', EventStatus.sent);
        var result = await repository.getEventById('event-1');
        expect(result!.status, equals(EventStatus.sent));

        // Sent -> Delivered
        await repository.updateMessageStatus('event-1', EventStatus.delivered);
        result = await repository.getEventById('event-1');
        expect(result!.status, equals(EventStatus.delivered));

        // Delivered -> Read
        await repository.updateMessageStatus('event-1', EventStatus.read);
        result = await repository.getEventById('event-1');
        expect(result!.status, equals(EventStatus.read));
      });
    });

    group('updateMessagesStatus', () {
      test('updates status of multiple messages', () async {
        await createTestRoom('room-1');

        for (var i = 1; i <= 5; i++) {
          await repository.insertMessage(
            RoomEvent(
              id: 'event-$i',
              roomId: 'room-1',
              senderId: 'sender-1',
              type: RoomEventType.text,
              content: {'text': 'Message $i'},
              status: EventStatus.pending,
              createdAt: DateTime.now().millisecondsSinceEpoch + i,
            ),
          );
        }

        await repository.updateMessagesStatus(
          ['event-1', 'event-2', 'event-3'],
          EventStatus.sent,
        );

        final event1 = await repository.getEventById('event-1');
        final event2 = await repository.getEventById('event-2');
        final event3 = await repository.getEventById('event-3');
        final event4 = await repository.getEventById('event-4');

        expect(event1!.status, equals(EventStatus.sent));
        expect(event2!.status, equals(EventStatus.sent));
        expect(event3!.status, equals(EventStatus.sent));
        expect(event4!.status, equals(EventStatus.pending));
      });

      test('handles empty list gracefully', () async {
        await repository.updateMessagesStatus([], EventStatus.sent);
      });
    });

    group('getEventById', () {
      test('returns null for non-existent event', () async {
        final result = await repository.getEventById('non-existent');
        expect(result, isNull);
      });

      test('returns event with all fields populated', () async {
        await createTestRoom('room-1');
        final now = DateTime.now().millisecondsSinceEpoch;

        await repository.insertMessage(
          RoomEvent(
            id: 'event-1',
            roomId: 'room-1',
            senderId: 'sender-1',
            senderContactId: 'contact-1',
            type: RoomEventType.image,
            content: {'url': 'https://example.com/image.jpg', 'size': 1024},
            parentId: 'parent-event',
            status: EventStatus.delivered,
            createdAt: now,
            serverTs: now + 100,
            localId: 'local-123',
          ),
        );

        final result = await repository.getEventById('event-1');
        expect(result, isNotNull);
        expect(result!.id, equals('event-1'));
        expect(result.roomId, equals('room-1'));
        expect(result.senderId, equals('sender-1'));
        expect(result.type, equals(RoomEventType.image));
        expect(result.content['url'], equals('https://example.com/image.jpg'));
        expect(result.parentId, equals('parent-event'));
        expect(result.status, equals(EventStatus.delivered));
        expect(result.createdAt, equals(now));
        expect(result.serverTs, equals(now + 100));
        expect(result.localId, equals('local-123'));
      });
    });

    group('getReactionsForEvent', () {
      test('returns empty list when no reactions', () async {
        await createTestRoom('room-1');

        await repository.insertMessage(
          RoomEvent(
            id: 'event-1',
            roomId: 'room-1',
            senderId: 'sender-1',
            type: RoomEventType.text,
            content: {'text': 'Hello'},
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        final reactions = await repository.getReactionsForEvent('event-1');
        expect(reactions, isEmpty);
      });

      test('returns reactions for message', () async {
        await createTestRoom('room-1');
        final now = DateTime.now().millisecondsSinceEpoch;

        // Parent message
        await repository.insertMessage(
          RoomEvent(
            id: 'event-1',
            roomId: 'room-1',
            senderId: 'sender-1',
            type: RoomEventType.text,
            content: {'text': 'Hello'},
            createdAt: now,
          ),
        );

        // Reactions
        await repository.insertMessage(
          RoomEvent(
            id: 'reaction-1',
            roomId: 'room-1',
            senderId: 'sender-2',
            type: RoomEventType.reaction,
            content: {'emoji': '👍'},
            parentId: 'event-1',
            createdAt: now + 1,
          ),
        );

        await repository.insertMessage(
          RoomEvent(
            id: 'reaction-2',
            roomId: 'room-1',
            senderId: 'sender-3',
            type: RoomEventType.reaction,
            content: {'emoji': '❤️'},
            parentId: 'event-1',
            createdAt: now + 2,
          ),
        );

        // Non-reaction reply (should not be included)
        await repository.insertMessage(
          RoomEvent(
            id: 'reply-1',
            roomId: 'room-1',
            senderId: 'sender-2',
            type: RoomEventType.text,
            content: {'text': 'Nice message!'},
            parentId: 'event-1',
            createdAt: now + 3,
          ),
        );

        final reactions = await repository.getReactionsForEvent('event-1');

        expect(reactions.length, equals(2));
        expect(reactions.every((r) => r.type == RoomEventType.reaction), isTrue);
        expect(reactions.any((r) => r.content['emoji'] == '👍'), isTrue);
        expect(reactions.any((r) => r.content['emoji'] == '❤️'), isTrue);
      });
    });

    group('watchMessagesForRoom', () {
      test('emits initial messages', () async {
        await createTestRoom('room-1');

        for (var i = 1; i <= 3; i++) {
          await repository.insertMessage(
            RoomEvent(
              id: 'event-$i',
              roomId: 'room-1',
              senderId: 'sender-1',
              type: RoomEventType.text,
              content: {'text': 'Message $i'},
              createdAt: DateTime.now().millisecondsSinceEpoch + i,
            ),
          );
        }

        final stream = repository.watchMessagesForRoom('room-1');
        final messages = await stream.first;

        expect(messages.length, equals(3));
      });

      test('emits updates when messages are inserted', () async {
        await createTestRoom('room-1');

        final stream = repository.watchMessagesForRoom('room-1');

        // Get initial empty state
        var messages = await stream.first;
        expect(messages, isEmpty);

        // Insert a message
        await repository.insertMessage(
          RoomEvent(
            id: 'event-1',
            roomId: 'room-1',
            senderId: 'sender-1',
            type: RoomEventType.text,
            content: {'text': 'New message'},
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );

        // Wait for the stream to emit the update
        messages = await stream.first;
        expect(messages.length, equals(1));
        expect(messages[0].content['text'], equals('New message'));
      });
    });
  });
}
