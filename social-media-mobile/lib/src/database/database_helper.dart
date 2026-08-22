import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// SQLite Database Helper - ONLY manages schema creation
/// 
/// RULE: This layer is NEVER read from during app runtime.
/// SQLite is WRITE-ONLY during app operation.
/// On app startup: Load from SQLite → populate in-memory cache.
/// During runtime: Write-behind only (after realtime logic completes).
class DatabaseHelper {
  static const String dbName = 'social_chat.db';
  static const int dbVersion = 2;

  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, dbName);

    // Check if database exists and has correct schema
    if (await databaseExists(path)) {
      try {
        final db = await openDatabase(path);
        
        // Check if messages table has our new columns
        final tables = await db.rawQuery(
          "PRAGMA table_info(messages)"
        );
        
        final hasOldSchema = tables.every((col) => 
          col['name'] != 'chat_id'
        );
        
        await db.close();
        
        // If old schema detected, delete and recreate
        if (hasOldSchema) {
          print('[DB] ⚠️ Old schema detected, recreating database...');
          await deleteDatabase(path);
        }
      } catch (e) {
        print('[DB] ⚠️ Error checking schema: $e, will recreate');
        try {
          await deleteDatabase(path);
        } catch (_) {}
      }
    }

    return await openDatabase(
      path,
      version: dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create tables on first app launch
  Future<void> _onCreate(Database db, int version) async {
    print('[DB] Creating tables for SQLite...');

    // Messages table - stores all chat messages with status
    await db.execute('''
      CREATE TABLE IF NOT EXISTS messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        client_message_id TEXT UNIQUE,
        chat_id INTEGER NOT NULL,
        sender_id INTEGER NOT NULL,
        receiver_id INTEGER NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'SENDING',
        FOREIGN KEY (chat_id) REFERENCES conversations(chat_id)
      )
    ''');
    print('[DB] ✅ messages table created');

    // Conversations table - stores conversation metadata
    await db.execute('''
      CREATE TABLE IF NOT EXISTS conversations (
        chat_id INTEGER PRIMARY KEY,
        other_user_id INTEGER NOT NULL,
        other_user_name TEXT,
        other_user_profile_pic TEXT,
        last_message TEXT,
        last_message_time INTEGER,
        unread_count INTEGER DEFAULT 0,
        UNIQUE(chat_id)
      )
    ''');
    print('[DB] ✅ conversations table created');

    // Call History table - stores call logs
    await db.execute('''
      CREATE TABLE IF NOT EXISTS call_history (
        id INTEGER PRIMARY KEY,
        initiator_id INTEGER NOT NULL,
        receiver_id INTEGER NOT NULL,
        type TEXT NOT NULL,
        status TEXT NOT NULL,
        duration INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    print('[DB] ✅ call_history table created');

    // Create indexes for faster queries
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_client_id ON messages(client_message_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_conversations_other_user ON conversations(other_user_id)');

    print('[DB] ✅ Database schema created successfully');
  }

  /// Handle database upgrades for future schema changes
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print('[DB] Upgrading database from v$oldVersion to v$newVersion');
    
    if (oldVersion < 2) {
      // Create call_history table for existing users
      await db.execute('''
        CREATE TABLE IF NOT EXISTS call_history (
          id INTEGER PRIMARY KEY,
          initiator_id INTEGER NOT NULL,
          receiver_id INTEGER NOT NULL,
          type TEXT NOT NULL,
          status TEXT NOT NULL,
          duration INTEGER NOT NULL,
          created_at INTEGER NOT NULL
        )
      ''');
      print('[DB] ✅ call_history table created (upgrade v2)');
    }
  }

  /// Close database connection
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// Clear all data (for testing/debugging)
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('conversations');
    print('[DB] ⚠️ All data cleared');
  }
}
