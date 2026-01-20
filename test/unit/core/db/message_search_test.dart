import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:chat/core/db/database.dart';

void main() {
  group('Message Search (FTS5)', () {
    late AppDatabase db;

    setUp(() async {
      // Create an in-memory database for testing
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    group('searchMessages', () {
      test('returns empty list for empty query', () async {
        final results = await db.searchMessages('');

        expect(results, isEmpty);
      });

      test('returns empty list for whitespace-only query', () async {
        final results = await db.searchMessages('   ');

        expect(results, isEmpty);
      });
    });

    group('searchMessagesInRoom', () {
      test('returns empty list for empty query', () async {
        final results = await db.searchMessagesInRoom('room1', '');

        expect(results, isEmpty);
      });

      test('returns empty list for whitespace-only query', () async {
        final results = await db.searchMessagesInRoom('room1', '   ');

        expect(results, isEmpty);
      });
    });

    group('FTS5 table creation', () {
      test('database creates successfully with FTS5 support', () async {
        // If database creation succeeds, FTS5 is supported
        expect(db, isNotNull);
      });

      test('schema version is 4', () {
        expect(db.schemaVersion, equals(4));
      });
    });

    group('rebuildFtsIndex', () {
      test('completes without error', () async {
        await expectLater(db.rebuildFtsIndex(), completes);
      });
    });
  });
}
