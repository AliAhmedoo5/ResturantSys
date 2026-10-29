import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/khata/vendor_khata_controller.dart';
import 'package:resturant_sys/core/khata/vendor_payment_source.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/finance/operations_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('Manager finance timeline separates source, recorder and drawer owner without duplicate cash', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final people = await db.query('staff');
    final manager = people.firstWhere((p) => p['role'] != 'CASHIER');
    final cashier = people.firstWhere((p) => p['role'] == 'CASHIER');
    final managerId = manager['id'] as int;
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: managerId);
    final shift = await shifts.openShift(staffId: cashier['id'] as int, openingFloat: 1000);
    final operations = OperationsController(db);
    final category = await operations.saveCategory(managerId: managerId, name: 'Utilities');
    final id = await operations.postExpense(managerId: managerId, categoryId: category,
      amountPaisa: 12000, description: 'Electricity', source: FundingSource.drawer,
      shiftId: shift.id, reason: 'Paid', requestKey: 'drawer-expense');
    await operations.postExpense(managerId: managerId, categoryId: category,
      amountPaisa: 7000, description: 'Bank bill', source: FundingSource.bank,
      reason: 'Paid externally', requestKey: 'bank-expense');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final report = (await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2100), live: true)))
      .section(AnalyticsFamily.expenses);
    final events = report.rows.where((r) => r.cells['kind'] == 'Finance payment').toList();
    expect(events, hasLength(2));
    final drawer = events.singleWhere((r) => r.cells['payment_source'] == 'DRAWER');
    expect(drawer.cells['source_id'], id);
    expect(drawer.cells['recorded_by'], managerId);
    expect(drawer.cells['shift_owner_id'], cashier['id']);
    expect(drawer.cells['amount_paisa'], -12000);
    expect(drawer.cells['actual_at'], isNotNull);
    expect(drawer.cells['recorded_at'], isNotNull);
    expect(events.singleWhere((r) => r.cells['payment_source'] == 'BANK').cells['shift_id'], isNull);
    expect(report.metrics.singleWhere((m) => m.id == 'finance_drawer_outflow').value, 12000);
    expect(report.metrics.singleWhere((m) => m.id == 'finance_bank_outflow').value, 7000);
  });
  test('late bank payroll and owner supplier payments follow actual calendar time and exclude accrual', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final people = await db.query('staff');
    final manager = people.firstWhere((p) => p['role'] != 'CASHIER');
    final managerId = manager['id'] as int;
    final employee = people.firstWhere((p) => p['role'] == 'CASHIER')['id'] as int;
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: managerId, openedAt: DateTime(2026, 10, 25, 18));
    final actual = DateTime.parse('2026-10-26T01:00:00+05:00');
    final operations = OperationsController(db);
    await operations.setSalary(managerId: managerId, employeeId: employee,
      effectivePeriod: '2026-10', amountPaisa: 100000, reason: 'Agreed salary');
    await operations.postPayroll(managerId: managerId, employeeId: employee, period: '2026-10',
      kind: 'ACCRUAL', reason: 'October earned salary', requestKey: 'earned-october');
    await operations.postPayroll(managerId: managerId, employeeId: employee, period: '2026-10',
      kind: 'PAYMENT', amountPaisa: 3000, source: FundingSource.bank, actualAt: actual,
      reason: 'Late entry bank payment', requestKey: 'paid-october');
    final khata = VendorKhataController(database: db);
    final vendor = await khata.createVendor(name: 'Supplier', phone: '03001234567', openingBalance: 100);
    await khata.recordSettlementPayment(vendorId: vendor.id, amount: 50,
      paymentSource: VendorPaymentSource.owner, staffId: managerId, actualAt: actual,
      requestKey: 'supplier-owner-payment');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2026, 10, 26), endDateExclusive: DateTime(2026, 10, 27),
      timeBasis: AnalyticsTimeBasis.calendarTime);
    final snapshot = await service.load(query);
    final report = snapshot.section(AnalyticsFamily.expenses);
    final events = report.rows.where((r) => r.cells['kind'] == 'Finance payment').toList();
    expect(events, hasLength(2));
    expect(events.every((r) => r.cells['shift_id'] == null), isTrue);
    expect(events.every((r) => r.cells['actual_at'].toString().startsWith('2026-10-26 01:00:00') && r.cells['actual_at'].toString().contains('Asia/Karachi')), isTrue);
    expect(report.metrics.singleWhere((m) => m.id == 'finance_bank_outflow').value, 3000);
    expect(report.metrics.singleWhere((m) => m.id == 'finance_owner_outflow').value, 5000);
    final export = AnalyticsExportService().csv(snapshot, AnalyticsFamily.expenses);
    expect(export, contains('2026-10-26 01:00:00'));
    expect(export, contains('SUPPLIER_PAYMENT'));
    expect(export, isNot(contains('03001234567')));
    final previous = await service.load(query.copyWith(startDate: DateTime(2026, 10, 25), endDateExclusive: DateTime(2026, 10, 26)));
    expect(previous.section(AnalyticsFamily.expenses).rows.where((r) => r.cells['kind'] == 'Finance payment'), isEmpty);
  });

  test('invalid late finance entries leave no partial posting and closed-period correction stays unavailable', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final people = await db.query('staff');
    final manager = people.firstWhere((p) => p['role'] != 'CASHIER');
    final managerId = manager['id'] as int;
    final cashierId = people.firstWhere((p) => p['role'] == 'CASHIER')['id'] as int;
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: managerId, openedAt: DateTime(2026, 10, 25, 18));
    final shift = await shifts.openShift(staffId: cashierId, openingFloat: 1000, openedAt: DateTime(2026, 10, 25, 18));
    final operations = OperationsController(db);
    final category = await operations.saveCategory(managerId: managerId, name: 'Utilities');
    Future<int> pay(String request, DateTime actual) => operations.postExpense(
      managerId: managerId, categoryId: category, amountPaisa: 12000,
      description: 'Electricity', source: FundingSource.drawer, shiftId: shift.id,
      reason: 'Paid late', requestKey: request, actualAt: actual);
    final original = await pay('valid', DateTime.parse('2026-10-26T01:00:00+05:00'));
    expect(await pay('valid', DateTime.parse('2026-10-26T01:00:00+05:00')), original);
    await expectLater(pay('too-early', DateTime.parse('2026-10-24T01:00:00+05:00')), throwsStateError);
    await expectLater(pay('future', DateTime.now().toUtc().add(const Duration(days: 1))), throwsArgumentError);
    expect(await operations.expenses(managerId: managerId), hasLength(1));
    expect(await shifts.getCashMovements(shift.id), hasLength(1));
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final snapshot = await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: DateTime(2026, 10, 25), endDateExclusive: DateTime(2026, 10, 26)));
    expect(snapshot.section(AnalyticsFamily.expenses).rows.where((r) => r.cells['kind'] == 'Finance payment'), hasLength(1));
    await shifts.closeShift(shiftId: shift.id, staffId: cashierId, countedCash: 880);
    await shifts.closeBusinessDay(closedByStaffId: managerId);
    await shifts.openBusinessDay(openedByStaffId: managerId);
    await expectLater(operations.reverseExpense(managerId: managerId, entryId: original,
      reason: 'Historical correction', requestKey: 'closed-correction'), throwsStateError);
    expect(await operations.expenses(managerId: managerId), hasLength(1));
  });

}
