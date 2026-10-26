import 'analytics_models.dart';

/// Serializes the displayed immutable snapshot without querying operational data.
class AnalyticsExportService {
  String csv(AnalyticsSnapshot snapshot, AnalyticsFamily family) =>
      [..._metadata(snapshot, family.name), ..._sectionRows(snapshot.section(family))]
          .map((row) => row.map(_csvCell).join(',')).join('\r\n');

  List<List<Object?>> _metadata(AnalyticsSnapshot s, String family) => [
    ['report_version', 'manager-analytics-v1'],
    ['report_kind', 'Exploratory current-record snapshot; not a sealed Z-report'],
    ['family', family], ['currency', 'PKR; monetary numbers are integer paisa (100 paisa = PKR 1)'],
    ['generated_utc', s.generatedAt.toUtc().toIso8601String()],
    ['generated_local', '${s.generatedAt.toUtc().add(const Duration(hours: 5)).toIso8601String().replaceAll('Z', '')}+05:00'],
    ['timezone', 'Asia/Karachi'], ['generated_by_staff_id', s.generatedByStaffId],
    ['business_date_start', _date(s.query.startDate)],
    ['business_date_end_exclusive', _date(s.query.endDateExclusive)],
    ['business_day_ids', s.businessDayIds.join(';')], ['live', s.query.live.toString()],
    ['cashier_id', s.query.cashierId], ['shift_id', s.query.shiftId],
    ['dining_type', s.query.diningType], ['payment_method', s.query.paymentMethod],
    ['time_basis', 'Orders/shifts/trips use Business Day IDs; timestamp events use selected actual Business Day intervals. Current stock is current.'],
    ['filter_scope', 'Order filters apply to order-derived datasets only; each section discloses its scope.'],
    for (final note in s.notes) ['snapshot_note', note],
  ];

  List<List<Object?>> _sectionRows(AnalyticsSection s) => [
    ['section', s.title],
    for (final note in s.notes) ['section_note', note],
    ['Metric ID', 'Metric', 'Value', 'Unit', 'Quality', 'Formula / explanation', 'Sample count', 'Population count', 'Change percent'],
    for (final m in s.metrics) [m.id, m.label, m.value, m.unit.name, m.quality.name, m.explanation, m.sampleCount, m.populationCount, m.changePercent],
    ['Row ID', 'Source type', 'Source ID', ...s.columns.map((c) => c.unit == null ? c.label : '${c.label} (${c.unit!.name})')],
    for (final row in s.rows) [row.id, row.sourceType, row.sourceId, ...s.columns.map((c) => row.cells[c.key])],
  ];

  String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _safeText(Object? value) {
    final text = value?.toString() ?? '';
    return RegExp(r'^[=+\-@\t\r\n]').hasMatch(text) ? "'$text" : text;
  }
  String _csvCell(Object? value) {
    final text = value is num ? value.toString() : _safeText(value);
    return text.contains(RegExp('[,"\r\n]')) ? '"${text.replaceAll('"', '""')}"' : text;
  }
}
