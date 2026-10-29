import 'package:sqflite_common/sqlite_api.dart';

/// Insert-time identity evidence. Migration deliberately does not backfill names.
/// Triggers share the source write transaction and never update financial rows.
Future<void> createReportingIdentitySchema(DatabaseExecutor db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS reporting_identity_snapshots (
    source_table TEXT NOT NULL, source_id INTEGER NOT NULL,
    identity_kind TEXT NOT NULL, identity_table TEXT NOT NULL,
    identity_id INTEGER NOT NULL, name_snapshot TEXT,
    PRIMARY KEY(source_table,source_id,identity_kind))''');
  const identities = <String, Map<String, String>>{
    'business_days': {'opened_by': 'opened_by_staff_id'},
    'shifts': {'shift_owner': 'staff_id'},
    'orders': {'order_cashier': 'cashier_id'},
    'order_revisions': {'recorded_by': 'cashier_id'},
    'cash_movements': {'recorded_by': 'staff_id', 'approved_by': 'approved_by'},
    'vendor_transactions': {'recorded_by': 'staff_id', 'supplier': 'vendor_id'},
    'payroll_entries': {'recorded_by': 'manager_id', 'employee': 'employee_id'},
    'expense_entries': {'recorded_by': 'manager_id', 'category': 'category_id'},
    'payment_events': {'recorded_by': 'recorded_by', 'approved_by': 'approved_by'},
    'worked_hours': {'recorded_by': 'manager_id', 'employee': 'employee_id'},
  };
  final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
      .map((row) => row['name']).toSet();
  for (final source in identities.entries) {
    if (!tables.contains(source.key)) continue;
    final columns = (await db.rawQuery('PRAGMA table_info(${source.key})'))
        .map((row) => row['name']).toSet();
    for (final identity in source.value.entries) {
      if (!columns.contains(identity.value)) continue;
      final table = identity.key == 'supplier' ? 'vendor_khata'
          : identity.key == 'category' ? 'expense_categories' : 'staff';
      await db.execute('''CREATE TRIGGER IF NOT EXISTS reporting_name_${source.key}_${identity.key}
        AFTER INSERT ON ${source.key} WHEN NEW.${identity.value} IS NOT NULL
        BEGIN INSERT INTO reporting_identity_snapshots
          (source_table,source_id,identity_kind,identity_table,identity_id,name_snapshot)
        VALUES('${source.key}',NEW.id,'${identity.key}','$table',NEW.${identity.value},
          (SELECT name FROM $table WHERE id=NEW.${identity.value})); END''');
    }
  }
  for (final operation in ['UPDATE', 'DELETE']) {
    await db.execute("CREATE TRIGGER IF NOT EXISTS reporting_names_no_$operation BEFORE $operation ON reporting_identity_snapshots BEGIN SELECT RAISE(ABORT,'Historical identity evidence is immutable'); END");
  }
}
