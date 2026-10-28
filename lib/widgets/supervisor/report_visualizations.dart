import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/analytics/analytics_models.dart';
import '../../core/theme/theme.dart';
import 'report_chart_data.dart';

class ReportVisualizations extends StatelessWidget {
  const ReportVisualizations({super.key, required this.section, required this.onInspect});
  final AnalyticsSection section;
  final void Function(String title, List<AnalyticsRow> rows) onInspect;

  @override
  Widget build(BuildContext context) {
    final charts = buildReportCharts(section);
    return Padding(padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.insights_rounded, size: 22, color: StreetFoodMafiaColors.cartelYellow),
          SizedBox(width: 8),
          Text('Visual analysis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 920 ? 2 : 1;
          final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            for (final chart in charts) SizedBox(width: width,
              child: _ChartCard(key: ValueKey('${section.family.name}_${chart.id}'),
                chart: chart, onInspect: onInspect)),
          ]);
        }),
        const SizedBox(height: 10),
        const Text('Exact values are shown on every bar. Select a bar with source records to inspect its evidence. '
          'Negative values extend left of zero. The source table below remains the full data alternative.',
          style: TextStyle(fontSize: 11, height: 1.5, color: StreetFoodMafiaColors.secondaryText)),
      ]));
  }
}

class _ChartCard extends StatefulWidget {
  const _ChartCard({super.key, required this.chart, required this.onInspect});
  final ReportChartData chart;
  final void Function(String, List<AnalyticsRow>) onInspect;

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  static const _pageSize = 8;
  int _page = 0;

  @override
  void didUpdateWidget(covariant _ChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chart != widget.chart) _page = 0;
  }

  @override
  Widget build(BuildContext context) {
    final chart = widget.chart;
    final values = chart.points.map((p) => p.value).whereType<num>().toList();
    // Normalize first so even extreme finite positive/negative values cannot
    // overflow the axis span into infinity.
    final magnitude = values.fold<double>(0, (maximum, value) => math.max(maximum, value.abs().toDouble()));
    final scale = magnitude == 0 ? 1.0 : magnitude;
    final min = values.fold<double>(0, (minimum, value) => math.min(minimum, value / scale));
    final max = values.fold<double>(0, (maximum, value) => math.max(maximum, value / scale));
    final span = max == min ? 1.0 : max - min;
    final origin = -min / span;
    final start = _page * _pageSize;
    final end = math.min(start + _pageSize, chart.points.length);
    return Material(color: StreetFoodMafiaColors.darkNavy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StreetFoodMafiaColors.border)),
      child: Padding(padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(chart.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(chart.scope, style: const TextStyle(fontSize: 12, height: 1.5,
            color: StreetFoodMafiaColors.secondaryText)),
          const SizedBox(height: 8),
          Text(chart.quantityUnit ?? switch (chart.unit) {
            AnalyticsUnit.paisa => 'PKR',
            AnalyticsUnit.count => 'Count',
            AnalyticsUnit.percent => 'Percent',
            AnalyticsUnit.minutes => 'Minutes',
            AnalyticsUnit.decimal => 'Quantity',
          }, style: const TextStyle(fontSize: 11, color: StreetFoodMafiaColors.cartelYellow)),
          const SizedBox(height: 12),
          if (chart.points.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('No recorded values for this selection. No history is inferred.',
              style: TextStyle(color: StreetFoodMafiaColors.secondaryText, fontSize: 12, height: 1.5))),
          for (var index = start; index < end; index++)
            _point(chart, chart.points[index], index, scale, span, origin),
          if (chart.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(chart.note, style: const TextStyle(fontSize: 11, height: 1.5,
              color: StreetFoodMafiaColors.secondaryText))),
          if (chart.points.length > _pageSize) Wrap(alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
            Text('${start + 1}–$end of ${chart.points.length}', style: const TextStyle(fontSize: 11)),
            IconButton(tooltip: 'Previous chart values', onPressed: _page == 0 ? null : () => setState(() => _page--),
              icon: const Icon(Icons.chevron_left)),
            IconButton(tooltip: 'Next chart values', onPressed: end >= chart.points.length ? null : () => setState(() => _page++),
              icon: const Icon(Icons.chevron_right)),
          ]),
        ])));
  }

  Widget _point(ReportChartData chart, ReportChartPoint point, int index,
      double scale, double span, double origin) {
    final value = point.value;
    final formatted = value == null ? (point.quality == AnalyticsQuality.notApplicable
      ? 'Not applicable' : 'Unavailable') : switch (chart.unit) {
      AnalyticsUnit.paisa => 'PKR ${NumberFormat('#,##0.00').format(value / 100)}',
      AnalyticsUnit.percent => '${NumberFormat('#,##0.0').format(value)}%',
      _ => '${NumberFormat('#,##0.########').format(value)}${chart.quantityUnit == null ? '' : ' ${chart.quantityUnit}'}',
    };
    final inspect = point.rows.isEmpty ? null : () => widget.onInspect(chart.title, point.rows);
    return Semantics(label: '${point.label}: $formatted', button: inspect != null,
      child: Tooltip(message: '${point.label}: $formatted'
        '${point.explanation.isEmpty ? '' : '\n${point.explanation}'}'
        '${inspect == null ? '' : '\nInspect ${point.rows.length} source records'}',
        child: InkWell(key: ValueKey('chart_point_${chart.id}_$index'), onTap: inspect,
          borderRadius: BorderRadius.circular(6),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 9),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: Text(point.label, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                const SizedBox(width: 10),
                Flexible(flex: 2, child: Text(formatted, textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: value == null ? StreetFoodMafiaColors.secondaryText : StreetFoodMafiaColors.offWhite))),
                if (inspect != null) const Padding(padding: EdgeInsets.only(left: 5),
                  child: Icon(Icons.open_in_new, size: 12, color: StreetFoodMafiaColors.secondaryText)),
              ]),
              const SizedBox(height: 8),
              if (value != null) LayoutBuilder(builder: (context, constraints) {
                final barWidth = ((value / scale).abs() / span * constraints.maxWidth).clamp(0.0, constraints.maxWidth);
                final zero = origin * constraints.maxWidth;
                return SizedBox(height: 15, child: Stack(children: [
                  Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                    color: StreetFoodMafiaColors.cardSurface, borderRadius: BorderRadius.circular(3)))),
                  Positioned(left: (value < 0 ? zero - barWidth : zero).clamp(0.0, constraints.maxWidth),
                    width: barWidth.toDouble(), top: 2, bottom: 2,
                    child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(3),
                      color: value < 0 ? StreetFoodMafiaColors.statusCanceled : StreetFoodMafiaColors.cartelYellow))),
                  Positioned(left: zero.clamp(0.0, math.max(0, constraints.maxWidth - 1)),
                    width: 1, top: 0, bottom: 0, child: const ColoredBox(color: StreetFoodMafiaColors.secondaryText)),
                ]));
              }),
              if (point.quality == AnalyticsQuality.estimated)
                const Text('Estimated', style: TextStyle(fontSize: 11, color: StreetFoodMafiaColors.burntGold)),
            ])))));
  }
}
