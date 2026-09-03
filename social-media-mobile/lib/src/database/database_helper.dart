import 'dart:convert';
import 'dart:math';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// SQLite Database Helper - ONLY manages schema creation
/// 
/// RULE: This layer is NEVER read from during app runtime.
/// SQLite is WRITE-ONLY during app operation.
/// On app startup: Load from SQLite → populate in-memory cache.
/// During runtime: Write-behind only (after realtime logic completes).
class DatabaseHelper {
  static const String dbName = 'social_chat.db';
  static const int dbVersion = 3;

  static final DatabaseHelper _instance = DatabaseHelper._internal();

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  static Database? _database;

  // Spec requirement: local chat DB encryption (SQLCipher). The passphrase
  // is generated once per install and kept in the platform Keystore/
  // Keychain — never written to disk in plaintext, same pattern as
  // ApiService's access-token storage. A separate FlutterSecureStorage
  // instance here (rather than reaching into ApiService's private field) is
  // intentional and harmless: multiple instances just talk to the same
  // underlying platform keystore via their key names, there's no shared
  // state to duplicate.
  static const FlutterSecureStorage _keyStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const String _encryptionKeyStorageKey = 'chat_db_encryption_key';

  Future<String> _getOrCreateEncryptionKey() async {
    final existing = await _keyStorage.read(key: _encryptionKeyStorageKey);
    if (existing != null && existing.isNotEmpty) return existing;

    // First run on this install (or upgrading from a pre-encryption
    // version, where no key has ever been generated) — mint a fresh
    // cryptographically random passphrase.
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64UrlEncode(bytes);
    await _keyStorage.write(key: _encryptionKeyStorageKey, value: key);
    print('[DB] 🔑 Generated new chat database encryption key');
    return key;
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final databasePath = await getDatabasesPath();
    final path = join(databasePath, dbName);
    final key = await _getOrCreateEncryptionKey();

    // Check if database exists and has correct schema
    if (await databaseExists(path)) {
      try {
        final db = await openDatabase(path, password: key);

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
        // Two distinct causes land here, both handled identically and
        // safely: (1) genuine schema corruption (the pre-existing case this
        // catch already handled), or (2) — new with SQLCipher — a database
        // file from BEFORE this encryption migration, which is plaintext;
        // SQLCipher correctly refuses to open a plaintext file with a key
        // ("file is not a database"), it does not silently succeed. Both
        // are safe to recover from the same way because this database is
        // an explicitly write-behind CACHE, never the source of truth (see
        // this class's own top-of-file doc comment) — a message "lost"
        // here simply re-syncs from the backend on the next connect
        // (Phase 4's cursor-based /sync), nothing is permanently lost.
        print('[DB] ⚠️ Could not open as encrypted database ($e), recreating...');
        try {
          await deleteDatabase(path);
        } catch (_) {}
      }
    }

    return await openDatabase(
      path,
      password: key,
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
        read_at INTEGER,
        media_url TEXT,
        media_type TEXT,
        media_name TEXT,
        reply_to_message_id INTEGER,
        is_edited INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        sync_status TEXT NOT NULL DEFAULT 'SYNCED',
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
        conversation_type TEXT NOT NULL DEFAULT 'DIRECT',
        updated_at INTEGER,
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

    await _createDraftsAndSyncStateTables(db);

    // Create indexes for faster queries
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_chat_id ON messages(chat_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_client_id ON messages(client_message_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_conversations_other_user ON conversations(other_user_id)');

    print('[DB] ✅ Database schema created successfully');
  }

  Future<void> _createDraftsAndSyncStateTables(Database db) async {
    // Drafts: one unsent draft per conversation, overwritten as the user types.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS drafts (
        conversation_id INTEGER PRIMARY KEY,
        content TEXT NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    print('[DB] ✅ drafts table created');

    // Sync state: server-controlled cursor per conversation, so reconnect
    // only fetches what changed instead of redownloading full history
    // (wired up by the Phase 4 sync manager — this phase just creates the
    // table it will use).
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state (
        conversation_id INTEGER PRIMARY KEY,
        last_sync_cursor TEXT,
        last_sync_timestamp INTEGER
      )
    ''');
    print('[DB] ✅ sync_state table created');
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

    if (oldVersion < 3) {
      // messages.read_at existed in the Dart model/code for a while (see
      // git history around "readAt") but was never actually added here —
      // every read-status write against a real (pre-v3) on-device database
      // was silently failing with "no such column: read_at" (caught and
      // logged, never surfaced). This is the fix.
      await _addColumnIfMissing(db, 'messages', 'read_at', 'INTEGER');
      await _addColumnIfMissing(db, 'messages', 'media_url', 'TEXT');
      await _addColumnIfMissing(db, 'messages', 'media_type', 'TEXT');
      await _addColumnIfMissing(db, 'messages', 'media_name', 'TEXT');
      await _addColumnIfMissing(db, 'messages', 'reply_to_message_id', 'INTEGER');
      await _addColumnIfMissing(db, 'messages', 'is_edited', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'messages', 'is_deleted', 'INTEGER NOT NULL DEFAULT 0');
      await _addColumnIfMissing(db, 'messages', 'sync_status', "TEXT NOT NULL DEFAULT 'SYNCED'");

      await _addColumnIfMissing(db, 'conversations', 'conversation_type', "TEXT NOT NULL DEFAULT 'DIRECT'");
      await _addColumnIfMissing(db, 'conversations', 'updated_at', 'INTEGER');

      await _createDraftsAndSyncStateTables(db);
      print('[DB] ✅ Phase 2 schema extension applied (upgrade v3)');
    }
  }

  /// SQLite only supports adding one column per ALTER TABLE statement, and
  /// throws if the column already exists — this makes each addition
  /// idempotent so a partially-applied upgrade (e.g. app killed mid-migration)
  /// can safely re-run.
  Future<void> _addColumnIfMissing(
    Database db,
    String table,
    String column,
    String definition,
  ) async {
    final info = await db.rawQuery('PRAGMA table_info($table)');
    final exists = info.any((col) => col['name'] == column);
    if (exists) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    print('[DB] ✅ Added column $table.$column');
  }

  /// Close database connection
  Future<void> close() async {
    final db = _database;
    if (db != null) {
      await db.close();
      _database = null;
    }
  }

  /// Clear all locally-cached chat data. Called on logout (see
  /// ApiService.logout()) so a previous account's messages never remain
  /// readable to whoever logs into the same device next — this was
  /// previously NOT happening (only the separate SharedPreferences-based
  /// cache was cleared on logout, not this SQLite database).
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('messages');
    await db.delete('conversations');
    await db.delete('drafts');
    await db.delete('sync_state');
    print('[DB] ⚠️ All data cleared');
  }
}
