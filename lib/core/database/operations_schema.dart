import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Additive migration: old cash movements remain cash history, never inferred
/// payroll or expense accruals. Legacy supplier receipts seed explicit mappings.
Future<void> createOperationsSchema(DatabaseExecutor db) async {
  final columns = (await db.rawQuery('PRAGMA table_info(vendor_transactions)'))
      .map((c) => c['name']).toSet();
  for (final column in ['due_date', 'ingredient_name_snapshot', 'unit_snapshot', 'request_key']) {
    if (!columns.contains(column)) {
      await db.execute('ALTER TABLE vendor_transactions ADD COLUMN $column TEXT');
    }
  }
  await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS supplier_request_key ON vendor_transactions(request_key) WHERE request_key IS NOT NULL');
  if (!columns.contains('amount_paisa')) {
    await db.execute('ALTER TABLE vendor_transactions ADD COLUMN amount_paisa INTEGER');
    await db.execute('UPDATE vendor_transactions SET amount_paisa = CAST(ROUND(amount * 100) AS INTEGER)');
  }
  await db.execute('''CREATE TABLE IF NOT EXISTS supplier_items (
    vendor_id INTEGER NOT NULL REFERENCES vendor_khata(id) ON DELETE CASCADE,
    ingredient_id INTEGER NOT NULL REFERENCES raw_ingredients(id),
    sku TEXT NOT NULL DEFAULT '', active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)),
    PRIMARY KEY(vendor_id, ingredient_id))''');
  await db.execute('''INSERT OR IGNORE INTO supplier_items(vendor_id,ingredient_id)
    SELECT DISTINCT vendor_id,raw_ingredient_id FROM vendor_transactions
    WHERE raw_ingredient_id IS NOT NULL''');
  await db.execute('''CREATE TABLE IF NOT EXISTS supplier_payment_allocations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    payment_id INTEGER NOT NULL REFERENCES vendor_transactions(id),
    invoice_id INTEGER REFERENCES vendor_transactions(id),
    amount_paisa INTEGER NOT NULL CHECK(amount_paisa > 0))''');
  await db.execute('CREATE INDEX IF NOT EXISTS supplier_allocations_invoice ON supplier_payment_allocations(invoice_id)');
  // Reconstruct historical allocations deterministically: opening payable first,
  // then invoices in posting order. Excess legacy payments stay unallocated.
  for (final vendor in await db.query('vendor_khata')) {
    var opening = ((vendor['opening_balance'] as num) * 100).round();
    final invoices = <int, int>{};
    final events = await db.query('vendor_transactions', where: 'vendor_id = ?',
        whereArgs: [vendor['id']], orderBy: 'created_at, id');
    for (final event in events.where((e) => e['type'] == 'PURCHASE_CREDIT')) {
      invoices[event['id'] as int] = event['amount_paisa'] as int;
    }
    for (final event in events) {
      final id = event['id'] as int;
      final amount = event['amount_paisa'] as int;
      if (event['type'] == 'PURCHASE_CREDIT') {
        continue;
      } else {
        var remaining = amount;
        if (opening > 0) {
          final allocated = remaining < opening ? remaining : opening;
          if (allocated > 0) await db.insert('supplier_payment_allocations',
              {'payment_id': id, 'amount_paisa': allocated});
          opening -= allocated;
          remaining -= allocated;
        }
        for (final invoice in invoices.keys.toList()) {
          final due = invoices[invoice]!;
          final allocated = remaining < due ? remaining : due;
          if (allocated > 0) await db.insert('supplier_payment_allocations',
              {'payment_id': id, 'invoice_id': invoice, 'amount_paisa': allocated});
          invoices[invoice] = due - allocated;
          remaining -= allocated;
        }
      }
    }
  }
  await db.execute('''CREATE TABLE IF NOT EXISTS salary_rates (
    id INTEGER PRIMARY KEY AUTOINCREMENT, employee_id INTEGER NOT NULL REFERENCES staff(id),
    effective_period TEXT NOT NULL, amount_paisa INTEGER NOT NULL CHECK(amount_paisa > 0),
    manager_id INTEGER NOT NULL REFERENCES staff(id), reason TEXT NOT NULL,
    created_at TEXT NOT NULL, UNIQUE(employee_id,effective_period))''');
  await db.execute('''CREATE TABLE IF NOT EXISTS payroll_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT, employee_id INTEGER NOT NULL REFERENCES staff(id),
    period TEXT NOT NULL, kind TEXT NOT NULL CHECK(kind IN ('ACCRUAL','PAYMENT','ADVANCE','RECOVERY','REVERSAL')),
    amount_paisa INTEGER NOT NULL CHECK(amount_paisa > 0),
    payable_delta_paisa INTEGER NOT NULL, advance_delta_paisa INTEGER NOT NULL,
    source TEXT NOT NULL CHECK(source IN ('NONE','DRAWER','BANK','OWNER')),
    cash_movement_id INTEGER UNIQUE REFERENCES cash_movements(id),
    reversal_of INTEGER UNIQUE REFERENCES payroll_entries(id),
    manager_id INTEGER NOT NULL REFERENCES staff(id), reason TEXT NOT NULL,
    request_key TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL)''');
  await db.execute('CREATE INDEX IF NOT EXISTS payroll_employee_period ON payroll_entries(employee_id,period)');
  await db.execute("""CREATE TRIGGER IF NOT EXISTS payroll_accrual_once BEFORE INSERT ON payroll_entries
    WHEN NEW.kind='ACCRUAL' AND EXISTS(SELECT 1 FROM payroll_entries a
      WHERE a.employee_id=NEW.employee_id AND a.period=NEW.period AND a.kind='ACCRUAL'
      AND NOT EXISTS(SELECT 1 FROM payroll_entries r WHERE r.reversal_of=a.id))
    BEGIN SELECT RAISE(ABORT,'Salary already accrued for this period'); END""");
  await db.execute('''CREATE TABLE IF NOT EXISTS expense_categories (
    id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL COLLATE NOCASE UNIQUE,
    description TEXT NOT NULL DEFAULT '', active INTEGER NOT NULL DEFAULT 1 CHECK(active IN (0,1)),
    sort_order INTEGER NOT NULL DEFAULT 0,
    allowed_source TEXT NOT NULL DEFAULT 'ANY' CHECK(allowed_source IN ('ANY','DRAWER','BANK','OWNER')),
    approval_threshold_paisa INTEGER CHECK(approval_threshold_paisa >= 0))''');
  await db.execute('''CREATE TABLE IF NOT EXISTS expense_entries (
    id INTEGER PRIMARY KEY AUTOINCREMENT, category_id INTEGER NOT NULL REFERENCES expense_categories(id),
    category_snapshot TEXT NOT NULL, description TEXT NOT NULL, payee TEXT NOT NULL,
    amount_paisa INTEGER NOT NULL CHECK(amount_paisa > 0),
    expense_delta_paisa INTEGER NOT NULL,
    source TEXT NOT NULL CHECK(source IN ('DRAWER','BANK','OWNER')),
    business_day_id INTEGER NOT NULL REFERENCES business_days(id),
    cash_movement_id INTEGER UNIQUE REFERENCES cash_movements(id),
    reversal_of INTEGER UNIQUE REFERENCES expense_entries(id),
    correction_of INTEGER UNIQUE REFERENCES expense_entries(id),
    receipt_path TEXT, manager_id INTEGER NOT NULL REFERENCES staff(id),
    reason TEXT NOT NULL, request_key TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL)''');
  await db.execute('''CREATE TABLE IF NOT EXISTS operations_audit (
    id INTEGER PRIMARY KEY AUTOINCREMENT, manager_id INTEGER NOT NULL REFERENCES staff(id),
    entity TEXT NOT NULL, entity_id INTEGER NOT NULL, action TEXT NOT NULL,
    detail TEXT NOT NULL, created_at TEXT NOT NULL)''');
  for (final table in ['salary_rates','payroll_entries','expense_entries','operations_audit','supplier_payment_allocations']) {
    for (final operation in ['UPDATE','DELETE']) {
      await db.execute("CREATE TRIGGER IF NOT EXISTS ${table}_no_$operation BEFORE $operation ON $table BEGIN SELECT RAISE(ABORT,'Financial history is immutable'); END");
    }
  }
}
