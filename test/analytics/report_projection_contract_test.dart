import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('real report totals, charts and drill-down share signed cost evidence', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((row) => row['role'] != 'CASHIER');
    final cashier = staff.firstWhere((row) => row['role'] == 'CASHIER');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final day = await db.insert('business_days', {'opened_at': '2026-10-25 18:00:00',
      'status': 'OPEN', 'opened_by_staff_id': manager['id']});
    final shift = await db.insert('shifts', {'business_day_id': day, 'staff_id': cashier['id'],
      'opened_at': '2026-10-25 18:00:00', 'opening_float': 0, 'status': 'OPEN'});
    final order = await db.insert('orders', {'business_day_id': day, 'shift_id': shift,
      'cashier_id': cashier['id'], 'token_number': 1, 'dining_type': 'TAKEAWAY',
      'subtotal': 200, 'grand_total': 200, 'payment_status': 'SETTLED',
      'created_at': '2026-10-25 19:00:00'});
    final ingredient = await db.insert('raw_ingredients', {'name': 'Synthetic flour',
      'storage_unit': 'g', 'current_stock': -1, 'low_stock_threshold': 0,
      'created_at': '2026-10-25 18:00:00'});
    await db.insert('order_cost_coverage', {'order_id': order,
      'policy': 'EVENT_ACQUISITION_RATE_V1', 'recorded_at': '2026-10-25 19:00:00'});
    final sourceIds = <String>[];
    for (final event in [('CONSUME', 10000), ('RETURN', 2500), ('COOKED_WASTE', 9000)]) {
      final id = await db.insert('order_cost_events', {'order_id': order,
        'ingredient_id': ingredient, 'revision': 0, 'kind': event.$1,
        'quantity': 1, 'unit_cost_rupees': event.$2 / 100, 'cost_paisa': event.$2,
        'recorded_at': '2026-10-25 19:00:00'});
      sourceIds.add('$id');
    }
    final report = await AnalyticsService(database: db, authService: auth).load(
      AnalyticsQuery(startDate: DateTime(2026, 10, 25), endDateExclusive: DateTime(2026, 10, 26)));
    final profit = report.section(AnalyticsFamily.profitability);
    final cogs = profit.metrics.singleWhere((metric) => metric.id == 'cogs');
    final point = profit.charts.singleWhere((chart) => chart.id == 'cost_dates').points.single;
    expect(cogs.value, 7500);
    expect(point.value, cogs.value);
    expect(point.rows.map((row) => row.sourceId), sourceIds.take(2));
    expect(profit.rows, hasLength(3), reason: 'Cooked waste remains visible as evidence.');
    expect(AnalyticsExportService().csv(report, AnalyticsFamily.profitability), contains('COOKED_WASTE'));
    expect(report.overview.alerts.map((alert) => alert.kind), contains(OverviewAttentionKind.negativeStock));
    expect(report.overview.alerts.map((alert) => alert.kind), isNot(contains(OverviewAttentionKind.profitCoverage)));
    expect(() => profit.charts.clear(), throwsUnsupportedError);
    expect(() => report.overview.alerts.clear(), throwsUnsupportedError);
  });
}
