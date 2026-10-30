import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/finance/operations_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import '../orders/order_and_checkout_controller_test.dart' show publishFixtures;

void main() {
  setUpAll(sqfliteFfiInit);
  test('actual-time money peaks retain tied outflows, signed net and immutable export contributors', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final people = await db.query('staff');
    final manager = people.firstWhere((p) => p['role'] != 'CASHIER');
    final managerId = manager['id'] as int;
    final shifts = ShiftAndCashController(database: db);
    await shifts.openBusinessDay(openedByStaffId: managerId, openedAt: DateTime(2026, 10, 25, 18));
    final operations = OperationsController(db);
    final category = await operations.saveCategory(managerId: managerId, name: 'Utilities');
    for (final hour in [1, 2]) {
      await operations.postExpense(managerId: managerId, categoryId: category,
        amountPaisa: 7000, description: 'Bank payment', source: FundingSource.bank,
        actualAt: DateTime.parse('2026-10-26T0$hour:00:00+05:00'),
        reason: 'Verified late entry', requestKey: 'bank-$hour');
    }
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2026, 10, 26), endDateExclusive: DateTime(2026, 10, 27), timeBasis: AnalyticsTimeBasis.calendarTime);
    final snapshot = await service.load(query);
    final section = snapshot.section(AnalyticsFamily.expenses);
    final hours = section.rows.where((r) => r.cells['kind'] == 'Hourly money flow' && r.cells['funding_stream'] == 'BANK').toList();
    final peaks = hours.where((r) => r.cells['outflow_peak'] == true).toList();
    expect(peaks.map((r) => r.cells['hour']), [1, 2]);
    expect(peaks.map((r) => r.cells['outflow_paisa']), [7000, 7000]);
    expect(peaks.map((r) => r.cells['net_paisa']), [-7000, -7000]);
    expect(peaks.every((r) => r.cells['least_net_rank'] == 1), isTrue);
    final day = section.rows.singleWhere((r) => r.cells['kind'] == 'Period money flow' && r.cells['funding_stream'] == 'BANK');
    expect(day.cells['inflow_paisa'], 0);
    expect(day.cells['outflow_paisa'], 14000);
    expect(day.cells['net_paisa'], -14000);
    expect(section.charts.any((c) => c.id == 'money_BANK_outflow_hours'), isTrue);
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.expenses);
    expect(csv, contains('Hourly money flow'));
    expect(csv, contains('least net rank'));
    expect(csv, contains('-14000'));
    final outside = await service.load(query.copyWith(startDate: DateTime(2026, 10, 26, 2, 0, 1)));
    expect(outside.section(AnalyticsFamily.expenses).rows.where((r) => r.cells['kind'] == 'Money flow contributor'), isEmpty);
    expect(day.cells['net_paisa'], -14000, reason: 'Earlier snapshot stays immutable');
  });
  test('receiving receipt and linked refund retain one effect outside original cohort with honest missing attribution', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    await db.update('staff', {'name': 'Cashier 03012345678'}, where: 'id=2');
    final shifts = ShiftAndCashController(database: db);
    final old = await shifts.openBusinessDay(openedByStaffId: 1, openedAt: DateTime.now().subtract(const Duration(days: 7)));
    final origin = await shifts.openShift(staffId: 2, openingFloat: 0);
    final catalog = CatalogAndRecipeController(database: db);
    final category = await catalog.createCategory(name: 'Flows', displayOrder: 1, colorHex: '#FFFFFF');
    final menu = await catalog.createMenuItem(categoryId: category.id, name: 'Tea', basePrice: 100);
    await publishFixtures(catalog);
    final orders = OrderAndCheckoutController(database: db);
    final order = await orders.checkoutOrder(commandId: 'flow-origin', businessDayId: old.id, shiftId: origin.id,
      cashierId: 2, diningType: DiningType.dineIn, items: [CartItem(menuItem: await catalog.getMenuItem(menu.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]);
    await orders.recordCashierRefund(orderId: order.order.id, shiftId: origin.id, cashierId: 2,
      amountPaisa: 5000, method: PaymentMethod.cash, reason: 'Partial refund', commandId: 'flow-old-refund');
    await shifts.closeShift(shiftId: origin.id, staffId: 2, countedCash: 50);
    await shifts.closeBusinessDay(closedByStaffId: 1);
    final receivingDay = await shifts.openBusinessDay(openedByStaffId: 1);
    final receiving = await shifts.openShift(staffId: 2, openingFloat: 0);
    final receiptId = await orders.recordCashierReceipt(orderId: order.order.id, shiftId: receiving.id, cashierId: 2,
      amountPaisa: 5000, method: PaymentMethod.cash, commandId: 'flow-receipt');
    final refund = await orders.recordCashierRefund(orderId: order.order.id, shiftId: receiving.id, cashierId: 2,
      amountPaisa: 2500, method: PaymentMethod.cash, reason: 'Partial return', commandId: 'flow-refund');
    final auth = AuthService(database: db)..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    addTearDown(auth.session.dispose);
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2100), live: true);
    final snapshot = await service.load(query);
    expect(snapshot.section(AnalyticsFamily.orders).rows.where((r) => r.sourceType == 'orders'), isEmpty);
    final section = snapshot.section(AnalyticsFamily.expenses);
    final period = section.rows.singleWhere((r) => r.cells['kind'] == 'Period money flow');
    expect(period.cells['inflow_paisa'], 5000);
    expect(period.cells['outflow_paisa'], 2500);
    expect(period.cells['net_paisa'], 2500);
    final contributors = section.rows.where((r) => r.cells['kind'] == 'Money flow contributor').toList();
    expect(contributors, hasLength(2));
    expect(contributors.singleWhere((r) => r.sourceId == '$receiptId').cells['originating_business_day_id'], old.id);
    expect(contributors.singleWhere((r) => r.cells['event_kind'] == 'REFUND').cells['movement_id'], refund.cashMovementId);
    expect(period.cells['contributing_business_day_ids'], '${receivingDay.id}');
    final chart = section.charts.singleWhere((c) => c.id == 'money_DRAWER_greatest_net_periods');
    expect(chart.points.single.rows.fold<int>(0, (sum, r) => sum + (r.cells['amount_paisa'] as int)), 2500);
    expect(chart.points.single.value, 2500);
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.expenses);
    expect(csv, isNot(contains('03012345678')), reason: 'Raw retained names require the same masking as identity projection names');
    final now = DateTime.now().toUtc().toIso8601String();
    for (final legacy in [(key: 'missing-shift', at: now, amount: 3000), (key: 'missing-time', at: null, amount: 3500)]) {
      await db.insert('payment_events', {'event_key': legacy.key, 'kind': 'RECEIPT', 'amount_paisa': legacy.amount,
        'payment_source': 'DRAWER', 'actual_at': legacy.at, 'recorded_at': now,
        'business_day_id': receivingDay.id, 'shift_id': legacy.at == null ? receiving.id : null, 'recorded_by': 2});
    }
    final legacy = await service.load(query);
    final gap = legacy.section(AnalyticsFamily.expenses).rows.singleWhere((r) => r.cells['kind'] == 'Money flow coverage');
    expect(gap.cells['unknown_receiving_events'], 1);
    expect(gap.cells['unknown_receiving_paisa'], 3000);
    expect(gap.cells['unknown_time_events'], 1);
    expect(legacy.section(AnalyticsFamily.expenses).rows.singleWhere((r) => r.cells['kind'] == 'Period money flow').cells['inflow_paisa'], 5000);
    expect(legacy.section(AnalyticsFamily.expenses).rows.where((r) => r.cells['kind'] == 'Money flow contributor'), hasLength(2));
  });
}
