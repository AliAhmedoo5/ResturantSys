part of 'analytics_service.dart';

/// Monthly earned expense and its settlement, over the same committed read as
/// posting and payment views. Settlement figures are as of snapshot generation.
class _EarnedPayroll {
  _EarnedPayroll(this.e);
  final _Evidence e;
  late final all = e.get('all_payroll_entries');
  late final byId = {for (final p in all) p['id']: p};
  bool get wholeMonths {
    final start = analyticsWallClock(e.query.startDate);
    final end = analyticsWallClock(e.query.endDateExclusive);
    return !e.query.live && start == DateTime.utc(start.year, start.month) &&
      end == DateTime.utc(end.year, end.month);
  }
  bool _earned(_Record p) {
    final period = p['period'];
    if (period is! String || !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(period)) return false;
    final month = DateTime.parse('${period}-01T00:00:00Z');
    return !month.isBefore(analyticsWallClock(e.query.startDate)) && month.isBefore(analyticsWallClock(e.query.endDateExclusive));
  }
  late final entries = all.where(_earned).toList();
  _Record _original(_Record p) => p['kind'] == 'REVERSAL' ? byId[p['reversal_of']] ?? p : p;
  int _delta(_Record p, String kind, String key) => _original(p)['kind'] == kind ? (p[key] as int? ?? 0) : 0;
  int get accrued => entries.fold(0, (v, p) => v + _delta(p, 'ACCRUAL', 'payable_delta_paisa'));
  int get paid => -entries.fold<int>(0, (v, p) => v + _delta(p, 'PAYMENT', 'payable_delta_paisa'));
  int get recovered => -entries.fold<int>(0, (v, p) => v + _delta(p, 'RECOVERY', 'payable_delta_paisa'));
  int get advances => _integers(entries, 'advance_delta_paisa');
  int get unpaid => _integers(entries, 'payable_delta_paisa');
  bool get supported => wholeMonths && !e.absent.contains('payroll_entries') && all.isNotEmpty;
  bool get settlementSupported {
    final groups = <String, List<_Record>>{};
    for (final p in entries) {
      groups.putIfAbsent('${p['employee_id']}:${p['period']}', () => []).add(p);
    }
    return groups.values.every((rows) => _integers(rows, 'payable_delta_paisa') >= 0 &&
      _integers(rows, 'advance_delta_paisa') >= 0);
  }
  static const basis = 'Recorded earned salary uses explicit payroll YYYY-MM, independently of posting and payment dates. Only ACCRUAL and its linked reversal recognize expense. No rate, attendance, Shift duration or unposted salary is inferred. Whole calendar months only; order filters do not allocate payroll.';
  List<AnalyticsMetric> get metrics => [
    for (final item in [
      ('earned_salary', 'Recorded earned salary', accrued),
      ('earned_paid', 'Earned-month salary paid to cutoff', paid),
      ('earned_recovered', 'Earned-month advance offsets to cutoff', recovered),
      ('earned_unpaid', 'Earned-month unpaid payable to cutoff', unpaid),
      ('earned_advances', 'Earned-month outstanding advances to cutoff', advances),
    ]) AnalyticsMetric(id: item.$1, label: item.$2,
      value: supported && (item.$1 == 'earned_salary' || settlementSupported) ? item.$3 : null,
      unit: AnalyticsUnit.paisa,
      quality: supported && (item.$1 == 'earned_salary' || settlementSupported) ? AnalyticsQuality.complete : AnalyticsQuality.missing,
      explanation: '$basis Settlement sums entries explicitly labeled with the earned month through ${e.now.toIso8601String()}, not the month-end balance. Accrued minus paid minus recovered equals unpaid; advances remain separate. Cross-month or negative legacy settlement balances are unavailable; no silent reassignment. Empty history and partial-month ranges are unavailable.'),
  ];
  List<AnalyticsRow> get rows {
    final postingIds = e.get('payroll_entries').map((p) => p['id']).toSet();
    return all.where((p) => _earned(p) || postingIds.contains(p['id'])).map((p) {
      final event = e.get('payment_events').where((x) => x['source_table'] == 'payroll_entries' && x['source_id'] == p['id']).firstOrNull;
      final original = _original(p);
      return _ReportBuilder(e)._row('payroll_entries', p, {
        'kind': 'Payroll evidence', 'payroll_kind': p['kind'], 'employee_id': p['employee_id'],
        'earned_period': p['period'], 'in_earned_scope': _earned(p) ? 'Yes' : 'No',
        'in_posting_scope': postingIds.contains(p['id']) ? 'Yes' : 'No',
        'amount_paisa': p['amount_paisa'],
        'salary_expense_paisa': original['kind'] == 'ACCRUAL' ? p['payable_delta_paisa'] : 0,
        'payable_delta_paisa': p['payable_delta_paisa'], 'advance_delta_paisa': p['advance_delta_paisa'],
        'payment_source': p['source'], 'payment_event_id': event?['id'],
        'cash_movement_id': p['cash_movement_id'], 'reversal_of': p['reversal_of'],
        'business_day_id': p['business_day_id'] ?? event?['business_day_id'],
        'posting_day_coverage': p['business_day_id'] != null ? 'Retained posting day' : 'Posting day not retained; payment assignment is separate',
        'shift_id': event?['shift_id'], 'payment_business_day_id': event?['business_day_id'],
        'actual_at': event?['actual_at'], 'recorded_at': p['created_at'],
        'payment_recorded_at': event?['recorded_at'],
        'reason': _ReportBuilder._safeText(p['reason']),
        'time_coverage': event != null ? 'Retained payment evidence' : p['source'] == 'NONE' ? 'Noncash entry' : 'Unknown actual payment time; not inferred from posting',
      });
    }).toList();
  }
  List<String> get notes => [
    basis,
    'Payroll settlement cutoff: ${e.now.toIso8601String()}. Later settlements update this exploratory earned view, never original sealed reports. Rows mark earned scope and posting scope separately; do not add these views together.',
    'Legacy payroll does not retain a posting Business Day FK. Payment Business Day and Shift come only from linked payment events; accrual/recovery posting day remains unknown.',
    'Unsupported historical allocation stays unknown: no fabricated earned month, attendance, department allocation or actual payment time. No historical correction bridge exists in this installation; sealed reports are not correction-adjusted.',
    'Approved proration uses floor(monthly base paisa × worked calendar days / days in month), capped at monthly base. Report the explicit approved accrual; do not calculate missing worked days from Cashier Shifts.',
  ];
}
