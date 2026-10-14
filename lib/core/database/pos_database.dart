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

    await _createOperationalAccountingTables(db);
    await _createCatalogAndRecipeTables(db);
    await _createOrderItemsAndDealsTables(db);
    await _createOrderVoidsTables(db);
    await _createProcurementAndWastageTables(db);
    await _createVendorKhataTables(db);
  }

  Future<void> _createOperationalAccountingTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableBusinessDays} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        opened_by_staff_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        closed_by_staff_id INTEGER REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        status TEXT NOT NULL
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableShifts} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_day_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableBusinessDays}(id),
        staff_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        opened_at TEXT NOT NULL,
        closed_at TEXT,
        opening_float REAL NOT NULL,
        counted_cash REAL,
        expected_cash REAL,
        discrepancy REAL,
        discrepancy_status TEXT NOT NULL DEFAULT 'CLEAN',
        status TEXT NOT NULL,
        resolved_by_staff_id INTEGER REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        resolution_notes TEXT,
        resolved_at TEXT
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableCashMovements} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableShifts}(id),
        staff_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        notes TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableOrders} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_day_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableBusinessDays}(id),
        shift_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableShifts}(id),
        cashier_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        token_number INTEGER NOT NULL,
        dining_type TEXT NOT NULL,
        subtotal REAL NOT NULL,
        discount_amount REAL NOT NULL DEFAULT 0.0,
        discount_id INTEGER,
        tax_amount REAL NOT NULL DEFAULT 0.0,
        grand_total REAL NOT NULL,
        payment_status TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableOrderPayments} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableOrders}(id),
        payment_method TEXT NOT NULL,
        amount_tendered REAL NOT NULL,
        change_returned REAL NOT NULL DEFAULT 0.0,
        reference_code TEXT
      );
    ''');
  }

  Future<void> _createCatalogAndRecipeTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableCategories} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        display_order INTEGER NOT NULL DEFAULT 0,
        color_hex TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableMenuItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableCategories}(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        base_price REAL NOT NULL,
        tax_rate REAL NOT NULL DEFAULT 0.0,
        is_tax_inclusive INTEGER NOT NULL DEFAULT 1,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableRawIngredients} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        storage_unit TEXT NOT NULL,
        current_stock REAL NOT NULL DEFAULT 0.0,
        low_stock_threshold REAL NOT NULL DEFAULT 0.0,
        cost_per_recipe_unit REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableRecipes} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        menu_item_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableMenuItems}(id) ON DELETE CASCADE,
        raw_ingredient_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableRawIngredients}(id) ON DELETE RESTRICT,
        quantity_per_recipe_unit REAL NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(menu_item_id, raw_ingredient_id)
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableModifiers} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        menu_item_id INTEGER REFERENCES ${PosDatabaseConstants.tableMenuItems}(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        price_delta REAL NOT NULL DEFAULT 0.0,
        raw_ingredient_id INTEGER REFERENCES ${PosDatabaseConstants.tableRawIngredients}(id) ON DELETE SET NULL,
        ingredient_qty_delta REAL NOT NULL DEFAULT 0.0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableDiscountPresets} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        value REAL NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      );
    ''');
  }

  Future<void> _createOrderItemsAndDealsTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableDeals} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        base_price REAL NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableDealItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deal_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableDeals}(id) ON DELETE CASCADE,
        group_name TEXT NOT NULL,
        category_id INTEGER REFERENCES ${PosDatabaseConstants.tableCategories}(id) ON DELETE SET NULL,
        default_menu_item_id INTEGER REFERENCES ${PosDatabaseConstants.tableMenuItems}(id) ON DELETE SET NULL,
        is_upgradeable INTEGER NOT NULL DEFAULT 0,
        upgrade_price REAL NOT NULL DEFAULT 0.0
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableDealItemOptions} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deal_item_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableDealItems}(id) ON DELETE CASCADE,
        menu_item_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableMenuItems}(id) ON DELETE CASCADE,
        is_default INTEGER NOT NULL DEFAULT 0,
        upgrade_price REAL NOT NULL DEFAULT 0.0
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableOrderItems} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableOrders}(id) ON DELETE CASCADE,
        menu_item_id INTEGER REFERENCES ${PosDatabaseConstants.tableMenuItems}(id) ON DELETE SET NULL,
        deal_id INTEGER REFERENCES ${PosDatabaseConstants.tableDeals}(id) ON DELETE SET NULL,
        name TEXT NOT NULL,
        quantity INTEGER NOT NULL DEFAULT 1,
        unit_price REAL NOT NULL,
        total_price REAL NOT NULL,
        modifiers_json TEXT,
        deal_choices_json TEXT,
        created_at TEXT NOT NULL
      );
    ''');
  }

  Future<void> _createOrderVoidsTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableOrderVoids} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableOrders}(id),
        voided_by_supervisor_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        cashier_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        reason TEXT NOT NULL,
        voided_at TEXT NOT NULL
      );
    ''');
  }

  Future<void> _createProcurementAndWastageTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableMandiProcurements} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        raw_ingredient_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableRawIngredients}(id) ON DELETE CASCADE,
        traditional_unit TEXT NOT NULL,
        quantity REAL NOT NULL,
        total_cost REAL NOT NULL,
        converted_quantity REAL NOT NULL,
        cost_per_recipe_unit REAL NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableKitchenWastage} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staff_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        raw_ingredient_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableRawIngredients}(id) ON DELETE CASCADE,
        quantity REAL NOT NULL,
        cost_loss REAL NOT NULL,
        reason TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      );
    ''');
  }

  Future<void> _createVendorKhataTables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableVendorKhata} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        phone TEXT NOT NULL,
        supplied_ingredients TEXT,
        opening_balance REAL NOT NULL DEFAULT 0.0,
        current_balance REAL NOT NULL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableVendorTransactions} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        vendor_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableVendorKhata}(id) ON DELETE CASCADE,
        shift_id INTEGER REFERENCES ${PosDatabaseConstants.tableShifts}(id) ON DELETE SET NULL,
        staff_id INTEGER REFERENCES ${PosDatabaseConstants.tableStaff}(id) ON DELETE SET NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        reference_slip TEXT,
        notes TEXT,
        raw_ingredient_id INTEGER REFERENCES ${PosDatabaseConstants.tableRawIngredients}(id) ON DELETE SET NULL,
        quantity REAL,
        created_at TEXT NOT NULL
      );
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createOperationalAccountingTables(db);
    }
    if (oldVersion < 3) {
      await _createCatalogAndRecipeTables(db);
    }
    if (oldVersion < 4) {
      await _createOrderItemsAndDealsTables(db);
    }
    if (oldVersion < 5) {
      await _createOrderVoidsTables(db);
    }
    if (oldVersion < 6) {
      await _createProcurementAndWastageTables(db);
    }
    if (oldVersion < 7) {
      await _createVendorKhataTables(db);
    }
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
      PosDatabaseConstants.settingDiscrepancyThreshold: PosDatabaseConstants.defaultDiscrepancyThreshold,
      PosDatabaseConstants.settingCashierVoidRequestsEnabled: PosDatabaseConstants.defaultCashierVoidRequestsEnabled,
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
