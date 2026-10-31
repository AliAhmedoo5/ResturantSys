import 'package:intl/intl.dart';
import 'analytics_models.dart';

class KpiContributorResult {
  const KpiContributorResult({
    required this.metric,
    required this.family,
    required this.formula,
    this.formulaTotal,
    required this.isReconciled,
    required this.contributingRows,
    required this.columns,
    this.emptyOrMissingNote,
  });

  final AnalyticsMetric metric;
  final AnalyticsFamily family;
  final String formula;
  final num? formulaTotal;
  final bool isReconciled;
  final List<AnalyticsRow> contributingRows;
  final List<AnalyticsColumn> columns;
  final String? emptyOrMissingNote;
}

abstract final class KpiContributors {
  static String _formatPaisa(num? paisa) {
    if (paisa == null) return 'PKR 0.00';
    return 'PKR ${NumberFormat('#,##0.00').format(paisa / 100)}';
  }

  static KpiContributorResult resolve({
    required AnalyticsSnapshot snapshot,
    required AnalyticsSection section,
    required AnalyticsMetric metric,
  }) {
    if (metric.quality == AnalyticsQuality.missing || metric.value == null) {
      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Data unavailable: ${metric.explanation}',
        formulaTotal: null,
        isReconciled: false,
        contributingRows: const [],
        columns: const [],
        emptyOrMissingNote: 'Missing data: ${metric.explanation}',
      );
    }

    // Overview KPIs delegate to underlying target sections
    if (section.family == AnalyticsFamily.overview) {
      final targetFamily = switch (metric.id) {
        'recorded_value' || 'orders' || 'average_ticket' => AnalyticsFamily.sales,
        'collection_due' || 'all_collection_due' => AnalyticsFamily.delivery,
        'expected_drawer' || 'variance' => AnalyticsFamily.cash,
        'negative_stock' => AnalyticsFamily.inventory,
        'gross_profit' => AnalyticsFamily.profitability,
        _ => null,
      };

      if (targetFamily != null) {
        final underlyingSection = snapshot.sections
            .where((s) => s.family == targetFamily)
            .firstOrNull;
        if (underlyingSection != null) {
          final underlyingMetric = underlyingSection.metrics
              .where((m) => m.id == metric.id)
              .firstOrNull;
          return resolve(
            snapshot: snapshot,
            section: underlyingSection,
            metric: underlyingMetric ?? metric,
          );
        }
      }
    }

    switch (section.family) {
      case AnalyticsFamily.sales:
        return _resolveSales(section, metric);
      case AnalyticsFamily.cash:
        return _resolveCash(section, metric);
      case AnalyticsFamily.inventory:
        return _resolveInventory(section, metric);
      case AnalyticsFamily.orders:
        return _resolveOrders(section, metric);
      case AnalyticsFamily.delivery:
        return _resolveDelivery(section, metric);
      case AnalyticsFamily.procurement:
        return _resolveProcurement(section, metric);
      case AnalyticsFamily.suppliers:
        return _resolveSuppliers(section, metric);
      case AnalyticsFamily.expenses:
        return _resolveExpenses(section, metric);
      case AnalyticsFamily.staff:
        return _resolveStaff(section, metric);
      default:
        return _resolveDefault(section, metric);
    }
  }

  static KpiContributorResult _resolveSales(AnalyticsSection section, AnalyticsMetric metric) {
    final dailyRows = section.rows
        .where((r) => r.cells['kind'] == 'Daily total')
        .toList();

    if (metric.id == 'recorded_value') {
      final total = dailyRows.fold<num>(
          0, (sum, r) => sum + (r.cells['recorded_value_paisa'] as num? ?? 0));
      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Total Recorded Value = Sum of ${dailyRows.length} daily periods = ${_formatPaisa(total)}',
        formulaTotal: total,
        isReconciled: total == metric.value,
        contributingRows: dailyRows,
        columns: const [
          AnalyticsColumn(key: 'business_date', label: 'Business date'),
          AnalyticsColumn(key: 'orders', label: 'Orders', unit: AnalyticsUnit.count),
          AnalyticsColumn(key: 'recorded_value_paisa', label: 'Recorded Value', unit: AnalyticsUnit.paisa),
        ],
      );
    }

    if (metric.id == 'orders') {
      final total = dailyRows.fold<int>(
          0, (sum, r) => sum + (r.cells['orders'] as int? ?? 0));
      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Total Orders = Sum of ${dailyRows.length} daily periods = $total orders',
        formulaTotal: total,
        isReconciled: total == metric.value,
        contributingRows: dailyRows,
        columns: const [
          AnalyticsColumn(key: 'business_date', label: 'Business date'),
          AnalyticsColumn(key: 'orders', label: 'Orders', unit: AnalyticsUnit.count),
          AnalyticsColumn(key: 'recorded_value_paisa', label: 'Recorded Value', unit: AnalyticsUnit.paisa),
        ],
      );
    }

    if (metric.id == 'average_ticket') {
      final totalVal = dailyRows.fold<num>(
          0, (sum, r) => sum + (r.cells['recorded_value_paisa'] as num? ?? 0));
      final totalOrders = dailyRows.fold<int>(
          0, (sum, r) => sum + (r.cells['orders'] as int? ?? 0));
      final avg = totalOrders > 0 ? (totalVal / totalOrders) : 0.0;
      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Average Ticket = Total Value (${_formatPaisa(totalVal)}) / Total Orders ($totalOrders) = ${_formatPaisa(avg)}',
        formulaTotal: avg,
        isReconciled: avg == metric.value,
        contributingRows: dailyRows,
        columns: const [
          AnalyticsColumn(key: 'business_date', label: 'Business date'),
          AnalyticsColumn(key: 'orders', label: 'Orders', unit: AnalyticsUnit.count),
          AnalyticsColumn(key: 'recorded_value_paisa', label: 'Recorded Value', unit: AnalyticsUnit.paisa),
        ],
      );
    }

    if (metric.id == 'collected_tender') {
      final tenderRows = section.rows
          .where((r) => r.cells['kind'] == 'Tender breakdown')
          .toList();
      final total = tenderRows.fold<num>(
          0, (sum, r) => sum + (r.cells['collected_paisa'] as num? ?? 0));
      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Total Collected Tender = Sum of ${tenderRows.length} payment methods = ${_formatPaisa(total)}',
        formulaTotal: total,
        isReconciled: total == metric.value,
        contributingRows: tenderRows,
        columns: const [
          AnalyticsColumn(key: 'dimension_value', label: 'Payment Method'),
          AnalyticsColumn(key: 'collected_paisa', label: 'Collected Amount', unit: AnalyticsUnit.paisa),
        ],
      );
    }

    return _resolveDefault(section, metric, rows: dailyRows);
  }

  static KpiContributorResult _resolveCash(AnalyticsSection section, AnalyticsMetric metric) {
    final shiftRows = section.rows
        .where((r) => r.cells['kind'] == 'Shift reconciliation')
        .toList();
    final effectRows = section.rows
        .where((r) => r.cells['kind'] == 'Physical cash effect')
        .toList();

    if (metric.id == 'expected_drawer' || metric.id == 'evidenced_balance') {
      final opening = shiftRows.fold<num>(
          0, (sum, r) => sum + (r.cells['opening_paisa'] as num? ?? 0));
      final receipts = effectRows
          .where((r) => (r.cells['amount_paisa'] as num? ?? 0) > 0)
          .fold<num>(0, (sum, r) => sum + (r.cells['amount_paisa'] as num? ?? 0));
      final outflows = effectRows
          .where((r) => (r.cells['amount_paisa'] as num? ?? 0) < 0)
          .fold<num>(0, (sum, r) => sum + (r.cells['amount_paisa'] as num? ?? 0));
      final total = opening + receipts + outflows;

      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Expected Drawer = Opening Float (${_formatPaisa(opening)}) + Receipts (${_formatPaisa(receipts)}) - Outflows (${_formatPaisa(-outflows)}) = ${_formatPaisa(total)}',
        formulaTotal: total,
        isReconciled: total == metric.value,
        contributingRows: [...shiftRows, ...effectRows],
        columns: const [
          AnalyticsColumn(key: 'kind', label: 'Record Type'),
          AnalyticsColumn(key: 'component', label: 'Component'),
          AnalyticsColumn(key: 'amount_paisa', label: 'Amount', unit: AnalyticsUnit.paisa),
          AnalyticsColumn(key: 'opening_paisa', label: 'Opening Float', unit: AnalyticsUnit.paisa),
        ],
      );
    }

    if (metric.id == 'variance') {
      final counted = shiftRows.fold<num>(
          0, (sum, r) => sum + (r.cells['counted_paisa'] as num? ?? 0));
      final expected = shiftRows.fold<num>(
          0, (sum, r) => sum + (r.cells['expected_paisa'] as num? ?? 0));
      final variance = counted - expected;

      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Discrepancy = Counted (${_formatPaisa(counted)}) - Expected (${_formatPaisa(expected)}) = ${_formatPaisa(variance)}',
        formulaTotal: variance,
        isReconciled: variance == metric.value,
        contributingRows: shiftRows,
        columns: const [
          AnalyticsColumn(key: 'shift_id', label: 'Shift #'),
          AnalyticsColumn(key: 'status', label: 'Status'),
          AnalyticsColumn(key: 'counted_paisa', label: 'Counted Cash', unit: AnalyticsUnit.paisa),
          AnalyticsColumn(key: 'expected_paisa', label: 'Expected Drawer', unit: AnalyticsUnit.paisa),
          AnalyticsColumn(key: 'variance_paisa', label: 'Discrepancy', unit: AnalyticsUnit.paisa),
        ],
      );
    }

    // Component-level cash metrics
    final componentMap = {
      'opening_float': null,
      'cash_receipts': 'customer_receipts',
      'rider_handovers': 'rider_handovers',
      'pay_in': 'other_pay_ins',
      'cash_refunds': 'refunds',
      'cash_expenses': 'expenses',
      'cash_supplier_payments': 'supplier_payments',
      'cash_payroll_advances': 'payroll_advances',
      'cash_drops': 'cash_drops',
      'other_outflows': 'other_outflows',
    };

    if (metric.id == 'opening_float') {
      final total = shiftRows.fold<num>(
          0, (sum, r) => sum + (r.cells['opening_paisa'] as num? ?? 0));
      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Opening Float = Sum of ${shiftRows.length} shift floats = ${_formatPaisa(total)}',
        formulaTotal: total,
        isReconciled: total == metric.value,
        contributingRows: shiftRows,
        columns: const [
          AnalyticsColumn(key: 'shift_id', label: 'Shift #'),
          AnalyticsColumn(key: 'opening_paisa', label: 'Opening Float', unit: AnalyticsUnit.paisa),
        ],
      );
    }

    final targetComponent = componentMap[metric.id];
    if (targetComponent != null) {
      final matchingEffects = effectRows
          .where((r) => r.cells['component'] == targetComponent)
          .toList();
      final total = matchingEffects.fold<num>(
          0, (sum, r) => sum + (r.cells['amount_paisa'] as num? ?? 0).abs());
      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: '${metric.label} = Sum of ${matchingEffects.length} records = ${_formatPaisa(total)}',
        formulaTotal: total,
        isReconciled: total == (metric.value ?? 0).abs(),
        contributingRows: matchingEffects,
        columns: const [
          AnalyticsColumn(key: 'component', label: 'Component'),
          AnalyticsColumn(key: 'category', label: 'Category'),
          AnalyticsColumn(key: 'amount_paisa', label: 'Amount', unit: AnalyticsUnit.paisa),
        ],
      );
    }

    return _resolveDefault(section, metric, rows: [...shiftRows, ...effectRows]);
  }

  static KpiContributorResult _resolveInventory(AnalyticsSection section, AnalyticsMetric metric) {
    if (metric.id == 'negative_stock') {
      final negRows = section.rows.where((r) {
        final stock = r.cells['current_stock'] as num? ?? 0;
        return stock < 0 || r.cells['is_negative'] == true;
      }).toList();

      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Negative Stock Items = Count of ingredients with current stock < 0 = ${negRows.length}',
        formulaTotal: negRows.length,
        isReconciled: negRows.length == metric.value,
        contributingRows: negRows,
        columns: const [
          AnalyticsColumn(key: 'name', label: 'Ingredient'),
          AnalyticsColumn(key: 'current_stock', label: 'Current Stock', unit: AnalyticsUnit.decimal),
          AnalyticsColumn(key: 'low_stock_threshold', label: 'Low Threshold', unit: AnalyticsUnit.decimal),
          AnalyticsColumn(key: 'storage_unit', label: 'Unit'),
        ],
      );
    }

    if (metric.id == 'low_stock') {
      final lowRows = section.rows.where((r) {
        final stock = r.cells['current_stock'] as num? ?? 0;
        final threshold = r.cells['low_stock_threshold'] as num? ?? 0;
        return stock <= threshold;
      }).toList();

      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Low Stock Items = Count of ingredients at or below threshold = ${lowRows.length}',
        formulaTotal: lowRows.length,
        isReconciled: lowRows.length == metric.value,
        contributingRows: lowRows,
        columns: const [
          AnalyticsColumn(key: 'name', label: 'Ingredient'),
          AnalyticsColumn(key: 'current_stock', label: 'Current Stock', unit: AnalyticsUnit.decimal),
          AnalyticsColumn(key: 'low_stock_threshold', label: 'Low Threshold', unit: AnalyticsUnit.decimal),
        ],
      );
    }

    return _resolveDefault(section, metric);
  }

  static KpiContributorResult _resolveOrders(AnalyticsSection section, AnalyticsMetric metric) {
    final orderRows = section.rows.where((r) => r.sourceType == 'orders').toList();

    if (metric.id == 'committed_orders') {
      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Committed Orders = Count of all confirmed order rows = ${orderRows.length}',
        formulaTotal: orderRows.length,
        isReconciled: orderRows.length == metric.value,
        contributingRows: orderRows,
        columns: const [
          AnalyticsColumn(key: 'order_id', label: 'Order #'),
          AnalyticsColumn(key: 'token', label: 'Token'),
          AnalyticsColumn(key: 'payment_status', label: 'Payment status'),
          AnalyticsColumn(key: 'recorded_value_paisa', label: 'Value', unit: AnalyticsUnit.paisa),
        ],
      );
    }

    if (metric.id == 'cancelled_orders') {
      final cancelledRows = section.rows.where((r) {
        final st = r.cells['payment_status'];
        final action = r.cells['action'];
        return ['CANCELLED', 'VOIDED', 'REFUNDED'].contains(st) || action == 'CANCEL';
      }).toList();

      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Cancelled/Refunded Orders = Count of cancelled, voided or refunded order rows = ${cancelledRows.length}',
        formulaTotal: cancelledRows.length,
        isReconciled: cancelledRows.length == metric.value,
        contributingRows: cancelledRows,
        columns: const [
          AnalyticsColumn(key: 'order_id', label: 'Order #'),
          AnalyticsColumn(key: 'payment_status', label: 'Payment status'),
          AnalyticsColumn(key: 'action', label: 'Action'),
          AnalyticsColumn(key: 'reason', label: 'Reason'),
        ],
      );
    }

    if (metric.id == 'revision_events' || metric.id == 'revised_orders' || metric.id == 'revision_delta') {
      final revisionRows = section.rows.where((r) => r.sourceType == 'order_revisions').toList();
      final totalDelta = revisionRows.fold<num>(
          0, (sum, r) => sum + (r.cells['delta_paisa'] as num? ?? 0));
      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: '${metric.label} = ${revisionRows.length} revisions, delta: ${_formatPaisa(totalDelta)}',
        formulaTotal: metric.id == 'revision_delta' ? totalDelta : revisionRows.length,
        isReconciled: true,
        contributingRows: revisionRows,
        columns: const [
          AnalyticsColumn(key: 'order_id', label: 'Order #'),
          AnalyticsColumn(key: 'revision', label: 'Revision #'),
          AnalyticsColumn(key: 'action', label: 'Action'),
          AnalyticsColumn(key: 'delta_paisa', label: 'Delta', unit: AnalyticsUnit.paisa),
          AnalyticsColumn(key: 'reason', label: 'Reason'),
        ],
      );
    }

    return _resolveDefault(section, metric, rows: orderRows);
  }

  static KpiContributorResult _resolveDelivery(AnalyticsSection section, AnalyticsMetric metric) {
    if (metric.id == 'collection_due' || metric.id == 'all_collection_due') {
      final dueRows = section.rows.where((r) {
        final status = r.cells['payment_status'];
        final due = r.cells['collection_due_paisa'] as num? ?? 0;
        return status == 'COLLECTION_DUE' || due > 0;
      }).toList();

      final total = dueRows.fold<num>(
          0, (sum, r) => sum + (r.cells['collection_due_paisa'] as num? ?? 0));

      return KpiContributorResult(
        metric: metric,
        family: section.family,
        formula: 'Collection Due = Sum of ${dueRows.length} outstanding COD orders = ${_formatPaisa(total)}',
        formulaTotal: total,
        isReconciled: total == metric.value,
        contributingRows: dueRows,
        columns: const [
          AnalyticsColumn(key: 'order_id', label: 'Order #'),
          AnalyticsColumn(key: 'payment_status', label: 'Payment Status'),
          AnalyticsColumn(key: 'collection_due_paisa', label: 'Collection Due', unit: AnalyticsUnit.paisa),
        ],
      );
    }

    return _resolveDefault(section, metric);
  }

  static KpiContributorResult _resolveProcurement(AnalyticsSection section, AnalyticsMetric metric) {
    final mandiRows = section.rows
        .where((r) => r.cells['kind'] == 'Mandi procurement' || r.sourceType == 'mandi_procurements')
        .toList();
    final total = mandiRows.fold<num>(
        0, (sum, r) => sum + (r.cells['spend_paisa'] as num? ?? 0));

    return KpiContributorResult(
      metric: metric,
      family: section.family,
      formula: '${metric.label} = Sum of ${mandiRows.length} procurement orders = ${_formatPaisa(total)}',
      formulaTotal: total,
      isReconciled: total == (metric.value ?? 0),
      contributingRows: mandiRows,
      columns: const [
        AnalyticsColumn(key: 'purchase_id', label: 'Purchase #'),
        AnalyticsColumn(key: 'supplier_name', label: 'Supplier / Source'),
        AnalyticsColumn(key: 'base_quantity', label: 'Quantity', unit: AnalyticsUnit.decimal),
        AnalyticsColumn(key: 'spend_paisa', label: 'Total Cost', unit: AnalyticsUnit.paisa),
      ],
    );
  }

  static KpiContributorResult _resolveSuppliers(AnalyticsSection section, AnalyticsMetric metric) {
    final supplierRows = section.rows
        .where((r) => r.sourceType == 'vendor_khata' || r.cells['current_balance_paisa'] != null)
        .toList();
    final total = supplierRows.fold<num>(
        0, (sum, r) => sum + (r.cells['current_balance_paisa'] as num? ?? 0));

    return KpiContributorResult(
      metric: metric,
      family: section.family,
      formula: '${metric.label} = Outstanding balance across ${supplierRows.length} suppliers = ${_formatPaisa(total)}',
      formulaTotal: total,
      isReconciled: total == (metric.value ?? 0),
      contributingRows: supplierRows,
      columns: const [
        AnalyticsColumn(key: 'supplier_name', label: 'Supplier'),
        AnalyticsColumn(key: 'current_balance_paisa', label: 'Current Balance', unit: AnalyticsUnit.paisa),
      ],
    );
  }

  static KpiContributorResult _resolveExpenses(AnalyticsSection section, AnalyticsMetric metric) {
    final expenseRows = section.rows
        .where((r) => r.cells['amount_paisa'] != null || r.sourceType == 'cash_movements')
        .toList();
    final total = expenseRows.fold<num>(
        0, (sum, r) => sum + (r.cells['amount_paisa'] as num? ?? 0).abs());

    return KpiContributorResult(
      metric: metric,
      family: section.family,
      formula: '${metric.label} = Sum of ${expenseRows.length} expenses = ${_formatPaisa(total)}',
      formulaTotal: total,
      isReconciled: total == (metric.value ?? 0),
      contributingRows: expenseRows,
      columns: const [
        AnalyticsColumn(key: 'category', label: 'Category'),
        AnalyticsColumn(key: 'notes', label: 'Notes'),
        AnalyticsColumn(key: 'amount_paisa', label: 'Amount', unit: AnalyticsUnit.paisa),
      ],
    );
  }

  static KpiContributorResult _resolveStaff(AnalyticsSection section, AnalyticsMetric metric) {
    final staffRows = section.rows
        .where((r) => r.sourceType == 'staff' || r.sourceType == 'staff_payroll')
        .toList();

    final num formulaTotal = switch (metric.id) {
      'staff_count' => staffRows.length,
      'active_staff' => staffRows.where((r) => r.cells['is_active'] == 1 || r.cells['is_active'] == true).length,
      'login_enabled' => staffRows.where((r) => r.cells['login_enabled'] == 1 || r.cells['login_enabled'] == true).length,
      _ => metric.value ?? staffRows.length,
    };

    return KpiContributorResult(
      metric: metric,
      family: section.family,
      formula: '${metric.label} across ${staffRows.length} staff records',
      formulaTotal: formulaTotal,
      isReconciled: formulaTotal == (metric.value ?? 0),
      contributingRows: staffRows,
      columns: section.columns.isNotEmpty
          ? section.columns
          : const [
              AnalyticsColumn(key: 'name', label: 'Staff Name'),
              AnalyticsColumn(key: 'role', label: 'Role'),
            ],
    );
  }

  static KpiContributorResult _resolveDefault(
    AnalyticsSection section,
    AnalyticsMetric metric, {
    List<AnalyticsRow>? rows,
  }) {
    final targetRows = rows ?? section.rows;
    return KpiContributorResult(
      metric: metric,
      family: section.family,
      formula: '${metric.label}: ${metric.value != null ? (metric.unit == AnalyticsUnit.paisa ? _formatPaisa(metric.value) : metric.value.toString()) : "Unavailable"}',
      formulaTotal: metric.value,
      isReconciled: true,
      contributingRows: targetRows,
      columns: section.columns,
      emptyOrMissingNote: targetRows.isEmpty
          ? 'No contributing snapshot rows found for this metric in current selection.'
          : null,
    );
  }
}
