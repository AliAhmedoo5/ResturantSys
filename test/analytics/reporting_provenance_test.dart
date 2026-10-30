import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/finance/operations_controller.dart';
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('authorized expense history retains actor and category names after renames', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final manager = (await db.query('staff', where: "role != 'CASHIER'")).first;
    final managerId = manager['id'] as int;
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    await ShiftAndCashController(database: db).openBusinessDay(openedByStaffId: managerId);
    final operations = OperationsController(db);
    final category = await operations.saveCategory(managerId: managerId, name: 'Electricity');
    final id = await operations.postExpense(managerId: managerId, categoryId: category,
      amountPaisa: 12000, description: 'Meter bill', source: FundingSource.bank,
      reason: 'Approved bill', requestKey: 'identity-expense');
    await db.update('staff', {'name': 'Renamed manager'}, where: 'id=?', whereArgs: [managerId]);
    await operations.saveCategory(managerId: managerId, id: category, name: 'Utilities');
    final snapshot = await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2040)));
    final row = snapshot.section(AnalyticsFamily.expenses).rows.singleWhere(
      (row) => row.sourceType == 'expense_entries' && row.sourceId == '$id');
    expect(row.cells['recorded_by_name_at_transaction'], manager['name']);
    expect(row.cells['recorded_by_name_current'], 'Renamed manager');
    expect(row.cells['category_name_at_transaction'], 'Electricity');
    expect(row.cells['category_name_current'], 'Utilities');
    expect(snapshot.sourceSchemaVersion, await db.getVersion());
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.expenses);
    expect(csv, contains('source_schema_version'));
    expect(csv, contains('recorded by name at transaction'));
    expect(csv, contains('Renamed manager'));
    auth.session.lock();
    await expectLater(AnalyticsService(database: db, authService: auth).load(snapshot.query), throwsStateError);
  });

  test('supplier history survives rename and archival while Shift owner stays distinct from recorder', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final manager = (await db.query('staff', where: "role != 'CASHIER'")).first;
    final cashier = (await db.query('staff', where: "role = 'CASHIER'")).first;
    final managerId = manager['id'] as int;
    final cashierId = cashier['id'] as int;
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: managerId);
    final shift = await shifts.openShift(staffId: cashierId, openingFloat: 1000);
    final vendors = VendorKhataController(database: db);
    final supplier = await vendors.createVendor(name: 'Original supplier', phone: '0000000000');
    final entry = await vendors.recordCreditDelivery(vendorId: supplier.id, amount: 100,
      staffId: managerId, requestKey: 'identity-credit');
    await vendors.updateVendor(id: supplier.id, name: 'Renamed supplier', phone: '0000000000');
    await vendors.setVendorArchived(supplier.id, true);
    final category = await OperationsController(db).saveCategory(managerId: managerId, name: 'Utilities');
    await OperationsController(db).postExpense(managerId: managerId, categoryId: category,
      amountPaisa: 100, description: 'Drawer expense', source: FundingSource.drawer,
      shiftId: shift.id, reason: 'Approved', requestKey: 'identity-drawer');
    await db.update('staff', {'name': 'Renamed cashier', 'is_active': 0}, where: 'id=?', whereArgs: [cashierId]);
    final snapshot = await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2040)));
    final vendorRow = snapshot.section(AnalyticsFamily.suppliers).rows.singleWhere(
      (row) => row.sourceType == 'vendor_transactions' && row.sourceId == '${entry.id}');
    expect(vendorRow.cells['supplier_name_at_transaction'], 'Original supplier');
    expect(vendorRow.cells['supplier_name_current'], 'Renamed supplier');
    final movement = snapshot.section(AnalyticsFamily.cash).rows.singleWhere((row) => row.sourceType == 'cash_movements');
    expect(movement.cells['shift_owner_id'], cashierId);
    expect(movement.cells['shift_owner_name_at_transaction'], cashier['name']);
    expect(movement.cells['shift_owner_name_current'], 'Renamed cashier');
    expect(movement.cells['recorded_by_id'], managerId);
    expect(movement.cells['shift_start_source'], isNotNull);
    expect(movement.cells['shift_start'], contains('Asia/Karachi'));
  });

  test('timestamp evidence crosses Karachi midnight without losing offset or naive assumption', () {
    expect(analyticsTimestamp('2026-10-29T19:30:00Z'), '2026-10-30 00:30:00 +05:00 [Asia/Karachi]');
    expect(analyticsTimestamp('2026-10-29T23:30:00+04:00'), '2026-10-30 00:30:00 +05:00 [Asia/Karachi]');
    expect(analyticsTimestamp('2026-10-30 00:30:00'), contains('assumed Asia/Karachi'));
    expect(analyticsTimestamp(null), isNull);
    expect(analyticsTimestamp('missing'), isNull);
  });
}
