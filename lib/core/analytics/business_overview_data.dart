part of 'analytics_models.dart';

enum OverviewAttentionKind { countCoverage, profitCoverage, negativeStock, discrepancy, reportDelivery }

class OverviewAttention {
  const OverviewAttention(this.title, this.description, this.action, this.family, this.kind);
  final String title, description, action;
  final AnalyticsFamily family;
  final OverviewAttentionKind kind;
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

    final alerts = <OverviewAttention>[];
    final coverage = _metric(AnalyticsFamily.cash, 'count_coverage');
    if (coverage?.sampleCount != null && coverage?.populationCount != null &&
        coverage!.sampleCount! < coverage.populationCount!) {
      alerts.add(OverviewAttention('Drawer count incomplete',
        '${coverage.sampleCount} of ${coverage.populationCount} selected shifts counted',
        'Review shifts', AnalyticsFamily.cash, OverviewAttentionKind.countCoverage));
    }
    final profit = _metric(AnalyticsFamily.overview, 'gross_profit');
    if (profit != null && profit.value == null && profit.quality == AnalyticsQuality.missing) {
      alerts.add(OverviewAttention('Gross profit unavailable', 'Required cost data is missing',
        'Review cost data', AnalyticsFamily.profitability, OverviewAttentionKind.profitCoverage));
    }
    final negative = _metric(AnalyticsFamily.overview, 'negative_stock');
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

    this.primary = List.unmodifiable(primary);
    this.position = List.unmodifiable(position);
    this.additional = List.unmodifiable(additional);
    this.alerts = List.unmodifiable(alerts);
  }
  final AnalyticsSnapshot _snapshot;
  late final List<AnalyticsMetric> primary, position, additional;
  late final List<OverviewAttention> alerts;

  AnalyticsMetric? _metric(AnalyticsFamily family, String id) {
    for (final section in _snapshot.sections.where((s) => s.family == family)) {
      for (final metric in section.metrics) {
        if (metric.id == id) return metric;
      }
    }
    return null;
  }

}
