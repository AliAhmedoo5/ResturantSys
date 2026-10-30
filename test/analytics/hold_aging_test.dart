import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/catalog/menu_item.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/orders/cart_item.dart';
import 'package:resturant_sys/core/orders/dining_type.dart';
import 'package:resturant_sys/core/orders/order_and_checkout_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('Manager sees current persisted Holds outside historical Orders and revenue with safe ownership', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final orders = OrderAndCheckoutController(database: db);
    final line = CartItem(menuItem: const MenuItem(id: 987, categoryId: 1,
      name: 'Private draft item', basePrice: 100));
    final hold = await orders.holdCart(cashierId: 2, label: 'Private home 03001234567',
      items: [line], diningType: DiningType.takeaway);
    final removed = await orders.holdCart(cashierId: 2, label: 'Deleted private label',
      items: [line], diningType: DiningType.takeaway);
    await orders.removeHold(2, removed);
    final manager = (await db.query('staff', where: 'id=1')).single;
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2020, 2));
    final snapshot = await service.load(query);
    final report = snapshot.section(AnalyticsFamily.orders);
    expect(report.metrics.singleWhere((m) => m.id == 'active_holds').value, 1);
    expect(report.metrics.singleWhere((m) => m.id == 'committed_orders').value, 0);
    expect(snapshot.section(AnalyticsFamily.sales).metrics.singleWhere((m) => m.id == 'recorded_value').value, 0);
    final row = report.rows.singleWhere((r) => r.sourceType == 'held_carts');
    expect(row.sourceId, '$hold');
    expect(row.cells['cashier_id'], 2);
    expect(row.cells['age_minutes'], isNonNegative);
    expect(row.cells['age_minutes'], lessThan(1));
    expect(row.cells['created_at_source'].toString(), endsWith('Z'));
    expect(row.cells['created_at'], contains('Asia/Karachi'));
    expect(row.cells['business_day_id'], isNull);
    expect(row.cells['shift_id'], isNull);
    final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.orders);
    for (final private in ['Private home', '03001234567', 'Private draft item', 'Deleted private label', 'payload']) {
      expect(csv, isNot(contains(private)));
    }
    expect(report.metrics.singleWhere((m) => m.id == 'held_history').quality, AnalyticsQuality.missing);
    expect(report.metrics.singleWhere((m) => m.id == 'held_history').explanation, contains('deleted'));
    await orders.removeHold(2, hold);
    expect((await service.load(query)).section(AnalyticsFamily.orders).metrics.singleWhere((m) => m.id == 'active_holds').value, 0);
    expect(report.rows.where((r) => r.sourceType == 'held_carts'), hasLength(1));
    auth.session.lock();
    await expectLater(service.load(query), throwsStateError);
  });

  test('configured stale minutes change current Hold classification and survive query copies and exports', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final orders = OrderAndCheckoutController(database: db);
    final hold = await orders.holdCart(cashierId: 2, label: 'Synthetic draft',
      items: [CartItem(menuItem: const MenuItem(id: 987, categoryId: 1, name: 'Draft', basePrice: 100))],
      diningType: DiningType.takeaway);
    // Synthetic retained historical creation evidence for a thirty-minute Hold.
    await db.update('held_carts', {'created_at': DateTime.now().toUtc().subtract(const Duration(minutes: 30)).toIso8601String()}, where: 'id=?', whereArgs: [hold]);
    final manager = (await db.query('staff', where: 'id=1')).single;
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(startDate: DateTime(2020), endDateExclusive: DateTime(2020, 2),
      holdStaleMinutes: 15, cashierId: 2, shiftId: 999, diningType: 'DELIVERY', paymentMethod: 'CARD');
    final stale = await service.load(query);
    final current = stale.section(AnalyticsFamily.orders).rows.singleWhere((r) => r.sourceType == 'held_carts');
    expect(current.cells['aging_status'], 'Stale');
    expect(current.cells['stale_threshold_minutes'], 15);
    final relaxed = query.copyWith(holdStaleMinutes: 60);
    expect(relaxed.copyWith(live: true).holdStaleMinutes, 60);
    expect(relaxed, isNot(query));
    final fresh = await service.load(relaxed);
    expect(fresh.section(AnalyticsFamily.orders).metrics.singleWhere((m) => m.id == 'stale_holds').value, 0);
    expect(stale.section(AnalyticsFamily.orders).metrics.singleWhere((m) => m.id == 'stale_holds').value, 1);
    expect(AnalyticsExportService().csv(stale, AnalyticsFamily.orders), contains('hold_stale_threshold_minutes,15'));
    expect((await service.load(query.copyWith(cashierId: 999))).section(AnalyticsFamily.orders).metrics.singleWhere((m) => m.id == 'active_holds').value, 0);
    expect(() => query.copyWith(holdStaleMinutes: 0), throwsArgumentError);
  });
}
