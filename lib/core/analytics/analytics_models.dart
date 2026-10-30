import 'package:intl/intl.dart';
import 'analytics_time.dart';
export 'analytics_time.dart';

part 'report_chart_projection.dart';
part 'business_overview_data.dart';

enum AnalyticsFamily { overview, sales, orders, delivery, customers, menu, inventory, procurement, suppliers, cash, expenses, staff, profitability, audit }
enum AnalyticsUnit { count, paisa, percent, decimal, minutes }
enum AnalyticsQuality { complete, estimated, missing, notApplicable }
enum AnalyticsTimeBasis { businessDay, calendarTime }
enum AnalyticsGrouping { day, week, month }

class AnalyticsMetric {
  const AnalyticsMetric({required this.id, required this.label, this.value, required this.unit, required this.explanation, this.quality = AnalyticsQuality.complete, this.sampleCount, this.populationCount, this.changePercent, this.changeAbsolute});
  final String id, label, explanation;
  final num? value;
  final AnalyticsUnit unit;
  final AnalyticsQuality quality;
  final int? sampleCount, populationCount;
  final double? changePercent;
  final num? changeAbsolute;
}

class AnalyticsColumn {
  const AnalyticsColumn({required this.key, required this.label, this.unit});
  final String key, label;
  final AnalyticsUnit? unit;
}

class AnalyticsRow {
  AnalyticsRow({required this.id, required Map<String, Object?> cells, required this.sourceType, this.sourceId}) : cells = Map.unmodifiable(cells);
  final String id, sourceType;
  final String? sourceId;
  final Map<String, Object?> cells;
}

class AnalyticsSection {
  AnalyticsSection({required this.family, required this.title, List<AnalyticsMetric> metrics = const [], List<AnalyticsColumn> columns = const [], List<AnalyticsRow> rows = const [], List<String> notes = const []}) : metrics = List.unmodifiable(metrics), columns = List.unmodifiable(columns), rows = List.unmodifiable(rows), notes = List.unmodifiable(notes);
  late final List<ReportChartData> charts = List.unmodifiable(_buildReportCharts(this));
  final AnalyticsFamily family;
  final String title;
  final List<AnalyticsMetric> metrics;
  final List<AnalyticsColumn> columns;
  final List<AnalyticsRow> rows;
  final List<String> notes;
}

const _unchanged = Object();

class AnalyticsQuery {
  AnalyticsQuery({required this.startDate, required this.endDateExclusive, this.live = false, this.cashierId, this.shiftId, this.diningType, this.paymentMethod, this.timeBasis = AnalyticsTimeBasis.businessDay, this.grouping = AnalyticsGrouping.day, this.holdStaleMinutes = 30}) {
    if (holdStaleMinutes <= 0) throw ArgumentError('Hold stale minutes must be positive.');
    if (!startDate.isBefore(endDateExclusive)) throw ArgumentError('Business Day range must have start < end.');
    if (cashierId != null && cashierId! <= 0 || shiftId != null && shiftId! <= 0) throw ArgumentError('Staff and shift IDs must be positive.');
  }
  final DateTime startDate, endDateExclusive;
  final bool live;
  final AnalyticsTimeBasis timeBasis;
  final AnalyticsGrouping grouping;
  final int holdStaleMinutes;
  final int? cashierId, shiftId;
  final String? diningType, paymentMethod;
  bool get hasOrderFilters => cashierId != null || shiftId != null || diningType != null || paymentMethod != null;
  AnalyticsQuery copyWith({DateTime? startDate, DateTime? endDateExclusive, bool? live, AnalyticsTimeBasis? timeBasis, AnalyticsGrouping? grouping, int? holdStaleMinutes, Object? cashierId = _unchanged, Object? shiftId = _unchanged, Object? diningType = _unchanged, Object? paymentMethod = _unchanged}) => AnalyticsQuery(startDate: startDate ?? this.startDate, endDateExclusive: endDateExclusive ?? this.endDateExclusive, live: live ?? this.live, timeBasis: timeBasis ?? this.timeBasis, grouping: grouping ?? this.grouping, holdStaleMinutes: holdStaleMinutes ?? this.holdStaleMinutes, cashierId: identical(cashierId, _unchanged) ? this.cashierId : cashierId as int?, shiftId: identical(shiftId, _unchanged) ? this.shiftId : shiftId as int?, diningType: identical(diningType, _unchanged) ? this.diningType : diningType as String?, paymentMethod: identical(paymentMethod, _unchanged) ? this.paymentMethod : paymentMethod as String?);
  @override
  bool operator ==(Object other) => other is AnalyticsQuery && startDate == other.startDate && endDateExclusive == other.endDateExclusive && live == other.live && timeBasis == other.timeBasis && grouping == other.grouping && holdStaleMinutes == other.holdStaleMinutes && cashierId == other.cashierId && shiftId == other.shiftId && diningType == other.diningType && paymentMethod == other.paymentMethod;
  @override
  int get hashCode => Object.hash(startDate, endDateExclusive, live, cashierId, shiftId, diningType, paymentMethod, timeBasis, grouping, holdStaleMinutes);
}

class AnalyticsSnapshot {
  AnalyticsSnapshot({required this.query, required this.generatedAt, required List<AnalyticsSection> sections, required List<int> businessDayIds, List<String> notes = const [], this.generatedByStaffId, this.sourceSchemaVersion, this.reportVersion = 'manager-analytics-v3'}) : sections = List.unmodifiable(sections), businessDayIds = List.unmodifiable(businessDayIds), notes = List.unmodifiable(notes);
  late final BusinessOverviewData overview = BusinessOverviewData(this);
  final AnalyticsQuery query;
  final DateTime generatedAt;
  final int? generatedByStaffId;
  final int? sourceSchemaVersion;
  final String reportVersion;
  final List<AnalyticsSection> sections;
  final List<int> businessDayIds;
  final List<String> notes;
  AnalyticsSection section(AnalyticsFamily family) => sections.firstWhere((section) => section.family == family);
}

/// Cooked wastage is already consumed; raw returns reverse original-rate COGS.
/// Used by report totals and dated chart postings alike.
int orderCostSign(Object? kind) => kind == 'COOKED_WASTE' ? 0 : kind == 'RETURN' ? -1 : 1;

