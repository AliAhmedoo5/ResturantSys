part of 'analytics_service.dart';

/// Actual money evidence and custody legs share a ledger, but only external
/// business effects enter consolidated flows. Posting time is never substituted.
class _MoneyFlowPeaks {
  _MoneyFlowPeaks(this.builder);
  final _ReportBuilder builder;
  _Evidence get e => builder.e;
  static const streams = ['DRAWER', 'BANK', 'OWNER', 'RIDER_HELD', 'EXTERNAL_UNKNOWN'];
  static const kinds = ['RECEIPT', 'REFUND', 'RIDER_COLLECTION', 'RIDER_HANDOVER',
    'EXPENSE', 'EXPENSE_REVERSAL', 'SUPPLIER_PAYMENT', 'PAYROLL_PAYMENT',
    'PAYROLL_ADVANCE', 'PAYROLL_REVERSAL'];
  bool transfer(_Record row) => row['kind'] == 'RIDER_HANDOVER';

  bool context(_Record row) =>
    (e.query.shiftId == null || row['shift_id'] == e.query.shiftId) &&
    (e.query.cashierId == null || row['shift_owner_id'] == e.query.cashierId);

  bool selected(_Record row) {
    if (!context(row)) return false;
    if (e.query.timeBasis == AnalyticsTimeBasis.businessDay) {
      return e.get('days').any((d) => d['id'] == row['business_day_id']);
    }
    final time = _karachi(row['actual_at']);
    return time != null && !time.isBefore(analyticsWallClock(e.query.startDate)) &&
      time.isBefore(analyticsWallClock(e.query.endDateExclusive));
  }

  String period(DateTime time) {
    final date = _date(time);
    return _sqlDate(switch (e.query.grouping) {
      AnalyticsGrouping.day => date,
      AnalyticsGrouping.week => date.subtract(Duration(days: date.weekday - 1)),
      AnalyticsGrouping.month => DateTime.utc(date.year, date.month),
    });
  }

  List<AnalyticsRow> build() {
    final all = e.get('payment_events').where((p) => kinds.contains(p['kind'])).toList();
    final selectedEvents = all.where(selected).toList();
    final known = selectedEvents.where((r) => _karachi(r['actual_at']) != null).toList();
    final unknown = all.where((r) => context(r) && _karachi(r['actual_at']) == null &&
      (e.query.timeBasis == AnalyticsTimeBasis.calendarTime || selected(r))).toList();
    final knownMovementIds = all.map((p) => p['movement_id']).whereType<int>().toSet();
    final legacyMovements = e.get('movements').where((m) => !knownMovementIds.contains(m['id']) &&
      (e.query.shiftId == null || m['shift_id'] == e.query.shiftId) &&
      (e.query.cashierId == null || e.get('shifts').any((s) => s['id'] == m['shift_id'] && s['staff_id'] == e.query.cashierId))).toList();
    final linkedTenders = all.map((p) => p['tender_id']).whereType<int>().toSet();
    final legacyTenders = e.get('payments').where((p) => !linkedTenders.contains(p['id'])).toList();
    final financeGaps = _FinanceTimeline(e).uncovered;
    final incomplete = unknown.isNotEmpty || legacyMovements.isNotEmpty || legacyTenders.isNotEmpty ||
      financeGaps.isNotEmpty || e.absent.contains('payment_events');
    final days = {for (final d in [...e.get('days'), ...e.get('event_days')]) d['id']: d};
    final rows = <AnalyticsRow>[];
    final groups = <String, List<_Record>>{};
    for (final event in known) {
      final source = '${event['payment_source']}';
      if (!streams.contains(source)) continue;
      final actual = _karachi(event['actual_at'])!;
      final day = days[event['business_day_id']];
      final time = e.query.timeBasis == AnalyticsTimeBasis.businessDay ? _karachi(day?['opened_at']) : actual;
      if (time == null) continue;
      final label = e.query.timeBasis == AnalyticsTimeBasis.businessDay && e.query.grouping == AnalyticsGrouping.day
        ? '${period(time)} · Business Day #${event['business_day_id']}' : period(time);
      for (final key in ['$source|period|$label', '$source|hour|${actual.hour.toString().padLeft(2, '0')}']) {
        groups.putIfAbsent(key, () => []).add(event);
      }
      final detail = builder._row('payment_events', event, {
        'kind': 'Money flow contributor', 'event_kind': event['kind'],
        'funding_stream': source, 'amount_paisa': event['amount_paisa'],
        'business_day_id': event['business_day_id'], 'shift_id': event['shift_id'],
        'originating_business_day_id': event['originating_business_day_id'],
        'originating_shift_id': event['originating_shift_id'],
        'order_id': event['order_id'], 'tender_id': event['tender_id'],
        'movement_id': event['movement_id'], 'settlement_id': event['settlement_id'],
        'source_table': event['source_table'], 'source_id': event['source_id'],
        'actual_at': event['actual_at'], 'recorded_at': event['recorded_at'],
        'recorded_by': event['recorded_by'], 'approved_by': event['approved_by'],
        'recorded_by_name_snapshot': event['recorded_by_name_snapshot'],
        'shift_owner_name_snapshot': event['shift_owner_name_snapshot'],
        'internal_transfer': transfer(event),
        'consolidated_business_effect': !transfer(event),
      });
      rows.add(AnalyticsRow(id: 'money-${detail.id}', sourceType: 'money_flow_event', sourceId: detail.sourceId, cells: detail.cells));
    }
    int amount(_Record r) => (r['amount_paisa'] as num).toInt();
    int inflow(List<_Record> rs) => rs.where((r) => amount(r) > 0).fold(0, (sum, r) => sum + amount(r));
    int outflow(List<_Record> rs) => rs.where((r) => amount(r) < 0).fold(0, (sum, r) => sum - amount(r));
    int net(List<_Record> rs) => inflow(rs) - outflow(rs);
    final entries = groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      final parts = entry.key.split('|');
      final source = parts[0], kind = parts[1], label = parts[2];
      final peers = entries.where((p) => p.key.startsWith('$source|$kind|')).toList();
      int rank(int Function(List<_Record>) value, {bool ascending = false}) => 1 + peers.where((p) => ascending
        ? value(p.value) < value(entry.value) : value(p.value) > value(entry.value)).length;
      final inflowRank = rank(inflow), outflowRank = rank(outflow);
      final greatest = rank(net), least = rank(net, ascending: true);
      final external = entry.value.where((p) => !transfer(p)).toList();
      final open = entry.value.any((p) => days[p['business_day_id']]?['status'] != 'CLOSED');
      rows.add(AnalyticsRow(id: 'money-bucket-${entry.key}', sourceType: 'money_flow_bucket',
        sourceId: entry.value.map((p) => p['id']).join(','), cells: {
        'kind': kind == 'hour' ? 'Hourly money flow' : 'Period money flow',
        'period': kind == 'hour' ? '$label:00' : label, 'hour': kind == 'hour' ? int.parse(label) : null,
        'funding_stream': source, 'time_basis': e.query.timeBasis.name,
        'grouping': e.query.grouping.name, 'inflow_paisa': inflow(entry.value),
        'outflow_paisa': outflow(entry.value), 'net_paisa': net(entry.value),
        'consolidated_inflow_paisa': inflow(external), 'consolidated_outflow_paisa': outflow(external),
        'consolidated_net_paisa': net(external),
        'internal_transfer_inflow_paisa': inflow(entry.value.where(transfer).toList()),
        'inflow_rank': inflowRank, 'outflow_rank': outflowRank,
        'greatest_net_rank': greatest, 'least_net_rank': least,
        'inflow_peak': inflowRank == 1, 'outflow_peak': outflowRank == 1,
        'greatest_net_peak': greatest == 1, 'least_net_peak': least == 1,
        'event_ids': entry.value.map((p) => p['id']).join(','),
        'contributing_business_day_ids': entry.value.map((p) => p['business_day_id']).whereType<int>().toSet().join(','),
        'coverage': incomplete ? 'Observed actual-time evidence only; historical gaps excluded' : 'Retained actual-time evidence',
        'period_status': open ? 'Includes open Business Day activity; incomplete at cutoff' : 'Closed contributing Business Days',
        'ranking_basis': 'Observed actual-time buckets within each stream; all ties retained chronologically. Open activity is partial, not a completed-period comparison.',
        'coverage_cutoff': analyticsTimestamp(e.now.toIso8601String()),
      }));
    }
    rows.add(AnalyticsRow(id: 'money-flow-coverage', sourceType: 'money_flow_coverage',
      sourceId: known.isNotEmpty ? known.map((p) => p['id']).join(',') : 'none', cells: {
      'kind': 'Money flow coverage', 'included_events': known.length,
      'unknown_time_events': unknown.length, 'unknown_time_paisa': unknown.fold<int>(0, (sum, p) => sum + amount(p).abs()),
      'legacy_movement_count': legacyMovements.length, 'legacy_tender_count': legacyTenders.length,
      'legacy_finance_posting_count': financeGaps.length,
      'coverage': incomplete ? 'Incomplete historical evidence; missing times/receiving attribution never inferred' : 'Retained event evidence; no missing sources detected',
      'scope': 'Unknown-time calendar evidence is unallocatable installation-wide, not asserted to belong to the selected window. Legacy counts retain selected posting/order context only.',
    }));
    return rows;
  }

  static const notes = [
    'Money-flow peaks use actual event time and receiving Business Day/Shift independently of originating Orders. Recording time, sales value, Opening Float, accruals and unpaid purchases never substitute for money movement.',
    'Inflow/outflow are nonnegative Integer Paisa magnitudes; net = inflow - outflow. Streams remain separate. RIDER_HELD is confirmed customer collection. Rider handover enters drawer custody only; consolidated business totals exclude this internal transfer and COD settlement attribution. Linked Cash Movements and tenders are not added again.',
    'Period grouping uses assigned Business Day date or actual Asia/Karachi calendar date, Monday-start weeks and local calendar months. Hours use actual Karachi clock time. Rankings cover observed buckets, retain every tie in chronological order, and explicitly label open-period activity. No zero-activity periods are invented from missing event coverage.',
    'Legacy order-cohort collections remain in Sales with their original scope. Unknown event times and missing receiving attribution remain excluded from unsupported buckets, with coverage counts; unlinked manual Cash Movements have unknown actual time. Order-only dimensions do not alter physical whole-Shift balances.',
  ];
}
