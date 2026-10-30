import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';

AnalyticsRow row(String source, String id, Map<String, Object?> cells) =>
  AnalyticsRow(id: id, sourceType: source, sourceId: id, cells: cells);

List<ReportChartData> charts(AnalyticsFamily family, List<AnalyticsRow> rows,
    [List<AnalyticsMetric> metrics = const []]) => buildReportCharts(
  AnalyticsSection(family: family, title: family.name, rows: rows, metrics: metrics));

void main() {
  for (final spec in [
    (AnalyticsFamily.procurement, 'mandi_procurements', 'spend_paisa', 'purchase_dates'),
    (AnalyticsFamily.expenses, 'expense_entries', 'amount_paisa', 'expense_dates'),
    (AnalyticsFamily.profitability, 'order_cost_events', 'cost_paisa', 'cost_dates'),
  ]) {
    test('${spec.$4} groups original UTC evidence after display formatting', () {
      final source = row(spec.$2, '1', {
        'kind': 'CONSUME', spec.$3: 125,
        'created_at': '2026-10-30 00:30:00 +05:00 [Asia/Karachi]',
        'created_at_source': '2026-10-29T19:30:00Z',
      });
      final chart = charts(spec.$1, [source]).singleWhere((chart) => chart.id == spec.$4);
      expect(chart.points.single.label, '2026-10-30');
      expect(chart.points.single.value, 125);
      expect(chart.points.single.rows.single, same(source));
    });
  }

  test('Order and delivery distributions never count their auxiliary row kinds', () {
    final orders = charts(AnalyticsFamily.orders, [
      row('orders', '1', {'payment_status': 'SETTLED', 'dining_type': 'TAKEAWAY'}),
      row('orders', '2', {'payment_status': 'CANCELLED', 'dining_type': 'DELIVERY'}),
      row('order_revisions', '3', {'payment_status': 'SETTLED'}),
    ]);
    expect(orders.first.points.fold<num>(0, (sum, p) => sum + p.value!), 2);
    final delivery = charts(AnalyticsFamily.delivery, [
      row('orders', '1', {'area': 'North', 'status': 'DELIVERED'}),
      row('rider_trip_orders', '2', {'status': 'DELIVERED'}),
      row('rider_trip_orders', '3', {'status': 'RETURNED'}),
      row('rider_trips', '4', {'status': 'SETTLED'}),
    ]);
    expect(delivery[0].points.fold<num>(0, (sum, p) => sum + p.value!), 2);
    expect(delivery[1].points.single.value, 1);
    expect(delivery[2].points.single.label, 'SETTLED');
    expect(delivery[0].points.expand((p) => p.rows).every((r) => r.sourceType == 'rider_trip_orders'), isTrue);
  });

  test('Customer and menu rankings exclude duplicate history and zero-seller projections', () {
    final customer = charts(AnalyticsFamily.customers, [
      row('orders', 'a', {'kind': 'Customer aggregate', 'customer': 'Customer •••1234', 'recorded_value_paisa': 30000}),
      row('orders', 'b', {'kind': 'Order history', 'customer': 'Customer •••1234', 'recorded_value_paisa': 30000}),
    ]).first;
    expect(customer.points.single.value, 30000);
    expect(customer.points.single.rows.single.id, 'a');
    final menu = charts(AnalyticsFamily.menu, [
      row('order_items', '1', {'kind': 'Item/deal aggregate', 'name': 'Burger', 'quantity': 3, 'line_value_paisa': 150000}),
      row('menu_items', '2', {'kind': 'Current active zero seller', 'name': 'Fries', 'quantity': 0}),
    ]);
    expect(menu.first.points.single.value, 3);
    expect(menu.last.points.single.value, 150000);
  });

  test('Inventory quantities stay separated by base unit and status counts do not overlap', () {
    final result = charts(AnalyticsFamily.inventory, [
      row('raw_ingredients', '1', {'kind': 'Current position', 'ingredient_id': 1, 'name': 'Flour',
        'unit': 'g', 'current_stock': -10, 'status': 'Negative'}),
      row('raw_ingredients', '2', {'kind': 'Current position', 'ingredient_id': 2, 'name': 'Oil',
        'unit': 'ml', 'current_stock': 50, 'status': 'Low'}),
      row('order_items', '3', {'kind': 'BOM quantity snapshot', 'ingredient_id': '1', 'quantity': 125}),
      row('order_items', '4', {'kind': 'BOM quantity snapshot', 'ingredient_id': '2', 'quantity': 30}),
      row('inventory_movements', '5', {'kind': 'Movement', 'quantity_delta': -9999}),
    ]);
    expect(result.first.points.fold<num>(0, (sum, p) => sum + p.value!), 2);
    expect(result.singleWhere((c) => c.id == 'stock_g').points.single.value, -10);
    expect(result.singleWhere((c) => c.id == 'bom_g').points.single.value, 125);
    expect(result.singleWhere((c) => c.id == 'bom_ml').points.single.value, 30);
  });

  test('Procurement dates use Karachi time and do not invent missing-date zeros', () {
    final result = charts(AnalyticsFamily.procurement, [
      row('mandi_procurements', '1', {'ingredient_id': 7, 'spend_paisa': 20000, 'created_at': '2026-10-26T20:00:00Z'}),
      row('mandi_procurements', '2', {'ingredient_id': 7, 'spend_paisa': 5000, 'created_at': '2026-10-27 12:00:00'}),
      row('mandi_procurements', '3', {'ingredient_id': 8, 'spend_paisa': 100, 'created_at': null}),
    ]);
    expect(result.first.points.single.label, '2026-10-27');
    expect(result.first.points.single.value, 25000);
    expect(result.first.note, contains('1 undated'));
    expect(result.last.points.first.value, 25000);
  });

  test('Current supplier balances exclude interval transactions', () {
    final result = charts(AnalyticsFamily.suppliers, [
      row('vendor_khata', '1', {'name': 'Supplier', 'current_paisa': -5000}),
      row('vendor_transactions', '2', {'name': 'Supplier', 'current_paisa': 999999}),
    ]);
    expect(result.first.points.single.value, -5000);
    expect(result.first.scope, contains('Current installation-wide'));
  });

  test('Cash charts keep missing counts distinct from zero and retain signed variance', () {
    final result = charts(AnalyticsFamily.cash, [
      row('shifts', '1', {'kind': 'Shift reconciliation', 'shift_id': 1,
        'expected_paisa': 10000, 'counted_paisa': null, 'variance_paisa': null}),
      row('shifts', '2', {'kind': 'Shift reconciliation', 'shift_id': 2,
        'expected_paisa': 10000, 'counted_paisa': 9000, 'variance_paisa': -1000}),
      row('cash_movements', '3', {'kind': 'Drawer movement', 'expected_paisa': 999999}),
    ]);
    expect(result.first.points, hasLength(4));
    expect(result.first.points[1].value, isNull);
    expect(result.last.points.first.value, -1000);
    expect(result.last.points.last.value, isNull);
  });

  test('Operating expenses and drawer outflows remain separate and reversals subtract', () {
    final result = charts(AnalyticsFamily.expenses, [
      row('expense_entries', '1', {'category': 'Utilities', 'amount_paisa': 10000, 'created_at': '2026-10-28 12:00:00'}),
      row('expense_entries', '2', {'category': 'Utilities', 'amount_paisa': -2500, 'created_at': '2026-10-28 13:00:00'}),
      row('cash_movements', '3', {'category': 'Utilities', 'amount_paisa': 10000}),
    ]);
    expect(result[0].points.single.value, 7500);
    expect(result[1].points.single.value, 7500);
    expect(result[2].points.single.value, 10000);
    expect(result[0].points.single.rows.map((r) => r.id), ['1', '2']);
  });

  test('Staff activity uses reported order counts while department counts use directory rows', () {
    final result = charts(AnalyticsFamily.staff, [
      row('staff', '1', {'name': 'Ayesha', 'department': 'Counter', 'selected_orders': 12}),
      row('staff', '2', {'name': 'Zain', 'department': 'Counter', 'selected_orders': 0}),
    ]);
    expect(result[0].points.first.value, 12);
    expect(result[1].points.single.value, 2);
  });

  test('Profit charts withhold unknown costs, sign returns, and exclude already consumed cooked waste', () {
    final result = charts(AnalyticsFamily.profitability, [
      row('order_cost_events', '1', {'kind': 'CONSUME', 'cost_paisa': 10000, 'created_at': '2026-10-26 12:00:00'}),
      row('order_cost_events', '2', {'kind': 'RETURN', 'cost_paisa': 2500, 'created_at': '2026-10-26 12:00:00'}),
      row('order_cost_events', '3', {'kind': 'COOKED_WASTE', 'cost_paisa': 9000, 'created_at': '2026-10-26 12:00:00'}),
      row('order_cost_events', '4', {'kind': 'CONSUME', 'cost_paisa': null, 'created_at': '2026-10-27 12:00:00'}),
      row('order_cost_events', '5', {'kind': 'CONSUME', 'cost_paisa': 5000, 'created_at': '2026-10-27 12:00:00'}),
    ], [const AnalyticsMetric(id: 'gross_profit', label: 'Gross profit', unit: AnalyticsUnit.paisa,
      quality: AnalyticsQuality.missing, explanation: 'Missing cost coverage')]);
    expect(result.first.points.single.value, isNull);
    expect(result.last.points.first.value, 7500);
    expect(result.last.points.last.value, isNull);
    expect(result.last.points.last.rows, hasLength(2));
  });

  test('Audit outbox chart excludes other audit event statuses', () {
    final result = charts(AnalyticsFamily.audit, [
      row('report_outbox', '1', {'kind': 'Report delivery', 'status': 'FAILED'}),
      row('report_delivery_audit', '2', {'kind': 'Delivery audit', 'status': 'FAILED'}),
    ]);
    expect(result.last.points.single.value, 1);
    expect(result.first.points, hasLength(2));
  });

  test('Unavailable and non-finite amounts never become zero', () {
    expect(ReportChartPoint('Unknown', null).value, isNull);
    expect(ReportChartPoint('Invalid', double.infinity).value, isNull);
    expect(ReportChartPoint('Invalid', double.nan).value, isNull);
    expect(ReportChartPoint('Zero', 0).value, 0);
    expect(ReportChartPoint('Missing', 123, quality: AnalyticsQuality.missing).value, isNull);
  });
}
