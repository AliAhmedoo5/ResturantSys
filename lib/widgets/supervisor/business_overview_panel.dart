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

  @override
  Widget build(BuildContext context) {
    final data = snapshot.overview;
    final primary = data.primary;
    final position = data.position;
    final additional = data.additional;
    final alerts = data.alerts;

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
      if (additional.isNotEmpty) ExpansionTile(tilePadding: EdgeInsets.zero,
        title: const Text('Additional overview measures', style: TextStyle(fontSize: 13)),
        children: [metricGrid(additional, 3)]),
    ]);
  }

  Widget _attentionPanel(BuildContext context, List<OverviewAttention> alerts) => Container(
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
        if (index > 0) const Divider(height: 16),
        Padding(padding: const EdgeInsets.only(top: 12), child: _attentionRow(alerts[index])),
      ],
    ]),
  );

  Widget _attentionRow(OverviewAttention alert) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Container(width: 38, height: 38, decoration: BoxDecoration(
      color: StreetFoodMafiaColors.cardSurface, borderRadius: BorderRadius.circular(12)),
      child: Icon(switch (alert.kind) {
        OverviewAttentionKind.countCoverage => Icons.receipt_long_outlined,
        OverviewAttentionKind.profitCoverage => Icons.bar_chart_rounded,
        OverviewAttentionKind.negativeStock => Icons.inventory_2_outlined,
        OverviewAttentionKind.discrepancy => Icons.account_balance_wallet_outlined,
        OverviewAttentionKind.reportDelivery => Icons.outgoing_mail,
      }, color: StreetFoodMafiaColors.cartelYellow, size: 21)),
    const SizedBox(width: 12),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(alert.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      Text(alert.description, style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
      TextButton.icon(onPressed: () => onReport(alert.family),
        style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft,
          minimumSize: const Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        icon: const Icon(Icons.arrow_forward_rounded, size: 16), label: Text(alert.action)),
    ])),
  ]);
}
