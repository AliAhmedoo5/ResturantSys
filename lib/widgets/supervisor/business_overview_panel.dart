import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/analytics/analytics_models.dart';
import '../../core/theme/theme.dart';

/// Composes the executive overview from the same authorized snapshot used for exports.
/// Synthesizes four commercial pillars:
/// 1. Executive KPI Scorecard
/// 2. Menu Margin Intelligence (Star Contributors vs Food Cost Traps & Missing Recipe BOM)
/// 3. Kitchen & Fulfillment Bottlenecks (p50/p90 preparation duration & peak orders)
/// 4. Risk & Leakage Radar (Unsettled COD > 24h, unresolved drawer variances, negative stock)
class BusinessOverviewPanel extends StatelessWidget {
  const BusinessOverviewPanel({
    super.key,
    required this.snapshot,
    required this.metricGrid,
    required this.salesChart,
    required this.dayDetails,
    required this.onReport,
  });

  final AnalyticsSnapshot snapshot;
  final Widget Function(List<AnalyticsMetric>, int) metricGrid;
  final Widget salesChart;
  final Widget dayDetails;
  final ValueChanged<AnalyticsFamily> onReport;

  static String _formatPaisa(int paisa) =>
      'PKR ${NumberFormat('#,##0.00').format(paisa / 100)}';

  @override
  Widget build(BuildContext context) {
    final data = snapshot.overview;
    final primary = data.primary;
    final position = data.position;
    final additional = data.additional;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pillar 1: Executive KPI Scorecard
        _sectionHeader(
          icon: Icons.dashboard_customize_outlined,
          title: 'Executive KPI Scorecard',
          badgeText: '${primary.length} metrics',
        ),
        const SizedBox(height: 12),
        metricGrid(primary, 4),
        const SizedBox(height: 20),

        // Responsive Middle Section: Pillars 2, 3, 4 + Sales Chart
        LayoutBuilder(builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 920;

          final menuMarginCard = _menuMarginCard(context, data.menuMargin);
          final bottlenecksCard = _bottlenecksCard(context, data.bottlenecks);
          final riskRadarCard = _riskRadarCard(context, data.riskRadar);

          if (!isWide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                salesChart,
                const SizedBox(height: 16),
                riskRadarCard,
                const SizedBox(height: 16),
                menuMarginCard,
                const SizedBox(height: 16),
                bottlenecksCard,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: salesChart),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: riskRadarCard),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: menuMarginCard),
                  const SizedBox(width: 16),
                  Expanded(flex: 3, child: bottlenecksCard),
                ],
              ),
            ],
          );
        }),

        if (position.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionHeader(
            icon: Icons.inventory_2_outlined,
            title: 'Cash & inventory',
          ),
          const SizedBox(height: 12),
          metricGrid(position, 3),
        ],

        const SizedBox(height: 20),
        dayDetails,

        if (additional.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Additional overview measures', style: TextStyle(fontSize: 13)),
            children: [metricGrid(additional, 3)],
          ),
        ],
      ],
    );
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    String? badgeText,
  }) =>
      Row(
        children: [
          Icon(icon, color: StreetFoodMafiaColors.cartelYellow, size: 21),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (badgeText != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: StreetFoodMafiaColors.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: StreetFoodMafiaColors.border),
              ),
              child: Text(
                badgeText,
                style: const TextStyle(
                  fontSize: 11,
                  color: StreetFoodMafiaColors.secondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      );

  // Pillar 2: Menu Margin Intelligence Card
  Widget _menuMarginCard(BuildContext context, MenuMarginData menuMargin) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: StreetFoodMafiaColors.darkNavy,
          border: Border.all(color: StreetFoodMafiaColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (context, constraints) {
              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.restaurant_menu_rounded, color: StreetFoodMafiaColors.cartelYellow, size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('Menu Margin Intelligence',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      onPressed: () => onReport(AnalyticsFamily.menu),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text('View menu report'),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  const Icon(Icons.restaurant_menu_rounded, color: StreetFoodMafiaColors.cartelYellow, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Menu Margin Intelligence',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  TextButton(
                    onPressed: () => onReport(AnalyticsFamily.menu),
                    style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: const Text('View menu report'),
                  ),
                ],
              );
            }),
            const SizedBox(height: 14),

            if (!menuMargin.hasData)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text(
                  'No menu item margin data recorded for this selection. Ensure recipe BOMs are configured.',
                  style: TextStyle(color: StreetFoodMafiaColors.secondaryText, height: 1.4),
                ),
              )
            else ...[
              // Missing Recipe BOM disclosure banner
              if (menuMargin.hasMissingBom) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Wrap(
                              spacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  'Missing Recipe BOM',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                                Text(
                                  '· Cost evidence absent',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: StreetFoodMafiaColors.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              menuMargin.uncostedItems.map((i) => '${i.name} (${i.quantity} sold)').join(', '),
                              style: const TextStyle(
                                fontSize: 11,
                                color: StreetFoodMafiaColors.secondaryText,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Top 3 Star Contributors
              _subSectionTitle('Star Contributors', 'Top 3 high-margin profit drivers', Icons.star_rounded, const Color(0xFF10B981)),
              const SizedBox(height: 8),
              if (menuMargin.starContributors.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Text('No star contributors identified with complete BOM.', style: TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
                )
              else
                for (final item in menuMargin.starContributors) ...[
                  _marginItemRow(
                    name: item.name,
                    subtitle: '${item.quantity} sold · ${item.marginRate != null ? "${item.marginRate!.toStringAsFixed(1)}% margin" : ""}',
                    trailingValue: _formatPaisa(item.marginPaisa ?? 0),
                    trailingLabel: 'Net profit',
                    accentColor: const Color(0xFF10B981),
                  ),
                  const SizedBox(height: 8),
                ],

              const SizedBox(height: 12),
              const Divider(color: StreetFoodMafiaColors.border, height: 1),
              const SizedBox(height: 14),

              // Top 3 Food Cost Traps
              _subSectionTitle('Food Cost Traps', 'High-volume items with food cost > 40%', Icons.error_outline_rounded, const Color(0xFFEF4444)),
              const SizedBox(height: 8),
              if (menuMargin.foodCostTraps.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('No high-volume items exceed 40% food cost BOM.', style: TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
                )
              else
                for (final item in menuMargin.foodCostTraps) ...[
                  _marginItemRow(
                    name: item.name,
                    subtitle: '${item.quantity} sold · Food cost ${_formatPaisa(item.bomRecipeCostPaisa ?? 0)}',
                    trailingValue: '${item.foodCostRate?.toStringAsFixed(1)}% BOM',
                    trailingLabel: 'Food cost rate',
                    accentColor: const Color(0xFFEF4444),
                  ),
                  const SizedBox(height: 8),
                ],
            ],
          ],
        ),
      );

  Widget _subSectionTitle(String title, String subtitle, IconData icon, Color color) => Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '· $subtitle',
              style: const TextStyle(fontSize: 11, color: StreetFoodMafiaColors.secondaryText),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );

  Widget _marginItemRow({
    required String name,
    required String subtitle,
    required String trailingValue,
    required String trailingLabel,
    required Color accentColor,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: StreetFoodMafiaColors.cardSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: StreetFoodMafiaColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 28,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: StreetFoodMafiaColors.secondaryText),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  trailingValue,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  trailingLabel,
                  style: const TextStyle(fontSize: 10, color: StreetFoodMafiaColors.secondaryText),
                ),
              ],
            ),
          ],
        ),
      );

  // Pillar 3: Kitchen & Fulfillment Bottlenecks Card
  Widget _bottlenecksCard(BuildContext context, BottlenecksData bottlenecks) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: StreetFoodMafiaColors.darkNavy,
          border: Border.all(color: StreetFoodMafiaColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(builder: (context, constraints) {
              if (constraints.maxWidth < 360) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.kitchen_rounded, color: StreetFoodMafiaColors.cartelYellow, size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text('Kitchen & Fulfillment Bottlenecks',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: () => onReport(AnalyticsFamily.orders),
                      icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                      label: const Text('Inspect peak orders'),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 30),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  const Icon(Icons.kitchen_rounded, color: StreetFoodMafiaColors.cartelYellow, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Kitchen & Fulfillment Bottlenecks',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  TextButton.icon(
                    onPressed: () => onReport(AnalyticsFamily.orders),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 14),
                    label: const Text('Inspect peak orders'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 14),

            // Metrics row: p50 prep, p90 prep, Target ETA
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metricPill(
                  label: 'p50 Prep Duration',
                  value: bottlenecks.prepMedianMinutes != null
                      ? '${bottlenecks.prepMedianMinutes!.toStringAsFixed(1)}m'
                      : 'Unavailable',
                  subtext: 'Observed median',
                  color: const Color(0xFF3B82F6),
                ),
                _metricPill(
                  label: 'p90 Prep Duration',
                  value: bottlenecks.prepP90Minutes != null
                      ? '${bottlenecks.prepP90Minutes!.toStringAsFixed(1)}m'
                      : 'Unavailable',
                  subtext: '90th percentile prep',
                  color: (bottlenecks.prepP90Minutes ?? 0) > 25
                      ? const Color(0xFFEF4444)
                      : StreetFoodMafiaColors.cartelYellow,
                ),
                _metricPill(
                  label: 'Delivery Target ETA',
                  value: '${bottlenecks.targetEtaMinutes.toStringAsFixed(0)}m',
                  subtext: bottlenecks.transitP90Minutes != null
                      ? 'Transit p90: ${bottlenecks.transitP90Minutes!.toStringAsFixed(1)}m'
                      : 'Area target SLA',
                  color: const Color(0xFF10B981),
                ),
              ],
            ),

            const SizedBox(height: 14),
            // Peak rush hour summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: StreetFoodMafiaColors.cardSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: StreetFoodMafiaColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_filled_rounded, color: StreetFoodMafiaColors.cartelYellow, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bottlenecks.peakHour != null
                              ? 'Peak Rush Window: ${bottlenecks.peakHour!.toString().padLeft(2, '0')}:00 – ${(bottlenecks.peakHour! + 1).toString().padLeft(2, '0')}:00'
                              : 'Peak Rush Window: No order volume recorded',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          bottlenecks.peakHour != null
                              ? '${bottlenecks.peakHourOrders} orders completed · ${_formatPaisa(bottlenecks.peakHourSalesPaisa)} sales'
                              : 'Peak rush metrics available with order history',
                          style: const TextStyle(fontSize: 11, color: StreetFoodMafiaColors.secondaryText),
                        ),
                      ],
                    ),
                  ),
                  if (bottlenecks.reworkCycles > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${bottlenecks.reworkCycles} kitchen rework',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFEF4444), fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _metricPill({
    required String label,
    required String value,
    required String subtext,
    required Color color,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: StreetFoodMafiaColors.cardSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: StreetFoodMafiaColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, color: StreetFoodMafiaColors.secondaryText)),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 2),
            Text(subtext, style: const TextStyle(fontSize: 10, color: StreetFoodMafiaColors.secondaryText)),
          ],
        ),
      );

  // Pillar 4: Risk & Leakage Radar Card
  Widget _riskRadarCard(BuildContext context, RiskRadarData riskRadar) {
    final alerts = riskRadar.alerts;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: StreetFoodMafiaColors.darkNavy,
        border: Border.all(color: StreetFoodMafiaColors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                alerts.isEmpty ? Icons.check_circle_outline : Icons.shield_outlined,
                size: 22,
                color: alerts.isEmpty ? StreetFoodMafiaColors.statusReady : const Color(0xFFEF4444),
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Risk & Leakage Radar',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: StreetFoodMafiaColors.cardSurface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Needs attention',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: alerts.isEmpty ? StreetFoodMafiaColors.statusReady : StreetFoodMafiaColors.cartelYellow,
                  ),
                ),
              ),
            ],
          ),
          if (riskRadar.hasActiveRisks) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _radarCounterChip(
                  label: 'Unsettled COD > 24h',
                  value: riskRadar.unsettledCodOver24hPaisa > 0
                      ? _formatPaisa(riskRadar.unsettledCodOver24hPaisa)
                      : 'PKR 0.00',
                  isRisk: riskRadar.unsettledCodOver24hPaisa > 0,
                  onTap: () => onReport(AnalyticsFamily.delivery),
                ),
                _radarCounterChip(
                  label: 'Unresolved Drawer Variances',
                  value: '${riskRadar.unresolvedDrawerVariances} shifts',
                  isRisk: riskRadar.unresolvedDrawerVariances > 0,
                  onTap: () => onReport(AnalyticsFamily.cash),
                ),
                _radarCounterChip(
                  label: 'Negative Stock Items',
                  value: '${riskRadar.negativeStockCount} items',
                  isRisk: riskRadar.negativeStockCount > 0,
                  onTap: () => onReport(AnalyticsFamily.inventory),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),

          if (alerts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'No issues detected in the available checks. Review individual reports for coverage.',
                style: TextStyle(color: StreetFoodMafiaColors.secondaryText, height: 1.5),
              ),
            )
          else
            for (var index = 0; index < alerts.length; index++) ...[
              if (index > 0) const Divider(height: 16),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _attentionRow(alerts[index]),
              ),
            ],
        ],
      ),
    );
  }

  Widget _radarCounterChip({
    required String label,
    required String value,
    required bool isRisk,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: StreetFoodMafiaColors.cardSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isRisk ? const Color(0xFFEF4444).withValues(alpha: 0.5) : StreetFoodMafiaColors.border,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: StreetFoodMafiaColors.secondaryText),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isRisk ? const Color(0xFFEF4444) : StreetFoodMafiaColors.statusReady,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _attentionRow(OverviewAttention alert) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: StreetFoodMafiaColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              switch (alert.kind) {
                OverviewAttentionKind.countCoverage => Icons.receipt_long_outlined,
                OverviewAttentionKind.profitCoverage => Icons.bar_chart_rounded,
                OverviewAttentionKind.negativeStock => Icons.inventory_2_outlined,
                OverviewAttentionKind.discrepancy => Icons.account_balance_wallet_outlined,
                OverviewAttentionKind.reportDelivery => Icons.outgoing_mail,
                OverviewAttentionKind.unsettledCod => Icons.local_shipping_outlined,
              },
              color: StreetFoodMafiaColors.cartelYellow,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  alert.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  alert.description,
                  style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText),
                ),
                TextButton.icon(
                  onPressed: () => onReport(alert.family),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                  label: Text(alert.action),
                ),
              ],
            ),
          ),
        ],
      );
}
