import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('supplier catalog, allocation, payroll and expense records persist', () async {
    final store = PosDatabase(factory: databaseFactoryFfi,
        customPath: inMemoryDatabasePath, seedDefaultStaff: false);
    final db = await store.initialize();
    addTearDown(store.close);
    final tables = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name']).toSet();
    expect(tables, containsAll([
      'supplier_items', 'supplier_payment_allocations', 'salary_rates',
      'payroll_entries', 'expense_categories', 'expense_entries', 'worked_hours',
    ]));
    final columns = (await db.rawQuery('PRAGMA table_info(vendor_transactions)'))
        .map((r) => r['name']);
    expect(columns, contains('due_date'));
  });
}
