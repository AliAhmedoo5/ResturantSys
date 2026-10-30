import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import '../orders/order_and_checkout_controller_test.dart' show publishFixtures;

void main() {
  setUpAll(sqfliteFfiInit);
  test('open workload remains partial beside completed days and future hours are unavailable', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final auth = AuthService(database: db)..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    addTearDown(auth.session.dispose);
    final shifts = ShiftAndCashController(database: db);
    final previous = DateTime.now().subtract(const Duration(days: 1));
    final completed = await shifts.openBusinessDay(openedByStaffId: 1, openedAt: previous);
    final previousShift = await shifts.openShift(staffId: 2, openingFloat: 0, openedAt: previous);
    await shifts.closeShift(shiftId: previousShift.id, staffId: 2, countedCash: 0);
    await shifts.closeBusinessDay(closedByStaffId: 1);
    final open = await shifts.openBusinessDay(openedByStaffId: 1);
    final shift = await shifts.openShift(staffId: 2, openingFloat: 0);
    final catalog = CatalogAndRecipeController(database: db);
    final category = await catalog.createCategory(name: 'Partial workload', displayOrder: 1, colorHex: '#FFFFFF');
    final menu = await catalog.createMenuItem(categoryId: category.id, name: 'Partial tea', basePrice: 100);
    await publishFixtures(catalog);
    await OrderAndCheckoutController(database: db).checkoutOrder(commandId: 'partial-workload',
      businessDayId: open.id, shiftId: shift.id, cashierId: 2, diningType: DiningType.dineIn,
      items: [CartItem(menuItem: await catalog.getMenuItem(menu.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]);
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2100));
    final snapshot = await service.load(query);
    final section = snapshot.section(AnalyticsFamily.orders);
    final daily = section.rows.where((r) => r.cells['kind'] == 'Daily workload');
    final closed = daily.singleWhere((r) => r.cells['business_day_id'] == completed.id);
    final partial = daily.singleWhere((r) => r.cells['business_day_id'] == open.id);
    expect(closed.cells['period_complete'], isTrue);
    expect(partial.cells['period_complete'], isFalse);
    expect(partial.cells['period_status'], contains('Open Business Day'));
    expect(partial.cells['confirmed_orders'], 1);
    expect(partial.cells['count_rank'], isNull, reason: 'Open activity is not ranked against completed days');
    expect(closed.cells['count_rank'], 1);
    final partialPoint = section.charts.singleWhere((c) => c.id == 'workload_days').points.singleWhere((p) => p.rows.any((r) => r.sourceType == 'orders'));
    expect(partialPoint.label, contains('Incomplete'));
    expect(partialPoint.quality, AnalyticsQuality.estimated);
    final local = snapshot.generatedAt.toUtc().add(const Duration(hours: 5));
    final today = DateTime(local.year, local.month, local.day);
    final operationalDate = DateTime(open.openedAt.year, open.openedAt.month, open.openedAt.day);
    final active = await service.load(query.copyWith(startDate: operationalDate, endDateExclusive: operationalDate.add(const Duration(days: 1))));
    final nextHour = (local.hour + 1) % 24;
    final future = active.section(AnalyticsFamily.orders).rows.singleWhere((r) => r.cells['kind'] == 'Hourly workload' && r.cells['hour'] == nextHour);
    expect(future.cells['observed_confirmed_orders'], 0);
    expect(future.cells['confirmed_orders'], isNull);
    expect(future.cells['period_status'], contains('Not yet observed'));
    final calendar = await service.load(query.copyWith(timeBasis: AnalyticsTimeBasis.calendarTime,
      startDate: today, endDateExclusive: today.add(const Duration(days: 1))));
    final date = calendar.section(AnalyticsFamily.orders).rows.singleWhere((r) => r.cells['kind'] == 'Daily workload');
    expect(date.cells['period_complete'], isFalse);
    expect(date.cells['open_business_day_ids'], '${open.id}');
    expect(date.cells['period_status'], contains('Calendar'));
    expect(AnalyticsExportService().csv(calendar, AnalyticsFamily.orders), contains('period_complete'));
  });

  test('confirmed workload retains cancellation once and excludes Holds and revisions', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final auth = AuthService(database: db)..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    addTearDown(auth.session.dispose);
    final shifts = ShiftAndCashController(database: db);
    final day = await shifts.openBusinessDay(openedByStaffId: 1);
    final shift = await shifts.openShift(staffId: 2, openingFloat: 0);
    final catalog = CatalogAndRecipeController(database: db);
    final category = await catalog.createCategory(name: 'Workload', displayOrder: 1, colorHex: '#FFFFFF');
    final menu = await catalog.createMenuItem(categoryId: category.id, name: 'Workload tea', basePrice: 100);
    await publishFixtures(catalog);
    final line = CartItem(menuItem: await catalog.getMenuItem(menu.id));
    final controller = OrderAndCheckoutController(database: db);
    await controller.holdCart(cashierId: 2, label: 'Not confirmed', items: [line], diningType: DiningType.dineIn);
    final first = await controller.checkoutOrder(commandId: 'workload-1', businessDayId: day.id, shiftId: shift.id,
      cashierId: 2, diningType: DiningType.dineIn, items: [line],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]);
    await controller.checkoutOrder(commandId: 'workload-2', businessDayId: day.id, shiftId: shift.id,
      cashierId: 2, diningType: DiningType.dineIn, items: [line],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 100)]);
    await controller.cancelOrder(orderId: first.order.id, cashierId: 2, reason: 'Customer Cancelled', commandId: 'cancel-workload');
    await controller.recordCashierRefund(orderId: first.order.id, shiftId: shift.id, cashierId: 2,
      amountPaisa: 10000, method: PaymentMethod.cash, reason: 'Cancelled Order refund', commandId: 'workload-refund');
    final local = DateTime.now().toUtc().add(const Duration(hours: 5));
    final date = DateTime.utc(local.year, local.month, local.day);
    final snapshot = await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: date.subtract(const Duration(days: 1)), endDateExclusive: date.add(const Duration(days: 1))));
    final section = snapshot.section(AnalyticsFamily.orders);
    final daily = section.rows.singleWhere((r) => r.cells['kind'] == 'Daily workload');
    expect(daily.cells['confirmed_orders'], 2);
    expect(daily.cells['eligible_orders'], 1);
    expect(daily.cells['recorded_value_paisa'], 10000);
    expect(daily.cells['average_ticket_paisa'], 10000);
    expect(daily.cells['cancelled_orders'], 1);
    expect(daily.cells['order_ids'], '1,2');
    final hourly = section.rows.where((r) => r.cells['kind'] == 'Hourly workload').toList();
    expect(hourly, hasLength(24));
    expect(hourly.fold<int>(0, (sum, r) => sum + (r.cells['confirmed_orders'] as int)), 2);
    final chart = section.charts.singleWhere((c) => c.id == 'workload_hours');
    expect(chart.points.fold<num>(0, (sum, p) => sum + (p.value ?? 0)), 2);
    expect(chart.points.expand((p) => p.rows).map((r) => r.sourceId).toSet(), {'1', '2'});
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.orders);
    expect(csv, contains('Daily workload'));
    expect(csv, contains('Hourly workload'));
    expect(csv, contains('eligible_orders'));
    expect(() => daily.cells.clear(), throwsUnsupportedError);
  });
  test('count/value peaks retain chronological ties, same-date days and overnight calendar scope', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final auth = AuthService(database: db)..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    addTearDown(auth.session.dispose);
    // Historical import fixtures retain original timestamps; live domain commands
    // above cover confirmation/cancellation/refund semantics without rewriting time.
    final days = <int>[];
    final shifts = <int>[];
    for (final opening in ['2026-10-29T08:00:00+05:00', '2026-10-29T18:00:00+05:00', '2026-10-30T08:00:00+05:00']) {
      final day = await db.insert('business_days', {'opened_at': opening, 'status': 'OPEN', 'opened_by_staff_id': 1});
      days.add(day);
      shifts.add(await db.insert('shifts', {'business_day_id': day, 'staff_id': 2,
        'opened_at': opening, 'opening_float': 0, 'status': 'OPEN'}));
    }
    Future<int> order(int index, int token, int amount, String at) => db.insert('orders', {
      'business_day_id': days[index], 'shift_id': shifts[index], 'cashier_id': 2,
      'token_number': token, 'dining_type': 'TAKEAWAY', 'subtotal': amount,
      'grand_total': amount, 'payment_status': 'SETTLED', 'created_at': at,
    });
    await order(0, 1, 10, '2026-10-29T10:00:00+05:00');
    await order(0, 2, 10, '2026-10-29T10:30:00+05:00');
    await order(1, 1, 500, '2026-10-29T20:00:00Z'); // 30 Oct 01:00 Karachi
    await order(2, 1, 10, '2026-10-30T11:00:00+05:00');
    await order(2, 2, 10, '2026-10-30T11:30:00+05:00');
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2026, 10, 29), endDateExclusive: DateTime(2026, 10, 31));
    final snapshot = await service.load(query);
    final section = snapshot.section(AnalyticsFamily.orders);
    final daily = section.rows.where((r) => r.cells['kind'] == 'Daily workload').toList();
    expect(daily.map((r) => r.cells['business_day_id']), days);
    expect(daily.map((r) => r.cells['confirmed_orders']), [2, 1, 2]);
    expect(daily.map((r) => r.cells['count_peak']), [true, false, true]);
    expect(daily.map((r) => r.cells['value_peak']), [false, true, false]);
    final count = section.charts.singleWhere((c) => c.id == 'workload_days');
    expect(count.points.map((p) => p.label), ['2026-10-29 · Business Day #${days[0]}',
      '2026-10-30 · Business Day #${days[2]}', '2026-10-29 · Business Day #${days[1]}']);
    expect(count.points.map((p) => p.value), [2, 2, 1]);
    final value = section.charts.singleWhere((c) => c.id == 'value_days');
    expect(value.points.map((p) => p.value), [50000, 2000, 2000]);
    expect(value.points.first.rows.map((r) => r.sourceId), ['3']);
    final hours = section.charts.singleWhere((c) => c.id == 'workload_hours');
    expect(hours.points.take(2).map((p) => p.label), ['10:00', '11:00']);
    final hourValue = section.charts.singleWhere((c) => c.id == 'value_hours');
    expect(hourValue.points.first.label, '01:00');
    expect(hourValue.points.first.value, 50000);
    final calendar = await service.load(query.copyWith(timeBasis: AnalyticsTimeBasis.calendarTime));
    final calendarRows = calendar.section(AnalyticsFamily.orders).rows.where((r) => r.cells['kind'] == 'Daily workload').toList();
    expect(calendarRows.map((r) => r.cells['period']), ['2026-10-29', '2026-10-30']);
    expect(calendarRows.map((r) => r.cells['confirmed_orders']), [2, 3]);
    expect(calendarRows.map((r) => r.cells['recorded_value_paisa']), [2000, 52000]);
    expect(calendar.section(AnalyticsFamily.orders).charts.singleWhere((c) => c.id == 'workload_days').points.first.value, 3);
    final empty = await service.load(query.copyWith(startDate: DateTime(2020, 1, 1), endDateExclusive: DateTime(2020, 1, 2)));
    final absentHours = empty.section(AnalyticsFamily.orders).rows.where((r) => r.cells['kind'] == 'Hourly workload');
    expect(absentHours, hasLength(24));
    expect(absentHours.every((r) => r.cells['confirmed_orders'] == null && r.cells['count_rank'] == null), isTrue);
    final zero = section.rows.singleWhere((r) => r.cells['kind'] == 'Hourly workload' && r.cells['hour'] == 0);
    expect(zero.cells['confirmed_orders'], 0);
    expect(zero.cells['coverage'], 'Observed selected Order cohort');
    final csv = AnalyticsExportService().csv(calendar, AnalyticsFamily.orders);
    expect(csv, contains('calendarTime'));
    expect(csv, contains('52000'));
  });
}
