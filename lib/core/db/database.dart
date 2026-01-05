import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// Table definitions
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  IntColumn get updatedAt => integer().nullable()();
  TextColumn get metadata => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Roster table mirrors the server roster with contact information.
/// - id: Unique roster entry identifier
/// - profileId: Foreign key to profiles table (nullable - null if user hasn't logged in)
/// - contactId: Contact's unique identifier from server (available after successful sync)
/// - contactDetail: Email/phone number as stored locally for display
class Roster extends Table {
  TextColumn get id => text()();
  TextColumn get profileId =>
      text().nullable()(); // Null if user hasn't logged in yet
  TextColumn get contactId =>
      text().nullable()(); // Contact's unique ID from server
  IntColumn get contactType => integer().withDefault(const Constant(0))();
  TextColumn get contactDetail => text()();
  BoolColumn get isVerified => boolean().withDefault(const Constant(false))();
  TextColumn get displayName => text().nullable()();
  BoolColumn get isBlocked => boolean().withDefault(const Constant(false))();
  IntColumn get syncedAt => integer().nullable()();
  IntColumn get createdAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Rooms extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  TextColumn get type => text().nullable()();
  TextColumn get lastEventId => text().nullable()();
  IntColumn get lastEventIndex => integer().nullable()();
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();
  TextColumn get metadata => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Room subscriptions table - represents a user's subscription to a room
/// Uses subscription_id from API as primary key
class RoomMembers extends Table {
  TextColumn get subscriptionId => text()(); // Primary key from API
  TextColumn get roomId => text().references(Rooms, #id)();
  TextColumn get profileId => text().nullable()(); // From ContactLink, nullable
  TextColumn get contactId => text().nullable()(); // From ContactLink, nullable
  TextColumn get role => text().nullable()();
  IntColumn get joinedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {subscriptionId};
}

class RoomEvents extends Table {
  TextColumn get id => text()();
  TextColumn get roomId => text().references(Rooms, #id)();
  TextColumn get senderId => text()(); // Profile ID from ContactLink
  TextColumn get senderContactId =>
      text().nullable()(); // Contact ID from ContactLink
  IntColumn get type => integer()();
  TextColumn get content => text().nullable()();
  TextColumn get parentId => text().nullable()();
  IntColumn get status => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer().nullable()();
  IntColumn get serverTs => integer().nullable()();
  TextColumn get localId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Sessions extends Table {
  TextColumn get sessionId => text()();
  TextColumn get profileId => text()();
  TextColumn get deviceId => text()();
  BlobColumn get ratchetState => blob().nullable()();
  IntColumn get createdAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {sessionId};
}

class Prekeys extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get publicKey => text().nullable()();
  TextColumn get privateKey => text().nullable()();
  BoolColumn get isSigned => boolean().withDefault(const Constant(false))();
}

class PendingJobs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => text()();
  TextColumn get payload => text().nullable()();
  IntColumn get createdAt => integer().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
}

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get roomId => text().references(Rooms, #id)();
  TextColumn get amount => text().nullable()();
  TextColumn get currency => text().nullable()();
  TextColumn get status => text().nullable()();
  TextColumn get initiatorId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class SyncMetadata extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();
  IntColumn get updatedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Profiles,
    Roster,
    Rooms,
    RoomMembers,
    RoomEvents,
    Sessions,
    Prekeys,
    PendingJobs,
    Transactions,
    SyncMetadata,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._() : super(_openConnection());

  static final AppDatabase instance = AppDatabase._();

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 3) {
          await m.createTable(syncMetadata);
        }
        if (from < 4) {
          // Drop old Contacts table and create new Roster table
          await m.deleteTable('contacts');
          await m.createTable(roster);
        }
        if (from < 6) {
          // Handle profileId nullable change and fix FK constraint
          // First, update any empty profileId values to null
          await customStatement(
            'UPDATE roster SET profile_id = NULL WHERE profile_id = ""',
          );
          // Drop and recreate table with new schema
          await m.deleteTable(roster.actualTableName);
          await m.createTable(roster);
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'chat_v2.db');
  }
}
