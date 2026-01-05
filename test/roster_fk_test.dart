import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNull;
import '../lib/core/db/database.dart';

void main() {
  group('Roster Foreign Key Constraint Tests', () {
    late AppDatabase database;

    setUp(() async {
      // Use existing database instance for testing
      database = AppDatabase.instance;
      // Clean up any existing test data
      await database.delete(database.roster).go();
      await database.delete(database.profiles).go();
    });

    tearDown(() async {
      // Clean up test data
      await database.delete(database.roster).go();
      await database.delete(database.profiles).go();
    });

    test(
      'should insert roster entry with null profileId without FK violation',
      () async {
        // Create a roster entry with null profileId (this was causing the FK constraint error)
        final rosterEntry = RosterCompanion.insert(
          id: 'test-id-1',
          profileId: Value(
            null,
          ), // This should work now with nullable profileId
          contactId: Value(null),
          contactType: const Value(0), // email
          contactDetail: 'test@example.com',
          isVerified: const Value(false),
          displayName: Value('Test Contact'),
          isBlocked: const Value(false),
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        );

        // This should not throw a foreign key constraint violation
        expect(
          () async => await database.into(database.roster).insert(rosterEntry),
          returnsNormally,
        );

        // Verify the entry was inserted
        final query = database.select(database.roster)
          ..where((r) => r.id.equals('test-id-1'));
        final result = await query.getSingle();

        expect(result.id, equals('test-id-1'));
        expect(result.profileId, isNull); // Should be null
        expect(result.contactDetail, equals('test@example.com'));
      },
    );

    test('should insert roster entry with valid profileId', () async {
      // First insert a profile
      final profile = ProfilesCompanion.insert(
        id: 'profile-1',
        name: Value('Test Profile'),
      );
      await database.into(database.profiles).insert(profile);

      // Now insert a roster entry with that profileId
      final rosterEntry = RosterCompanion.insert(
        id: 'test-id-2',
        profileId: Value('profile-1'), // Valid profileId
        contactId: Value('contact-1'),
        contactType: const Value(1), // msisdn
        contactDetail: '+1234567890',
        isVerified: const Value(true),
        displayName: Value('Test Contact 2'),
        isBlocked: const Value(false),
        createdAt: Value(DateTime.now().millisecondsSinceEpoch),
      );

      // This should work fine
      expect(
        () async => await database.into(database.roster).insert(rosterEntry),
        returnsNormally,
      );

      // Verify the entry was inserted
      final query = database.select(database.roster)
        ..where((r) => r.id.equals('test-id-2'));
      final result = await query.getSingle();

      expect(result.id, equals('test-id-2'));
      expect(result.profileId, equals('profile-1'));
      expect(result.contactDetail, equals('+1234567890'));
    });

    test('should handle mixed null and valid profileIds', () async {
      // Insert one profile
      final profile = ProfilesCompanion.insert(
        id: 'profile-3',
        name: Value('Test Profile 3'),
      );
      await database.into(database.profiles).insert(profile);

      // Insert multiple roster entries with mixed profileId states
      final entries = [
        RosterCompanion.insert(
          id: 'test-id-3',
          profileId: Value(null), // Null profileId
          contactType: const Value(0),
          contactDetail: 'null@example.com',
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
        RosterCompanion.insert(
          id: 'test-id-4',
          profileId: Value('profile-3'), // Valid profileId
          contactType: const Value(1),
          contactDetail: '+9876543210',
          createdAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      ];

      // Insert all entries in a batch
      await database.batch((batch) {
        for (final entry in entries) {
          batch.insert(database.roster, entry);
        }
      });

      // Verify all entries were inserted
      final query = database.select(database.roster)
        ..orderBy([(r) => OrderingTerm.asc(r.id)]);
      final results = await query.get();

      expect(results.length, equals(2));
      expect(results[0].profileId, isNull);
      expect(results[1].profileId, equals('profile-3'));
    });
  });
}
