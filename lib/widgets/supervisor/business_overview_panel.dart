import 'package:flutter/material.dart';

import '../../core/analytics/analytics_models.dart';
import '../../core/theme/theme.dart';

/// Composes the overview from the same authorized snapshot used for exports.
/// Attention links change report only; they never mutate operational records.
class BusinessOverviewPanel extends StatelessWidget {
  const BusinessOverviewPanel({super.key, required this.snapshot,
    required this.metricGrid, required this.salesChart, required this.dayDetails,
    required this.onReport});

  final AnalyticsSnapshot snapshot;
  final Widget Function(List<AnalyticsMetric>, int) metricGrid;
  final Widget salesChart;
  final Widget dayDetails;
  final ValueChanged<AnalyticsFamily> onReport;

  AnalyticsMetric? _metric(AnalyticsFamily family, String id) {
    for (final section in snapshot.sections.where((s) => s.family == family)) {
      for (final metric in section.metrics) {
        if (metric.id == id) return metric;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final overview = snapshot.sections.where((s) => s.family == AnalyticsFamily.overview).firstOrNull;
    final primary = overview?.metrics.where((m) =>
      ['recorded_value', 'orders', 'average_ticket', 'collection_due'].contains(m.id)).toList() ?? [];
    // Older/custom snapshot providers can still expose their own overview metrics.
    if (primary.isEmpty && overview != null) primary.addAll(overview.metrics.take(4));
    final position = overview?.metrics.where((m) =>
      ['all_collection_due', 'expected_drawer', 'negative_stock'].contains(m.id)).toList() ?? [];
    final alerts = <_Attention>[];
    final coverage = _metric(AnalyticsFamily.cash, 'count_coverage');
    if (coverage?.sampleCount != null && coverage?.populationCount != null &&
        coverage!.sampleCount! < coverage.populationCount!) {
      alerts.add(_Attention('Drawer count incomplete',
        '${coverage.sampleCount} of ${coverage.populationCount} selected shifts counted',
        'Review shifts', AnalyticsFamily.cash, Icons.receipt_long_outlined));
    }
    final profit = _metric(AnalyticsFamily.overview, 'gross_profit');
    if (profit != null && profit.value == null && profit.quality == AnalyticsQuality.missing) {
      alerts.add(_Attention('Gross profit unavailable', 'Required cost data is missing',
        'Review cost data', AnalyticsFamily.profitability, Icons.bar_chart_rounded));
    }
    final negative = _metric(AnalyticsFamily.overview, 'negative_stock');
    if ((negative?.value ?? 0) > 0) {
      alerts.add(_Attention('Negative stock', '${negative!.value!.toInt()} ingredients below zero',
        'Review inventory', AnalyticsFamily.inventory, Icons.inventory_2_outlined));
    }
    final discrepancy = _metric(AnalyticsFamily.cash, 'unresolved_discrepancies');
    if ((discrepancy?.value ?? 0) > 0) {
      alerts.add(_Attention('Cash discrepancies need review',
        '${discrepancy!.value!.toInt()} selected shifts flagged', 'Review discrepancies',
        AnalyticsFamily.cash, Icons.account_balance_wallet_outlined));
    }
    final delivery = _metric(AnalyticsFamily.audit, 'delivery_attention');
    if ((delivery?.value ?? 0) > 0) {
      alerts.add(_Attention('Report delivery needs review',
        '${delivery!.value!.toInt()} failed or uncertain deliveries', 'Review delivery',
        AnalyticsFamily.audit, Icons.outgoing_mail));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      metricGrid(primary, 4),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, constraints) {
        final attention = _attentionPanel(context, alerts);
        if (constraints.maxWidth < 920) {
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            salesChart, const SizedBox(height: 16), attention,
          ]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 5, child: salesChart), const SizedBox(width: 16),
          Expanded(flex: 3, child: attention),
        ]);
      }),
      if (position.isNotEmpty) ...[
        const SizedBox(height: 18),
        const Row(children: [
          Icon(Icons.inventory_2_outlined, color: StreetFoodMafiaColors.cartelYellow, size: 21),
          SizedBox(width: 10),
          Text('Cash & inventory', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 10),
        metricGrid(position, 3),
      ],
      const SizedBox(height: 16),
      dayDetails,
    ]);
  }

  Widget _attentionPanel(BuildContext context, List<_Attention> alerts) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(color: StreetFoodMafiaColors.darkNavy,
      border: Border.all(color: StreetFoodMafiaColors.border), borderRadius: BorderRadius.circular(12)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(alerts.isEmpty ? Icons.check_circle_outline : Icons.warning_amber_rounded,
          size: 23, color: alerts.isEmpty ? StreetFoodMafiaColors.statusReady : StreetFoodMafiaColors.cartelYellow),
        const SizedBox(width: 9),
        const Expanded(child: Text('Needs attention', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
        Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(color: StreetFoodMafiaColors.cardSurface, borderRadius: BorderRadius.circular(20)),
          child: Text('${alerts.length}', style: const TextStyle(color: StreetFoodMafiaColors.cartelYellow))),
      ]),
      if (alerts.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('No issues detected in the available checks. Review individual reports for coverage.',
          style: TextStyle(color: StreetFoodMafiaColors.secondaryText, height: 1.5))),
      for (var index = 0; index < alerts.length; index++) ...[
        if (index > 0) const Divider(height: 24),
        Padding(padding: const EdgeInsets.only(top: 16), child: _attentionRow(alerts[index])),
      ],
    ]),
  );

  Widget _attentionRow(_Attention alert) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 38, height: 38, decoration: BoxDecoration(
      color: StreetFoodMafiaColors.cardSurface, borderRadius: BorderRadius.circular(12)),
      child: Icon(alert.icon, color: StreetFoodMafiaColors.cartelYellow, size: 21)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(alert.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      Text(alert.description, style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
      TextButton.icon(onPressed: () => onReport(alert.family),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft),
        icon: const Icon(Icons.arrow_forward_rounded, size: 16), label: Text(alert.action)),
    ])),
  ]);
}

class _Attention {
  const _Attention(this.title, this.description, this.action, this.family, this.icon);
  final String title, description, action;
  final AnalyticsFamily family;
  final IconData icon;
}
