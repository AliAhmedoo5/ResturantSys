part of 'analytics_models.dart';

/// Semantic chart projections of the authorized report. No database reads,
/// estimates of absent history, or combinations of different ledger row kinds.
class ReportChartPoint {
  ReportChartPoint(this.label, num? value, {List<AnalyticsRow> rows = const [],
    this.explanation = '', this.quality = AnalyticsQuality.complete})
      : value = quality != AnalyticsQuality.missing && quality != AnalyticsQuality.notApplicable &&
          value != null && value.isFinite ? value : null,
        rows = List.unmodifiable(rows);
  final String label, explanation;
  final num? value;
  final AnalyticsQuality quality;
  final List<AnalyticsRow> rows;
}

class ReportChartData {
  ReportChartData({required this.id, required this.title, required this.scope,
    required this.unit, required List<ReportChartPoint> points, this.quantityUnit,
    this.note = ''}) : points = List.unmodifiable(points);
  final String id, title, scope, note;
  final AnalyticsUnit unit;
  final String? quantityUnit;
  final List<ReportChartPoint> points;
}

/// Compatibility entry point; the section owns its immutable chart projection.
List<ReportChartData> buildReportCharts(AnalyticsSection section) => section.charts;

List<ReportChartData> _buildReportCharts(AnalyticsSection section) => _Charts(section).build();

class _Charts {
  _Charts(this.section);
  final AnalyticsSection section;
  List<AnalyticsRow> source(String name) => section.rows.where((r) => r.sourceType == name).toList();

  List<ReportChartData> build() => switch (section.family) {
    AnalyticsFamily.overview || AnalyticsFamily.sales => [],
    AnalyticsFamily.orders => [
      count('order_status', 'Orders by payment status', source('orders'), 'payment_status',
        'Filtered committed orders · current stored status, including cancellations'),
      count('dining_mix', 'Orders by Dining Type', source('orders'), 'dining_type',
        'Filtered committed orders · revisions are not counted again'),
    ],
    AnalyticsFamily.delivery => [
      count('attempt_outcomes', 'Delivery attempt outcomes', source('rider_trip_orders'), 'status',
        'Filtered order attempts · returned attempts are not final failed orders'),
      count('delivery_areas', 'Delivery orders by area', source('orders'), 'area',
        'Eligible filtered delivery orders · transaction-time area snapshots'),
      count('trip_status', 'Trips by status', source('rider_trips'), 'status',
        'Whole selected Business Days · order filters do not restrict trip counts'),
    ],
    AnalyticsFamily.customers => [
      ranked('customer_value', 'Recorded value by known customer',
        section.rows.where((r) => r.cells['kind'] == 'Customer aggregate').toList(),
        'recorded_value_paisa', 'customer', AnalyticsUnit.paisa,
        'Filtered eligible orders · masked phone identities, not verified individuals'),
      metrics('customer_coverage', 'Known and guest order coverage', ['known_orders', 'guest_orders'],
        AnalyticsUnit.count, 'Filtered eligible orders · guests excluded from repeat-customer calculations'),
    ],
    AnalyticsFamily.menu => [
      ranked('menu_quantity', 'Menu & deal popularity',
        section.rows.where((r) => r.cells['kind'] == 'Item/deal aggregate').toList(),
        'quantity', 'name', AnalyticsUnit.count, 'Eligible sold lines · deal counts are not component counts'),
      ranked('menu_value', 'Recorded line value by item or deal',
        section.rows.where((r) => r.cells['kind'] == 'Item/deal aggregate').toList(),
        'line_value_paisa', 'name', AnalyticsUnit.paisa,
        'Before order discount, tax and fee allocation · this is not item net revenue'),
      if (section.rows.any((r) => r.cells['allocated_discount_paisa'] != null && (r.cells['allocated_discount_paisa'] as num) > 0))
        ranked('menu_net_sales', 'Allocated net sales by item or deal',
          section.rows.where((r) => r.cells['kind'] == 'Item/deal aggregate').toList(),
          'net_sales_paisa', 'name', AnalyticsUnit.paisa,
          'Net sales after proportional order-level discount allocation adhering to ADR-0021'),
      if (section.rows.any((r) => r.cells['margin_paisa'] != null))
        ranked('menu_margins', 'Item contribution margin',
          section.rows.where((r) => r.cells['kind'] == 'Item/deal aggregate' && r.cells['margin_paisa'] != null).toList(),
          'margin_paisa', 'name', AnalyticsUnit.paisa,
          'Contribution margin based on event-time recipe BOM ingredient costing'),
    ],
    AnalyticsFamily.inventory => inventory(),
    AnalyticsFamily.procurement => [
      dated('purchase_dates', 'Mandi purchase spend by date', source('mandi_procurements'),
        'spend_paisa', 'created_at', 'Recorded purchase dates within selected Business Day intervals · Asia/Karachi'),
      summed('purchase_ingredients', 'Purchase spend by ingredient', source('mandi_procurements'),
        'ingredient_id', 'spend_paisa', AnalyticsUnit.paisa,
        'Selected interval Mandi records · purchase spend is not sales COGS', labelPrefix: 'Ingredient #'),
    ],
    AnalyticsFamily.suppliers => [
      ranked('supplier_payable', 'Current payable by supplier', source('vendor_khata'),
        'current_paisa', 'name', AnalyticsUnit.paisa,
        'Current installation-wide balances · independent of selected dates and order filters'),
      metrics('supplier_settlements', 'Supplier settlement sources', ['drawer_payments', 'external_payments'],
        AnalyticsUnit.paisa, 'Selected interval payments · credit deliveries and current payable are separate'),
    ],
    AnalyticsFamily.cash => cash(),
    AnalyticsFamily.expenses => [
      summed('expense_categories', 'Operating expenses by category', source('expense_entries'),
        'category', 'amount_paisa', AnalyticsUnit.paisa,
        'Selected Business Day postings · reversals reduce their original category'),
      dated('expense_dates', 'Operating expense postings by date', source('expense_entries'),
        'amount_paisa', 'created_at', 'Actual posting dates · Asia/Karachi · all recorded funding sources'),
      summed('drawer_categories', 'Drawer outflows by category', source('cash_movements'),
        'category', 'amount_paisa', AnalyticsUnit.paisa,
        'Selected-day cash movements · not added to operating expense ledger totals'),
    ],
    AnalyticsFamily.staff => [
      ranked('staff_orders', 'Selected order activity by staff', source('staff'), 'selected_orders',
        'name', AnalyticsUnit.count, 'Filtered order counts · not labor-hour productivity'),
      count('staff_departments', 'Current staff by department', source('staff'), 'department',
        'Current staff directory · includes active and inactive profiles'),
      metrics('salary_accruals', 'Posted salary accruals', ['labor_cost'], AnalyticsUnit.paisa,
        'Selected-day accrual postings and reversals · salary payments are not another expense'),
    ],
    AnalyticsFamily.profitability => [
      metrics('profit_components', 'Revenue, cost and operating result',
        ['recognized_revenue', 'cogs', 'gross_profit', 'net_profit'], AnalyticsUnit.paisa,
        'Selected Business Days · overlapping measures, never add these bars together'),
      dated('cost_dates', 'Recorded COGS postings by date',
        source('order_cost_events').where((r) => orderCostSign(r.cells['kind']) != 0).toList(),
        'cost_paisa', 'created_at',
        'Selected order cohort · cost-event posting dates in Asia/Karachi; returns subtract cost',
        signedReturns: true),
    ],
    AnalyticsFamily.audit => [
      count('audit_kinds', 'Recorded audit evidence by kind', section.rows, 'kind',
        'Source-event counts with the scope stated in this report · not unique orders'),
      count('outbox_status', 'Report delivery status', source('report_outbox'), 'status',
        'Whole selected Business Days · recorded outbox status, not proof of recipient receipt'),
    ],
  };

  List<ReportChartData> inventory() {
    final positions = section.rows.where((r) => r.cells['kind'] == 'Current position').toList();
    final units = positions.map((r) => r.cells['unit']?.toString()).whereType<String>()
      .where((unit) => unit.isNotEmpty).toSet().toList()..sort();
    final byIngredient = {for (final row in positions) '${row.cells['ingredient_id']}': row};
    final charts = [count('stock_status', 'Current stock status', positions, 'status',
      'Current installation-wide position · Low and Negative categories are separate')];
    for (final unit in units) {
      final rows = positions.where((r) => r.cells['unit'] == unit).toList();
      charts.add(ranked('stock_$unit', 'Current stock levels ($unit)', rows,
        'current_stock', 'name', AnalyticsUnit.decimal,
        'Current position · $unit only; not a historical balance', quantityUnit: unit));
      final quantities = <String, List<AnalyticsRow>>{};
      for (final row in section.rows.where((r) => r.cells['kind'] == 'BOM quantity snapshot')) {
        final id = '${row.cells['ingredient_id']}';
        if (byIngredient[id]?.cells['unit'] == unit) quantities.putIfAbsent(id, () => []).add(row);
      }
      charts.add(ReportChartData(id: 'bom_$unit', title: 'Recorded BOM quantities ($unit)',
        unit: AnalyticsUnit.decimal, quantityUnit: unit,
        scope: 'Selected sold-line snapshots · $unit only; quantity evidence is not cost evidence',
        note: 'Grouped by current ingredient base unit; historical unit changes are not reconstructed. '
          'Ingredients without a known unit remain in source detail. Units are never combined.',
        points: _rank([for (final entry in quantities.entries)
          point(byIngredient[entry.key]?.cells['name']?.toString() ?? 'Ingredient #${entry.key}',
            entry.value, 'quantity')])));
    }
    if (units.isEmpty) {
      charts.add(ReportChartData(id: 'stock_units', title: 'Stock levels by base unit',
        scope: 'Current position · no unit-backed stock evidence available',
        unit: AnalyticsUnit.decimal, points: []));
    }
    return charts;
  }

  List<ReportChartData> cash() {
    final rows = source('shifts').where((r) => r.cells['kind'] == 'Shift reconciliation').toList();
    return [
      ReportChartData(id: 'shift_cash', title: 'Expected and counted cash by shift',
        scope: 'Whole selected owning/receiving Shifts · missing cash evidence or blind counts remain unavailable',
        unit: AnalyticsUnit.paisa, points: [for (final row in rows) ...[
          ReportChartPoint('Shift #${row.cells['shift_id']} · expected', number(row.cells['expected_paisa']), rows: [row]),
          ReportChartPoint('Shift #${row.cells['shift_id']} · counted', number(row.cells['counted_paisa']), rows: [row]),
        ]]),
      ranked('shift_variance', 'Cash variance by shift', rows, 'variance_paisa', 'shift_id',
        AnalyticsUnit.paisa, 'Physical count minus expected · uncounted shifts are not zero', labelPrefix: 'Shift #'),
    ];
  }

  ReportChartData metrics(String id, String title, List<String> ids, AnalyticsUnit unit, String scope) =>
    ReportChartData(id: id, title: title, scope: scope, unit: unit,
      points: [for (final name in ids)
        for (final metric in section.metrics.where((m) => m.id == name))
          ReportChartPoint(metric.label, metric.value, explanation: metric.explanation, quality: metric.quality)]);

  ReportChartData count(String id, String title, List<AnalyticsRow> rows, String key, String scope) {
    final groups = <String, List<AnalyticsRow>>{};
    for (final row in rows) {
      final label = row.cells[key]?.toString().replaceAll('_', ' ') ?? 'Not recorded';
      groups.putIfAbsent(label, () => []).add(row);
    }
    return ReportChartData(id: id, title: title, scope: scope, unit: AnalyticsUnit.count,
      points: _rank([for (final group in groups.entries)
        ReportChartPoint(group.key, group.value.length, rows: group.value)]));
  }

  ReportChartData ranked(String id, String title, List<AnalyticsRow> rows, String valueKey,
      String labelKey, AnalyticsUnit unit, String scope, {String labelPrefix = '', String? quantityUnit}) =>
    ReportChartData(id: id, title: title, scope: scope, unit: unit, quantityUnit: quantityUnit,
      points: _rank([for (final row in rows) ReportChartPoint(
        '$labelPrefix${row.cells[labelKey] ?? row.sourceId ?? row.id}', number(row.cells[valueKey]), rows: [row])]));

  ReportChartData summed(String id, String title, List<AnalyticsRow> rows, String groupKey,
      String valueKey, AnalyticsUnit unit, String scope, {String labelPrefix = ''}) {
    final groups = <String, List<AnalyticsRow>>{};
    for (final row in rows) {
      groups.putIfAbsent('${row.cells[groupKey] ?? 'Not recorded'}', () => []).add(row);
    }
    return ReportChartData(id: id, title: title, scope: scope, unit: unit,
      points: _rank([for (final entry in groups.entries) point('$labelPrefix${entry.key}', entry.value, valueKey)]));
  }

  ReportChartData dated(String id, String title, List<AnalyticsRow> rows, String valueKey,
      String dateKey, String scope, {bool signedReturns = false}) {
    final groups = <String, List<AnalyticsRow>>{};
    var undated = 0;
    for (final row in rows) {
      final local = analyticsKarachiTime(row.cells['${dateKey}_source'] ?? row.cells[dateKey]);
      if (local == null) { undated++; continue; }
      groups.putIfAbsent(DateFormat('yyyy-MM-dd').format(local), () => []).add(row);
    }
    final dates = groups.keys.toList()..sort();
    return ReportChartData(id: id, title: title, scope: scope, unit: AnalyticsUnit.paisa,
      note: '${undated == 0 ? '' : '$undated undated entries excluded; retained in source detail. '}'
        '${signedReturns ? 'Recorded postings may cover only part of the selected order cohort. '
          'Cooked wastage is already in consumed cost; pre-upgrade cost history is not inferred. ' : ''}'
        'Dates with unknown amounts remain unavailable. No missing-date zeros are invented.',
      points: [for (final date in dates) point(date, groups[date]!, valueKey, signedReturns: signedReturns)]);
  }

  ReportChartPoint point(String label, List<AnalyticsRow> rows, String key, {bool signedReturns = false}) {
    num sum = 0;
    var complete = true;
    for (final row in rows) {
      final value = number(row.cells[key]);
      if (value == null) { complete = false; continue; }
      sum += signedReturns ? orderCostSign(row.cells['kind']) * value : value;
    }
    return ReportChartPoint(label, complete ? sum : null, rows: rows,
      explanation: complete ? '' : 'At least one source amount is unavailable; a complete total cannot be shown.');
  }

  static num? number(Object? value) => value is num && value.isFinite ? value : null;
  static List<ReportChartPoint> _rank(List<ReportChartPoint> points) => points..sort((a, b) {
    final order = (b.value?.abs() ?? -1).compareTo(a.value?.abs() ?? -1);
    return order != 0 ? order : a.label.compareTo(b.label);
  });
}
