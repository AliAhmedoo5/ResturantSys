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

  test('reports delivery timing, late SLA, final outcomes and unsettled COD aging (ADR-0022)', () async {
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
    final menuItem = await catalog.createMenuItem(categoryId: category.id, name: 'Beef Burger', basePrice: 600);
    await publishFixtures(catalog);

    // Setup delivery areas
    final areaAId = await db.insert('delivery_areas', {
      'name': 'Area Fast',
      'delivery_fee_paisa': 10000,
      'target_eta_minutes': 30, // 30 min SLA
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
    final areaBId = await db.insert('delivery_areas', {
      'name': 'Area Fallback',
      'delivery_fee_paisa': 15000,
      'target_eta_minutes': null, // Fallback SLA 45 min
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    final orderController = OrderAndCheckoutController(database: db);

    // Order 1: Area Fast (30 min SLA). Confirmed 12:00, Dispatched 12:10, Delivered 12:25 (elapsed 25m <= 30m -> On-Time)
    final o1 = (await orderController.checkoutOrder(
      commandId: 'del-1',
      businessDayId: bDay.id,
      shiftId: shift.id,
      cashierId: 2,
      diningType: DiningType.delivery,
      items: [CartItem(menuItem: await catalog.getMenuItem(menuItem.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 600)],
    )).order;
    await db.update('orders', {
      'created_at': '2026-10-31T12:00:00+05:00',
      'delivery_area_id': areaAId,
      'delivery_area_name_snapshot': 'Area Fast',
    }, where: 'id = ?', whereArgs: [o1.id]);

    // Order 2: Area Fast (30 min SLA). Confirmed 12:00, Dispatched 12:10, Delivered 12:40 (elapsed 40m > 30m -> Late)
    final o2 = (await orderController.checkoutOrder(
      commandId: 'del-2',
      businessDayId: bDay.id,
      shiftId: shift.id,
      cashierId: 2,
      diningType: DiningType.delivery,
      items: [CartItem(menuItem: await catalog.getMenuItem(menuItem.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 600)],
    )).order;
    await db.update('orders', {
      'created_at': '2026-10-31T12:00:00+05:00',
      'delivery_area_id': areaAId,
      'delivery_area_name_snapshot': 'Area Fast',
    }, where: 'id = ?', whereArgs: [o2.id]);

    // Order 3: Reattempt order. Dispatched trip 1 -> returned. Dispatched trip 2 -> delivered.
    // Unique orders = 1, reattempts = 1, final failure = 0.
    final o3 = (await orderController.checkoutOrder(
      commandId: 'del-3',
      businessDayId: bDay.id,
      shiftId: shift.id,
      cashierId: 2,
      diningType: DiningType.delivery,
      items: [CartItem(menuItem: await catalog.getMenuItem(menuItem.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 600)],
    )).order;
    await db.update('orders', {
      'created_at': '2026-10-31T12:00:00+05:00',
      'delivery_area_id': areaBId,
      'delivery_area_name_snapshot': 'Area Fallback',
    }, where: 'id = ?', whereArgs: [o3.id]);

    // Order 4: Final failure. Dispatched, returned, customer canceled undelivered.
    final o4 = (await orderController.checkoutOrder(
      commandId: 'del-4',
      businessDayId: bDay.id,
      shiftId: shift.id,
      cashierId: 2,
      diningType: DiningType.delivery,
      items: [CartItem(menuItem: await catalog.getMenuItem(menuItem.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 600)],
    )).order;
    await db.update('orders', {
      'created_at': '2026-10-31T12:00:00+05:00',
      'delivery_area_id': areaAId,
      'delivery_area_name_snapshot': 'Area Fast',
      'payment_status': 'CANCELLED',
    }, where: 'id = ?', whereArgs: [o4.id]);

    // Order 5: Out of order sequence (delivered_at before dispatched_at)
    final o5 = (await orderController.checkoutOrder(
      commandId: 'del-5',
      businessDayId: bDay.id,
      shiftId: shift.id,
      cashierId: 2,
      diningType: DiningType.delivery,
      items: [CartItem(menuItem: await catalog.getMenuItem(menuItem.id))],
      payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 600)],
    )).order;
    await db.update('orders', {
      'created_at': '2026-10-31T12:00:00+05:00',
      'delivery_area_id': areaAId,
      'delivery_area_name_snapshot': 'Area Fast',
    }, where: 'id = ?', whereArgs: [o5.id]);

    // Setup trips and attempts
    final trip1Id = await db.insert('rider_trips', {
      'trip_name': 'Trip 1',
      'rider_staff_id': 2,
      'shift_id': shift.id,
      'business_day_id': bDay.id,
      'status': 'RETURNED',
      'cash_expected_paisa': 60000,
      'cash_collected_paisa': 0,
      'dispatched_at': '2026-10-31T12:10:00+05:00',
      'returned_at': '2026-10-31T12:45:00+05:00',
      'created_at': '2026-10-31T12:10:00+05:00',
    });

    // Attempt for o1 (On-time, travel 15m)
    await db.insert('rider_trip_orders', {
      'trip_id': trip1Id,
      'order_id': o1.id,
      'status': 'DELIVERED',
      'assigned_at': '2026-10-31T12:10:00+05:00',
      'delivered_at': '2026-10-31T12:25:00+05:00',
    });

    // Attempt for o2 (Late, travel 30m)
    await db.insert('rider_trip_orders', {
      'trip_id': trip1Id,
      'order_id': o2.id,
      'status': 'DELIVERED',
      'assigned_at': '2026-10-31T12:10:00+05:00',
      'delivered_at': '2026-10-31T12:40:00+05:00',
    });

    // Attempt 1 for o3 (Returned)
    await db.insert('rider_trip_orders', {
      'trip_id': trip1Id,
      'order_id': o3.id,
      'status': 'RETURNED',
      'assigned_at': '2026-10-31T12:10:00+05:00',
      'returned_at': '2026-10-31T12:45:00+05:00',
    });

    // Attempt for o4 (Returned final failure)
    await db.insert('rider_trip_orders', {
      'trip_id': trip1Id,
      'order_id': o4.id,
      'status': 'RETURNED',
      'assigned_at': '2026-10-31T12:10:00+05:00',
      'returned_at': '2026-10-31T12:45:00+05:00',
      'notes': 'CANCELLED_UNDELIVERED',
    });

    // Attempt for o5 (Invalid sequence)
    await db.insert('rider_trip_orders', {
      'trip_id': trip1Id,
      'order_id': o5.id,
      'status': 'DELIVERED',
      'assigned_at': '2026-10-31T12:10:00+05:00',
      'delivered_at': '2026-10-31T12:05:00+05:00', // Before dispatch!
    });

    // Trip 2: redelivery for o3
    final trip2Id = await db.insert('rider_trips', {
      'trip_name': 'Trip 2',
      'rider_staff_id': 2,
      'shift_id': shift.id,
      'business_day_id': bDay.id,
      'status': 'RETURNED',
      'cash_expected_paisa': 60000,
      'cash_collected_paisa': 0,
      'dispatched_at': '2026-10-31T13:00:00+05:00',
      'returned_at': '2026-10-31T13:30:00+05:00',
      'created_at': '2026-10-31T13:00:00+05:00',
    });
    // Attempt 2 for o3 (Delivered)
    await db.insert('rider_trip_orders', {
      'trip_id': trip2Id,
      'order_id': o3.id,
      'status': 'DELIVERED',
      'assigned_at': '2026-10-31T13:00:00+05:00',
      'delivered_at': '2026-10-31T13:20:00+05:00',
    });

    // COD Aging Trips setup:
    // Trip A: shift is still OPEN -> Current Shift aging band
    // Trip 1 above is in shift (currently OPEN), expected cash 60000.

    // Trip B: shift was closed, returned 5 hours ago -> Overdue 0-24h
    final closedShift1 = await shifts.openShift(staffId: 2, openingFloat: 0, openedAt: DateTime.now().subtract(const Duration(hours: 10)));
    await shifts.closeShift(shiftId: closedShift1.id, staffId: 2, countedCash: 0);
    await db.insert('rider_trips', {
      'trip_name': 'Trip Overdue',
      'rider_staff_id': 2,
      'shift_id': closedShift1.id,
      'business_day_id': bDay.id,
      'status': 'RETURNED',
      'cash_expected_paisa': 25000,
      'cash_collected_paisa': 0,
      'dispatched_at': DateTime.now().subtract(const Duration(hours: 6)).toIso8601String(),
      'returned_at': DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
      'created_at': DateTime.now().subtract(const Duration(hours: 6)).toIso8601String(),
    });

    // Trip C: shift was closed, returned 36 hours ago -> Aged 1-3d
    final closedShift2 = await shifts.openShift(staffId: 2, openingFloat: 0, openedAt: DateTime.now().subtract(const Duration(hours: 48)));
    await shifts.closeShift(shiftId: closedShift2.id, staffId: 2, countedCash: 0);
    await db.insert('rider_trips', {
      'trip_name': 'Trip Aged',
      'rider_staff_id': 2,
      'shift_id': closedShift2.id,
      'business_day_id': bDay.id,
      'status': 'RETURNED',
      'cash_expected_paisa': 35000,
      'cash_collected_paisa': 0,
      'dispatched_at': DateTime.now().subtract(const Duration(hours: 38)).toIso8601String(),
      'returned_at': DateTime.now().subtract(const Duration(hours: 36)).toIso8601String(),
      'created_at': DateTime.now().subtract(const Duration(hours: 38)).toIso8601String(),
    });

    // Trip D: shift was closed, returned 80 hours ago -> Critical >3d
    final closedShift3 = await shifts.openShift(staffId: 2, openingFloat: 0, openedAt: DateTime.now().subtract(const Duration(hours: 90)));
    await shifts.closeShift(shiftId: closedShift3.id, staffId: 2, countedCash: 0);
    await db.insert('rider_trips', {
      'trip_name': 'Trip Critical',
      'rider_staff_id': 2,
      'shift_id': closedShift3.id,
      'business_day_id': bDay.id,
      'status': 'RETURNED',
      'cash_expected_paisa': 45000,
      'cash_collected_paisa': 0,
      'dispatched_at': DateTime.now().subtract(const Duration(hours: 85)).toIso8601String(),
      'returned_at': DateTime.now().subtract(const Duration(hours: 80)).toIso8601String(),
      'created_at': DateTime.now().subtract(const Duration(hours: 85)).toIso8601String(),
    });

    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2026, 10, 30), endDateExclusive: DateTime(2026, 11, 2));
    final snapshot = await service.load(query);

    final section = snapshot.section(AnalyticsFamily.delivery);

    // 1. Delivery timing & Late SLA
    final lateDeliveries = section.metrics.firstWhere((m) => m.id == 'late_deliveries');
    final lateDeliveryRate = section.metrics.firstWhere((m) => m.id == 'late_delivery_rate');
    expect(lateDeliveries.value, 1); // o2 is late (40m > 30m)
    expect(lateDeliveryRate.sampleCount, 1);
    expect(lateDeliveryRate.populationCount, 3); // 3 valid delivered orders (o1, o2, o3)

    // 2. Failure rate vs reattempts
    final finalFailures = section.metrics.firstWhere((m) => m.id == 'final_delivery_failures');
    final failureRate = section.metrics.firstWhere((m) => m.id == 'final_delivery_failure_rate');
    expect(finalFailures.value, 1); // o4 is final failure
    expect(failureRate.sampleCount, 1);
    expect(failureRate.populationCount, 5); // 5 unique attempted orders

    // 3. COD Aging bands
    final agingCurrentShift = section.metrics.firstWhere((m) => m.id == 'cod_aging_current_shift_paisa');
    final aging0to24h = section.metrics.firstWhere((m) => m.id == 'cod_aging_0_24h_paisa');
    final aging1to3d = section.metrics.firstWhere((m) => m.id == 'cod_aging_1_3d_paisa');
    final agingCritical = section.metrics.firstWhere((m) => m.id == 'cod_aging_critical_paisa');

    expect(agingCurrentShift.value, 120000); // trip1 (60000) + trip2 (60000)
    expect(aging0to24h.value, 25000);
    expect(aging1to3d.value, 35000);
    expect(agingCritical.value, 45000);

    // 4. Rows check: out of order sequence excluded from travel times
    final attemptRows = section.rows.where((r) => r.cells['kind'] == 'Delivery attempt').toList();
    final r5 = attemptRows.firstWhere((r) => r.cells['order_id'] == o5.id);
    expect(r5.cells['travel_minutes'], isNull);
    expect(r5.cells['delivery_quality'], 'Invalid sequence');
  });
}
