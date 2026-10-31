import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
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

  test('reports observed preparation and ready times with percentiles and sample coverage (ADR-0022)', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);

    final auth = AuthService(database: db)
      ..session.login(Staff.fromMap((await db.query('staff', where: 'id=1')).single));
    addTearDown(auth.session.dispose);

    final shifts = ShiftAndCashController(database: db);
    final bDay = await shifts.openBusinessDay(openedByStaffId: 1);
    final shift = await shifts.openShift(staffId: 2, openingFloat: 0);

    final catalog = CatalogAndRecipeController(database: db);
    final category = await catalog.createCategory(name: 'Burgers', displayOrder: 1, colorHex: '#FFFFFF');
    final item = await catalog.createMenuItem(categoryId: category.id, name: 'Zinger Burger', basePrice: 500);
    await publishFixtures(catalog);

    final orderController = OrderAndCheckoutController(database: db);

    // 1. Order 1: confirmed at 12:00, ready at 12:15 -> 15 mins
    final o1 = (await orderController.checkoutOrder(
      commandId: 'order-1',
      businessDayId: bDay.id,
      shiftId: shift.id,
      cashierId: 2,
      diningType: DiningType.dineIn,
      items: [CartItem(menuItem: await catalog.getMenuItem(item.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 500)],
    )).order;
    await db.update('orders', {'created_at': '2026-10-31T12:00:00+05:00'}, where: 'id = ?', whereArgs: [o1.id]);
    await db.insert('order_status_events', {
      'order_id': o1.id,
      'cashier_id': 2,
      'from_status': 'PREPARING',
      'to_status': 'READY',
      'recorded_at': '2026-10-31T12:15:00+05:00',
    });

    // 2. Order 2: confirmed at 12:00, ready at 12:25 -> 25 mins
    final o2 = (await orderController.checkoutOrder(
      commandId: 'order-2',
      businessDayId: bDay.id,
      shiftId: shift.id,
      cashierId: 2,
      diningType: DiningType.dineIn,
      items: [CartItem(menuItem: await catalog.getMenuItem(item.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 500)],
    )).order;
    await db.update('orders', {'created_at': '2026-10-31T12:00:00+05:00'}, where: 'id = ?', whereArgs: [o2.id]);
    await db.insert('order_status_events', {
      'order_id': o2.id,
      'cashier_id': 2,
      'from_status': 'PREPARING',
      'to_status': 'READY',
      'recorded_at': '2026-10-31T12:25:00+05:00',
    });

    // 3. Order 3 (rework): confirmed at 12:00, ready at 12:10, then back to PREPARING at 12:12, then READY at 12:20
    // First READY milestone at 12:10 is preserved (10 mins); rework cycle is tracked.
    final o3 = (await orderController.checkoutOrder(
      commandId: 'order-3',
      businessDayId: bDay.id,
      shiftId: shift.id,
      cashierId: 2,
      diningType: DiningType.dineIn,
      items: [CartItem(menuItem: await catalog.getMenuItem(item.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 500)],
    )).order;
    await db.update('orders', {'created_at': '2026-10-31T12:00:00+05:00'}, where: 'id = ?', whereArgs: [o3.id]);
    await db.insert('order_status_events', {
      'order_id': o3.id,
      'cashier_id': 2,
      'from_status': 'PREPARING',
      'to_status': 'READY',
      'recorded_at': '2026-10-31T12:10:00+05:00',
    });
    await db.insert('order_status_events', {
      'order_id': o3.id,
      'cashier_id': 2,
      'from_status': 'READY',
      'to_status': 'PREPARING',
      'recorded_at': '2026-10-31T12:12:00+05:00',
    });
    await db.insert('order_status_events', {
      'order_id': o3.id,
      'cashier_id': 2,
      'from_status': 'PREPARING',
      'to_status': 'READY',
      'recorded_at': '2026-10-31T12:20:00+05:00',
    });

    // 4. Order 4: missing READY milestone
    final o4 = (await orderController.checkoutOrder(
      commandId: 'order-4',
      businessDayId: bDay.id,
      shiftId: shift.id,
      cashierId: 2,
      diningType: DiningType.dineIn,
      items: [CartItem(menuItem: await catalog.getMenuItem(item.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 500)],
    )).order;
    await db.update('orders', {'created_at': '2026-10-31T12:00:00+05:00'}, where: 'id = ?', whereArgs: [o4.id]);

    // 5. Order 5: out-of-order sequence (ready timestamp before confirmed timestamp)
    final o5 = (await orderController.checkoutOrder(
      commandId: 'order-5',
      businessDayId: bDay.id,
      shiftId: shift.id,
      cashierId: 2,
      diningType: DiningType.dineIn,
      items: [CartItem(menuItem: await catalog.getMenuItem(item.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 500)],
    )).order;
    await db.update('orders', {'created_at': '2026-10-31T12:00:00+05:00'}, where: 'id = ?', whereArgs: [o5.id]);
    await db.insert('order_status_events', {
      'order_id': o5.id,
      'cashier_id': 2,
      'from_status': 'PREPARING',
      'to_status': 'READY',
      'recorded_at': '2026-10-31T11:55:00+05:00', // 5 mins prior to confirmed!
    });

    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2026, 10, 30), endDateExclusive: DateTime(2026, 11, 2));
    final snapshot = await service.load(query);

    final section = snapshot.section(AnalyticsFamily.orders);

    // Verify preparation metrics
    final prepMedian = section.metrics.firstWhere((m) => m.id == 'prep_median');
    final prepP90 = section.metrics.firstWhere((m) => m.id == 'prep_p90');
    final prepCoverage = section.metrics.firstWhere((m) => m.id == 'prep_coverage');
    final reworkCycles = section.metrics.firstWhere((m) => m.id == 'rework_cycles');

    // Durations: [10.0, 15.0, 25.0]
    // Median (p50) of [10, 15, 25] is 15.0
    expect(prepMedian.value, 15.0);
    expect(prepMedian.unit, AnalyticsUnit.minutes);
    expect(prepMedian.sampleCount, 3);
    expect(prepMedian.populationCount, 5);

    // 90th percentile of [10, 15, 25]
    expect(prepP90.value, isNotNull);
    expect(prepP90.unit, AnalyticsUnit.minutes);

    // Sample coverage: 3 valid out of 5 confirmed orders = 60%
    expect(prepCoverage.sampleCount, 3);
    expect(prepCoverage.populationCount, 5);
    expect(prepCoverage.value, closeTo(60.0, 0.01));

    // Rework cycles: 1 rework transition
    expect(reworkCycles.value, 1);

    // Ensure blanket missing claim is replaced
    expect(section.metrics.any((m) => m.id == 'prep_time'), isFalse);

    // Check rows for prep duration and quality
    final orderRows = section.rows.where((r) => r.sourceType == 'orders').toList();
    final r1 = orderRows.firstWhere((r) => r.cells['order_id'] == o1.id);
    final r3 = orderRows.firstWhere((r) => r.cells['order_id'] == o3.id);
    final r4 = orderRows.firstWhere((r) => r.cells['order_id'] == o4.id);
    final r5 = orderRows.firstWhere((r) => r.cells['order_id'] == o5.id);

    expect(r1.cells['prep_duration_minutes'], 15.0);
    expect(r3.cells['prep_duration_minutes'], 10.0);
    expect(r3.cells['rework_cycles'], 1);
    expect(r4.cells['prep_duration_minutes'], isNull);
    expect(r4.cells['prep_quality'], 'Missing milestone');
    expect(r5.cells['prep_duration_minutes'], isNull);
    expect(r5.cells['prep_quality'], 'Invalid sequence');
  });
}
