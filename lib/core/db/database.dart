import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

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

  /// Disappearing messages timeout in seconds (null = disabled)
  /// Supported values: null (off), 86400 (24h), 604800 (7d), 7776000 (90d)
  IntColumn get disappearingTimeout => integer().nullable()();

  /// Mute notifications until this timestamp (milliseconds since epoch)
  /// - null = not muted
  /// - 0 = muted forever
  /// - timestamp = muted until that time
  IntColumn get mutedUntil => integer().nullable()();

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

  /// Subscription ID of the sender (room-specific identifier)
  /// Use RoomMembers table to look up the profile ID from this subscription ID
  TextColumn get senderId => text()();

  /// Contact ID of the sender (nullable, for additional context)
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

  /// Whether the message has been deleted/redacted
  BoolColumn get redacted => boolean().withDefault(const Constant(false))();

  /// Timestamp when message was redacted
  IntColumn get redactedAt => integer().nullable()();

  /// Profile ID of who redacted the message (for admin deletions)
  TextColumn get redactedBy => text().nullable()();

  /// Number of retry attempts for failed messages
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// Error message if send failed
  TextColumn get errorMessage => text().nullable()();

  /// Room ID this message was forwarded from (null if not forwarded)
  TextColumn get forwardedFromRoom => text().nullable()();

  /// Event ID this message was forwarded from (null if not forwarded)
  TextColumn get forwardedFromEvent => text().nullable()();

  /// Number of times this message has been forwarded
  IntColumn get forwardCount => integer().withDefault(const Constant(0))();

  /// Whether this message is restricted from being forwarded
  BoolColumn get forwardRestricted =>
      boolean().withDefault(const Constant(false))();

  /// Timestamp when this message should be deleted (for disappearing messages)
  /// Null means the message does not expire
  IntColumn get expiresAt => integer().nullable()();

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

  /// Earliest time this job can be retried (for exponential backoff)
  /// Null means job can be processed immediately
  IntColumn get nextRetryAt => integer().nullable()();
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

/// User settings persistence table
///
/// Stores all user preferences as key-value pairs with timestamps.
/// Settings are loaded on app startup and cached in memory.
///
/// Example:
/// ```dart
/// final theme = await db.userSettings.select()
///   .where((s) => s.key.equals('theme_mode'))
///   .getSingleOrNull();
/// ```
class UserSettings extends Table {
  /// Setting key (e.g., 'theme_mode', 'font_size')
  TextColumn get key => text()();

  /// Setting value (stored as string, can be JSON for complex values)
  TextColumn get value => text()();

  /// Last update timestamp (milliseconds since epoch)
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Draft messages persistence table
///
/// Stores unsent message drafts for each room, allowing users to continue
/// composing messages after navigating away or restarting the app.
///
/// Example:
/// ```dart
/// final draft = await db.drafts.select()
///   .where((d) => d.roomId.equals(roomId))
///   .getSingleOrNull();
/// if (draft != null) {
///   textController.text = draft.content;
/// }
/// ```
class Drafts extends Table {
  /// Room ID this draft belongs to (primary key)
  TextColumn get roomId => text()();

  /// Draft message content
  TextColumn get content => text()();

  /// Optional parent message ID for reply drafts
  TextColumn get replyToId => text().nullable()();

  /// Last update timestamp (milliseconds since epoch)
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {roomId};
}

/// Read receipts for tracking who has read messages in group chats
///
/// Stores individual read events for messages, allowing the UI to
/// display "seen by X, Y, and Z" in groups with timestamps.
///
/// Example:
/// ```dart
/// final readers = await (db.readReceipts.select()
///   ..where((r) => r.eventId.equals(messageId))
///   ..orderBy([(r) => OrderingTerm.desc(r.readAt)])
/// ).get();
/// ```
class ReadReceipts extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Event/message ID that was read
  TextColumn get eventId => text()();

  /// Room ID for efficient querying
  TextColumn get roomId => text()();

  /// Profile ID of the reader
  TextColumn get profileId => text()();

  /// Timestamp when the message was read (milliseconds since epoch)
  IntColumn get readAt => integer()();
}

/// User reports for abuse/spam/harassment
///
/// Stores reports submitted by users about other users.
/// Reports are sent to the backend for review and action.
///
/// Example:
/// ```dart
/// final reports = await db.reports.select().get();
/// ```
class Reports extends Table {
  /// Unique report identifier
  TextColumn get id => text()();

  /// Profile ID of the user being reported
  TextColumn get reportedUserId => text()();

  /// Report reason category (spam, harassment, inappropriate_content, other)
  TextColumn get reason => text()();

  /// Additional details provided by the reporter
  TextColumn get details => text().nullable()();

  /// JSON array of event IDs used as evidence
  TextColumn get evidenceEventIds => text().nullable()();

  /// Timestamp when the report was created (milliseconds since epoch)
  IntColumn get reportedAt => integer()();

  /// Report status: pending, reviewed, resolved, dismissed
  TextColumn get status => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Invite links for group room joining
///
/// Stores shareable invite links that allow users to join rooms
/// via a unique code. Links can have expiration times, max uses,
/// and can be revoked by admins.
///
/// Example:
/// ```dart
/// final link = await db.inviteLinks.select()
///   .where((l) => l.code.equals('abc123'))
///   .getSingleOrNull();
/// if (link != null && !link.revoked) {
///   // Process invite
/// }
/// ```
class InviteLinks extends Table {
  /// Unique invite link identifier
  TextColumn get id => text()();

  /// Room this invite links to (foreign key)
  TextColumn get roomId => text().references(Rooms, #id)();

  /// Unique invite code for URL (e.g., chat.app/join/{code})
  TextColumn get code => text().unique()();

  /// Profile ID of the user who created this link
  TextColumn get createdBy => text()();

  /// Creation timestamp (milliseconds since epoch)
  IntColumn get createdAt => integer()();

  /// Optional expiration timestamp (milliseconds since epoch, null = never expires)
  IntColumn get expiresAt => integer().nullable()();

  /// Optional maximum number of uses (null = unlimited)
  IntColumn get maxUses => integer().nullable()();

  /// Current number of times this link has been used
  IntColumn get useCount => integer().withDefault(const Constant(0))();

  /// Whether this link has been revoked by an admin
  BoolColumn get revoked => boolean().withDefault(const Constant(false))();

  /// Whether joining via this link requires admin approval
  BoolColumn get requiresApproval =>
      boolean().withDefault(const Constant(false))();

  /// Optional custom name/label for the link
  TextColumn get name => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Tracks users who joined via invite links
///
/// Records each use of an invite link for analytics and
/// "see who joined" functionality.
///
/// Example:
/// ```dart
/// final joins = await (db.inviteLinkJoins.select()
///   ..where((j) => j.inviteLinkId.equals(linkId))
/// ).get();
/// ```
class InviteLinkJoins extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// The invite link that was used
  TextColumn get inviteLinkId => text().references(InviteLinks, #id)();

  /// Profile ID of the user who joined
  TextColumn get profileId => text()();

  /// Timestamp when the user joined (milliseconds since epoch)
  IntColumn get joinedAt => integer()();

  /// Approval status: 'approved', 'pending', 'rejected'
  TextColumn get status => text().withDefault(const Constant('approved'))();
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
    UserSettings,
    Drafts,
    ReadReceipts,
    Reports,
    InviteLinks,
    InviteLinkJoins,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._() : super(_openConnection());

  /// Constructor for testing with custom executor (e.g., in-memory database)
  @visibleForTesting
  AppDatabase.forTesting(super.executor);

  static final AppDatabase instance = AppDatabase._();

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // Create FTS5 virtual table for message search on new databases
      // Uses IF NOT EXISTS for idempotency
      await _createFtsTable();
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
      if (from <= 3) {
        // Migration from v3 to v4: Add message deletion columns
        await m.addColumn(roomEvents, roomEvents.redacted);
        await m.addColumn(roomEvents, roomEvents.redactedAt);
        await m.addColumn(roomEvents, roomEvents.redactedBy);
      }
      if (from <= 4) {
        // Migration from v4 to v5: Add FTS5 for full-text message search
        await _createFtsTable();
        // Populate FTS index with existing text messages
        await _populateFtsFromExistingMessages();
      }
      if (from <= 5) {
        // Migration from v5 to v6: Add user settings table
        await m.createTable(userSettings);
      }
      if (from <= 6) {
        // Migration from v6 to v7: Add retry tracking columns for messages
        await m.addColumn(roomEvents, roomEvents.retryCount);
        await m.addColumn(roomEvents, roomEvents.errorMessage);
        // Migration from v6 to v7: Add drafts table for message draft persistence
        await m.createTable(drafts);
      }
      if (from <= 7) {
        // Migration from v7 to v8: Add read receipts table
        await m.createTable(readReceipts);
        // Create index for efficient querying by eventId
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_read_receipts_event_id
          ON read_receipts(event_id)
        ''');
        // Create unique constraint to prevent duplicate receipts
        await customStatement('''
          CREATE UNIQUE INDEX IF NOT EXISTS idx_read_receipts_unique
          ON read_receipts(event_id, profile_id)
        ''');
      }
      if (from <= 8) {
        // Migration from v8 to v9: Add message forwarding columns
        await m.addColumn(roomEvents, roomEvents.forwardedFromRoom);
        await m.addColumn(roomEvents, roomEvents.forwardedFromEvent);
        await m.addColumn(roomEvents, roomEvents.forwardCount);
        await m.addColumn(roomEvents, roomEvents.forwardRestricted);
        // Migration from v8 to v9: Add reports table for user reports
        await m.createTable(reports);
        // Create index for efficient querying by reported user
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_reports_reported_user_id
          ON reports(reported_user_id)
        ''');
        // Migration from v8 to v9: Add invite links tables
        await m.createTable(inviteLinks);
        await m.createTable(inviteLinkJoins);
        // Create index for efficient querying by room
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_invite_links_room_id
          ON invite_links(room_id)
        ''');
        // Create index for efficient querying by code
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_invite_links_code
          ON invite_links(code)
        ''');
        // Create index for efficient querying joins by link
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_invite_link_joins_link_id
          ON invite_link_joins(invite_link_id)
        ''');
        // Add disappearing messages support
        await m.addColumn(rooms, rooms.disappearingTimeout);
        await m.addColumn(roomEvents, roomEvents.expiresAt);
        // Create index for efficient expiry checking
        await customStatement('''
          CREATE INDEX IF NOT EXISTS idx_room_events_expires_at
          ON room_events(expires_at)
          WHERE expires_at IS NOT NULL
        ''');
      }
      if (from <= 9) {
        // Migration from v9 to v10: Add mute notifications support
        await m.addColumn(rooms, rooms.mutedUntil);
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

  /// Create the FTS5 virtual table for full-text message search
  Future<void> _createFtsTable() async {
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS room_events_fts USING fts5(
        event_id,
        room_id,
        content,
        tokenize='porter unicode61'
      )
    ''');

    // Create triggers to keep FTS index in sync with room_events table

    // Trigger for new text messages
    await customStatement(r'''
      CREATE TRIGGER IF NOT EXISTS room_events_ai AFTER INSERT ON room_events
      WHEN new.type = 0 AND new.content IS NOT NULL
      BEGIN
        INSERT INTO room_events_fts(event_id, room_id, content)
        VALUES (new.id, new.room_id, json_extract(new.content, '$.text'));
      END
    ''');

    // Trigger for updated messages (editing)
    await customStatement(r'''
      CREATE TRIGGER IF NOT EXISTS room_events_au AFTER UPDATE ON room_events
      WHEN new.type = 0 AND new.content IS NOT NULL
      BEGIN
        DELETE FROM room_events_fts WHERE event_id = old.id;
        INSERT INTO room_events_fts(event_id, room_id, content)
        VALUES (new.id, new.room_id, json_extract(new.content, '$.text'));
      END
    ''');

    // Trigger for deleted messages
    await customStatement('''
      CREATE TRIGGER IF NOT EXISTS room_events_ad AFTER DELETE ON room_events
      BEGIN
        DELETE FROM room_events_fts WHERE event_id = old.id;
      END
    ''');
  }

  /// Populate FTS index from existing text messages
  Future<void> _populateFtsFromExistingMessages() async {
    await customStatement(r'''
      INSERT INTO room_events_fts(event_id, room_id, content)
      SELECT id, room_id, json_extract(content, '$.text')
      FROM room_events
      WHERE type = 0 AND content IS NOT NULL
        AND json_extract(content, '$.text') IS NOT NULL
    ''');
  }

  // ============================================================================
  // Full-Text Search Methods
  // ============================================================================

  /// Map a QueryRow to a RoomEvent
  ///
  /// Helper method to reduce duplication in search methods.
  RoomEvent _mapQueryRowToRoomEvent(QueryRow row) => RoomEvent(
    id: row.read<String>('id'),
    roomId: row.read<String>('room_id'),
    senderId: row.read<String>('sender_id'),
    senderContactId: row.readNullable<String>('sender_contact_id'),
    type: row.read<int>('type'),
    content: row.readNullable<String>('content'),
    parentId: row.readNullable<String>('parent_id'),
    status: row.read<int>('status'),
    createdAt: row.readNullable<int>('created_at'),
    serverTs: row.readNullable<int>('server_ts'),
    localId: row.readNullable<String>('local_id'),
    editedAt: row.readNullable<int>('edited_at'),
    originalContent: row.readNullable<String>('original_content'),
    redacted: row.read<bool>('redacted'),
    redactedAt: row.readNullable<int>('redacted_at'),
    redactedBy: row.readNullable<String>('redacted_by'),
    retryCount: row.readNullable<int>('retry_count') ?? 0,
    errorMessage: row.readNullable<String>('error_message'),
    forwardedFromRoom: row.readNullable<String>('forwarded_from_room'),
    forwardedFromEvent: row.readNullable<String>('forwarded_from_event'),
    forwardCount: row.readNullable<int>('forward_count') ?? 0,
    forwardRestricted: row.readNullable<bool>('forward_restricted') ?? false,
  );

  /// Search messages by text content across all rooms
  ///
  /// Returns messages matching the search query, ordered by relevance.
  ///
  /// Parameters:
  /// - [query]: The search query (supports FTS5 syntax)
  /// - [limit]: Maximum number of results (default 50)
  ///
  /// Example:
  /// ```dart
  /// final results = await db.searchMessages('hello world', limit: 20);
  /// ```
  Future<List<RoomEvent>> searchMessages(String query, {int limit = 50}) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final results = await customSelect(
      '''
      SELECT re.*
      FROM room_events re
      INNER JOIN room_events_fts fts ON re.id = fts.event_id
      WHERE room_events_fts MATCH ?
      ORDER BY rank
      LIMIT ?
      ''',
      variables: [Variable.withString(query), Variable.withInt(limit)],
      readsFrom: {roomEvents},
    ).get();

    return results.map(_mapQueryRowToRoomEvent).toList();
  }

  /// Search messages within a specific room
  ///
  /// Returns messages matching the search query in the specified room.
  ///
  /// Parameters:
  /// - [roomId]: The room to search in
  /// - [query]: The search query (supports FTS5 syntax)
  /// - [limit]: Maximum number of results (default 50)
  Future<List<RoomEvent>> searchMessagesInRoom(
    String roomId,
    String query, {
    int limit = 50,
  }) async {
    if (query.trim().isEmpty) {
      return [];
    }

    final results = await customSelect(
      '''
      SELECT re.*
      FROM room_events re
      INNER JOIN room_events_fts fts ON re.id = fts.event_id
      WHERE fts.room_id = ? AND room_events_fts MATCH ?
      ORDER BY rank
      LIMIT ?
      ''',
      variables: [
        Variable.withString(roomId),
        Variable.withString(query),
        Variable.withInt(limit),
      ],
      readsFrom: {roomEvents},
    ).get();

    return results.map(_mapQueryRowToRoomEvent).toList();
  }

  /// Rebuild the FTS index from scratch
  ///
  /// Use this if the index becomes corrupted or out of sync.
  Future<void> rebuildFtsIndex() async {
    await customStatement('DELETE FROM room_events_fts');
    await _populateFtsFromExistingMessages();
  }

  static QueryExecutor _openConnection() => driftDatabase(name: 'chat_v1.db');
}
