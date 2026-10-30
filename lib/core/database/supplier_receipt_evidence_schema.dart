import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Schema migration establishing immutable supplier receipt evidence,
/// append-only delivery promises and amendments, and stable links between
/// Mandi wholesale procurements and Vendor Khata credit purchases.
Future<void> createSupplierReceiptEvidenceSchema(DatabaseExecutor db) async {
  final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
      .map((row) => row['name'] as String).toSet();

  // 1. Add linking columns to mandi_procurements if table exists
  if (tables.contains('mandi_procurements')) {
    final mandiCols = (await db.rawQuery('PRAGMA table_info(mandi_procurements)'))
        .map((c) => c['name']).toSet();
    if (!mandiCols.contains('vendor_id')) {
      await db.execute('ALTER TABLE mandi_procurements ADD COLUMN vendor_id INTEGER REFERENCES vendor_khata(id) ON DELETE SET NULL');
    }
    if (!mandiCols.contains('vendor_transaction_id')) {
      await db.execute('ALTER TABLE mandi_procurements ADD COLUMN vendor_transaction_id INTEGER REFERENCES vendor_transactions(id) ON DELETE SET NULL');
    }
  }

  // 2. Add linking column to vendor_transactions if table exists
  if (tables.contains('vendor_transactions')) {
    final txnCols = (await db.rawQuery('PRAGMA table_info(vendor_transactions)'))
        .map((c) => c['name']).toSet();
    if (!txnCols.contains('procurement_id')) {
      await db.execute('ALTER TABLE vendor_transactions ADD COLUMN procurement_id INTEGER REFERENCES mandi_procurements(id) ON DELETE SET NULL');
    }
  }

  // 3. Stable link table between Mandi procurements and Vendor Khata transactions
  await db.execute('''CREATE TABLE IF NOT EXISTS procurement_vendor_links (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    procurement_id INTEGER NOT NULL REFERENCES mandi_procurements(id) ON DELETE CASCADE,
    vendor_transaction_id INTEGER NOT NULL REFERENCES vendor_transactions(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL,
    UNIQUE(procurement_id, vendor_transaction_id)
  )''');
  await db.execute('CREATE INDEX IF NOT EXISTS procurement_vendor_links_proc ON procurement_vendor_links(procurement_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS procurement_vendor_links_txn ON procurement_vendor_links(vendor_transaction_id)');

  // 4. Immutable append-only supplier receipt evidence table
  await db.execute('''CREATE TABLE IF NOT EXISTS supplier_receipt_evidence (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    vendor_id INTEGER NOT NULL REFERENCES vendor_khata(id) ON DELETE CASCADE,
    ingredient_id INTEGER REFERENCES raw_ingredients(id) ON DELETE SET NULL,
    procurement_id INTEGER REFERENCES mandi_procurements(id) ON DELETE SET NULL,
    vendor_transaction_id INTEGER REFERENCES vendor_transactions(id) ON DELETE SET NULL,
    promised_at TEXT,
    actual_at TEXT,
    recorded_at TEXT NOT NULL,
    recorded_by INTEGER NOT NULL REFERENCES staff(id),
    amendment_of INTEGER REFERENCES supplier_receipt_evidence(id),
    notes TEXT
  )''');

  await db.execute('CREATE INDEX IF NOT EXISTS supplier_receipt_evidence_vendor ON supplier_receipt_evidence(vendor_id, recorded_at)');
  await db.execute('CREATE INDEX IF NOT EXISTS supplier_receipt_evidence_amendment ON supplier_receipt_evidence(amendment_of)');
  await db.execute('CREATE INDEX IF NOT EXISTS supplier_receipt_evidence_proc ON supplier_receipt_evidence(procurement_id)');
  await db.execute('CREATE INDEX IF NOT EXISTS supplier_receipt_evidence_txn ON supplier_receipt_evidence(vendor_transaction_id)');

  // Triggers enforcing immutability: UPDATE and DELETE are rejected
  await db.execute("CREATE TRIGGER IF NOT EXISTS supplier_receipt_evidence_no_update BEFORE UPDATE ON supplier_receipt_evidence BEGIN SELECT RAISE(ABORT, 'Supplier receipt evidence is immutable'); END");
  await db.execute("CREATE TRIGGER IF NOT EXISTS supplier_receipt_evidence_no_delete BEFORE DELETE ON supplier_receipt_evidence BEGIN SELECT RAISE(ABORT, 'Supplier receipt evidence is immutable'); END");

  // Reporting identity snapshot triggers if reporting_identity_snapshots exists
  if (tables.contains('reporting_identity_snapshots')) {
    await db.execute('''CREATE TRIGGER IF NOT EXISTS reporting_name_supplier_receipt_evidence_recorded_by
      AFTER INSERT ON supplier_receipt_evidence WHEN NEW.recorded_by IS NOT NULL
      BEGIN INSERT INTO reporting_identity_snapshots
        (source_table,source_id,identity_kind,identity_table,identity_id,name_snapshot)
      VALUES('supplier_receipt_evidence',NEW.id,'recorded_by','staff',NEW.recorded_by,
        (SELECT name FROM staff WHERE id=NEW.recorded_by)); END''');

    await db.execute('''CREATE TRIGGER IF NOT EXISTS reporting_name_supplier_receipt_evidence_supplier
      AFTER INSERT ON supplier_receipt_evidence WHEN NEW.vendor_id IS NOT NULL
      BEGIN INSERT INTO reporting_identity_snapshots
        (source_table,source_id,identity_kind,identity_table,identity_id,name_snapshot)
      VALUES('supplier_receipt_evidence',NEW.id,'supplier','vendor_khata',NEW.vendor_id,
        (SELECT name FROM vendor_khata WHERE id=NEW.vendor_id)); END''');
  }
}
