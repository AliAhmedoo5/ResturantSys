enum AnalyticsFamily { overview, sales, orders, delivery, customers, menu, inventory, procurement, suppliers, cash, expenses, staff, profitability, audit }
enum AnalyticsUnit { count, paisa, percent, decimal, minutes }
enum AnalyticsQuality { complete, estimated, missing, notApplicable }

class AnalyticsMetric {
  const AnalyticsMetric({required this.id, required this.label, this.value, required this.unit, required this.explanation, this.quality = AnalyticsQuality.complete, this.sampleCount, this.populationCount, this.changePercent});
  final String id, label, explanation;
  final num? value;
  final AnalyticsUnit unit;
  final AnalyticsQuality quality;
  final int? sampleCount, populationCount;
  final double? changePercent;
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
  final AnalyticsFamily family;
  final String title;
  final List<AnalyticsMetric> metrics;
  final List<AnalyticsColumn> columns;
  final List<AnalyticsRow> rows;
  final List<String> notes;
}

const _unchanged = Object();

class AnalyticsQuery {
  AnalyticsQuery({required this.startDate, required this.endDateExclusive, this.live = false, this.cashierId, this.shiftId, this.diningType, this.paymentMethod}) {
    if (!startDate.isBefore(endDateExclusive)) throw ArgumentError('Business Day range must have start < end.');
    if (cashierId != null && cashierId! <= 0 || shiftId != null && shiftId! <= 0) throw ArgumentError('Staff and shift IDs must be positive.');
  }
  final DateTime startDate, endDateExclusive;
  final bool live;
  final int? cashierId, shiftId;
  final String? diningType, paymentMethod;
  bool get hasOrderFilters => cashierId != null || shiftId != null || diningType != null || paymentMethod != null;
  AnalyticsQuery copyWith({DateTime? startDate, DateTime? endDateExclusive, bool? live, Object? cashierId = _unchanged, Object? shiftId = _unchanged, Object? diningType = _unchanged, Object? paymentMethod = _unchanged}) => AnalyticsQuery(startDate: startDate ?? this.startDate, endDateExclusive: endDateExclusive ?? this.endDateExclusive, live: live ?? this.live, cashierId: identical(cashierId, _unchanged) ? this.cashierId : cashierId as int?, shiftId: identical(shiftId, _unchanged) ? this.shiftId : shiftId as int?, diningType: identical(diningType, _unchanged) ? this.diningType : diningType as String?, paymentMethod: identical(paymentMethod, _unchanged) ? this.paymentMethod : paymentMethod as String?);
  @override
  bool operator ==(Object other) => other is AnalyticsQuery && startDate == other.startDate && endDateExclusive == other.endDateExclusive && live == other.live && cashierId == other.cashierId && shiftId == other.shiftId && diningType == other.diningType && paymentMethod == other.paymentMethod;
  @override
  int get hashCode => Object.hash(startDate, endDateExclusive, live, cashierId, shiftId, diningType, paymentMethod);
}

class AnalyticsSnapshot {
  AnalyticsSnapshot({required this.query, required this.generatedAt, required List<AnalyticsSection> sections, required List<int> businessDayIds, List<String> notes = const [], this.generatedByStaffId}) : sections = List.unmodifiable(sections), businessDayIds = List.unmodifiable(businessDayIds), notes = List.unmodifiable(notes);
  final AnalyticsQuery query;
  final DateTime generatedAt;
  final int? generatedByStaffId;
  final List<AnalyticsSection> sections;
  final List<int> businessDayIds;
  final List<String> notes;
  AnalyticsSection section(AnalyticsFamily family) => sections.firstWhere((section) => section.family == family);
}
