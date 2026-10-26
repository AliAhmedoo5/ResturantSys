import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('historical analytics preserve overnight cohorts, interval gaps and timing coverage', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((row) => row['role'] != 'CASHIER');
    final cashier = staff.firstWhere((row) => row['role'] == 'CASHIER');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    addTearDown(auth.session.dispose);

    Future<int> day(String opened, String closed) => db.insert('business_days', {
      'opened_at': opened, 'closed_at': closed, 'status': 'OPEN',
      'opened_by_staff_id': manager['id'], 'closed_by_staff_id': manager['id'],
    });
    final previous = await day('2026-10-23 18:00:00', '2026-10-24 02:00:00');
    final selected = await day('2026-10-25 18:00:00', '2026-10-26 02:00:00');
    Future<int> shift(int businessDay, String opened) => db.insert('shifts', {
      'business_day_id': businessDay, 'staff_id': cashier['id'], 'opened_at': opened,
      'opening_float': 0, 'counted_cash': 0, 'status': 'CLOSED',
    });
    final previousShift = await shift(previous, '2026-10-23 18:00:00');
    final selectedShift = await shift(selected, '2026-10-25 18:00:00');
    Future<int> order(int businessDay, int cashierShift, int token, num amount, String created) => db.insert('orders', {
      'business_day_id': businessDay, 'shift_id': cashierShift, 'cashier_id': cashier['id'],
      'token_number': token, 'dining_type': 'DELIVERY', 'subtotal': amount,
      'grand_total': amount, 'payment_status': 'SETTLED', 'created_at': created,
    });
    await order(previous, previousShift, 1, 100, '2026-10-24 01:00:00');
    final selectedOrders = <int>[];
    for (var token = 1; token <= 3; token++) {
      selectedOrders.add(await order(selected, selectedShift, token, 200, '2026-10-26 01:00:00'));
    }

    final ingredient = await db.insert('raw_ingredients', {
      'name': 'Synthetic history ingredient', 'storage_unit': 'kg',
      'current_stock': 0, 'low_stock_threshold': 1, 'created_at': '2026-10-23 18:00:00',
    });
    Future<void> purchase(String created, num amount) async {
      await db.insert('mandi_procurements', {
        'raw_ingredient_id': ingredient, 'traditional_unit': 'kg', 'quantity': 1,
        'converted_quantity': 1, 'total_cost': amount, 'cost_per_recipe_unit': amount,
        'created_at': created,
      });
    }
    await purchase('2026-10-23 20:00:00', 25);
    await purchase('2026-10-24 20:00:00', 999); // Gap between selected Business Days.
    await purchase('2026-10-25 17:59:59', 999); // Before opening.
    await purchase('2026-10-25 23:00:00', 50);
    await purchase('2026-10-26 01:00:00', 75);
    await purchase('2026-10-26 02:00:00', 999); // Exclusive close boundary.

    final trip = await db.insert('rider_trips', {
      'rider_staff_id': cashier['id'], 'shift_id': selectedShift, 'business_day_id': selected,
      'status': 'SETTLED', 'dispatched_at': '2026-10-26 00:00:00',
      'created_at': '2026-10-26 00:00:00',
    });
    const delivered = ['2026-10-26 00:10:00', '2026-10-26 00:30:00', '2026-10-25 23:59:00'];
    for (var index = 0; index < selectedOrders.length; index++) {
      await db.insert('rider_trip_orders', {
        'trip_id': trip, 'order_id': selectedOrders[index], 'status': 'DELIVERED',
        'assigned_at': '2026-10-26 00:00:00', 'delivered_at': delivered[index],
      });
    }

    // Populate history while days are open; production integrity triggers reject
    // inserting orders into already closed Business Days.
    await db.update('business_days', {'status': 'CLOSED'},
        where: 'id IN (?, ?)', whereArgs: [previous, selected]);
    final report = await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: DateTime(2026, 10, 24), endDateExclusive: DateTime(2026, 10, 26)),
    );
    AnalyticsMetric metric(AnalyticsFamily family, String id) =>
        report.section(family).metrics.firstWhere((value) => value.id == id);
    expect(report.businessDayIds, [selected]);
    expect(metric(AnalyticsFamily.sales, 'recorded_value').value, 60000);
    expect(metric(AnalyticsFamily.sales, 'recorded_value').changePercent, 500);
    expect(metric(AnalyticsFamily.procurement, 'purchase_spend').value, 12500);
    expect(metric(AnalyticsFamily.procurement, 'purchase_spend').changePercent, 400);
    expect(report.section(AnalyticsFamily.procurement).rows.length, 2);
    expect(metric(AnalyticsFamily.delivery, 'travel_mean').value, 20);
    expect(metric(AnalyticsFamily.delivery, 'travel_median').value, 20);
    expect(metric(AnalyticsFamily.delivery, 'travel_p90').value, closeTo(28, 0.0001));
    expect(metric(AnalyticsFamily.delivery, 'travel_mean').sampleCount, 2);
    expect(metric(AnalyticsFamily.delivery, 'travel_mean').populationCount, 3);
    expect(metric(AnalyticsFamily.delivery, 'travel_mean').quality, AnalyticsQuality.estimated);
    final position = report.section(AnalyticsFamily.inventory).rows.firstWhere((row) => row.sourceType == 'raw_ingredients');
    expect(position.cells['as_of_balance'], isNull);
    expect(metric(AnalyticsFamily.inventory, 'as_of_coverage').value, 0);
    expect(metric(AnalyticsFamily.inventory, 'as_of_coverage').quality, AnalyticsQuality.estimated);
  });
}
