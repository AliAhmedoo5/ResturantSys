part of 'analytics_models.dart';

enum OverviewAttentionKind { countCoverage, profitCoverage, negativeStock, discrepancy, reportDelivery, unsettledCod }

class OverviewAttention {
  const OverviewAttention(this.title, this.description, this.action, this.family, this.kind);
  final String title, description, action;
  final AnalyticsFamily family;
  final OverviewAttentionKind kind;
}

class MenuMarginItem {
  const MenuMarginItem({
    required this.name,
    required this.quantity,
    required this.netSalesPaisa,
    this.bomRecipeCostPaisa,
    this.marginPaisa,
    this.marginRate,
    this.foodCostRate,
    required this.hasBom,
  });
  final String name;
  final int quantity;
  final int netSalesPaisa;
  final int? bomRecipeCostPaisa;
  final int? marginPaisa;
  final double? marginRate;
  final double? foodCostRate;
  final bool hasBom;
}

class MenuMarginData {
  const MenuMarginData({
    required this.starContributors,
    required this.foodCostTraps,
    required this.uncostedItems,
  });
  final List<MenuMarginItem> starContributors;
  final List<MenuMarginItem> foodCostTraps;
  final List<MenuMarginItem> uncostedItems;

  bool get hasData => starContributors.isNotEmpty || foodCostTraps.isNotEmpty || uncostedItems.isNotEmpty;
  bool get hasMissingBom => uncostedItems.isNotEmpty;
}

class BottlenecksData {
  const BottlenecksData({
    this.prepMedianMinutes,
    this.prepP90Minutes,
    this.prepCoverageCount,
    this.prepCoverageTotal,
    this.reworkCycles = 0,
    this.transitP90Minutes,
    this.lateDeliveries = 0,
    this.targetEtaMinutes = 45.0,
    this.peakHour,
    this.peakHourOrders = 0,
    this.peakHourSalesPaisa = 0,
  });
  final double? prepMedianMinutes;
  final double? prepP90Minutes;
  final int? prepCoverageCount;
  final int? prepCoverageTotal;
  final int reworkCycles;
  final double? transitP90Minutes;
  final int lateDeliveries;
  final double targetEtaMinutes;
  final int? peakHour;
  final int peakHourOrders;
  final int peakHourSalesPaisa;

  bool get hasData => prepMedianMinutes != null || prepP90Minutes != null || peakHour != null;
}

class RiskRadarData {
  const RiskRadarData({
    this.unsettledCodOver24hPaisa = 0,
    this.unresolvedDrawerVariances = 0,
    this.cashVariancePaisa,
    this.negativeStockCount = 0,
    required this.alerts,
  });
  final int unsettledCodOver24hPaisa;
  final int unresolvedDrawerVariances;
  final int? cashVariancePaisa;
  final int negativeStockCount;
  final List<OverviewAttention> alerts;

  bool get hasAlerts => alerts.isNotEmpty || hasActiveRisks;
  bool get hasActiveRisks => unsettledCodOver24hPaisa > 0 || unresolvedDrawerVariances > 0 || negativeStockCount > 0;
}

/// Meaning and report destinations for the Business overview, without widgets.
class BusinessOverviewData {
  BusinessOverviewData(this._snapshot) {
    final overview = _snapshot.sections.where((s) => s.family == AnalyticsFamily.overview).firstOrNull;
    final primary = overview?.metrics.where((m) =>
      ['recorded_value', 'orders', 'average_ticket', 'collection_due'].contains(m.id)).toList() ?? [];
    // Older/custom snapshot providers can still expose their own overview metrics.
    if (primary.isEmpty && overview != null) primary.addAll(overview.metrics.take(4));
    final position = overview?.metrics.where((m) =>
      ['all_collection_due', 'expected_drawer', 'negative_stock'].contains(m.id)).toList() ?? [];
    final displayed = {...primary.map((m) => m.id), ...position.map((m) => m.id)};
    final additional = overview?.metrics.where((m) => !displayed.contains(m.id)).toList() ?? [];

    // Synthesize Executive KPI Scorecard (standardized 4 core headline metrics in primary)
    final grossProfit = _metric(AnalyticsFamily.overview, 'gross_profit') ??
      _metric(AnalyticsFamily.profitability, 'gross_profit');
    final scorecard = <AnalyticsMetric>[];
    for (final m in primary) {
      if (m.id == 'collection_due' && grossProfit != null && grossProfit.quality == AnalyticsQuality.complete) {
        scorecard.add(grossProfit);
      } else {
        scorecard.add(m);
      }
    }
    if (scorecard.length < 4 && grossProfit != null && !scorecard.any((m) => m.id == 'gross_profit')) {
      scorecard.add(grossProfit);
    }

    // Tender breakdown for cash vs digital collections
    int? cashCollectionsPaisa;
    int? digitalCollectionsPaisa;
    final salesSection = _snapshot.sections.where((s) => s.family == AnalyticsFamily.sales).firstOrNull;
    if (salesSection != null) {
      for (final row in salesSection.rows) {
        if (row.cells['kind'] == 'Tender breakdown') {
          final dim = row.cells['dimension_value']?.toString().toUpperCase();
          final collected = _asInt(row.cells['collected_paisa']) ?? 0;
          if (dim == 'CASH') {
            cashCollectionsPaisa = (cashCollectionsPaisa ?? 0) + collected;
          } else {
            digitalCollectionsPaisa = (digitalCollectionsPaisa ?? 0) + collected;
          }
        }
      }
    }
    if (cashCollectionsPaisa != null && !scorecard.any((m) => m.id == 'cash_collections')) {
      scorecard.add(AnalyticsMetric(
        id: 'cash_collections',
        label: 'Cash collections',
        value: cashCollectionsPaisa,
        unit: AnalyticsUnit.paisa,
        explanation: 'Customer cash collected via cash drawer tenders',
      ));
    }
    if (digitalCollectionsPaisa != null && !scorecard.any((m) => m.id == 'digital_collections')) {
      scorecard.add(AnalyticsMetric(
        id: 'digital_collections',
        label: 'Digital collections',
        value: digitalCollectionsPaisa,
        unit: AnalyticsUnit.paisa,
        explanation: 'Card and digital wallet receipts',
      ));
    }

    // Food cost BOM %
    final foodCogs = _metric(AnalyticsFamily.profitability, 'food_cogs');
    final netSales = _metric(AnalyticsFamily.overview, 'recorded_value') ??
      _metric(AnalyticsFamily.sales, 'recorded_value');
    if (foodCogs != null && netSales?.value != null && (netSales!.value! > 0) && foodCogs.value != null) {
      final percent = (foodCogs.value! / netSales.value! * 100);
      if (!scorecard.any((m) => m.id == 'food_cost_bom_percent')) {
        scorecard.add(AnalyticsMetric(
          id: 'food_cost_bom_percent',
          label: 'Food Cost % (BOM)',
          value: percent,
          unit: AnalyticsUnit.percent,
          explanation: 'Historical food COGS vs net sales',
        ));
      }
    }

    // Cash Discrepancy & Wastage
    final cashDiscrepancy = _metric(AnalyticsFamily.cash, 'variance');
    if (cashDiscrepancy != null && cashDiscrepancy.value != null && !scorecard.any((m) => m.id == 'variance')) {
      scorecard.add(cashDiscrepancy);
    }
    final wasteLoss = _metric(AnalyticsFamily.profitability, 'waste_loss');
    if (wasteLoss != null && wasteLoss.value != null && !scorecard.any((m) => m.id == 'waste_loss')) {
      scorecard.add(wasteLoss);
    }

    // 2. Menu Margin Intelligence
    final menuSection = _snapshot.sections.where((s) => s.family == AnalyticsFamily.menu).firstOrNull;
    final starContributors = <MenuMarginItem>[];
    final foodCostTraps = <MenuMarginItem>[];
    final uncostedItems = <MenuMarginItem>[];

    if (menuSection != null) {
      final items = <MenuMarginItem>[];
      for (final row in menuSection.rows) {
        if (row.cells['kind'] == 'Item/deal aggregate') {
          final name = row.cells['name']?.toString() ?? 'Unnamed item';
          final quantity = _asInt(row.cells['quantity']) ?? 0;
          final netSalesPaisa = _asInt(row.cells['net_sales_paisa']) ?? 0;
          final bomCost = _asInt(row.cells['bom_recipe_cost_paisa']);
          final marginPaisa = _asInt(row.cells['margin_paisa']);
          final marginRate = _asDouble(row.cells['margin_rate']);
          final hasBom = bomCost != null;
          final foodCostRate = (hasBom && netSalesPaisa > 0) ? (bomCost / netSalesPaisa * 100) : null;

          final item = MenuMarginItem(
            name: name,
            quantity: quantity,
            netSalesPaisa: netSalesPaisa,
            bomRecipeCostPaisa: bomCost,
            marginPaisa: marginPaisa,
            marginRate: marginRate,
            foodCostRate: foodCostRate,
            hasBom: hasBom,
          );
          items.add(item);
          if (!hasBom) {
            uncostedItems.add(item);
          }
        }
      }

      // Top 3 Star Contributors (highest margin_paisa)
      final withMargin = items.where((i) => i.hasBom && i.marginPaisa != null).toList()
        ..sort((a, b) => b.marginPaisa!.compareTo(a.marginPaisa!));
      starContributors.addAll(withMargin.take(3));

      // Top 3 Food Cost Traps (highest volume with food cost % > 40%)
      final traps = items.where((i) => i.hasBom && i.foodCostRate != null && i.foodCostRate! > 40.0).toList()
        ..sort((a, b) => b.quantity.compareTo(a.quantity));
      foodCostTraps.addAll(traps.take(3));
    }

    // 3. Kitchen & Fulfillment Bottlenecks
    final prepMedian = _metric(AnalyticsFamily.orders, 'prep_median');
    final prepP90 = _metric(AnalyticsFamily.orders, 'prep_p90');
    final prepCoverage = _metric(AnalyticsFamily.orders, 'prep_coverage');
    final reworkCycles = _metric(AnalyticsFamily.orders, 'rework_cycles')?.value?.toInt() ?? 0;
    final transitP90 = _metric(AnalyticsFamily.delivery, 'travel_p90');
    final lateDeliveries = _metric(AnalyticsFamily.delivery, 'late_deliveries')?.value?.toInt() ?? 0;

    int? peakHour;
    var peakHourOrders = 0;
    var peakHourSales = 0;
    if (salesSection != null) {
      for (final row in salesSection.rows) {
        if (row.cells['kind'] == 'Hourly breakdown') {
          final orders = _asInt(row.cells['orders']) ?? 0;
          if (orders > peakHourOrders) {
            peakHourOrders = orders;
            peakHour = _asInt(row.cells['dimension_value']);
            peakHourSales = _asInt(row.cells['recorded_value_paisa']) ?? 0;
          }
        }
      }
    }

    // 4. Risk & Leakage Radar
    final alerts = <OverviewAttention>[];
    final coverage = _metric(AnalyticsFamily.cash, 'count_coverage');
    if (coverage?.sampleCount != null && coverage?.populationCount != null &&
        coverage!.sampleCount! < coverage.populationCount!) {
      alerts.add(OverviewAttention('Drawer count incomplete',
        '${coverage.sampleCount} of ${coverage.populationCount} selected shifts counted',
        'Review shifts', AnalyticsFamily.cash, OverviewAttentionKind.countCoverage));
    }
    final profit = _metric(AnalyticsFamily.overview, 'gross_profit') ??
      _metric(AnalyticsFamily.profitability, 'gross_profit');
    if (profit != null && profit.value == null && profit.quality == AnalyticsQuality.missing) {
      alerts.add(const OverviewAttention('Gross profit unavailable', 'Required cost data is missing',
        'Review cost data', AnalyticsFamily.profitability, OverviewAttentionKind.profitCoverage));
    }
    final negative = _metric(AnalyticsFamily.inventory, 'negative_stock') ??
      _metric(AnalyticsFamily.overview, 'negative_stock');
    if ((negative?.value ?? 0) > 0) {
      alerts.add(OverviewAttention('Negative stock', '${negative!.value!.toInt()} ingredients below zero',
        'Review inventory', AnalyticsFamily.inventory, OverviewAttentionKind.negativeStock));
    }
    final discrepancy = _metric(AnalyticsFamily.cash, 'unresolved_discrepancies');
    if ((discrepancy?.value ?? 0) > 0) {
      alerts.add(OverviewAttention('Cash discrepancies need review',
        '${discrepancy!.value!.toInt()} selected shifts flagged', 'Review discrepancies',
        AnalyticsFamily.cash, OverviewAttentionKind.discrepancy));
    }
    final delivery = _metric(AnalyticsFamily.audit, 'delivery_attention');
    if ((delivery?.value ?? 0) > 0) {
      alerts.add(OverviewAttention('Report delivery needs review',
        '${delivery!.value!.toInt()} failed or uncertain deliveries', 'Review delivery',
        AnalyticsFamily.audit, OverviewAttentionKind.reportDelivery));
    }

    final cod1to3d = _metric(AnalyticsFamily.delivery, 'cod_aging_1_3d_paisa')?.value?.toInt() ?? 0;
    final codCritical = _metric(AnalyticsFamily.delivery, 'cod_aging_critical_paisa')?.value?.toInt() ?? 0;
    final unsettledCod24h = cod1to3d + codCritical;
    if (unsettledCod24h > 0) {
      final formatted = NumberFormat('#,##0.00').format(unsettledCod24h / 100);
      alerts.add(OverviewAttention(
        'Unsettled COD aging > 24h',
        'PKR $formatted aged beyond 24 hours requiring settlement',
        'Review delivery',
        AnalyticsFamily.delivery,
        OverviewAttentionKind.unsettledCod,
      ));
    }

    final unresolvedVariances = discrepancy?.value?.toInt() ?? 0;
    final cashVariance = _metric(AnalyticsFamily.cash, 'variance')?.value?.toInt();
    final negStockCount = negative?.value?.toInt() ?? 0;

    this.primary = List.unmodifiable(scorecard.isNotEmpty ? scorecard : primary);
    this.position = List.unmodifiable(position);
    this.additional = List.unmodifiable(additional);
    this.alerts = List.unmodifiable(alerts);
    this.menuMargin = MenuMarginData(
      starContributors: List.unmodifiable(starContributors),
      foodCostTraps: List.unmodifiable(foodCostTraps),
      uncostedItems: List.unmodifiable(uncostedItems),
    );
    this.bottlenecks = BottlenecksData(
      prepMedianMinutes: prepMedian?.value?.toDouble(),
      prepP90Minutes: prepP90?.value?.toDouble(),
      prepCoverageCount: prepCoverage?.sampleCount,
      prepCoverageTotal: prepCoverage?.populationCount,
      reworkCycles: reworkCycles,
      transitP90Minutes: transitP90?.value?.toDouble(),
      lateDeliveries: lateDeliveries,
      targetEtaMinutes: 45.0,
      peakHour: peakHour,
      peakHourOrders: peakHourOrders,
      peakHourSalesPaisa: peakHourSales,
    );
    this.riskRadar = RiskRadarData(
      unsettledCodOver24hPaisa: unsettledCod24h,
      unresolvedDrawerVariances: unresolvedVariances,
      cashVariancePaisa: cashVariance,
      negativeStockCount: negStockCount,
      alerts: List.unmodifiable(alerts),
    );
  }

  final AnalyticsSnapshot _snapshot;
  late final List<AnalyticsMetric> primary, position, additional;
  late final List<OverviewAttention> alerts;
  late final MenuMarginData menuMargin;
  late final BottlenecksData bottlenecks;
  late final RiskRadarData riskRadar;

  AnalyticsMetric? _metric(AnalyticsFamily family, String id) {
    for (final section in _snapshot.sections.where((s) => s.family == family)) {
      for (final metric in section.metrics) {
        if (metric.id == id) return metric;
      }
    }
    return null;
  }
}

int? _asInt(Object? val) {
  if (val == null) return null;
  if (val is num) return val.toInt();
  if (val is String) {
    final clean = val.contains(':') ? val.split(':').first : val;
    return int.tryParse(clean.trim());
  }
  return null;
}

double? _asDouble(Object? val) {
  if (val == null) return null;
  if (val is num) return val.toDouble();
  if (val is String) return double.tryParse(val.trim());
  return null;
}

