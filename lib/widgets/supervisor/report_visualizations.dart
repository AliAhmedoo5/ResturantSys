import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/analytics/analytics_models.dart';
import '../../core/theme/theme.dart';

class ReportVisualizations extends StatelessWidget {
  const ReportVisualizations({super.key, required this.section, required this.onInspect});
  final AnalyticsSection section;
  final void Function(String title, List<AnalyticsRow> rows) onInspect;

  @override
  Widget build(BuildContext context) {
    final charts = section.charts;
    return Padding(padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.insights_rounded, size: 22, color: StreetFoodMafiaColors.cartelYellow),
          SizedBox(width: 8),
          Text('Visual analysis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 12),
        if (section.family == AnalyticsFamily.orders) _WeekdayPeakTables(section: section, onInspect: onInspect),
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
        child: InkWell(mouseCursor: WidgetStateMouseCursor.clickable, key: ValueKey('chart_point_${chart.id}_$index'), onTap: inspect,
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

class _WeekdayPeakTables extends StatelessWidget {
  const _WeekdayPeakTables({required this.section, required this.onInspect});
  final AnalyticsSection section;
  final void Function(String title, List<AnalyticsRow> rows) onInspect;

  @override
  Widget build(BuildContext context) {
    final comparisons = section.rows.where((r) => r.cells['kind'] == 'Weekday comparison').toList()
      ..sort((a, b) {
        final difference = ((b.cells['orders_per_completed_day'] as num?) ?? -1).compareTo((a.cells['orders_per_completed_day'] as num?) ?? -1);
        return difference != 0 ? difference : (a.cells['weekday'] as int).compareTo(b.cells['weekday'] as int);
      });
    final hours = {for (final row in section.rows.where((r) => r.cells['kind'] == 'Weekday/hour workload'))
      '${row.cells['weekday']}_${row.cells['hour']}': row};
    if (comparisons.isEmpty && hours.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (comparisons.isNotEmpty) ...[
        const Text('Operational weekday ranking · completed Business Days', style: TextStyle(fontWeight: FontWeight.w700)),
        const Text('Completed Orders / completed days includes opened zero-order days. Open activity is separate. Equal averages share the peak; ties use weekday order.'),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(columns: const [
          DataColumn(label: Text('Weekday')), DataColumn(label: Text('Completed Orders / days')),
          DataColumn(label: Text('Orders / completed day')), DataColumn(label: Text('Aggregate Orders')),
          DataColumn(label: Text('Open Orders / days')),
        ], rows: [for (final row in comparisons) DataRow(cells: [
          DataCell(Text('${row.cells['period']}'), onTap: () => onInspect('Weekday comparison', [row])),
          DataCell(Text('${row.cells['completed_confirmed_orders']} / ${row.cells['completed_business_days']}')),
          DataCell(Text(row.cells['orders_per_completed_day'] == null ? 'Unavailable' : (row.cells['orders_per_completed_day'] as num).toStringAsFixed(2))),
          DataCell(Text('${row.cells['confirmed_orders']}')),
          DataCell(Text('${row.cells['open_confirmed_orders']} / ${row.cells['open_business_days']}')),
        ])])),
        const SizedBox(height: 18),
      ],
      if (hours.isNotEmpty) ...[
        _RushHeatmapMatrix(
          key: const ValueKey('rush_heatmap_matrix'),
          section: section,
          hours: hours,
          onInspect: onInspect,
        ),
        const SizedBox(height: 18),
      ],
    ]);
  }
}

class _RushHeatmapMatrix extends StatelessWidget {
  const _RushHeatmapMatrix({
    super.key,
    required this.section,
    required this.hours,
    required this.onInspect,
  });

  final AnalyticsSection section;
  final Map<String, AnalyticsRow> hours;
  final void Function(String title, List<AnalyticsRow> rows) onInspect;

  static const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final firstRow = hours.values.first;
    var maxCount = 0;
    for (final row in hours.values) {
      final count = row.cells['confirmed_orders'];
      if (count is num && count > maxCount) {
        maxCount = count.toInt();
      }
    }

    return Material(
      color: StreetFoodMafiaColors.darkNavy,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: StreetFoodMafiaColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 640;
                final headerInfo = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.local_fire_department_rounded,
                            size: 20, color: StreetFoodMafiaColors.cartelYellow),
                        SizedBox(width: 8),
                        Text(
                          'Weekday by hour · confirmed Orders',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: StreetFoodMafiaColors.offWhite,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${firstRow.cells['weekday_basis']} · Asia/Karachi · actual clock hour',
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: StreetFoodMafiaColors.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '0 = observed zero; Unavailable = unobserved or missing evidence. Open Business Day cells show partial activity at cutoff. Select a cell for coverage and source IDs.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: StreetFoodMafiaColors.secondaryText,
                      ),
                    ),
                  ],
                );

                final legend = _RushHeatmapLegend(
                  key: const ValueKey('rush_heatmap_legend'),
                  maxCount: maxCount,
                );

                if (isCompact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      headerInfo,
                      const SizedBox(height: 12),
                      legend,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: headerInfo),
                    const SizedBox(width: 16),
                    legend,
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _buildGrid(context, maxCount),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, int maxCount) {
    const weekdayColWidth = 84.0;
    const hourColWidth = 44.0;
    const rowHeight = 36.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: weekdayColWidth,
              height: 28,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Day',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: StreetFoodMafiaColors.secondaryText,
                  ),
                ),
              ),
            ),
            for (var h = 0; h < 24; h++)
              SizedBox(
                width: hourColWidth,
                height: 28,
                child: Center(
                  child: Text(
                    '${h.toString().padLeft(2, '0')}:00',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: StreetFoodMafiaColors.secondaryText,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var weekday = 1; weekday <= 7; weekday++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: weekdayColWidth,
                  height: rowHeight,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      weekdays[weekday - 1],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: StreetFoodMafiaColors.offWhite,
                      ),
                    ),
                  ),
                ),
                for (var hour = 0; hour < 24; hour++)
                  _buildCell(
                    weekday: weekday,
                    hour: hour,
                    row: hours['${weekday}_$hour'],
                    maxCount: maxCount,
                    width: hourColWidth,
                    height: rowHeight,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCell({
    required int weekday,
    required int hour,
    required AnalyticsRow? row,
    required int maxCount,
    required double width,
    required double height,
  }) {
    final value = row?.cells['confirmed_orders'];
    final count = value is num ? value.toInt() : null;

    final cellColor = _cellColor(count, maxCount);
    final textColor = _cellTextColor(count, maxCount);
    final text = count == null ? 'Unavailable' : '$count';

    final tooltipMsg = _tooltipMessage(
      weekdayName: weekdays[weekday - 1],
      hour: hour,
      row: row,
    );

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(2),
      child: Material(
        key: ValueKey('weekday_hour_cell_${weekday}_$hour'),
        color: cellColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(
            color: count == null
                ? StreetFoodMafiaColors.borderSubtle
                : (count == 0
                    ? StreetFoodMafiaColors.border
                    : StreetFoodMafiaColors.cartelYellow.withValues(alpha: 0.3)),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('weekday_hour_${weekday}_$hour'),
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: row == null ? null : () => _handleInspect(row, weekday, hour),
          child: Tooltip(
            key: ValueKey('weekday_hour_tooltip_${weekday}_$hour'),
            message: tooltipMsg,
            child: Center(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: count == null ? 8 : 11,
                  fontWeight: count != null && count > 0 ? FontWeight.w700 : FontWeight.w500,
                  color: textColor,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _cellColor(int? count, int maxCount) {
    if (count == null) {
      return StreetFoodMafiaColors.cardSurface.withValues(alpha: 0.35);
    }
    if (count == 0 || maxCount == 0) {
      return StreetFoodMafiaColors.cardSurface;
    }
    final intensity = (count / maxCount).clamp(0.0, 1.0);
    return Color.lerp(
      StreetFoodMafiaColors.cardSurface,
      StreetFoodMafiaColors.cartelYellow,
      intensity,
    )!;
  }

  Color _cellTextColor(int? count, int maxCount) {
    if (count == null || count == 0) {
      return StreetFoodMafiaColors.secondaryText;
    }
    if (maxCount > 0) {
      final intensity = (count / maxCount).clamp(0.0, 1.0);
      if (intensity > 0.5) {
        return StreetFoodMafiaColors.textOnPrimary;
      }
    }
    return StreetFoodMafiaColors.offWhite;
  }

  String _tooltipMessage({
    required String weekdayName,
    required int hour,
    required AnalyticsRow? row,
  }) {
    final count = row?.cells['confirmed_orders'];
    final hourFormatted = '${hour.toString().padLeft(2, '0')}:00';
    final nextHourFormatted = '${((hour + 1) % 24).toString().padLeft(2, '0')}:00';
    final timeRange = '$hourFormatted–$nextHourFormatted';
    final countText = count == null ? 'Unavailable' : '$count ${count == 1 ? 'order' : 'orders'}';
    final coverage = row?.cells['coverage'] ?? 'Unavailable coverage';

    final netSales = row?.cells['net_sales_paisa'] ?? row?.cells['recorded_value_paisa'];
    final salesText = (netSales is num && netSales > 0)
        ? ' · PKR ${NumberFormat('#,##0.00').format(netSales / 100)}'
        : '';

    return '$weekdayName $timeRange: $countText$salesText · $coverage';
  }

  void _handleInspect(AnalyticsRow row, int weekday, int hour) {
    final weekdayName = weekdays[weekday - 1];
    final hourFormatted = '${hour.toString().padLeft(2, '0')}:00';
    final title = '$weekdayName $hourFormatted';

    final orderIdsRaw = row.cells['order_ids']?.toString() ?? row.sourceId ?? '';
    final orderIdSet = orderIdsRaw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();

    final contributingOrders = section.rows.where((r) {
      if (r.sourceType == 'orders') {
        final orderId = r.cells['order_id']?.toString() ?? r.sourceId;
        return orderIdSet.contains(orderId);
      }
      return false;
    }).toList();

    if (contributingOrders.isNotEmpty) {
      onInspect(title, contributingOrders);
    } else {
      onInspect(title, [row]);
    }
  }
}

class _RushHeatmapLegend extends StatelessWidget {
  const _RushHeatmapLegend({super.key, required this.maxCount});
  final int maxCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: StreetFoodMafiaColors.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: StreetFoodMafiaColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'RUSH INTENSITY',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: StreetFoodMafiaColors.secondaryText,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '0 orders',
                style: TextStyle(fontSize: 10, color: StreetFoodMafiaColors.secondaryText),
              ),
              const SizedBox(width: 8),
              Container(
                width: 90,
                height: 10,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  gradient: const LinearGradient(
                    colors: [
                      StreetFoodMafiaColors.cardSurface,
                      StreetFoodMafiaColors.cartelYellow,
                    ],
                  ),
                  border: Border.all(color: StreetFoodMafiaColors.border, width: 0.5),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$maxCount orders${maxCount > 0 ? ' (peak)' : ''}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: StreetFoodMafiaColors.cartelYellow,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
