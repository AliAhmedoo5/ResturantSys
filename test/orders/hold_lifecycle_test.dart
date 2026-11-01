import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/catalog/catalog_and_recipe_controller.dart';
import 'package:resturant_sys/core/catalog/storage_unit.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/database/pos_database_constants.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/payment_method.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('Ticket #77: Hold lifecycle persistence and immutability', () {
    late PosDatabase store;
    late Database db;
    late OrderAndCheckoutController orders;
    late ShiftAndCashController shifts;
    late CatalogAndRecipeController catalog;
    late CartItem testItem;

    setUp(() async {
      store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      db = await store.initialize();
      orders = OrderAndCheckoutController(database: db);
      shifts = ShiftAndCashController(database: db);
      catalog = CatalogAndRecipeController(database: db);
      final category = await catalog.createCategory(
        name: 'Main',
        displayOrder: 1,
        colorHex: '#FF0000',
      );
      final menuItem = await catalog.createMenuItem(categoryId: category.id, name: 'Burger', basePrice: 500);
      final ingredient = await catalog.createRawIngredient(name: 'Fixture ingredient', storageUnit: StorageUnit.count, currentStock: 1000);
      await catalog.setRecipeForMenuItem(menuItemId: menuItem.id, items: [(rawIngredientId: ingredient.id, quantity: 1.0)]);
      await catalog.toggleMenuItemActive(menuItem.id, true);
      testItem = CartItem(menuItem: await catalog.getMenuItem(menuItem.id));
    });

    tearDown(() => store.close());

    test('hold_lifecycle_events table is created at schema v29+ and is immutable', () async {
      expect(PosDatabaseConstants.schemaVersion, greaterThanOrEqualTo(29));
      final userVersion = (await db.rawQuery('PRAGMA user_version')).single.values.first;
      expect(userVersion, PosDatabaseConstants.schemaVersion);

      final tableInfo = await db.rawQuery("PRAGMA table_info('hold_lifecycle_events')");
      expect(tableInfo, isNotEmpty);
      final columns = tableInfo.map((c) => c['name']).toSet();
      expect(columns, containsAll(['id', 'hold_id', 'cashier_id', 'event_type', 'order_id', 'previous_hold_id', 'label', 'payload', 'recorded_at']));

      // Direct insert
      await db.insert('hold_lifecycle_events', {
        'hold_id': 100,
        'cashier_id': 2,
        'event_type': 'CREATED',
        'order_id': null,
        'previous_hold_id': null,
        'label': 'Test Hold',
        'payload': '{}',
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      });

      // UPDATE trigger check
      expect(
        () => db.update('hold_lifecycle_events', {'label': 'Modified'}, where: 'hold_id = ?', whereArgs: [100]),
        throwsA(isA<DatabaseException>().having((e) => e.toString(), 'message', contains('Hold lifecycle events are immutable'))),
      );

      // DELETE trigger check
      expect(
        () => db.delete('hold_lifecycle_events', where: 'hold_id = ?', whereArgs: [100]),
        throwsA(isA<DatabaseException>().having((e) => e.toString(), 'message', contains('Hold lifecycle events are immutable'))),
      );
    });

    test('database upgrading from v28 to v29 creates hold_lifecycle_events table and triggers', () async {
      await db.execute('DROP TABLE IF EXISTS hold_lifecycle_events');
      await db.execute('DROP TRIGGER IF EXISTS hold_lifecycle_events_no_update');
      await db.execute('DROP TRIGGER IF EXISTS hold_lifecycle_events_no_delete');
      await db.setVersion(28);
      await store.close();

      store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      db = await store.initialize();

      expect(await db.getVersion(), 29);
      final tableInfo = await db.rawQuery("PRAGMA table_info('hold_lifecycle_events')");
      expect(tableInfo, isNotEmpty);
    });

    test('holdCart, recallHold, replace, removeHold and checkout record lifecycle events atomically', () async {
      final line = testItem;
      final day = await shifts.openBusinessDay(openedByStaffId: 1);
      final shift = await shifts.openShift(staffId: 2, openingFloat: 1000);

      // 1. Initial holdCart -> CREATED
      final hold1 = await orders.holdCart(
        cashierId: 2,
        label: 'VIP Table 1',
        items: [line],
        diningType: DiningType.dineIn,
      );

      var events = await db.query('hold_lifecycle_events', orderBy: 'id ASC');
      expect(events, hasLength(1));
      expect(events.last['event_type'], 'CREATED');
      expect(events.last['hold_id'], hold1);
      expect(events.last['cashier_id'], 2);
      expect(events.last['label'], 'VIP Table 1');
      expect(events.last['order_id'], isNull);
      expect(events.last['previous_hold_id'], isNull);

      // 2. Recall hold -> RECALLED
      final recalledData = await orders.recallHold(2, hold1);
      expect(recalledData['id'], hold1);
      events = await db.query('hold_lifecycle_events', orderBy: 'id ASC');
      expect(events, hasLength(2));
      expect(events.last['event_type'], 'RECALLED');
      expect(events.last['hold_id'], hold1);
      expect(events.last['cashier_id'], 2);

      // 3. Re-hold with previousHoldId -> REPLACED for old hold, CREATED for new hold
      final hold2 = await orders.holdCart(
        cashierId: 2,
        label: 'VIP Table 1 (Updated)',
        items: [line.copyWith(quantity: 2)],
        diningType: DiningType.dineIn,
        previousHoldId: hold1,
      );

      events = await db.query('hold_lifecycle_events', orderBy: 'id ASC');
      expect(events, hasLength(4));
      // CREATED for hold2 links to previousHoldId
      final createdHold2 = events.firstWhere((e) => e['hold_id'] == hold2 && e['event_type'] == 'CREATED');
      expect(createdHold2['previous_hold_id'], hold1);
      // REPLACED for hold1 links to successor hold2 (not self-referential)
      final replacedHold1 = events.firstWhere((e) => e['hold_id'] == hold1 && e['event_type'] == 'REPLACED');
      expect(replacedHold1['previous_hold_id'], hold2);
      expect(replacedHold1['previous_hold_id'], isNot(hold1));

      // Old hold is removed from active held_carts
      final activeHolds = await orders.getHolds(2);
      expect(activeHolds.any((h) => h['id'] == hold1), isFalse);
      expect(activeHolds.any((h) => h['id'] == hold2), isTrue);

      // 4. Remove another hold -> DISCARDED
      final holdToDiscard = await orders.holdCart(
        cashierId: 2,
        label: 'Discardable Draft',
        items: [line],
        diningType: DiningType.takeaway,
      );
      await orders.removeHold(2, holdToDiscard);
      events = await db.query('hold_lifecycle_events', orderBy: 'id ASC');
      final discardEvent = events.last;
      expect(discardEvent['event_type'], 'DISCARDED');
      expect(discardEvent['hold_id'], holdToDiscard);
      expect(discardEvent['cashier_id'], 2);

      // 5. Checkout held cart -> CONVERTED linking to order_id without allocating extra tokens or orders
      final initialOrders = await db.query('orders');
      final checkoutResult = await orders.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.dineIn,
        items: [line.copyWith(quantity: 2)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 1000)],
        heldCartId: hold2,
      );

      final finalOrders = await db.query('orders');
      expect(finalOrders.length, initialOrders.length + 1);

      events = await db.query('hold_lifecycle_events', orderBy: 'id ASC');
      final convertEvent = events.last;
      expect(convertEvent['event_type'], 'CONVERTED');
      expect(convertEvent['hold_id'], hold2);
      expect(convertEvent['order_id'], checkoutResult.order.id);
      expect(convertEvent['cashier_id'], 2);

      // Held cart was deleted from active holds
      expect(await orders.getHolds(2), isEmpty);
    });

    test('Manager reports historical hold lifecycle counts and ages from observed events with privacy protection', () async {
      final line = testItem;
      final day = await shifts.openBusinessDay(openedByStaffId: 1);
      final shift = await shifts.openShift(staffId: 2, openingFloat: 1000);

      // Create hold, recall, replace, discard, convert
      final holdA = await orders.holdCart(
        cashierId: 2,
        label: 'Private Customer 03009999999',
        items: [line],
        diningType: DiningType.takeaway,
      );
      await orders.recallHold(2, holdA);
      final holdB = await orders.holdCart(
        cashierId: 2,
        label: 'Private Customer 03009999999 Updated',
        items: [line.copyWith(quantity: 2)],
        diningType: DiningType.takeaway,
        previousHoldId: holdA,
      );
      final discardHold = await orders.holdCart(
        cashierId: 2,
        label: 'Will Discard Secret',
        items: [line],
        diningType: DiningType.dineIn,
      );
      await orders.removeHold(2, discardHold);

      await orders.checkoutOrder(
        businessDayId: day.id,
        shiftId: shift.id,
        cashierId: 2,
        diningType: DiningType.takeaway,
        items: [line.copyWith(quantity: 2)],
        payments: [const PaymentTender(method: PaymentMethod.cash, amountTendered: 1000)],
        heldCartId: holdB,
      );

      final manager = (await db.query('staff', where: 'id=1')).single;
      final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
      final service = AnalyticsService(database: db, authService: auth);

      // Query covering today
      final query = AnalyticsQuery(
        startDate: DateTime.now().subtract(const Duration(days: 1)),
        endDateExclusive: DateTime.now().add(const Duration(days: 1)),
      );
      final snapshot = await service.load(query);
      final report = snapshot.section(AnalyticsFamily.orders);

      // Active holds should be 0 now
      expect(report.metrics.singleWhere((m) => m.id == 'active_holds').value, 0);

      // Lifecycle metrics
      final history = report.metrics.singleWhere((m) => m.id == 'held_history');
      expect(history.quality, AnalyticsQuality.complete);
      expect(history.value, isNotNull);

      expect(report.metrics.singleWhere((m) => m.id == 'held_created').value, 3); // holdA, holdB, discardHold
      expect(report.metrics.singleWhere((m) => m.id == 'held_recalled').value, 1); // holdA
      expect(report.metrics.singleWhere((m) => m.id == 'held_replaced').value, 1); // holdA replaced
      expect(report.metrics.singleWhere((m) => m.id == 'held_discarded').value, 1); // discardHold
      expect(report.metrics.singleWhere((m) => m.id == 'held_converted').value, 1); // holdB

      final rate = report.metrics.singleWhere((m) => m.id == 'hold_conversion_rate');
      expect(rate.quality, AnalyticsQuality.complete);
      expect(rate.value, closeTo(33.33, 0.1)); // 1 converted / 3 created * 100

      final avgAge = report.metrics.singleWhere((m) => m.id == 'hold_conversion_avg_age');
      expect(avgAge.quality, AnalyticsQuality.complete);
      expect(avgAge.value, isNonNegative);

      // Privacy checks on rows and exports
      final lifecycleRows = report.rows.where((r) => r.sourceType == 'hold_lifecycle_events').toList();
      // Events:
      // 1: CREATED holdA
      // 2: RECALLED holdA
      // 3: REPLACED holdA
      // 4: CREATED holdB
      // 5: CREATED discardHold
      // 6: DISCARDED discardHold
      // 7: CONVERTED holdB
      expect(lifecycleRows, hasLength(7));

      final convertedRow = lifecycleRows.firstWhere((r) => r.cells['event_type'] == 'CONVERTED');
      expect(convertedRow.cells['order_id'], isNotNull);
      expect(convertedRow.cells['cashier_id'], 2);

      final replacedRow = lifecycleRows.firstWhere((r) => r.cells['event_type'] == 'REPLACED');
      expect(replacedRow.cells['previous_hold_id'], holdB);

      // Ensure no draft label or private customer data is leaked in rows or CSV
      final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.orders);
      for (final leak in ['Private Customer', '03009999999', 'Will Discard Secret', 'Burger', 'payload']) {
        expect(csv, isNot(contains(leak)));
      }
    });

    test('Unretained legacy / pre-feature periods disclose missing hold lifecycle coverage', () async {
      final manager = (await db.query('staff', where: 'id=1')).single;
      final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
      final service = AnalyticsService(database: db, authService: auth);

      // Query for year 2020 where no events occurred
      final oldQuery = AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2020, 2));
      final snapshot = await service.load(oldQuery);
      final report = snapshot.section(AnalyticsFamily.orders);

      final history = report.metrics.singleWhere((m) => m.id == 'held_history');
      expect(history.quality, AnalyticsQuality.missing);
      expect(history.explanation, contains('deleted'));

      final conversionRate = report.metrics.singleWhere((m) => m.id == 'hold_conversion_rate');
      expect(conversionRate.quality, AnalyticsQuality.missing);

      final avgAge = report.metrics.singleWhere((m) => m.id == 'hold_conversion_avg_age');
      expect(avgAge.quality, AnalyticsQuality.missing);
    });
  });
}
