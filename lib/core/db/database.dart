import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:meta/meta.dart';

part 'database.g.dart';

// Table definitions

/// User profile information stored locally
///
/// Contains basic profile data synced from the server including
/// display name, avatar, and metadata.
///
/// Example:
/// ```dart
/// final profile = await db.profiles.select().getSingle();
/// print(profile.name);
/// ```
class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().nullable()();
  TextColumn get avatarUrl => text().nullable()();
  IntColumn get updatedAt => integer().nullable()();
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
  TextColumn get id => text()(); // Stable local UUID
  TextColumn get rosterId =>
      text().nullable()(); // Server roster entry ID (synced)
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

/// Chat room table storing room metadata and state
///
/// Rooms can be direct messages (1:1) or group chats.
/// Tracks last event for sync and unread message counts.
///
/// Example:
/// ```dart
/// final rooms = await db.rooms.select().get();
/// for (final room in rooms) {
///   print('${room.name}: ${room.unreadCount} unread');
/// }
/// ```
class Rooms extends Table {
  /// Unique room identifier from server
  TextColumn get id => text()();

  /// Display name for the room (null for direct messages)
  TextColumn get name => text().nullable()();

  /// Room type: 'direct', 'group', or 'channel'
  TextColumn get type => text().nullable()();

  /// ID of the last event received in this room
  TextColumn get lastEventId => text().nullable()();

  /// Index of the last event for ordering
  IntColumn get lastEventIndex => integer().nullable()();

  /// Count of unread messages in this room
  IntColumn get unreadCount => integer().withDefault(const Constant(0))();

  /// JSON-encoded room metadata (avatar, description, etc.)
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

/// Messages and events within chat rooms
///
/// Stores all types of room events including text messages, media,
/// reactions, calls, and system events. Events are ordered by server
/// timestamp for consistent ordering across devices.
///
/// Example:
/// ```dart
/// final messages = await (db.roomEvents.select()
///   ..where((e) => e.roomId.equals(roomId))
///   ..orderBy([(e) => OrderingTerm.desc(e.serverTs)])
/// ).get();
/// ```
class RoomEvents extends Table {
  /// Unique event identifier (server-assigned or local UUID)
  TextColumn get id => text()();

  /// Room this event belongs to (foreign key)
  TextColumn get roomId => text().references(Rooms, #id)();

  /// Profile ID of the sender from ContactLink
  TextColumn get senderId => text()();

  /// Contact ID of the sender from ContactLink (nullable)
  TextColumn get senderContactId => text().nullable()();

  /// Event type as integer (text=0, image=1, video=2, etc.)
  IntColumn get type => integer()();

  /// JSON-encoded event content (message text, attachment info, etc.)
  TextColumn get content => text().nullable()();

  /// Parent event ID for replies/threads
  TextColumn get parentId => text().nullable()();

  /// Event status (pending=0, sent=1, delivered=2, read=3, failed=4)
  IntColumn get status => integer().withDefault(const Constant(0))();

  /// Client-side creation timestamp
  IntColumn get createdAt => integer().nullable()();

  /// Server-assigned timestamp for consistent ordering
  IntColumn get serverTs => integer().nullable()();

  /// Temporary local ID before server confirmation
  TextColumn get localId => text().nullable()();

  /// Timestamp when message was last edited (null if never edited)
  IntColumn get editedAt => integer().nullable()();

  /// Original message content before editing (preserved for history)
  TextColumn get originalContent => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// End-to-end encryption sessions for secure messaging
///
/// Stores Olm/Megolm session state for encrypted communication.
/// Each session represents a cryptographic channel with a specific
/// user device pair.
///
/// Example:
/// ```dart
/// final session = await db.sessions.select()
///   .where((s) => s.profileId.equals(userId))
///   .getSingleOrNull();
/// ```
class Sessions extends Table {
  /// Unique session identifier
  TextColumn get sessionId => text()();

  /// Profile ID of the session peer
  TextColumn get profileId => text()();

  /// Device ID of the session peer
  TextColumn get deviceId => text()();

  /// Serialized ratchet state for session continuity
  BlobColumn get ratchetState => blob().nullable()();

  /// Session creation timestamp
  IntColumn get createdAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {sessionId};
}

/// Pre-keys for establishing encrypted sessions
///
/// Stores asymmetric key pairs used in the Double Ratchet algorithm
/// for initiating new encrypted sessions with other users.
///
/// Example:
/// ```dart
/// final prekeys = await db.prekeys.select().get();
/// final signedKey = prekeys.firstWhere((k) => k.isSigned);
/// ```
class Prekeys extends Table {
  /// Auto-incrementing prekey identifier
  IntColumn get id => integer().autoIncrement()();

  /// Base64-encoded public key for sharing
  TextColumn get publicKey => text().nullable()();

  /// Base64-encoded private key (securely stored)
  TextColumn get privateKey => text().nullable()();

  /// Whether this is a signed prekey (identity verification)
  BoolColumn get isSigned => boolean().withDefault(const Constant(false))();
}

/// Queue of pending operations for offline-first support
///
/// Stores operations that need to be synced with the server,
/// including message sends, reads, and other actions performed
/// while offline.
///
/// Example:
/// ```dart
/// final pendingCount = await db.pendingJobs.count()
///   .where((j) => j.status.equals('pending'))
///   .getSingle();
/// ```
class PendingJobs extends Table {
  /// Auto-incrementing job identifier
  IntColumn get id => integer().autoIncrement()();

  /// Job type identifier (e.g., 'send_message', 'mark_read')
  TextColumn get type => text()();

  /// JSON-encoded job payload with operation details
  TextColumn get payload => text().nullable()();

  /// Job creation timestamp
  IntColumn get createdAt => integer().nullable()();

  /// Number of retry attempts made
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// Job status: 'pending', 'processing', 'completed', 'failed'
  TextColumn get status => text().withDefault(const Constant('pending'))();
}

/// Financial transactions within group savings (chama) rooms
///
/// Tracks monetary transactions including contributions, withdrawals,
/// and payments within credit and savings groups.
///
/// Example:
/// ```dart
/// final transactions = await (db.transactions.select()
///   ..where((t) => t.roomId.equals(roomId))
/// ).get();
/// final total = transactions.fold(0.0, (sum, t) => sum + double.parse(t.amount ?? '0'));
/// ```
class Transactions extends Table {
  /// Unique transaction identifier
  TextColumn get id => text()();

  /// Room this transaction belongs to (foreign key)
  TextColumn get roomId => text().references(Rooms, #id)();

  /// Transaction amount as decimal string
  TextColumn get amount => text().nullable()();

  /// Currency code (e.g., 'KES', 'USD')
  TextColumn get currency => text().nullable()();

  /// Transaction status: 'pending', 'completed', 'cancelled'
  TextColumn get status => text().nullable()();

  /// Profile ID of the transaction initiator
  TextColumn get initiatorId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Key-value store for sync state and metadata
///
/// Tracks synchronization state including last sync timestamps,
/// cursor positions, and other sync-related metadata.
///
/// Example:
/// ```dart
/// final lastSync = await db.syncMetadata.select()
///   .where((m) => m.key.equals('last_sync_timestamp'))
///   .getSingleOrNull();
/// ```
class SyncMetadata extends Table {
  /// Unique key identifier
  TextColumn get key => text()();

  /// Stored value (can be JSON for complex data)
  TextColumn get value => text().nullable()();

  /// Last update timestamp
  IntColumn get updatedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Main application database using Drift (SQLite)
///
/// Provides type-safe access to all local data including profiles,
/// rooms, messages, contacts, and sync state. Uses a singleton pattern
/// for consistent database access across the app.
///
/// Example:
/// ```dart
/// final db = AppDatabase.instance;
/// final rooms = await db.rooms.select().get();
/// ```
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

  /// Constructor for testing with custom executor (e.g., in-memory database)
  @visibleForTesting
  AppDatabase.forTesting(QueryExecutor executor) : super(executor);

  static final AppDatabase instance = AppDatabase._();

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from <= 1) {
          // Migration from v1 to v2: Add rosterId column and convert existing IDs to stable local UUIDs
          // For now, we'll handle this in beforeOpen instead
        }
        if (from <= 2) {
          // Migration from v2 to v3: Add message editing columns
          await m.addColumn(roomEvents, roomEvents.editedAt);
          await m.addColumn(roomEvents, roomEvents.originalContent);
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
