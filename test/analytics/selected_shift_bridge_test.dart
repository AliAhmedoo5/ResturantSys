import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/finance/operations_controller.dart';
import 'package:resturant_sys/core/shifts/cash_movement.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';
import 'package:resturant_sys/core/khata/vendor_payment_source.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('selected Shift reconciles each linked expense once and ignores order-only filters', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
    final cashier = staff.firstWhere((r) => r['role'] == 'CASHIER');
    final managerId = manager['id'] as int;
    final cashierId = cashier['id'] as int;
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: managerId);
    final earlier = await shifts.openShift(staffId: cashierId, openingFloat: 200);
    await shifts.closeShift(shiftId: earlier.id, staffId: cashierId, countedCash: 200);
    final selected = await shifts.openShift(staffId: cashierId, openingFloat: 1000);
    final operations = OperationsController(db);
    final category = await operations.saveCategory(managerId: managerId, name: 'Utilities');
    for (final request in ['bill-one', 'bill-two']) {
      await operations.postExpense(managerId: managerId, categoryId: category,
        amountPaisa: 12000, description: 'Same value distinct bills', source: FundingSource.drawer,
        shiftId: selected.id, reason: 'Paid', requestKey: request);
    }
    await operations.postExpense(managerId: managerId, categoryId: category,
      amountPaisa: 7000, description: 'Bank bill', source: FundingSource.bank,
      reason: 'Paid externally', requestKey: 'external');
    await shifts.recordCashMovement(shiftId: selected.id, staffId: cashierId,
      type: CashMovementType.payIn, amount: 50, category: 'General 03001234567', notes: 'Private note');
    await operations.setSalary(managerId: managerId, employeeId: cashierId, effectivePeriod: '2026-10', amountPaisa: 100000, reason: 'Salary');
    await operations.postPayroll(managerId: managerId, employeeId: cashierId, period: '2026-10',
      kind: 'ADVANCE', amountPaisa: 3000, source: FundingSource.drawer,
      shiftId: selected.id, reason: 'Advance', requestKey: 'advance');
    final khata = VendorKhataController(database: db);
    final vendor = await khata.createVendor(name: 'Supplier', phone: '', openingBalance: 100);
    await khata.recordSettlementPayment(vendorId: vendor.id, amount: 20,
      paymentSource: VendorPaymentSource.paidFromActiveDrawer, staffId: managerId,
      shiftId: selected.id, requestKey: 'supplier-payment');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2100),
      live: true, shiftId: selected.id, cashierId: cashierId,
      diningType: 'DELIVERY', paymentMethod: 'CARD');
    final snapshot = await service.load(query);
    final report = snapshot.section(AnalyticsFamily.cash);
    num? value(String id) => report.metrics.singleWhere((m) => m.id == id).value;
    expect(value('opening_float'), 100000);
    expect(value('expected_drawer'), 76000);
    expect(value('variance'), isNull);
    expect(value('cash_expenses'), 24000);
    expect(value('cash_payroll_advances'), 3000);
    expect(value('cash_supplier_payments'), 2000);
    expect(report.rows.where((r) => r.cells['kind'] == 'Shift reconciliation'), hasLength(1));
    final effects = report.rows.where((r) => r.cells['kind'] == 'Physical cash effect');
    expect(effects.map((r) => r.cells['amount_paisa']), unorderedEquals([-12000, -12000, 5000, -3000, -2000]));
    expect(effects.where((r) => r.cells['component'] == 'expenses').every(
      (r) => r.cells['recorded_by_id'] == managerId && r.cells['shift_owner_id'] == cashierId), isTrue);
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.cash);
    expect(csv, contains('Physical cash effect'));
    expect(csv, contains('76000'));
    expect(csv, isNot(contains('03001234567')));
    expect(csv, isNot(contains('Private note')));
    await shifts.closeShift(shiftId: selected.id, staffId: cashierId, countedCash: 750);
    final closed = (await service.load(query)).section(AnalyticsFamily.cash);
    expect(closed.metrics.singleWhere((m) => m.id == 'variance').value, -1000);
    expect(value('variance'), isNull, reason: 'Earlier snapshot remains immutable');
  });

  test('unlinked historical lookalikes remain separate evidence and withhold complete cash', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
    final cashierId = staff.firstWhere((r) => r['role'] == 'CASHIER')['id'] as int;
    final shifts = ShiftAndCashController(database: db);
    final day = await shifts.openBusinessDay(openedByStaffId: manager['id'] as int);
    final shift = await shifts.openShift(staffId: cashierId, openingFloat: 100);
    // Imported historical records intentionally have no receiving-event link.
    final order = await db.insert('orders', {'business_day_id': day.id, 'shift_id': shift.id,
      'cashier_id': cashierId, 'token_number': 1, 'dining_type': 'TAKEAWAY',
      'subtotal': 100, 'grand_total': 100, 'payment_status': 'SETTLED',
      'created_at': DateTime.now().toUtc().toIso8601String()});
    for (var i = 0; i < 2; i++) {
      await db.insert('order_payments', {'order_id': order, 'payment_method': 'CASH',
        'amount_tendered': 50, 'change_returned': 0});
      await shifts.recordCashMovement(shiftId: shift.id, staffId: cashierId,
        type: CashMovementType.payIn, amount: 50, category: 'General', notes: 'Distinct physical entry');
    }
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final snapshot = await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2100), shiftId: shift.id));
    final cash = snapshot.section(AnalyticsFamily.cash);
    expect(cash.rows.where((r) => r.cells['kind'] == 'Cash coverage gap'), hasLength(2));
    expect(cash.rows.where((r) => r.cells['kind'] == 'Physical cash effect'), hasLength(2));
    expect(cash.metrics.singleWhere((m) => m.id == 'evidenced_balance').value, 20000);
    expect(cash.metrics.singleWhere((m) => m.id == 'expected_drawer').value, isNull);
    expect(cash.metrics.singleWhere((m) => m.id == 'expected_drawer').quality, AnalyticsQuality.missing);
    expect(cash.charts.singleWhere((c) => c.id == 'shift_cash').points.first.value, isNull);
    expect(AnalyticsExportService().csv(snapshot, AnalyticsFamily.cash), contains('Receiving Shift and actual time unavailable'));
  });
}

