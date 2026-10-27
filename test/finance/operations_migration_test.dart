import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('v18 migration preserves stock and reconstructs legacy opening/invoice allocations',() async {
    final directory=await Directory.systemTemp.createTemp('operations-migration-');
    final path='${directory.path}/legacy.db';
    final store=PosDatabase(factory:databaseFactoryFfi,customPath:path);
    var db=await store.initialize();
    addTearDown(() async {await store.close();await directory.delete(recursive:true);});
    // Reconstruct a v18 store by removing only the new additive schema before
    // inserting legacy-format records. No finance history exists at this point.
    for(final table in ['supplier_payment_allocations','supplier_items','salary_rates',
        'payroll_entries','expense_entries','expense_categories','operations_audit']) {
      await db.execute('DROP TABLE $table');
    }
    await db.execute('DROP INDEX supplier_request_key');
    for(final column in ['due_date','ingredient_name_snapshot','unit_snapshot','request_key','amount_paisa']) {
      await db.execute('ALTER TABLE vendor_transactions DROP COLUMN $column');
    }
    final vendor=await db.insert('vendor_khata',{'name':'Legacy supplier','phone':'1',
      'opening_balance':100.0,'current_balance':150.0,'created_at':'2026-10-01','updated_at':'2026-10-01'});
    final ingredient=await db.insert('raw_ingredients',{'name':'Legacy flour','storage_unit':'kg',
      'current_stock':5.0,'created_at':'2026-10-01'});
    final invoice=await db.insert('vendor_transactions',{'vendor_id':vendor,
      'type':'PURCHASE_CREDIT','amount':200.0,'raw_ingredient_id':ingredient,
      'quantity':5.0,'reference_slip':'OLD-1','created_at':'2026-10-01'});
    final payment=await db.insert('vendor_transactions',{'vendor_id':vendor,
      'type':'PAYMENT_EXTERNAL','amount':150.0,'created_at':'2026-10-02'});
    await db.setVersion(18);
    await store.close();
    db=await store.initialize();
    expect(await db.getVersion(),PosDatabaseConstants.schemaVersion);
    expect((await db.query('raw_ingredients',where:'id=?',whereArgs:[ingredient])).single['current_stock'],5.0);
    final khata=VendorKhataController(database:db);
    expect((await khata.suppliedItems(vendor)).single['id'],ingredient);
    final invoices=await khata.invoices(vendor);
    expect(invoices.single['id'],invoice);
    expect(invoices.single['due_date'],isNull);
    expect(invoices.single['due_paisa'],15000);
    final allocated=await db.query('supplier_payment_allocations',where:'payment_id=?',whereArgs:[payment],orderBy:'id');
    expect(allocated,hasLength(2));
    expect(allocated.first['invoice_id'],isNull);
    expect(allocated.first['amount_paisa'],10000);
    expect(allocated.last['amount_paisa'],5000);
    expect(await db.query('payroll_entries'),isEmpty);
    expect(await db.query('expense_entries'),isEmpty);
    expect(await db.rawQuery('PRAGMA foreign_key_check'),isEmpty);
    await store.close();
    db=await store.initialize();
    expect(await db.query('supplier_payment_allocations'),hasLength(2));
  });
}
