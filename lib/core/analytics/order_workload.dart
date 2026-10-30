part of 'analytics_service.dart';

typedef _WorkloadBucket = ({String id, String label, List<_Record> records, Object? dayId, int? hour});
typedef _WorkloadPeriod = ({bool complete, bool available, String status, List<_Record> days});

/// Independent confirmed-order workload and current eligible-value projections.
class _OrderWorkload {
  _OrderWorkload(this.builder);
  final _ReportBuilder builder;

  List<AnalyticsRow> build() {
    final e = builder.e;
    final days = {for (final day in [...e.get('days'), ...e.get('order_days')]) day['id']: day};
    final daily = <String, _WorkloadBucket>{};
    final operational = e.query.timeBasis == AnalyticsTimeBasis.businessDay;
    final cutoff = _karachi(e.now.toIso8601String())!;
    if (operational) {
      for (final day in e.get('days')) {
        final time = _karachi(day['opened_at']);
        if (time == null) continue;
        final key = 'day-${day['id']}';
        daily[key] = (id: key, label: '${_sqlDate(time)} · Business Day #${day['id']}',
          records: [], dayId: day['id'], hour: null);
      }
    }
    final hours = <_WorkloadBucket>[for (var h = 0; h < 24; h++)
      (id: 'hour-$h', label: '${h.toString().padLeft(2, '0')}:00', records: [], dayId: null, hour: h)];
    var unknownHours = 0;
    for (final order in builder.orders) {
      final created = _karachi(order['created_at']);
      if (created == null) { unknownHours++; } else { hours[created.hour].records.add(order); }
      final date = operational ? _karachi(days[order['business_day_id']]?['opened_at']) : created;
      if (date == null) continue;
      final key = operational ? 'day-${order['business_day_id']}' : _sqlDate(date);
      daily.putIfAbsent(key, () => (id: key,
        label: operational ? '${_sqlDate(date)} · Business Day #${order['business_day_id']}' : _sqlDate(date),
        records: [], dayId: operational ? order['business_day_id'] : null, hour: null)).records.add(order);
    }
    final observed = !e.absent.contains('orders') && days.isNotEmpty;
    final dates = daily.values.toList()..sort((a, b) {
      final date = a.label.split(' ·').first.compareTo(b.label.split(' ·').first);
      return date != 0 ? date : (a.dayId as int? ?? 0).compareTo(b.dayId as int? ?? 0);
    });
    bool closed(_Record day) {
      final end = _karachi(day['closed_at']);
      return day['status'] == 'CLOSED' && end != null && !end.isAfter(cutoff);
    }
    bool observedHour(int hour, Iterable<_Record> context) {
      for (final day in context) {
        if (operational && closed(day)) return true;
        var start = _karachi(day['opened_at']);
        var end = _karachi(day['closed_at']) ?? cutoff;
        if (start == null) continue;
        if (end.isAfter(cutoff)) end = cutoff;
        if (!operational) {
          final selectedStart = analyticsWallClock(e.query.startDate);
          final selectedEnd = analyticsWallClock(e.query.endDateExclusive);
          if (start.isBefore(selectedStart)) start = selectedStart;
          if (end.isAfter(selectedEnd)) end = selectedEnd;
        }
        if (!start.isBefore(end)) continue;
        if (end.difference(start) >= const Duration(hours: 24)) return true;
        for (var cursor = DateTime.utc(start.year, start.month, start.day, start.hour);
            cursor.isBefore(end); cursor = cursor.add(const Duration(hours: 1))) {
          if (cursor.hour == hour) return true;
        }
      }
      return false;
    }
    _WorkloadPeriod period(_WorkloadBucket bucket) {
      final ids = bucket.hour != null ? days.keys.toSet() : bucket.dayId != null
        ? {bucket.dayId} : bucket.records.map((r) => r['business_day_id']).toSet();
      final context = ids.map((id) => days[id]).whereType<_Record>().toList();
      final allClosed = context.isNotEmpty && context.length == ids.length && context.every(closed);
      final calendarEnd = bucket.hour == null && !operational
        ? DateTime.parse('${bucket.id}T00:00:00Z').add(const Duration(days: 1))
        : analyticsWallClock(e.query.endDateExclusive);
      final elapsed = operational || !calendarEnd.isAfter(cutoff);
      final available = observed && (bucket.hour == null || unknownHours == 0 &&
        (bucket.records.isNotEmpty || observedHour(bucket.hour!, context)));
      final complete = available && allClosed && elapsed;
      final status = !observed ? 'Unavailable coverage'
        : !available ? 'Not yet observed in selected intervals (incomplete)'
        : complete ? operational ? 'Completed Business Day cohort' : 'Elapsed Calendar period; contributing Business Days completed'
        : operational ? bucket.hour == null && context.any((d) => d['status'] == 'OPEN')
          ? 'Open Business Day (incomplete)' : 'Incomplete Business Day cohort; closure unavailable'
        : elapsed ? 'Elapsed Calendar period; contributing Business Days incomplete'
          : 'Calendar period incomplete at cutoff; Business Day closure retained separately';
      return (complete: complete, available: available, status: status, days: context);
    }
    List<AnalyticsRow> project(String kind, List<_WorkloadBucket> buckets) {
      final candidates = buckets.where((bucket) => period(bucket).complete).toList();
      return [for (final bucket in buckets) (() {
        final rows = bucket.records;
        final evidence = period(bucket);
        final eligible = rows.where(_valid).toList();
        final value = _sum(eligible, 'grand_total');
        final orderIds = rows.map((r) => r['id']).toSet();
        final cancelledIds = e.get('revisions').where((r) => r['action'] == 'CANCEL').map((r) => r['order_id']).toSet();
        final refunds = e.get('payments').where((p) => orderIds.contains(p['order_id']) && _money(p, 'amount_tendered') < 0);
        final countRank = 1 + candidates.where((b) => b.records.length > rows.length).length;
        final valueRank = 1 + candidates.where((b) => _sum(b.records.where(_valid), 'grand_total') > value).length;
        return AnalyticsRow(id: 'workload-${bucket.id}', sourceType: 'order_workload',
          sourceId: rows.map((r) => r['id']).join(','), cells: {
            'kind': kind, 'period': bucket.label, 'time_basis': e.query.timeBasis.name,
            'business_day_id': bucket.dayId, 'hour': bucket.hour,
            'confirmed_orders': evidence.available ? rows.length : null,
            'eligible_orders': evidence.available ? eligible.length : null,
            'recorded_value_paisa': evidence.available ? value : null,
            'observed_confirmed_orders': observed ? rows.length : null,
            'observed_recorded_value_paisa': observed ? value : null,
            'average_ticket_paisa': evidence.available && eligible.isNotEmpty ? value / eligible.length : null,
            'cancelled_orders': rows.where((r) => cancelledIds.contains(r['id']) || ['CANCELLED', 'VOIDED', 'REFUNDED'].contains(r['payment_status'])).length,
            'refunds_paisa': -_sum(refunds, 'amount_tendered'),
            'count_rank': evidence.complete ? countRank : null,
            'value_rank': evidence.complete ? valueRank : null,
            'count_peak': evidence.complete ? countRank == 1 : null,
            'value_peak': evidence.complete ? valueRank == 1 : null,
            'order_ids': rows.map((r) => r['id']).join(','),
            'eligible_order_ids': eligible.map((r) => r['id']).join(','),
            'period_complete': evidence.complete, 'period_status': evidence.status,
            'bucket_observed': evidence.available,
            'contributing_business_day_ids': evidence.days.map((d) => d['id']).join(','),
            'open_business_day_ids': evidence.days.where((d) => d['status'] == 'OPEN').map((d) => d['id']).join(','),
            'business_day_status_evidence': evidence.days.map((d) => '${d['id']}: ${d['status']}; closed_at=${d['closed_at'] ?? 'unavailable'}').join(' | '),
            'coverage_cutoff': analyticsTimestamp(e.now.toIso8601String()),
            'coverage_cutoff_source': e.now.toIso8601String(),
            'coverage': !evidence.available ? 'Unavailable coverage' : evidence.complete
              ? 'Observed selected Order cohort' : 'Observed selected Order cohort to cutoff; incomplete',
            'ranking_basis': 'Completed buckets only; incomplete activity displayed separately without completed-period peak rank',
            'unknown_creation_times': unknownHours,
            'value_basis': 'Current valid Order grand total, including Collection Due; excludes CANCELLED, VOIDED, REFUNDED. Average divides by eligible_orders; not receipts.',
          });
      })()];
    }
    return [...project('Daily workload', dates), ...project('Hourly workload', hours)];
  }
}
