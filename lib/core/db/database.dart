import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// Table definitions
/// Profile table stores user profile information
class Profiles extends Table {
  /// Profile ID
  TextColumn get id => text()();
  
  /// Profile name
  TextColumn get name => text().nullable()();
  
  /// Profile avatar URL
  TextColumn get avatarUrl => text().nullable()();
  
  /// Last updated timestamp
  IntColumn get updatedAt => integer().nullable()();
  
  /// Profile metadata
  TextColumn get metadata => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Roster table stores contact information with stable local IDs and separate server roster IDs.
/// - id: Stable local UUID identifier (never changes)
/// - rosterId: Server roster entry identifier (synced from server, nullable)
/// - profileId: Foreign key to profiles table (nullable - null if user hasn't logged in)
/// - contactId: Contact's unique identifier from server (available after successful sync)
/// - contactDetail: Email/phone number as stored locally for display
class Roster extends Table {
  /// Stable local UUID
  TextColumn get id => text()();
  
  /// Server roster entry ID (synced)
  TextColumn get rosterId =>
      text().nullable()();
  
  /// Null if user hasn't logged in yet
  TextColumn get profileId =>
      text().nullable()();
  
  /// Contact's unique ID from server
  TextColumn get contactId =>
      text().nullable()();
  
  /// Contact type (0=regular, 1=blocked, etc.)
  IntColumn get contactType => integer().withDefault(const Constant(0))();
  
  /// Email/phone number for display
  TextColumn get contactDetail => text()();
  
  /// Whether contact is verified
  BoolColumn get isVerified => boolean().withDefault(const Constant(false))();
  
  /// Display name for contact
  TextColumn get displayName => text().nullable()();
  
  /// Whether contact is blocked
  BoolColumn get isBlocked => boolean().withDefault(const Constant(false))();
  
  /// Last sync timestamp
  IntColumn get syncedAt => integer().nullable()();
  
  /// Creation timestamp
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

/// Room subscriptions table - represents a profile's presence in a room
/// Uses subscription_id from API as primary key (room-specific presence)
///
/// ID Types Clarified:
/// - subscriptionId: Room-specific presence ID (primary key) - UNIQUE per room per profile
/// - profileId: Global profile identity (from JWT 'sub' claim) - SAME across all rooms for user
///           - Can be null initially for anonymous/provisional subscriptions
///           - Can be updated later when user identity is established
/// - contactId: Contact method used (phone, email, etc.) - HOW the profile was reached
/// - roomId: Room identifier - WHICH room the subscription belongs to
class RoomMembers extends Table {
  TextColumn get subscriptionId => text()(); // Primary key from API
  TextColumn get roomId => text().references(Rooms, #id)();
  TextColumn get profileId => text()
      .nullable()(); // Global profile identity (from JWT) - nullable for anonymous subscriptions
  TextColumn get contactId =>
      text().nullable()(); // Contact method (phone/email/etc)
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
  /// Session ID
  TextColumn get sessionId => text()();
  
  /// Profile ID
  TextColumn get profileId => text()();
  
  /// Device ID
  TextColumn get deviceId => text()();
  
  /// Ratchet state blob
  BlobColumn get ratchetState => blob().nullable()();
  
  /// Creation timestamp
  IntColumn get createdAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {sessionId};
}

class Prekeys extends Table {
  /// Prekey ID
  IntColumn get id => integer().autoIncrement()();
  
  /// Public key
  TextColumn get publicKey => text().nullable()();
  
  /// Private key
  TextColumn get privateKey => text().nullable()();
  
  /// Whether key is signed
  BoolColumn get isSigned => boolean().withDefault(const Constant(false))();
}

class PendingJobs extends Table {
  /// Job ID
  IntColumn get id => integer().autoIncrement()();
  
  /// Job type
  TextColumn get type => text()();
  
  /// Job payload
  TextColumn get payload => text().nullable()();
  
  /// Creation timestamp
  IntColumn get createdAt => integer().nullable()();
  
  /// Retry count
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  
  /// Job status
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
      onCreate: (Migrator m) async => m.createAll(),
      onUpgrade: (Migrator m, int from, int to) async {
        if (from <= 1) {
          // Migration from v1 to v2: Add rosterId column and convert existing IDs to stable local UUIDs
          // For now, we'll handle this in beforeOpen instead
        }
      },
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON');

        // Handle data migration after schema changes
        if (details.hadUpgrade) {
          final currentVersion = await customSelect(
            'SELECT user_version FROM pragma_user_version()',
          ).getSingle();
          if (currentVersion.data['user_version'] == 2) {
            // Add rosterId column if it doesn't exist
            await customStatement('''
              ALTER TABLE roster ADD COLUMN rosterId TEXT
            ''');

            // Copy existing IDs to rosterId column (they were server IDs)
            await customStatement('''
              UPDATE roster SET rosterId = id WHERE rosterId IS NULL
            ''');

            // Generate new stable UUIDs for local id column using xid
            await customStatement('''
              UPDATE roster SET id = substr(lower(hex(randomblob(8))), 1, 8) || '-' ||
                                 substr(lower(hex(randomblob(4))), 1, 4) || '-4' ||
                                 substr(lower(hex(randomblob(4))), 1, 4) || '-' ||
                                 substr('89ab', (abs(random()) % 4) + 1, 1) ||
                                 substr(lower(hex(randomblob(4))), 1, 4) || '-' ||
                                 substr(lower(hex(randomblob(12))), 1, 12)
              WHERE id NOT LIKE '%-%-%-%-%'
            ''');
          }
        }
      },
    );
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'chat_v1.db');
  }
}
