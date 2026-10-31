part of 'analytics_service.dart';

/// Finance flows use linked payment evidence; postings and physical movement
/// contributors below are different views and never inputs to these totals.
class _FinanceTimeline {
  _FinanceTimeline(this.e);
  final _Evidence e;
  static const keys = ['event_kind', 'payment_source', 'actual_at', 'recorded_at', 'actual_at_utc', 'recorded_at_utc',
    'recorded_by', 'recorded_by_name_snapshot', 'shift_owner_id',
    'shift_owner_name_snapshot', 'approved_by', 'source_table', 'source_id',
    'movement_id', 'time_coverage'];
  bool _finance(_Record r) => ['expense_entries', 'payroll_entries', 'vendor_transactions'].contains(r['source_table']);
  bool _selected(_Record r) {
    final q = e.query;
    if (q.shiftId != null && r['shift_id'] != q.shiftId) return false;
    final shift = e.get('shifts').where((s) => s['id'] == r['shift_id']).firstOrNull;
    if (q.cashierId != null && (r['shift_owner_id'] ?? shift?['staff_id']) != q.cashierId) return false;
    if (q.timeBasis == AnalyticsTimeBasis.calendarTime) {
      final time = _karachi(r['actual_at']);
      return time != null && !time.isBefore(analyticsWallClock(q.startDate)) && time.isBefore(analyticsWallClock(q.endDateExclusive));
    }
    return e.get('days').any((d) => d['id'] == r['business_day_id']);
  }
  late final events = e.get('payment_events').where(_finance).where(_selected).toList()
    ..sort((a, b) => '${a['actual_at'] ?? ''}:${a['id']}'.compareTo('${b['actual_at'] ?? ''}:${b['id']}'));
  late final uncovered = <_Record>[
    for (final pair in [('expense_entries', 'expense_entries'), ('payroll_entries', 'payroll_entries'), ('vendor_events', 'vendor_transactions')])
      for (final r in e.get(pair.$1))
        if ((pair.$1 != 'payroll_entries' || ['PAYMENT', 'ADVANCE'].contains(r['kind']) || r['kind'] == 'REVERSAL' && r['source'] != 'NONE') &&
            (pair.$1 != 'vendor_events' || ['PAYMENT_DRAWER', 'PAYMENT_EXTERNAL'].contains(r['type'])) &&
            !e.get('payment_events').any((p) => p['source_table'] == pair.$2 && p['source_id'] == r['id']))
          {...r, 'source_table': pair.$2},
  ];
  List<AnalyticsMetric> get metrics => [
    AnalyticsMetric(id: 'finance_unknown_time', label: 'Finance postings without retained actual time',
      value: uncovered.length, unit: AnalyticsUnit.count,
      explanation: 'Selected posting-context records without linked payment evidence. Not allocated to actual calendar dates or cash streams. Historical coverage is incomplete.'),
    for (final source in ['DRAWER', 'BANK', 'OWNER', 'EXTERNAL_UNKNOWN'])
      for (final out in [false, true]) AnalyticsMetric(
        id: 'finance_${source.toLowerCase()}_${out ? 'outflow' : 'inflow'}',
        label: '$source finance ${out ? 'outflow' : 'inflow'}',
        value: events.where((r) => r['payment_source'] == source)
          .map((r) => (r['amount_paisa'] as num).toInt())
          .where((v) => out ? v < 0 : v > 0).fold<int>(0, (a, v) => a + v.abs()),
        unit: AnalyticsUnit.paisa,
        quality: uncovered.isNotEmpty || e.absent.contains('payment_events') ? AnalyticsQuality.estimated : AnalyticsQuality.complete,
        explanation: 'Linked finance payment events only, counted once. Accruals, advance offsets and unpaid supplier purchases are excluded. Actual-time calendar scope excludes unknown times; Business Day uses retained assignment. Order-only filters do not apply.'),
  ];
  List<AnalyticsRow> get rows => [...events.map((r) {
    final shift = e.get('shifts').where((s) => s['id'] == r['shift_id']).firstOrNull;
    return _ReportBuilder(e)._row('payment_events', r, {
        'kind': 'Finance payment', 'event_kind': r['kind'],
        'amount_paisa': r['amount_paisa'], 'payment_source': r['payment_source'],
        'business_day_id': r['business_day_id'], 'shift_id': r['shift_id'],
        'shift_owner_id': r['shift_owner_id'] ?? shift?['staff_id'],
        'shift_owner_name_snapshot': r['shift_owner_name_snapshot'] == null ? null : _ReportBuilder._safeText(r['shift_owner_name_snapshot']),
        'recorded_by': r['recorded_by'], 'recorded_by_name_snapshot': r['recorded_by_name_snapshot'] == null ? null : _ReportBuilder._safeText(r['recorded_by_name_snapshot']),
        'approved_by': r['approved_by'], 'actual_at': r['actual_at'],
        'recorded_at': r['recorded_at'],
        'actual_at_utc': r['actual_at'], 'recorded_at_utc': r['recorded_at'], 'source_table': r['source_table'],
        'source_id': r['source_id'], 'movement_id': r['movement_id'],
        'time_coverage': r['actual_at'] == null ? 'Unknown actual time' : 'Retained actual time',
      });
  }),
    ...uncovered.map((r) => AnalyticsRow(id: 'finance-unknown:${r['source_table']}:${r['id']}',
      sourceType: '${r['source_table']}', sourceId: '${r['id']}', cells: {
        'kind': 'Finance coverage gap', 'source_table': r['source_table'], 'source_id': r['id'],
        'time_coverage': 'Actual money time unknown; excluded from flow totals',
        'business_day_id': r['business_day_id'], 'payment_source': r['source'] ?? 'Unknown historical source',
      })),
  ];
  List<String> get notes => [
    'Finance timeline: signed Integer Paisa; DRAWER, BANK and OWNER streams remain separate. A linked Cash Movement is custody evidence for the same event, not a second payment. Non-drawer records legitimately have no physical Shift.',
    'Actual and immutable recording times are separate. Legacy expense/payroll/supplier posting timestamps are not inferred actual money times; ledger rows remain visible separately and are absent from actual-time totals unless retained payment evidence exists.',
    'Salary accrual, advance recovery offsets and unpaid supplier purchases are noncash obligations, excluded from flow. Original earned/posting views remain separate. Internal custody transfers are not finance expenses.',
    'Late finance entries require an open assigned Business Day and, for drawer cash, the same open physical Shift. Closed-period correction entry is unavailable; original sealed reports remain unchanged.',
  ];
}
