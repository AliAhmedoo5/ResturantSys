import 'package:intl/intl.dart';
import 'analytics_time.dart';
export 'analytics_time.dart';

part 'report_chart_projection.dart';
part 'business_overview_data.dart';
part 'domain_filter_models.dart';

enum AnalyticsFamily { overview, sales, orders, delivery, customers, menu, inventory, procurement, suppliers, cash, expenses, staff, profitability, audit }
enum AnalyticsUnit { count, paisa, percent, decimal, minutes }
enum AnalyticsQuality { complete, estimated, missing, notApplicable }
enum AnalyticsTimeBasis { businessDay, calendarTime }
enum AnalyticsGrouping { day, week, month }
enum AnalyticsComparisonMode { none, precedingPeriod, comparableWeekday }

class AnalyticsMetric {
  const AnalyticsMetric({
    required this.id,
    required this.label,
    this.value,
    required this.unit,
    required this.explanation,
    this.quality = AnalyticsQuality.complete,
    this.sampleCount,
    this.populationCount,
    this.changePercent,
    this.changeAbsolute,
    this.priorValue,
    this.isBalance = false,
  });
  final String id, label, explanation;
  final num? value;
  final AnalyticsUnit unit;
  final AnalyticsQuality quality;
  final int? sampleCount, populationCount;
  final double? changePercent;
  final num? changeAbsolute;
  final num? priorValue;
  final bool isBalance;
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
  AnalyticsQuery({
    required this.startDate,
    required this.endDateExclusive,
    this.live = false,
    this.cashierId,
    this.shiftId,
    this.diningType,
    this.paymentMethod,
    this.timeBasis = AnalyticsTimeBasis.businessDay,
    this.grouping = AnalyticsGrouping.day,
    this.comparisonMode = AnalyticsComparisonMode.none,
    this.holdStaleMinutes = 30,
    this.fundingStream,
    Map<AnalyticsDimension, String> domainFilters = const {},
  }) : domainFilters = Map.unmodifiable(domainFilters) {
    if (fundingStream != null && !['DRAWER','BANK','OWNER','RIDER_HELD','EXTERNAL_UNKNOWN'].contains(fundingStream)) throw ArgumentError('Unknown funding stream.');
    for (final entry in domainFilters.entries) {
      if (entry.key == AnalyticsDimension.customerSegment) {
        if (!['known', 'guest'].contains(entry.value)) throw ArgumentError('Unsupported customer segment.');
      } else if (entry.key == AnalyticsDimension.acquisition) {
        if (!['mandi', 'supplier'].contains(entry.value)) throw ArgumentError('Unsupported acquisition evidence.');
      } else if ((int.tryParse(entry.value) ?? 0) <= 0) {
        throw ArgumentError('Domain IDs must be positive.');
      }
    }
    if (holdStaleMinutes <= 0) throw ArgumentError('Hold stale minutes must be positive.');
    if (!startDate.isBefore(endDateExclusive)) throw ArgumentError('Business Day range must have start < end.');
    if (cashierId != null && cashierId! <= 0 || shiftId != null && shiftId! <= 0) throw ArgumentError('Staff and shift IDs must be positive.');
  }
  final DateTime startDate, endDateExclusive;
  final bool live;
  final AnalyticsTimeBasis timeBasis;
  final AnalyticsGrouping grouping;
  final AnalyticsComparisonMode comparisonMode;
  final int holdStaleMinutes;
  final int? cashierId, shiftId;
  final String? diningType, paymentMethod, fundingStream;
  final Map<AnalyticsDimension, String> domainFilters;
  bool get hasOrderFilters => domainFilters.keys.any((d) => d.isOrder) || cashierId != null || shiftId != null || diningType != null || paymentMethod != null;

  DateTime? get priorStartDate {
    switch (comparisonMode) {
      case AnalyticsComparisonMode.none:
        return null;
      case AnalyticsComparisonMode.precedingPeriod:
        final duration = timeBasis == AnalyticsTimeBasis.calendarTime
            ? endDateExclusive.difference(startDate)
            : DateTime.utc(endDateExclusive.year, endDateExclusive.month, endDateExclusive.day)
                .difference(DateTime.utc(startDate.year, startDate.month, startDate.day));
        return startDate.subtract(duration);
      case AnalyticsComparisonMode.comparableWeekday:
        return startDate.subtract(const Duration(days: 7));
    }
  }

  DateTime? get priorEndDateExclusive {
    switch (comparisonMode) {
      case AnalyticsComparisonMode.none:
        return null;
      case AnalyticsComparisonMode.precedingPeriod:
        return startDate;
      case AnalyticsComparisonMode.comparableWeekday:
        return endDateExclusive.subtract(const Duration(days: 7));
    }
  }

  AnalyticsQuery? get priorQuery {
    final start = priorStartDate;
    final end = priorEndDateExclusive;
    if (start == null || end == null) return null;
    return copyWith(startDate: start, endDateExclusive: end, live: false);
  }

  AnalyticsQuery copyWith({
    DateTime? startDate,
    DateTime? endDateExclusive,
    bool? live,
    AnalyticsTimeBasis? timeBasis,
    AnalyticsGrouping? grouping,
    AnalyticsComparisonMode? comparisonMode,
    int? holdStaleMinutes,
    Map<AnalyticsDimension, String>? domainFilters,
    Object? fundingStream = _unchanged,
    Object? cashierId = _unchanged,
    Object? shiftId = _unchanged,
    Object? diningType = _unchanged,
    Object? paymentMethod = _unchanged,
  }) => AnalyticsQuery(
    startDate: startDate ?? this.startDate,
    endDateExclusive: endDateExclusive ?? this.endDateExclusive,
    live: live ?? this.live,
    timeBasis: timeBasis ?? this.timeBasis,
    grouping: grouping ?? this.grouping,
    comparisonMode: comparisonMode ?? this.comparisonMode,
    holdStaleMinutes: holdStaleMinutes ?? this.holdStaleMinutes,
    domainFilters: domainFilters ?? this.domainFilters,
    fundingStream: identical(fundingStream, _unchanged) ? this.fundingStream : fundingStream as String?,
    cashierId: identical(cashierId, _unchanged) ? this.cashierId : cashierId as int?,
    shiftId: identical(shiftId, _unchanged) ? this.shiftId : shiftId as int?,
    diningType: identical(diningType, _unchanged) ? this.diningType : diningType as String?,
    paymentMethod: identical(paymentMethod, _unchanged) ? this.paymentMethod : paymentMethod as String?,
  );

  @override
  bool operator ==(Object other) => other is AnalyticsQuery && startDate == other.startDate && endDateExclusive == other.endDateExclusive && live == other.live && timeBasis == other.timeBasis && grouping == other.grouping && comparisonMode == other.comparisonMode && holdStaleMinutes == other.holdStaleMinutes && cashierId == other.cashierId && shiftId == other.shiftId && diningType == other.diningType && paymentMethod == other.paymentMethod && fundingStream == other.fundingStream && domainFilters.length == other.domainFilters.length && domainFilters.entries.every((e) => other.domainFilters[e.key] == e.value);

  @override
  int get hashCode => Object.hash(startDate, endDateExclusive, live, cashierId, shiftId, diningType, paymentMethod, timeBasis, grouping, comparisonMode, holdStaleMinutes, fundingStream, Object.hashAll(AnalyticsDimension.values.map((d) => domainFilters[d])));
}

class AnalyticsSnapshot {
  AnalyticsSnapshot({required this.query, required this.generatedAt, required List<AnalyticsSection> sections, required List<int> businessDayIds, List<String> notes = const [], this.generatedByStaffId, this.sourceSchemaVersion, this.reportVersion = 'manager-analytics-v4', List<AnalyticsFilterOption> filterOptions = const []}) : filterOptions = List.unmodifiable(filterOptions), sections = List.unmodifiable(sections), businessDayIds = List.unmodifiable(businessDayIds), notes = List.unmodifiable(notes);
  late final BusinessOverviewData overview = BusinessOverviewData(this);
  final AnalyticsQuery query;
  final List<AnalyticsFilterOption> filterOptions;
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
