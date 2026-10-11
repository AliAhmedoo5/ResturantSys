import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/pin_hasher.dart';
import 'pos_database_constants.dart';

/// Embedded SQLite database manager for the Restaurant POS system.
///
/// Ensures WAL mode, relational foreign keys, schema migrations, and idempotent seed records.
class PosDatabase {
  PosDatabase({
    this.factory,
    this.customPath,
  });

  final DatabaseFactory? factory;
  final String? customPath;
  Database? _database;

  Database? get database => _database;

  /// Resolves the default SQLite file path on the host system.
  ///
  /// On Windows, resolves to `%ProgramData%\ResturantPOS\data\pos.db`.
  static String resolveDefaultDatabasePath({
    Map<String, String>? environment,
    bool? isWindows,
  }) {
    final win = isWindows ?? Platform.isWindows;
    if (win) {
      final env = environment ?? Platform.environment;
      final programData = env['ProgramData'] ?? r'C:\ProgramData';
      return '$programData\\${PosDatabaseConstants.defaultProgramDataFolder}\\${PosDatabaseConstants.defaultDataSubFolder}\\${PosDatabaseConstants.databaseFileName}';
    }

    final env = environment ?? Platform.environment;
    final home = env['HOME'] ?? '.';
    return p.join(
      home,
      '.resturant_pos',
      'data',
      PosDatabaseConstants.databaseFileName,
    );
  }

  /// Initializes the SQLite database, executes PRAGMAs, runs migrations, and seeds defaults.
  Future<Database> initialize() async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    final dbPath = customPath ?? resolveDefaultDatabasePath();
    final dbFactory = factory ?? databaseFactoryFfi;

    if (dbPath != inMemoryDatabasePath) {
      final parentDir = Directory(p.dirname(dbPath));
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }
    }

    _database = await dbFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: PosDatabaseConstants.schemaVersion,
        onConfigure: _onConfigure,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );

    await _seedDefaults(_database!);
    return _database!;
  }

  Future<void> _onConfigure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
    await db.execute('PRAGMA journal_mode = WAL;');
    await db.execute('PRAGMA synchronous = NORMAL;');
    await db.execute('PRAGMA busy_timeout = 5000;');
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableDepartments} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableStaff} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        department_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableDepartments}(id),
        pin_hash TEXT NOT NULL UNIQUE,
        role TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableSystemSettings} (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Future schema migrations will go here
  }

  static String _formatTimestamp(DateTime dt) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${twoDigits(dt.month)}-${twoDigits(dt.day)} '
        '${twoDigits(dt.hour)}:${twoDigits(dt.minute)}:${twoDigits(dt.second)}';
  }

  Future<void> _seedDefaults(Database db) async {
    final now = _formatTimestamp(DateTime.now());

    // 1. Seed departments idempotently
    for (final dept in PosDatabaseConstants.defaultDepartments) {
      await db.rawInsert('''
        INSERT OR IGNORE INTO ${PosDatabaseConstants.tableDepartments} (name, created_at)
        VALUES (?, ?);
      ''', [dept, now]);
    }

    // 2. Seed initial staff accounts if no staff exist (Supervisor, Cashier, Kitchen Cook)
    final staffCountResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM ${PosDatabaseConstants.tableStaff};',
    );
    final count = (staffCountResult.isNotEmpty
            ? staffCountResult.first['count'] as int?
            : 0) ??
        0;

    if (count == 0) {
      final deptRows = await db.query(PosDatabaseConstants.tableDepartments);
      final deptMap = {for (final row in deptRows) row['name'] as String: row['id'] as int};

      final staffSeeds = [
        (
          name: PosDatabaseConstants.defaultSupervisorName,
          dept: PosDatabaseConstants.defaultSupervisorDepartment,
          pin: PosDatabaseConstants.defaultSupervisorPin,
          role: 'SUPERVISOR',
        ),
        (
          name: PosDatabaseConstants.defaultCashierName,
          dept: PosDatabaseConstants.defaultCashierDepartment,
          pin: PosDatabaseConstants.defaultCashierPin,
          role: 'CASHIER',
        ),
        (
          name: PosDatabaseConstants.defaultKitchenName,
          dept: PosDatabaseConstants.defaultKitchenDepartment,
          pin: PosDatabaseConstants.defaultKitchenPin,
          role: 'KITCHEN',
        ),
      ];

      for (final seed in staffSeeds) {
        final deptId = deptMap[seed.dept] ?? 1;
        final hashedPin = PinHasher.hashPin(seed.pin);

        await db.rawInsert('''
          INSERT OR IGNORE INTO ${PosDatabaseConstants.tableStaff} 
          (name, department_id, pin_hash, role, is_active, created_at)
          VALUES (?, ?, ?, ?, 1, ?);
        ''', [seed.name, deptId, hashedPin, seed.role, now]);
      }
    }

    // 3. Seed default system settings
    final defaultSettings = {
      'schema_version': '${PosDatabaseConstants.schemaVersion}',
      'app_name': 'ResturantPOS',
      'paper_width': '80mm',
    };

    for (final entry in defaultSettings.entries) {
      await db.rawInsert('''
        INSERT OR IGNORE INTO ${PosDatabaseConstants.tableSystemSettings} (key, value, updated_at)
        VALUES (?, ?, ?);
      ''', [entry.key, entry.value, now]);
    }
  }

  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }
}
