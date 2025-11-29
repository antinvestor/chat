class AppSchema {
  static const int version = 2;

  static const String createProfilesTable = """
    CREATE TABLE IF NOT EXISTS profiles (
      id TEXT PRIMARY KEY,
      name TEXT,
      avatar_url TEXT,
      updated_at INTEGER,
      metadata TEXT
    );
  """;

  static const String createContactsTable = """
    CREATE TABLE IF NOT EXISTS contacts (
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL,
      display_name TEXT,
      phone_hash TEXT,
      is_blocked INTEGER DEFAULT 0,
      created_at INTEGER,
      FOREIGN KEY (profile_id) REFERENCES profiles (id) ON DELETE CASCADE
    );
  """;

  static const String createRoomsTable = """
    CREATE TABLE IF NOT EXISTS rooms (
      id TEXT PRIMARY KEY,
      name TEXT,
      type TEXT,
      last_event_id TEXT,
      last_event_index INTEGER,
      unread_count INTEGER DEFAULT 0,
      metadata TEXT
    );
  """;

  static const String createRoomMembersTable = """
    CREATE TABLE IF NOT EXISTS room_members (
      room_id TEXT NOT NULL,
      profile_id TEXT NOT NULL,
      role TEXT,
      joined_at INTEGER,
      PRIMARY KEY (room_id, profile_id),
      FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE CASCADE,
      FOREIGN KEY (profile_id) REFERENCES profiles (id) ON DELETE CASCADE
    );
  """;

  static const String createRoomEventsTable = """
    CREATE TABLE IF NOT EXISTS room_events (
      id TEXT PRIMARY KEY,
      room_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      type INTEGER NOT NULL,
      content TEXT,
      parent_id TEXT,
      status INTEGER DEFAULT 0,
      created_at INTEGER,
      server_ts INTEGER,
      local_id TEXT,
      FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE CASCADE,
      FOREIGN KEY (sender_id) REFERENCES profiles (id) ON DELETE CASCADE
    );
  """;

  static const String createSessionsTable = """
    CREATE TABLE IF NOT EXISTS sessions (
      session_id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL,
      device_id TEXT NOT NULL,
      ratchet_state BLOB,
      created_at INTEGER
    );
  """;

  static const String createPrekeysTable = """
    CREATE TABLE IF NOT EXISTS prekeys (
      id INTEGER PRIMARY KEY,
      public_key TEXT,
      private_key TEXT,
      is_signed INTEGER DEFAULT 0
    );
  """;

  static const String createPendingJobsTable = """
    CREATE TABLE IF NOT EXISTS pending_jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      payload TEXT,
      created_at INTEGER,
      retry_count INTEGER DEFAULT 0,
      status TEXT DEFAULT 'pending'
    );
  """;

  static const String createTransactionsTable = """
    CREATE TABLE IF NOT EXISTS transactions (
      id TEXT PRIMARY KEY,
      room_id TEXT NOT NULL,
      amount TEXT,
      currency TEXT,
      status TEXT,
      initiator_id TEXT,
      FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE CASCADE
    );
  """;

  // Indexes
  static const String indexRoomEventsRoomId = "CREATE INDEX IF NOT EXISTS idx_room_events_room_id ON room_events (room_id);";
  static const String indexRoomEventsParentId = "CREATE INDEX IF NOT EXISTS idx_room_events_parent_id ON room_events (parent_id);";
  static const String indexPendingJobsStatus = "CREATE INDEX IF NOT EXISTS idx_pending_jobs_status ON pending_jobs (status);";
  
  // Version 2 indexes
  static const String indexRoomEventsCreatedAt = "CREATE INDEX IF NOT EXISTS idx_room_events_created_at ON room_events (created_at);";
  static const String indexRoomsLastEventIndex = "CREATE INDEX IF NOT EXISTS idx_rooms_last_event_index ON rooms (last_event_index);";
}
