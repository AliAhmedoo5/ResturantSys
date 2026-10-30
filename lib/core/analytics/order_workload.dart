part of 'analytics_service.dart';

/// Independent confirmed-order workload and current eligible-value projections.
class _OrderWorkload {
  _OrderWorkload(this.builder);
  final _ReportBuilder builder;

  List<AnalyticsRow> build() {
    final e = builder.e;
    final days = {for (final day in [...e.get('days'), ...e.get('order_days')]) day['id']: day};
    final daily = <String, List<_Record>>{};
    final labels = <String, String>{};
    final dayIds = <String, Object?>{};
    final operational = e.query.timeBasis == AnalyticsTimeBasis.businessDay;
    if (operational) {
      for (final day in e.get('days')) {
        final time = _karachi(day['opened_at']);
        if (time == null) continue;
        final key = 'day-${day['id']}';
        daily[key] = [];
        labels[key] = '${_sqlDate(time)} · Business Day #${day['id']}';
        dayIds[key] = day['id'];
      }
    }
    final hours = List.generate(24, (_) => <_Record>[]);
    var unknownHours = 0;
    for (final order in builder.orders) {
      final created = _karachi(order['created_at']);
      if (created == null) { unknownHours++; } else { hours[created.hour].add(order); }
      final date = operational ? _karachi(days[order['business_day_id']]?['opened_at']) : created;
      if (date == null) continue;
      final key = operational ? 'day-${order['business_day_id']}' : _sqlDate(date);
      daily.putIfAbsent(key, () => []).add(order);
      labels[key] = operational ? '${_sqlDate(date)} · Business Day #${order['business_day_id']}' : _sqlDate(date);
      dayIds[key] = operational ? order['business_day_id'] : null;
    }
    final observed = !e.absent.contains('orders') && days.isNotEmpty;
    final keys = daily.keys.toList()..sort((a, b) {
      final date = labels[a]!.split(' ·').first.compareTo(labels[b]!.split(' ·').first);
      if (date != 0) return date;
      return (dayIds[a] as int? ?? 0).compareTo(dayIds[b] as int? ?? 0);
    });
    List<AnalyticsRow> project(String kind, List<String> ids, List<List<_Record>> groups,
        List<String> names, bool complete) {
      final counts = groups.map((rows) => rows.length).toList();
      final values = groups.map((rows) => _sum(rows.where(_valid), 'grand_total')).toList();
      return [for (var i = 0; i < ids.length; i++) (() {
        final rows = groups[i];
        final eligible = rows.where(_valid).toList();
        final orderIds = rows.map((r) => r['id']).toSet();
        final cancelledIds = e.get('revisions').where((r) => r['action'] == 'CANCEL').map((r) => r['order_id']).toSet();
        final refunds = e.get('payments').where((p) => orderIds.contains(p['order_id']) && _money(p, 'amount_tendered') < 0);
        final countRank = 1 + counts.where((n) => n > counts[i]).length;
        final valueRank = 1 + values.where((n) => n > values[i]).length;
        return AnalyticsRow(id: 'workload-${ids[i]}', sourceType: 'order_workload',
          sourceId: rows.map((r) => r['id']).join(','), cells: {
            'kind': kind, 'period': names[i], 'time_basis': e.query.timeBasis.name,
            'business_day_id': kind == 'Daily workload' ? dayIds[ids[i]] : null,
            'hour': kind == 'Hourly workload' ? i : null,
            'confirmed_orders': complete ? counts[i] : null,
            'eligible_orders': complete ? eligible.length : null,
            'recorded_value_paisa': complete ? values[i] : null,
            'average_ticket_paisa': complete && eligible.isNotEmpty ? values[i] / eligible.length : null,
            'cancelled_orders': rows.where((r) => cancelledIds.contains(r['id']) || ['CANCELLED', 'VOIDED', 'REFUNDED'].contains(r['payment_status'])).length,
            'refunds_paisa': -_sum(refunds, 'amount_tendered'),
            'count_rank': complete ? countRank : null,
            'value_rank': complete ? valueRank : null,
            'count_peak': complete ? countRank == 1 : null,
            'value_peak': complete ? valueRank == 1 : null,
            'order_ids': rows.map((r) => r['id']).join(','),
            'eligible_order_ids': eligible.map((r) => r['id']).join(','),
            'coverage': complete ? 'Observed selected Order cohort' : 'Unavailable coverage',
            'unknown_creation_times': unknownHours,
            'value_basis': 'Current valid Order grand total, including Collection Due; excludes CANCELLED, VOIDED, REFUNDED. Average divides by eligible_orders; not receipts.',
          });
      })()];
    }
    return [
      ...project('Daily workload', keys, keys.map((k) => daily[k]!).toList(), keys.map((k) => labels[k]!).toList(), observed),
      ...project('Hourly workload', List.generate(24, (h) => 'hour-$h'), hours,
        List.generate(24, (h) => '${h.toString().padLeft(2, '0')}:00'), observed && unknownHours == 0),
    ];
  }
}
