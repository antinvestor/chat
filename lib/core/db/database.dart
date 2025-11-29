import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'schema.dart';

class AppDatabase {
  static final AppDatabase _instance = AppDatabase._internal();
  static AppDatabase get instance => _instance;

  Database? _db;

  AppDatabase._internal();

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    // Ensure sqlite3 is loaded
    await applyWorkaroundToOpenSqlite3OnOldAndroidVersions();

    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(join(dbFolder.path, 'chat_v1.db'));

    final db = sqlite3.open(file.path);

    // Enable foreign keys
    db.execute('PRAGMA foreign_keys = ON;');

    _migrate(db);

    return db;
  }

  void _migrate(Database db) {
    final currentVersion = db.userVersion;

    if (currentVersion < AppSchema.version) {
      db.execute('BEGIN TRANSACTION;');
      try {
        if (currentVersion < 1) {
          db.execute(AppSchema.createProfilesTable);
          db.execute(AppSchema.createContactsTable);
          db.execute(AppSchema.createRoomsTable);
          db.execute(AppSchema.createRoomMembersTable);
          db.execute(AppSchema.createRoomEventsTable);
          db.execute(AppSchema.createSessionsTable);
          db.execute(AppSchema.createPrekeysTable);
          db.execute(AppSchema.createPendingJobsTable);
          db.execute(AppSchema.createTransactionsTable);
          
          // Indexes
          db.execute(AppSchema.indexRoomEventsRoomId);
          db.execute(AppSchema.indexRoomEventsParentId);
          db.execute(AppSchema.indexPendingJobsStatus);
          db.execute(AppSchema.indexRoomEventsCreatedAt);
          db.execute(AppSchema.indexRoomsLastEventIndex);
        }

        if (currentVersion < 2) {
          db.execute(AppSchema.indexRoomEventsCreatedAt);
          db.execute(AppSchema.indexRoomsLastEventIndex);
        }
        
        db.userVersion = AppSchema.version;
        db.execute('COMMIT;');
      } catch (e) {
        db.execute('ROLLBACK;');
        rethrow;
      }
    }
  }

  void close() {
    _db?.dispose();
    _db = null;
  }
}
