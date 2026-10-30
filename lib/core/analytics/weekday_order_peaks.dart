part of 'analytics_service.dart';

class _WeekdayOrderPeaks {
  _WeekdayOrderPeaks(this.builder);
  final _ReportBuilder builder;
  static const note = 'Operational weekday average = confirmed Orders on selected completed Business Days / those distinct completed Business Days, including opened zero-order days. Open days are separate; zero denominator is unavailable. Order-only filters restrict the numerator, not the opened-day denominator. Calendar weekdays use actual Karachi creation date; operational weekdays use assigned Business Day date. Weekday/hour cells use actual Karachi clock hours; weeks start Monday and months use local calendar boundaries. Projections overlap and must not be added. Missing evidence remains unavailable; exports retain these same rows and exact bucket boundaries.';
  static const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  List<AnalyticsRow> build() {
    final e = builder.e;
    final operational = e.query.timeBasis == AnalyticsTimeBasis.businessDay;

    final cutoff = _karachi(e.now.toIso8601String())!;
    final days = operational ? e.get('days') : e.get('peak_coverage_days');
    bool completed(_Record day) {
      final end = _karachi(day['closed_at']);
      return day['status'] == 'CLOSED' && end != null && !end.isAfter(cutoff);
    }
    final rows = <AnalyticsRow>[];
    if (operational) for (var weekday = 1; weekday <= 7; weekday++) {
      final selected = days.where((d) => _karachi(d['opened_at'])?.weekday == weekday).toList();
      final closed = selected.where(completed).toList();
      final open = selected.where((d) => d['status'] == 'OPEN').toList();
      List<_Record> ordersFor(List<_Record> context) {
        final ids = context.map((d) => d['id']).toSet();
        return builder.orders.where((o) => ids.contains(o['business_day_id'])).toList();
      }
      final orders = ordersFor(selected), numerator = ordersFor(closed), live = ordersFor(open);
      rows.add(AnalyticsRow(id: 'weekday-$weekday', sourceType: 'weekday_order_peaks',
        sourceId: orders.map((o) => o['id']).join(','), cells: {
          'kind': 'Weekday comparison', 'period': names[weekday - 1], 'weekday': weekday,
          'weekday_basis': 'Operational Business Day weekday', 'time_basis': e.query.timeBasis.name,
          'confirmed_orders': orders.length, 'completed_confirmed_orders': numerator.length,
          'completed_business_days': closed.length,
          'orders_per_completed_day': closed.isEmpty || e.absent.contains('orders') ? null : numerator.length / closed.length,
          'open_business_days': open.length, 'open_confirmed_orders': live.length,
          'unavailable_closure_business_days': selected.length - closed.length - open.length,
          'contributing_business_day_ids': selected.map((d) => d['id']).join(','),
          'completed_business_day_ids': closed.map((d) => d['id']).join(','),
          'open_business_day_ids': open.map((d) => d['id']).join(','),
          'order_ids': orders.map((o) => o['id']).join(','),
          'completed_order_ids': numerator.map((o) => o['id']).join(','),
          'coverage_cutoff': analyticsTimestamp(e.now.toIso8601String()),
          'coverage': closed.isEmpty ? 'Unavailable completed-day denominator' : 'Selected completed Business Days including opened zero-order days',
          'denominator_policy': 'All selected opened Business Days; order-only filters restrict numerator, not denominator. Open days separate.',
        }));
    }
    final ranked = [for (final row in rows) AnalyticsRow(id: row.id, sourceType: row.sourceType, sourceId: row.sourceId,
      cells: {...row.cells,
        'weekday_rank': row.cells['orders_per_completed_day'] == null ? null : 1 + rows.where((other) =>
          other.cells['orders_per_completed_day'] is num && (other.cells['orders_per_completed_day'] as num) > (row.cells['orders_per_completed_day'] as num)).length,
        'weekday_peak': row.cells['orders_per_completed_day'] == null ? null : !rows.any((other) =>
          other.cells['orders_per_completed_day'] is num && (other.cells['orders_per_completed_day'] as num) > (row.cells['orders_per_completed_day'] as num)),
        'ranking_basis': 'Completed-day average only; every tie included, chronological weekday order',
      })];
    return [...ranked, ...recurring(days, operational, cutoff, completed)];
  }

  List<AnalyticsRow> recurring(List<_Record> days, bool operational, DateTime cutoff,
      bool Function(_Record) completed) {
    final e = builder.e;
    final dayMap = {for (final d in [...days, ...e.get('order_days')]) d['id']: d};
    final basis = operational ? 'Operational Business Day weekday' : 'Actual Calendar weekday';
    final selectedStart = analyticsWallClock(e.query.startDate);
    final selectedEnd = analyticsWallClock(e.query.endDateExclusive);
    final matrix = <int, List<_Record>>{};
    final observed = <int, Set<Object?>>{};
    final weekOrders = <String, List<_Record>>{}, monthOrders = <String, List<_Record>>{};
    final weekDays = <String, Set<Object?>>{}, monthDays = <String, Set<Object?>>{};
    var unknownTime = 0, unknownDay = 0;
    DateTime date(DateTime t) => DateTime.utc(t.year, t.month, t.day);
    DateTime monday(DateTime t) => DateTime.utc(t.year, t.month, t.day - t.weekday + 1);
    DateTime month(DateTime t) => DateTime.utc(t.year, t.month);
    DateTime end(DateTime t, bool weekly) => weekly ? t.add(const Duration(days: 7)) : DateTime.utc(t.year, t.month + 1);
    void addPeriods(DateTime at, Object? dayId) {
      weekDays.putIfAbsent(_sqlDate(monday(at)), () => {}).add(dayId);
      monthDays.putIfAbsent(_sqlDate(month(at)), () => {}).add(dayId);
    }
    for (final day in days) {
      final opening = _karachi(day['opened_at']);
      if (opening == null) continue;
      if (operational) {
        addPeriods(opening, day['id']);
        if (completed(day)) {
          // A completed operational cohort supports observed zero-order cells
          // for every actual clock hour; no unopened weekday is manufactured.
          for (var h = 0; h < 24; h++) {
            observed.putIfAbsent((opening.weekday - 1) * 24 + h, () => {}).add(day['id']);
          }
        }
      }
      var start = opening;
      var stop = _karachi(day['closed_at']) ?? cutoff;
      if (stop.isAfter(cutoff)) stop = cutoff;
      if (!operational) {
        if (start.isBefore(selectedStart)) start = selectedStart;
        if (stop.isAfter(selectedEnd)) stop = selectedEnd;
        for (final weekly in [true, false]) {
          var cursor = weekly ? monday(start) : month(start);
          while (cursor.isBefore(stop)) {
            (weekly ? weekDays : monthDays).putIfAbsent(_sqlDate(cursor), () => {}).add(day['id']);
            cursor = end(cursor, weekly);
          }
        }
      }
      if (!start.isBefore(stop)) continue;
      // One complete local week establishes every recurring clock cell.
      final allHours = stop.difference(start) >= const Duration(days: 7);
      if (!operational && allHours) {
        for (var i = 0; i < 168; i++) { observed.putIfAbsent(i, () => {}).add(day['id']); }
      } else if (!operational || !completed(day)) {
        final capped = allHours ? start.add(const Duration(days: 7)) : stop;
        for (var cursor = DateTime.utc(start.year, start.month, start.day, start.hour);
            cursor.isBefore(capped); cursor = cursor.add(const Duration(hours: 1))) {
          final weekday = operational ? opening.weekday : cursor.weekday;
          observed.putIfAbsent((weekday - 1) * 24 + cursor.hour, () => {}).add(day['id']);
        }
      }
    }
    for (final order in builder.orders) {
      final at = _karachi(order['created_at']);
      final assigned = _karachi(dayMap[order['business_day_id']]?['opened_at']);
      if (at == null) unknownTime++;
      if (operational && assigned == null) unknownDay++;
      final bucketDate = operational ? assigned : at;
      if (bucketDate == null) continue;
      addPeriods(bucketDate, order['business_day_id']);
      weekOrders.putIfAbsent(_sqlDate(monday(bucketDate)), () => []).add(order);
      monthOrders.putIfAbsent(_sqlDate(month(bucketDate)), () => []).add(order);
      if (at != null) {
        final cell = (bucketDate.weekday - 1) * 24 + at.hour;
        matrix.putIfAbsent(cell, () => []).add(order);
        observed.putIfAbsent(cell, () => {}).add(order['business_day_id']);
      }
    }
    final sourceAvailable = !e.absent.contains('orders') && !e.absent.contains('business_days');
    AnalyticsRow row(String id, Map<String, Object?> cells, List<_Record> orders, Iterable<Object?> context) {
      final ids = context.toSet().toList()..sort((a, b) => '$a'.compareTo('$b'));
      final open = ids.where((id) => dayMap[id]?['status'] == 'OPEN');
      return AnalyticsRow(id: id, sourceType: 'weekday_order_peaks', sourceId: orders.map((o) => o['id']).join(','), cells: {
        ...cells, 'time_basis': e.query.timeBasis.name, 'weekday_basis': basis,
        'order_ids': orders.map((o) => o['id']).join(','),
        'contributing_business_day_ids': ids.join(','), 'open_business_day_ids': open.join(','),
        'coverage_cutoff': analyticsTimestamp(e.now.toIso8601String()),
        'selected_start': _sqlDate(selectedStart), 'selected_end_exclusive': _sqlDate(selectedEnd),
        'unknown_creation_times': unknownTime, 'unknown_assigned_dates': unknownDay,
        'bucket_definition': 'Asia/Karachi UTC+05:00; inclusive start/exclusive end; Monday-start weeks; local calendar months; $basis and actual clock hour',
      });
    }
    final result = <AnalyticsRow>[];
    for (var weekday = 1; weekday <= 7; weekday++) {
      final weekdayOrders = <_Record>[];
      final weekdayDays = <Object?>{};
      for (var hour = 0; hour < 24; hour++) {
        final key = (weekday - 1) * 24 + hour;
        final records = matrix[key] ?? [];
        final ids = observed[key] ?? {};
        weekdayOrders.addAll(records); weekdayDays.addAll(ids);
        final available = sourceAvailable && ids.isNotEmpty && unknownTime == 0 && unknownDay == 0;
        final complete = available && ids.every((id) => dayMap[id] != null && completed(dayMap[id]!));
        result.add(row('weekday-hour-$weekday-$hour', {
          'kind': 'Weekday/hour workload', 'period': '${names[weekday - 1]} ${hour.toString().padLeft(2, '0')}:00',
          'weekday': weekday, 'hour': hour, 'confirmed_orders': available ? records.length : null,
          'observed_confirmed_orders': sourceAvailable ? records.length : null,
          'period_complete': complete,
          'coverage': !available ? 'Unavailable coverage' : complete ? 'Observed completed Business Days' : 'Observed to cutoff; incomplete Business Days',
        }, records, ids));
      }
      if (!operational) {
        result.add(row('calendar-weekday-$weekday', {
          'kind': 'Calendar weekday total', 'period': names[weekday - 1], 'weekday': weekday,
          'confirmed_orders': sourceAvailable && weekdayDays.isNotEmpty && unknownTime == 0 ? weekdayOrders.length : null,
          'orders_per_completed_day': null,
          'coverage': weekdayDays.isEmpty ? 'Unavailable observed calendar coverage' : 'Actual Calendar weekday total over observed intervals; not an operational average',
        }, weekdayOrders, weekdayDays));
      }
    }
    for (final weekly in [true, false]) {
      final contexts = weekly ? weekDays : monthDays;
      final orders = weekly ? weekOrders : monthOrders;
      final keys = contexts.keys.toList()..sort();
      for (final key in keys) {
        final start = date(DateTime.parse('${key}T00:00:00Z'));
        final stop = end(start, weekly);
        final ids = contexts[key]!;
        final records = orders[key] ?? [];
        final clipped = start.isBefore(selectedStart) || stop.isAfter(selectedEnd);
        final complete = sourceAvailable && !clipped && !stop.isAfter(cutoff) &&
          ids.every((id) => dayMap[id] != null && completed(dayMap[id]!));
        result.add(row('${weekly ? 'week' : 'month'}-$key', {
          'kind': weekly ? 'Weekly workload' : 'Monthly workload', 'period': key,
          'period_start': key, 'period_end_exclusive': _sqlDate(stop),
          'confirmed_orders': sourceAvailable ? records.length : null,
          'recorded_value_paisa': sourceAvailable ? _sum(records.where(_valid), 'grand_total') : null,
          'period_complete': complete, 'range_clipped': clipped,
          'coverage': !sourceAvailable ? 'Unavailable coverage' : complete ? 'Observed completed Business Day evidence; unopened days not assumed' : 'Incomplete period; clipped range, open day or unelapsed boundary',
        }, records, ids));
      }
    }
    return result;
  }}
