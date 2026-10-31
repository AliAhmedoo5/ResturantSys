import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/pin_hasher.dart';
import 'pos_database_constants.dart';
import 'operations_schema.dart';
import 'feature_gaps_schema.dart';
import 'historical_cost_schema.dart';
import 'payment_events_schema.dart';
import 'historical_corrections_schema.dart';
import 'reporting_identity_schema.dart';
import 'menu_allocations_schema.dart';
import 'supplier_receipt_evidence_schema.dart';
import 'backup_attempts_schema.dart';
import 'manager_presets_schema.dart';
import '../delivery/delivery_controller.dart';

/// Embedded SQLite database manager for the Restaurant POS system.
///
/// Ensures WAL mode, relational foreign keys, schema migrations, and idempotent seed records.
class PosDatabase {
  PosDatabase({
    this.factory,
    this.customPath,
    this.seedDefaultStaff = true,
  });

  final DatabaseFactory? factory;
  final String? customPath;
  final bool seedDefaultStaff;
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
    await _createV9Tables(db);
    await _upgradeToVersion10(db);
    await _upgradeToVersion11(db);
    await _upgradeToVersion12(db);
    await _upgradeToVersion14(db);
    await _upgradeToVersion15(db);
    await _upgradeToVersion16(db);
    await _upgradeToVersion17(db);
    await _upgradeToVersion18(db);
    await createOperationsSchema(db);
    await createFeatureGapsSchema(db);
    await createHistoricalCostSchema(db);
    await createPaymentEventsSchema(db);

    await createReportingIdentitySchema(db);
    await createMenuAllocationsSchema(db);
    await createSupplierReceiptEvidenceSchema(db);
    await createBackupAttemptsSchema(db);
    await createHistoricalCorrectionsSchema(db);
    await createManagerPresetsSchema(db);
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
        approved_by INTEGER REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        created_at TEXT NOT NULL
      );
    ''');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_cash_movements_shift_id ON ${PosDatabaseConstants.tableCashMovements}(shift_id);');

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
        token_status TEXT NOT NULL DEFAULT 'PREPARING',
        current_revision INTEGER NOT NULL DEFAULT 1,
        cash_rounding_paisa INTEGER NOT NULL DEFAULT 0,
        delivery_area_id INTEGER REFERENCES ${PosDatabaseConstants.tableDeliveryAreas}(id),
        delivery_area_name_snapshot TEXT,
        delivery_address_snapshot TEXT,
        delivery_fee_paisa INTEGER NOT NULL DEFAULT 0,
        customer_phone TEXT,
        customer_name TEXT,
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
    if (oldVersion < 8) {
      await db.execute("ALTER TABLE ${PosDatabaseConstants.tableOrders} ADD COLUMN token_status TEXT NOT NULL DEFAULT 'PREPARING';");
    }
    if (oldVersion < 9) {
      await _upgradeToVersion9(db);
    }
    if (oldVersion < 10) await _upgradeToVersion10(db);
    if (oldVersion < 11) await _upgradeToVersion11(db);
    if (oldVersion < 12) await _upgradeToVersion12(db);
    if (oldVersion < 13) await _upgradeToVersion13(db);
    if (oldVersion < 14) await _upgradeToVersion14(db);
    if (oldVersion < 15) await _upgradeToVersion15(db);
    if (oldVersion < 16) await _upgradeToVersion16(db);
    if (oldVersion < 17) await _upgradeToVersion17(db);
    if (oldVersion < 18) await _upgradeToVersion18(db);
    if (oldVersion < 19) await createOperationsSchema(db);
    if (oldVersion < 20) await createFeatureGapsSchema(db);
    if (oldVersion < 21) await createHistoricalCostSchema(db);
    if (oldVersion < 22) await createPaymentEventsSchema(db);

    if (oldVersion < 23) await createReportingIdentitySchema(db);
    if (oldVersion < 24) await createMenuAllocationsSchema(db);
    if (oldVersion < 25) await createSupplierReceiptEvidenceSchema(db);
    if (oldVersion < 26) {
      await createBackupAttemptsSchema(db);
      final ingredientColumns = await db.rawQuery('PRAGMA table_info(raw_ingredients)');
      if (ingredientColumns.isNotEmpty && !ingredientColumns.any((c) => c['name'] == 'category')) {
        await db.execute('ALTER TABLE raw_ingredients ADD COLUMN category TEXT');
      }
      final costColumns = await db.rawQuery('PRAGMA table_info(order_cost_events)');
      if (costColumns.isNotEmpty && !costColumns.any((c) => c['name'] == 'classification')) {
        await db.execute('ALTER TABLE order_cost_events ADD COLUMN classification TEXT');
      }
    }
    if (oldVersion < 27) await createHistoricalCorrectionsSchema(db);
    if (oldVersion < 28) await createManagerPresetsSchema(db);
  }

  Future<void> _upgradeToVersion18(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS customers (
      id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL,
      phone TEXT NOT NULL UNIQUE, notes TEXT NOT NULL DEFAULT '',
      merged_into INTEGER REFERENCES customers(id), created_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS customer_merges (
      id INTEGER PRIMARY KEY AUTOINCREMENT, source_id INTEGER NOT NULL REFERENCES customers(id),
      target_id INTEGER NOT NULL REFERENCES customers(id), manager_id INTEGER NOT NULL REFERENCES staff(id),
      reason TEXT NOT NULL, created_at TEXT NOT NULL)''');
    for (final operation in ['UPDATE', 'DELETE']) {
      await db.execute("CREATE TRIGGER IF NOT EXISTS customer_merges_no_$operation BEFORE $operation ON customer_merges BEGIN SELECT RAISE(ABORT,'Customer merge history is immutable'); END");
    }
    await db.execute('''CREATE TABLE IF NOT EXISTS held_carts (
      id INTEGER PRIMARY KEY AUTOINCREMENT, cashier_id INTEGER NOT NULL REFERENCES staff(id),
      label TEXT NOT NULL, payload TEXT NOT NULL, created_at TEXT NOT NULL)''');
    final columns = await db.rawQuery('PRAGMA table_info(orders)');
    if (!columns.any((c) => c['name'] == 'customer_id')) {
      await db.execute('ALTER TABLE orders ADD COLUMN customer_id INTEGER REFERENCES customers(id)');
    }
    await db.execute('CREATE INDEX IF NOT EXISTS orders_customer ON orders(customer_id, id)');
    await db.execute('CREATE INDEX IF NOT EXISTS held_carts_cashier ON held_carts(cashier_id, id)');
    await db.execute('''CREATE TABLE IF NOT EXISTS customer_order_links (
      order_id INTEGER PRIMARY KEY REFERENCES orders(id),
      customer_id INTEGER NOT NULL REFERENCES customers(id))''');
    // Closed-day orders cannot be updated. Link legacy snapshots separately.
    final legacyOrders = await db.query('orders', where: 'customer_phone IS NOT NULL', orderBy: 'id');
    for (final order in legacyOrders) {
      final phone = DeliveryController.normalizePhone(order['customer_phone'] as String);
      if (phone.length < 7) continue;
      final existing = await db.query('customers', where: 'phone = ?', whereArgs: [phone]);
      final id = existing.isEmpty ? await db.insert('customers', {
        'name': (order['customer_name'] as String?)?.trim().isNotEmpty == true ? order['customer_name'] : phone,
        'phone': phone, 'created_at': order['created_at'],
      }) : existing.single['id'] as int;
      await db.insert('customer_order_links', {'order_id': order['id'], 'customer_id': id}, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<void> _upgradeToVersion17(DatabaseExecutor db) async {
    // Some legacy recovery databases contain only the core operational tables.
    await _createVendorKhataTables(db);
    final vendorColumns = await db.rawQuery('PRAGMA table_info(vendor_khata)');
    if (!vendorColumns.any((column) => column['name'] == 'archived_at')) {
      await db.execute('ALTER TABLE vendor_khata ADD COLUMN archived_at TEXT');
    }
    // This guard also protects existing ON DELETE CASCADE foreign keys.
    await db.execute('''CREATE TRIGGER IF NOT EXISTS vendor_financial_history_delete_guard
      BEFORE DELETE ON vendor_khata
      WHEN OLD.opening_balance != 0 OR OLD.current_balance != 0
        OR EXISTS (SELECT 1 FROM vendor_transactions WHERE vendor_id = OLD.id)
      BEGIN SELECT RAISE(ABORT, 'Archive suppliers with financial history'); END''');
    final staffColumns = await db.rawQuery('PRAGMA table_info(staff)');
    if (!staffColumns.any((column) => column['name'] == 'pin_fingerprint')) {
      await db.execute('ALTER TABLE staff ADD COLUMN pin_fingerprint TEXT');
    }
    await db.execute('''CREATE UNIQUE INDEX IF NOT EXISTS staff_pin_fingerprint_unique
      ON staff(pin_fingerprint) WHERE pin_fingerprint IS NOT NULL''');
    await db.execute('''CREATE TABLE IF NOT EXISTS auth_security_state (
      scope TEXT PRIMARY KEY,
      failures INTEGER NOT NULL DEFAULT 0,
      locked_until INTEGER NOT NULL DEFAULT 0,
      key_check TEXT
    )''');
  }

  Future<void> _upgradeToVersion16(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS order_status_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES orders(id),
      cashier_id INTEGER NOT NULL REFERENCES staff(id),
      from_status TEXT NOT NULL,
      to_status TEXT NOT NULL,
      recorded_at TEXT NOT NULL
    )''');
    await db.execute('CREATE INDEX IF NOT EXISTS order_status_events_order ON order_status_events(order_id, id)');
    for (final operation in ['UPDATE', 'DELETE']) {
      await db.execute("CREATE TRIGGER IF NOT EXISTS order_status_events_no_$operation BEFORE $operation ON order_status_events BEGIN SELECT RAISE(ABORT,'Order status history is immutable'); END");
    }
  }

  Future<void> _upgradeToVersion15(DatabaseExecutor db) async {
    await db.execute('CREATE TABLE IF NOT EXISTS job_roles (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE UNIQUE)');
    final columns = (await db.rawQuery('PRAGMA table_info(staff)')).map((c) => c['name']).toSet();
    if (!columns.contains('job_role_id')) {
      await db.execute('ALTER TABLE staff ADD COLUMN job_role_id INTEGER REFERENCES job_roles(id) ON DELETE RESTRICT');
    }
    if (!columns.contains('login_enabled')) {
      await db.execute('ALTER TABLE staff ADD COLUMN login_enabled INTEGER NOT NULL DEFAULT 1 CHECK(login_enabled IN (0, 1))');
    }
  }

  Future<void> _upgradeToVersion14(DatabaseExecutor db) async {
    await db.execute("""CREATE TABLE IF NOT EXISTS report_runs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      business_day_id INTEGER NOT NULL UNIQUE REFERENCES business_days(id),
      snapshot_json TEXT NOT NULL, content_hash TEXT NOT NULL,
      created_by INTEGER NOT NULL REFERENCES staff(id), created_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'PENDING', artifacts_json TEXT,
      error_message TEXT
    )""");
    final reportColumns=await db.rawQuery('PRAGMA table_info(report_runs)');
    if(!reportColumns.any((column)=>column['name']=='export_lease_until')) {
      await db.execute('ALTER TABLE report_runs ADD COLUMN export_lease_until TEXT');
    }
    await db.execute("""CREATE TABLE IF NOT EXISTS inventory_movements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ingredient_id INTEGER NOT NULL REFERENCES raw_ingredients(id),
      business_day_id INTEGER REFERENCES business_days(id),
      quantity_delta REAL NOT NULL, balance_after REAL NOT NULL,
      recorded_at TEXT NOT NULL
    )""");
    await db.execute("""CREATE TRIGGER IF NOT EXISTS inventory_balance_change AFTER UPDATE OF current_stock ON raw_ingredients
      WHEN NEW.current_stock != OLD.current_stock BEGIN
      INSERT INTO inventory_movements(ingredient_id,business_day_id,quantity_delta,balance_after,recorded_at)
      VALUES(NEW.id,(SELECT id FROM business_days WHERE status='OPEN' ORDER BY id DESC LIMIT 1),
        NEW.current_stock-OLD.current_stock,NEW.current_stock,strftime('%Y-%m-%d %H:%M:%f','now','localtime'));
    END""");
    await db.execute("""CREATE TRIGGER IF NOT EXISTS inventory_initial_balance AFTER INSERT ON raw_ingredients
      WHEN NEW.current_stock != 0 BEGIN
      INSERT INTO inventory_movements(ingredient_id,business_day_id,quantity_delta,balance_after,recorded_at)
      VALUES(NEW.id,(SELECT id FROM business_days WHERE status='OPEN' ORDER BY id DESC LIMIT 1),
        NEW.current_stock,NEW.current_stock,strftime('%Y-%m-%d %H:%M:%f','now','localtime'));
    END""");
    final outboxColumns = await db.rawQuery('PRAGMA table_info(report_outbox)');
    if (!outboxColumns.any((column) => column['name'] == 'idempotency_key')) {
      await db.execute('ALTER TABLE report_outbox RENAME TO report_outbox_legacy');
      await db.execute("""CREATE TABLE report_outbox (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_day_id INTEGER NOT NULL REFERENCES business_days(id),
        channel TEXT NOT NULL CHECK(channel IN ('EMAIL','WHATSAPP')),
        recipient TEXT NOT NULL, payload_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','PROCESSING','SENT','ACCEPTED','FAILED','AMBIGUOUS','CANCELLED')),
        retry_count INTEGER NOT NULL DEFAULT 0, next_attempt_at TEXT NOT NULL,
        error_message TEXT, created_at TEXT NOT NULL, processed_at TEXT,
        idempotency_key TEXT UNIQUE, report_run_id INTEGER REFERENCES report_runs(id),
        endpoint TEXT, max_attempts INTEGER NOT NULL DEFAULT 8,
        lease_until TEXT, provider_reference TEXT
      )""");
      await db.execute("""INSERT INTO report_outbox(id,business_day_id,channel,recipient,payload_json,status,retry_count,next_attempt_at,error_message,created_at,processed_at)
        SELECT id,business_day_id,channel,recipient,payload_json,status,retry_count,next_attempt_at,error_message,created_at,processed_at FROM report_outbox_legacy""");
      await db.execute('DROP TABLE report_outbox_legacy');
      await db.execute('CREATE INDEX idx_report_outbox_status_attempt ON report_outbox(status,next_attempt_at)');
    }
    await db.execute("""CREATE TABLE IF NOT EXISTS report_delivery_audit (
      id INTEGER PRIMARY KEY AUTOINCREMENT, staff_id INTEGER NOT NULL REFERENCES staff(id),
      action TEXT NOT NULL, details_json TEXT NOT NULL, created_at TEXT NOT NULL
    )""");
    // A closed day is a durable boundary even for stale UI controllers.
    for (final operation in ['UPDATE','DELETE','INSERT']) {
      final ref = operation == 'INSERT' ? 'NEW' : 'OLD';
      for (final table in ['orders','shifts']) {
        final event = table == 'shifts' && operation == 'UPDATE'
            ? 'UPDATE OF business_day_id,staff_id,opened_at,closed_at,opening_float,counted_cash,expected_cash,discrepancy,status' : operation;
        final changedDay = operation == 'UPDATE' ? " OR EXISTS(SELECT 1 FROM business_days WHERE id=NEW.business_day_id AND status='CLOSED')" : '';
        await db.execute("""CREATE TRIGGER IF NOT EXISTS closed_${table}_$operation BEFORE $event ON $table
          WHEN EXISTS(SELECT 1 FROM business_days WHERE id=$ref.business_day_id AND status='CLOSED')$changedDay
          BEGIN SELECT RAISE(ABORT,'Business Day is permanently closed'); END""");
      }
      for (final table in ['order_items','order_payments']) {
        final changedOrder = operation == 'UPDATE' ? " OR EXISTS(SELECT 1 FROM orders o JOIN business_days b ON b.id=o.business_day_id WHERE o.id=NEW.order_id AND b.status='CLOSED')" : '';
        await db.execute("""CREATE TRIGGER IF NOT EXISTS closed_${table}_$operation BEFORE $operation ON $table
          WHEN EXISTS(SELECT 1 FROM orders o JOIN business_days b ON b.id=o.business_day_id
            WHERE o.id=$ref.order_id AND b.status='CLOSED')$changedOrder
          BEGIN SELECT RAISE(ABORT,'Business Day is permanently closed'); END""");
      }
      final changedShift = operation == 'UPDATE' ? " OR EXISTS(SELECT 1 FROM shifts s JOIN business_days b ON b.id=s.business_day_id WHERE s.id=NEW.shift_id AND b.status='CLOSED')" : '';
      await db.execute("""CREATE TRIGGER IF NOT EXISTS closed_movements_$operation BEFORE $operation ON cash_movements
        WHEN EXISTS(SELECT 1 FROM shifts s JOIN business_days b ON b.id=s.business_day_id
          WHERE s.id=$ref.shift_id AND b.status='CLOSED')$changedShift
        BEGIN SELECT RAISE(ABORT,'Business Day is permanently closed'); END""");
    }
    await db.execute("""CREATE TRIGGER IF NOT EXISTS closed_day_immutable BEFORE UPDATE ON business_days
      WHEN OLD.status='CLOSED' BEGIN SELECT RAISE(ABORT,'Business Day is permanently closed'); END""");
    await db.execute("""CREATE TRIGGER IF NOT EXISTS report_snapshot_immutable BEFORE UPDATE OF id,snapshot_json,content_hash,business_day_id,created_by,created_at ON report_runs
      BEGIN SELECT RAISE(ABORT,'Report snapshot is immutable'); END""");
    for (final table in ['report_runs','inventory_movements']) {
      await db.execute("CREATE TRIGGER IF NOT EXISTS ${table}_no_delete BEFORE DELETE ON $table BEGIN SELECT RAISE(ABORT,'Report audit is immutable'); END");
    }
    await db.execute("CREATE TRIGGER IF NOT EXISTS inventory_movements_no_update BEFORE UPDATE ON inventory_movements BEGIN SELECT RAISE(ABORT,'Inventory audit is immutable'); END");
  }

  Future<void> _upgradeToVersion13(DatabaseExecutor db) async {
    final tripColumns = await db.rawQuery('PRAGMA table_info(${PosDatabaseConstants.tableRiderTrips})');
    if (!tripColumns.any((c) => c['name'] == 'trip_name')) {
      await db.execute("ALTER TABLE ${PosDatabaseConstants.tableRiderTrips} ADD COLUMN trip_name TEXT NOT NULL DEFAULT ''");
    }

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableRiderTripOrders} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableRiderTrips}(id) ON DELETE CASCADE,
        order_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableOrders}(id),
        status TEXT NOT NULL DEFAULT 'DISPATCHED' CHECK (status IN ('DISPATCHED','DELIVERED','RETURNED')),
        assigned_at TEXT NOT NULL,
        delivered_at TEXT,
        returned_at TEXT,
        notes TEXT
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_rider_trip_orders_trip ON ${PosDatabaseConstants.tableRiderTripOrders}(trip_id);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_rider_trip_orders_order ON ${PosDatabaseConstants.tableRiderTripOrders}(order_id);');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableRiderDispatchAlerts} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableRiderTrips}(id) ON DELETE CASCADE,
        order_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableOrders}(id),
        revision_id INTEGER REFERENCES ${PosDatabaseConstants.tableOrderRevisions}(id),
        alert_type TEXT NOT NULL CHECK (alert_type IN ('ORDER_MODIFIED', 'ORDER_CANCELLED')),
        message TEXT NOT NULL,
        is_acknowledged INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        acknowledged_at TEXT,
        acknowledged_by INTEGER REFERENCES ${PosDatabaseConstants.tableStaff}(id)
      );
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_rider_dispatch_alerts_trip ON ${PosDatabaseConstants.tableRiderDispatchAlerts}(trip_id, is_acknowledged);');
  }

  Future<void> _upgradeToVersion12(DatabaseExecutor db) async {
    await _createOperationalAccountingTables(db);
    final orderColumns = await db.rawQuery('PRAGMA table_info(orders)');
    if (!orderColumns.any((c) => c['name'] == 'checkout_command_id')) {
      await db.execute("ALTER TABLE orders ADD COLUMN checkout_command_id TEXT");
    }
    final paymentColumns = await db.rawQuery('PRAGMA table_info(order_payments)');
    for (final column in ['amount_tendered', 'change_returned']) {
      if (paymentColumns.any((c) => c['name'] == '${column}_paisa')) continue;
      await db.execute('ALTER TABLE order_payments ADD COLUMN ${column}_paisa INTEGER');
      await db.execute('UPDATE order_payments SET ${column}_paisa = CAST(ROUND($column * 100) AS INTEGER)');
    }

    await db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_checkout_command ON orders(checkout_command_id) WHERE checkout_command_id IS NOT NULL");
    await db.execute("""
      CREATE TABLE IF NOT EXISTS checkout_stock_alerts (
        order_id INTEGER NOT NULL REFERENCES orders(id),
        ingredient_id INTEGER NOT NULL REFERENCES raw_ingredients(id),
        stock_at_checkout REAL NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY(order_id, ingredient_id)
      )
    """);

    await db.execute("""CREATE TABLE IF NOT EXISTS checkout_tokens (
      order_id INTEGER PRIMARY KEY REFERENCES orders(id),
      business_day_id INTEGER NOT NULL REFERENCES business_days(id),
      token_number INTEGER NOT NULL,
      UNIQUE(business_day_id, token_number)
    )""");
    await db.execute('INSERT OR IGNORE INTO checkout_tokens SELECT id, business_day_id, token_number FROM orders');
    await db.execute("""CREATE TABLE IF NOT EXISTS checkout_token_audit (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES orders(id),
      business_day_id INTEGER NOT NULL,
      token_number INTEGER NOT NULL,
      action TEXT NOT NULL,
      payment_status TEXT NOT NULL,
      revision INTEGER NOT NULL,
      recorded_at TEXT NOT NULL
    )""");
    await db.execute("""INSERT INTO checkout_token_audit(order_id,business_day_id,token_number,action,payment_status,revision,recorded_at)
      SELECT id,business_day_id,token_number,'ALLOCATED',payment_status,current_revision,created_at FROM orders o
      WHERE NOT EXISTS (SELECT 1 FROM checkout_token_audit a WHERE a.order_id=o.id)""");
    await db.execute("""CREATE TRIGGER IF NOT EXISTS checkout_token_allocate AFTER INSERT ON orders BEGIN
      INSERT INTO checkout_tokens VALUES(NEW.id,NEW.business_day_id,NEW.token_number);
      INSERT INTO checkout_token_audit(order_id,business_day_id,token_number,action,payment_status,revision,recorded_at)
        VALUES(NEW.id,NEW.business_day_id,NEW.token_number,'ALLOCATED',NEW.payment_status,NEW.current_revision,NEW.created_at);
    END""");
    await db.execute("""CREATE TRIGGER IF NOT EXISTS checkout_token_status AFTER UPDATE OF payment_status,current_revision ON orders
      WHEN NEW.payment_status != OLD.payment_status OR NEW.current_revision != OLD.current_revision BEGIN
      INSERT INTO checkout_token_audit(order_id,business_day_id,token_number,action,payment_status,revision,recorded_at)
        VALUES(NEW.id,NEW.business_day_id,NEW.token_number,
          CASE WHEN NEW.current_revision != OLD.current_revision THEN 'REVISED' ELSE 'STATUS_CHANGED' END,
          NEW.payment_status,NEW.current_revision,strftime('%Y-%m-%d %H:%M:%f','now'));
    END""");
    await db.execute("""CREATE TRIGGER IF NOT EXISTS checkout_token_identity BEFORE UPDATE OF token_number,business_day_id ON orders
      WHEN NEW.token_number != OLD.token_number OR NEW.business_day_id != OLD.business_day_id
      BEGIN SELECT RAISE(ABORT,'Allocated tokens are immutable'); END""");
    for (final table in ['checkout_tokens', 'checkout_token_audit']) {
      for (final operation in ['UPDATE', 'DELETE']) {
        await db.execute("CREATE TRIGGER IF NOT EXISTS ${table}_no_$operation BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT,'Token audit is immutable'); END");
      }
    }

  }

  Future<void> _upgradeToVersion11(DatabaseExecutor db) async {
    final columns = await db.rawQuery('PRAGMA table_info(delivery_areas)');
    if (!columns.any((column) => column['name'] == 'archived_at')) {
      await db.execute('ALTER TABLE delivery_areas ADD COLUMN archived_at TEXT;');
    }
  }

  Future<void> _upgradeToVersion10(DatabaseExecutor db) async {
    await _createCatalogAndRecipeTables(db);
    await _createOrderItemsAndDealsTables(db);
    await db.execute("""
      CREATE TABLE IF NOT EXISTS modifier_groups (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        menu_item_id INTEGER NOT NULL REFERENCES menu_items(id) ON DELETE CASCADE,
        name TEXT NOT NULL,
        selection_mode TEXT NOT NULL CHECK(selection_mode IN ('SINGLE','MULTIPLE')),
        min_selected INTEGER NOT NULL CHECK(min_selected >= 0),
        max_selected INTEGER NOT NULL CHECK(max_selected >= 1 AND max_selected >= min_selected),
        is_required INTEGER NOT NULL CHECK(is_required IN (0,1)),
        CHECK(selection_mode != 'SINGLE' OR max_selected = 1)
      )
    """);
    final modifierColumns = await db.rawQuery('PRAGMA table_info(modifiers)');
    final migratingLegacyModifiers = !modifierColumns.any((column) => column['name'] == 'group_id');
    if (migratingLegacyModifiers) {
      await db.execute('ALTER TABLE modifiers ADD COLUMN group_id INTEGER REFERENCES modifier_groups(id) ON DELETE RESTRICT');
    }
    final orderColumns = await db.rawQuery('PRAGMA table_info(order_items)');
    if (!orderColumns.any((column) => column['name'] == 'bom_json')) {
      await db.execute('ALTER TABLE order_items ADD COLUMN bom_json TEXT');
    }
    if (migratingLegacyModifiers) {
    // Preserve legacy item-specific removal semantics once, as explicit deltas.
    await db.execute("""
      UPDATE modifiers SET ingredient_qty_delta = -(
        SELECT quantity_per_recipe_unit FROM recipes r
        WHERE r.menu_item_id = modifiers.menu_item_id AND r.raw_ingredient_id = modifiers.raw_ingredient_id
      ) WHERE menu_item_id IS NOT NULL AND raw_ingredient_id IS NOT NULL
        AND (ingredient_qty_delta = 0 OR lower(name) LIKE '%no %')
        AND EXISTS (SELECT 1 FROM recipes r WHERE r.menu_item_id = modifiers.menu_item_id AND r.raw_ingredient_id = modifiers.raw_ingredient_id)
    """);
    // Global legacy removals need per-item quantities; keep them off the counter
    // until a manager supplies explicit deltas.
    await db.execute("UPDATE modifiers SET is_active = 0 WHERE menu_item_id IS NULL AND raw_ingredient_id IS NOT NULL AND (ingredient_qty_delta = 0 OR lower(name) LIKE '%no %')");
    }
    await db.execute("UPDATE menu_items SET is_active = 0 WHERE NOT EXISTS (SELECT 1 FROM recipes r WHERE r.menu_item_id = menu_items.id) OR EXISTS (SELECT 1 FROM recipes r WHERE r.menu_item_id = menu_items.id AND r.quantity_per_recipe_unit <= 0)");
  }

  Future<void> _createV9Tables(DatabaseExecutor executor) async {
    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableDeliveryAreas} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        code TEXT UNIQUE,
        coverage_description TEXT,
        delivery_fee_paisa INTEGER NOT NULL CHECK(delivery_fee_paisa >= 0),
        min_order_paisa INTEGER NOT NULL DEFAULT 0 CHECK(min_order_paisa >= 0),
        target_eta_minutes INTEGER,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_delivery_areas_active ON ${PosDatabaseConstants.tableDeliveryAreas}(is_active);');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableCustomerAddresses} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_phone TEXT NOT NULL,
        customer_name TEXT,
        delivery_area_id INTEGER REFERENCES ${PosDatabaseConstants.tableDeliveryAreas}(id) ON DELETE SET NULL,
        full_address TEXT NOT NULL,
        landmark TEXT,
        notes TEXT,
        is_default INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_customer_addresses_phone ON ${PosDatabaseConstants.tableCustomerAddresses}(customer_phone);');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_customer_addresses_area ON ${PosDatabaseConstants.tableCustomerAddresses}(delivery_area_id);');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableOrderRevisions} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableOrders}(id) ON DELETE RESTRICT,
        revision_no INTEGER NOT NULL CHECK (revision_no >= 1),
        prior_revision_id INTEGER REFERENCES ${PosDatabaseConstants.tableOrderRevisions}(id),
        action TEXT NOT NULL CHECK (action IN ('ADD','CHANGE','REMOVE','CANCEL','CORRECTION')),
        reason TEXT NOT NULL,
        cashier_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        business_day_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableBusinessDays}(id),
        created_at_utc TEXT NOT NULL,
        old_total_paisa INTEGER NOT NULL,
        new_total_paisa INTEGER NOT NULL,
        money_delta_paisa INTEGER NOT NULL,
        prior_snapshot_json TEXT NOT NULL,
        new_snapshot_json TEXT NOT NULL,
        command_id TEXT NOT NULL UNIQUE,
        UNIQUE(order_id, revision_no)
      );
    ''');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_order_revisions_order_id ON ${PosDatabaseConstants.tableOrderRevisions}(order_id);');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableOrderRevisionLines} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        revision_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableOrderRevisions}(id) ON DELETE CASCADE,
        original_order_line_id INTEGER,
        item_id INTEGER,
        action TEXT NOT NULL,
        old_qty_decimal TEXT NOT NULL,
        new_qty_decimal TEXT NOT NULL,
        line_price_delta_paisa INTEGER NOT NULL,
        bom_disposition TEXT NOT NULL,
        ingredient_delta_snapshot_json TEXT NOT NULL
      );
    ''');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_order_revision_lines_rev ON ${PosDatabaseConstants.tableOrderRevisionLines}(revision_id);');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableRiderTrips} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_name TEXT NOT NULL DEFAULT '',
        rider_staff_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        shift_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableShifts}(id),
        business_day_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableBusinessDays}(id),
        status TEXT NOT NULL DEFAULT 'DISPATCHED' CHECK (status IN ('DISPATCHED','RETURNED','SETTLED','CANCELLED')),
        cash_expected_paisa INTEGER NOT NULL DEFAULT 0,
        cash_collected_paisa INTEGER NOT NULL DEFAULT 0,
        dispatched_at TEXT NOT NULL,
        returned_at TEXT,
        settled_at_utc TEXT,
        created_at TEXT NOT NULL
      );
    ''');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_rider_trips_rider_status ON ${PosDatabaseConstants.tableRiderTrips}(rider_staff_id, status);');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_rider_trips_bday ON ${PosDatabaseConstants.tableRiderTrips}(business_day_id);');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableRiderTripOrders} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableRiderTrips}(id) ON DELETE CASCADE,
        order_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableOrders}(id),
        status TEXT NOT NULL DEFAULT 'DISPATCHED' CHECK (status IN ('DISPATCHED','DELIVERED','RETURNED')),
        assigned_at TEXT NOT NULL,
        delivered_at TEXT,
        returned_at TEXT,
        notes TEXT
      );
    ''');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_rider_trip_orders_trip ON ${PosDatabaseConstants.tableRiderTripOrders}(trip_id);');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_rider_trip_orders_order ON ${PosDatabaseConstants.tableRiderTripOrders}(order_id);');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableRiderDispatchAlerts} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trip_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableRiderTrips}(id) ON DELETE CASCADE,
        order_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableOrders}(id),
        revision_id INTEGER REFERENCES ${PosDatabaseConstants.tableOrderRevisions}(id),
        alert_type TEXT NOT NULL CHECK (alert_type IN ('ORDER_MODIFIED', 'ORDER_CANCELLED')),
        message TEXT NOT NULL,
        is_acknowledged INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        acknowledged_at TEXT,
        acknowledged_by INTEGER REFERENCES ${PosDatabaseConstants.tableStaff}(id)
      );
    ''');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_rider_dispatch_alerts_trip ON ${PosDatabaseConstants.tableRiderDispatchAlerts}(trip_id, is_acknowledged);');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableCatalogImages} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entity_type TEXT NOT NULL CHECK(entity_type IN ('menu_item','deal')),
        entity_id INTEGER NOT NULL,
        relative_file_path TEXT NOT NULL,
        thumbnail_path TEXT,
        content_type TEXT,
        byte_count INTEGER,
        sha256_checksum TEXT,
        is_primary INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        deleted_at TEXT
      );
    ''');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_catalog_images_entity ON ${PosDatabaseConstants.tableCatalogImages}(entity_type, entity_id, deleted_at);');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableReportOutbox} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_day_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableBusinessDays}(id),
        channel TEXT NOT NULL CHECK(channel IN ('EMAIL','WHATSAPP')),
        recipient TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'PENDING' CHECK(status IN ('PENDING','PROCESSING','SENT','FAILED')),
        retry_count INTEGER NOT NULL DEFAULT 0,
        next_attempt_at TEXT NOT NULL,
        error_message TEXT,
        created_at TEXT NOT NULL,
        processed_at TEXT
      );
    ''');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_report_outbox_status_attempt ON ${PosDatabaseConstants.tableReportOutbox}(status, next_attempt_at);');

    await executor.execute('''
      CREATE TABLE IF NOT EXISTS ${PosDatabaseConstants.tableRoundingVarianceLedger} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER REFERENCES ${PosDatabaseConstants.tableOrders}(id) ON DELETE SET NULL,
        shift_id INTEGER REFERENCES ${PosDatabaseConstants.tableShifts}(id) ON DELETE SET NULL,
        cash_rounding_paisa INTEGER NOT NULL,
        reason TEXT,
        created_at TEXT NOT NULL
      );
    ''');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_rounding_ledger_order ON ${PosDatabaseConstants.tableRoundingVarianceLedger}(order_id);');
    await executor.execute('CREATE INDEX IF NOT EXISTS idx_rounding_ledger_shift ON ${PosDatabaseConstants.tableRoundingVarianceLedger}(shift_id);');
  }

  Future<void> _upgradeToVersion9(Database db) async {
    // 1. Create all new v9 schema tables
    await _createV9Tables(db);

    // 2. Safe addition of missing columns to orders table
    final orderColsInfo = await db.rawQuery('PRAGMA table_info(${PosDatabaseConstants.tableOrders});');
    final orderColNames = orderColsInfo.map((r) => r['name'] as String).toSet();

    if (!orderColNames.contains('current_revision')) {
      await db.execute('ALTER TABLE ${PosDatabaseConstants.tableOrders} ADD COLUMN current_revision INTEGER NOT NULL DEFAULT 1;');
    }
    if (!orderColNames.contains('cash_rounding_paisa')) {
      await db.execute('ALTER TABLE ${PosDatabaseConstants.tableOrders} ADD COLUMN cash_rounding_paisa INTEGER NOT NULL DEFAULT 0;');
    }
    if (!orderColNames.contains('delivery_area_id')) {
      await db.execute('ALTER TABLE ${PosDatabaseConstants.tableOrders} ADD COLUMN delivery_area_id INTEGER REFERENCES ${PosDatabaseConstants.tableDeliveryAreas}(id);');
    }
    if (!orderColNames.contains('delivery_area_name_snapshot')) {
      await db.execute('ALTER TABLE ${PosDatabaseConstants.tableOrders} ADD COLUMN delivery_area_name_snapshot TEXT;');
    }
    if (!orderColNames.contains('delivery_address_snapshot')) {
      await db.execute('ALTER TABLE ${PosDatabaseConstants.tableOrders} ADD COLUMN delivery_address_snapshot TEXT;');
    }
    if (!orderColNames.contains('delivery_fee_paisa')) {
      await db.execute('ALTER TABLE ${PosDatabaseConstants.tableOrders} ADD COLUMN delivery_fee_paisa INTEGER NOT NULL DEFAULT 0;');
    }
    if (!orderColNames.contains('customer_phone')) {
      await db.execute('ALTER TABLE ${PosDatabaseConstants.tableOrders} ADD COLUMN customer_phone TEXT;');
    }
    if (!orderColNames.contains('customer_name')) {
      await db.execute('ALTER TABLE ${PosDatabaseConstants.tableOrders} ADD COLUMN customer_name TEXT;');
    }

    // 3. Safe transactional table-rebuild of cash_movements to make approved_by nullable
    final cashMovementsColsInfo = await db.rawQuery('PRAGMA table_info(${PosDatabaseConstants.tableCashMovements});');
    final cashColNames = cashMovementsColsInfo.map((r) => r['name'] as String).toSet();

    await db.execute('''
      CREATE TABLE cash_movements_v9_rebuild (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        shift_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableShifts}(id),
        staff_id INTEGER NOT NULL REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        notes TEXT NOT NULL,
        approved_by INTEGER REFERENCES ${PosDatabaseConstants.tableStaff}(id),
        created_at TEXT NOT NULL
      );
    ''');

    if (cashColNames.contains('approved_by')) {
      await db.execute('''
        INSERT INTO cash_movements_v9_rebuild (id, shift_id, staff_id, type, amount, category, notes, approved_by, created_at)
        SELECT id, shift_id, staff_id, type, amount, category, notes, approved_by, created_at
        FROM ${PosDatabaseConstants.tableCashMovements};
      ''');
    } else {
      await db.execute('''
        INSERT INTO cash_movements_v9_rebuild (id, shift_id, staff_id, type, amount, category, notes, approved_by, created_at)
        SELECT id, shift_id, staff_id, type, amount, category, notes, NULL, created_at
        FROM ${PosDatabaseConstants.tableCashMovements};
      ''');
    }

    await db.execute('DROP TABLE ${PosDatabaseConstants.tableCashMovements};');
    await db.execute('ALTER TABLE cash_movements_v9_rebuild RENAME TO ${PosDatabaseConstants.tableCashMovements};');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cash_movements_shift_id ON ${PosDatabaseConstants.tableCashMovements}(shift_id);');
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

    // 2. Seed initial staff accounts only if explicitly requested (e.g. test environments)
    if (seedDefaultStaff) {
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
    }

    // 3. Seed default system settings
    // Existing installations predate the wizard. Only infer completion when the
    // marker is first created; an explicit false marker survives partial setup.
    final existingStaff = await db.query(PosDatabaseConstants.tableStaff, where: 'is_active = 1 AND login_enabled = 1');
    final hasManager = existingStaff.any((s) =>
        const ['MANAGER', 'SUPERVISOR', 'OWNER'].contains(s['role']));
    final hasCashier = existingStaff.any((s) => s['role'] == 'CASHIER');
    final defaultSettings = {
      'schema_version': '${PosDatabaseConstants.schemaVersion}',
      'app_name': 'ResturantPOS',
      PosDatabaseConstants.settingDiscrepancyThreshold: PosDatabaseConstants.defaultDiscrepancyThreshold,
      PosDatabaseConstants.settingCashierVoidRequestsEnabled: PosDatabaseConstants.defaultCashierVoidRequestsEnabled,
      PosDatabaseConstants.settingRestaurantName: PosDatabaseConstants.defaultRestaurantName,
      PosDatabaseConstants.settingCurrencyCode: PosDatabaseConstants.defaultCurrencyCode,
      PosDatabaseConstants.settingDefaultTaxRate: PosDatabaseConstants.defaultDefaultTaxRate,
      PosDatabaseConstants.settingTaxInclusive: PosDatabaseConstants.defaultTaxInclusive,
      PosDatabaseConstants.settingOnboardingCompleted: hasManager && hasCashier ? 'true' : 'false',
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
