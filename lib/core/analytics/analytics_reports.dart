part of 'analytics_service.dart';

/// Pure projections and formulas over a single committed evidence snapshot.
class _ReportBuilder {
  _ReportBuilder(this.e);
  final _Evidence e;
  List<_Record> get orders => e.get('orders');
  late final List<_Record> valid = orders.where(_valid).toList();
  late final Set<Object?> validIds = valid.map((o) => o['id']).toSet();
  late final List<_Record> soldItems = e.get('items').where((i) => validIds.contains(i['order_id'])).toList();
  bool get partial => e.query.live || [...e.get('days'), ...e.get('order_days')].any((d) => d['status'] == 'OPEN');
  String get _orderBasis => 'Filtered order cohort by ${e.query.timeBasis == AnalyticsTimeBasis.businessDay ? 'assigned Business Day FK' : 'actual creation time in Asia/Karachi, inclusive start/exclusive end'}. Recorded current valid value includes Collection Due; excludes VOIDED, CANCELLED and REFUNDED. This is not recognized revenue.';
  static const _globalBasis = 'Selected Business Days, all shifts/domain events. Cashier, shift, Dining Type and payment filters apply only to order-based reports, not these totals.';
  static const _currentBasis = 'Current installation-wide position at refresh; not historical. Order filters do not apply.';
  static const _intervalBasis = 'Timestamp-only events within the union of selected actual Business Day intervals; opening inclusive, closing exclusive. No five-minute extension.';

  AnalyticsSnapshot build() {
    final sections = [_sales(), _orders(), _delivery(), _customers(),
      _ReportBuilder(_domainEvidence(e, AnalyticsFamily.menu))._menu(),
      _ReportBuilder(_domainEvidence(e, AnalyticsFamily.inventory))._inventory(),
      _ReportBuilder(_domainEvidence(e, AnalyticsFamily.procurement))._procurement(),
      _ReportBuilder(_domainEvidence(e, AnalyticsFamily.suppliers))._suppliers(), _cash(),
      _ReportBuilder(_domainEvidence(e, AnalyticsFamily.expenses))._expenses(),
      _ReportBuilder(_domainEvidence(e, AnalyticsFamily.staff))._staff(), _profitability(), _audit()];
    final overview = AnalyticsSection(family: AnalyticsFamily.overview, title: 'Overview', metrics: [
      ...sections.first.metrics.where((m) => ['recorded_value', 'orders', 'average_ticket'].contains(m.id)),
      ...sections.firstWhere((s) => s.family == AnalyticsFamily.delivery).metrics.where((m) => ['collection_due', 'all_collection_due'].contains(m.id)),
      ...sections.firstWhere((s) => s.family == AnalyticsFamily.cash).metrics.where((m) => ['expected_drawer', 'variance'].contains(m.id)),
      ...sections.firstWhere((s) => s.family == AnalyticsFamily.inventory).metrics.where((m) => m.id == 'negative_stock'),
      ...sections.firstWhere((s) => s.family == AnalyticsFamily.profitability).metrics.where((m) => m.id == 'gross_profit'),
    ], rows: e.get('days').map((d) => _row('business_days', d, {'business_date': _sqlDate(_karachi(d['opened_at'])!), 'opened_at': d['opened_at'], 'closed_at': d['closed_at'], 'status': d['status']})).toList(), columns: _columns(['business_date', 'opened_at', 'opened_at_source', 'closed_at', 'closed_at_source', 'status']), notes: [
      'Overview combines explicitly labeled order-cohort, selected-day and current global measures. See each formula for scope.',
      if (e.query.live && !e.get('days').any((d) => d['status'] == 'OPEN')) 'No Business Day is currently open. Historical reporting remains available.',
    ]);
    return AnalyticsSnapshot(filterOptions: e.filterOptions, query: e.query, generatedAt: e.now, generatedByStaffId: e.actor, sourceSchemaVersion: e.sourceSchemaVersion, businessDayIds: {...e.get('days').map((d) => d['id'] as int), ...e.get('order_days').map((d) => d['id'] as int), ...e.get('event_days').map((d) => d['id'] as int), ...e.get('bridge_days').map((d) => d['id'] as int)}.toList(), sections: [overview, ...sections], notes: [
      'Analytics formula version 4; PKR; Order time basis: ${e.query.timeBasis.name}; grouping: ${e.query.grouping.name}; Asia/Karachi (UTC+05:00). Start inclusive; end exclusive. Business Day weekday uses assigned opening date; calendar weekday uses actual creation date. Weeks start Monday; months use local calendar months.',
      'Non-order ledgers and drawer reconciliation retain Business Day opening-date scope. Calendar Order activity does not change their scope or Order assignments.',

      'Domain filters use stable IDs and current readable picker names. Whole drawers and current global balances are outside scope of unrelated domains; section notes state every exception.',
      for (final entry in e.query.domainFilters.entries) 'Selected ${entry.key.name}: ${entry.value} (${e.filterOptions.where((o) => o.dimension == entry.key && o.id == entry.value).firstOrNull?.label ?? "Unknown / archived ID"}).',
      'Exploratory view over current committed local records. Immutable sealed Z-reports retain their original content hash and revision.',
      'Legacy REAL rupees are normalized once per source amount through PaisaEngine; integer-paisa columns are preferred. Historical floating-point precision is not restored.',
      _intervalBasis,
      'Source schema version: ${e.sourceSchemaVersion ?? "unavailable"}; snapshot cutoff ${e.now.toIso8601String()}. Event time and immutable recording time are separate where stored. Missing evidence stays unavailable.',
      'Naive legacy timestamps are assumed Asia/Karachi; original values and explicit UTC/offset evidence remain in source details. Historical names are captured only from migration onward; current names are separate context.',
      if (e.query.hasOrderFilters) 'Order filters affect sales/orders/customers/menu, related delivery attempts and order audits. Current inventory/staff/Khata and whole-day cash/procurement/expense totals keep their labeled scope.',
      if (e.query.comparisonMode == AnalyticsComparisonMode.none)
        'Comparison mode: none. Historical prior window comparisons are disabled.'
      else if (e.query.comparisonMode == AnalyticsComparisonMode.comparableWeekday && e.query.priorStartDate != null)
        'Comparison mode: comparableWeekday. Comparing against the previous week equivalent window (${_sqlDate(e.query.priorStartDate!)} to ${_sqlDate(e.query.priorEndDateExclusive!)}).'
      else if (e.query.comparisonMode == AnalyticsComparisonMode.precedingPeriod && e.query.priorStartDate != null)
        'Comparison mode: precedingPeriod. Comparing against the preceding equal window (${_sqlDate(e.query.priorStartDate!)} to ${_sqlDate(e.query.priorEndDateExclusive!)}).',
      'Snapshot balances (inventory current stock, closing vendor payables, drawer custody, staff counts) are not historical flow measures and are excluded from comparisons.',
      if (partial) 'Percentage comparisons withheld: selected coverage contains a live/open Business Day and equivalent elapsed prior coverage is not established.',
      if (e.get('days').isEmpty) 'No Business Days match the selected date range.',
      if (e.absent.isNotEmpty) 'Missing source tables: ${e.absent.join(', ')}. No unavailable dataset is represented as a reliable zero.',
    ]);
  }

  AnalyticsSection _sales() {
    final prior = e.get('previous_orders').where(_valid).toList();
    final value = _sum(valid, 'grand_total');
    final collectedOrders = orders.where(_collected).map((o) => o['id']).toSet();
    final payments = e.get('payments').where((p) => collectedOrders.contains(p['order_id']) && (e.query.paymentMethod == null || p['payment_method'] == e.query.paymentMethod)).toList();
    final daily = _orderPeriods();
    final metrics = <AnalyticsMetric>[
      _metric('recorded_value', 'Recorded order value', value, explanation: _orderBasis, previous: _sum(prior, 'grand_total')),
      _metric('orders', 'Eligible orders', valid.length, unit: AnalyticsUnit.count, explanation: _orderBasis, previous: prior.length),
      _metric('subtotal', 'Item subtotal', _sum(valid, 'subtotal'), explanation: 'Current eligible order item subtotal before order discount; $_orderBasis'),
      _metric('discounts', 'Applied discounts', _sum(valid, 'discount_amount'), explanation: 'Sum stored order discount once per eligible order; $_orderBasis'),
      _metric('tax', 'Tax carve-out', _sum(valid, 'tax_amount'), explanation: 'Stored transaction tax amount, separate from recorded order value; $_orderBasis'),
      _metric('delivery_fees', 'Delivery fees', _integers(valid, 'delivery_fee_paisa'), explanation: 'Stored integer-paisa fee snapshots; $_orderBasis'),
      _metric('rounding', 'Cash rounding', _integers(valid, 'cash_rounding_paisa'), explanation: 'Signed stored cash rounding delta; $_orderBasis'),
      _metric('collected_tender', 'Collected tender', payments.fold<int>(0, (sum, p) => sum + _money(p, 'amount_tendered') - _money(p, 'change_returned')), explanation: 'Tender minus change, including negative explicit refunds; retained funds in SETTLED/REFUND_PENDING/CANCELLED/REFUNDED orders. Selected Order cohort, not receipt-event date. ${e.query.paymentMethod == null ? 'All methods.' : 'Only ${e.query.paymentMethod} tender lines; full matching orders remain the sales cohort.'}'),
      _average('average_ticket', 'Average ticket', value, valid.length, AnalyticsUnit.paisa, 'Recorded eligible order value / eligible order count; denominator shown. $_orderBasis'),
      _metric('recognized_revenue', 'Tax-exclusive recognized revenue', _sum(valid, 'grand_total') - _sum(valid, 'tax_amount'), explanation: 'Recognized on confirmation including COD receivables and delivery fees, less stored tax carve-out; cancellations/revisions use current recorded totals.'),
      _metric(
        'recorded_value_change',
        e.query.comparisonMode == AnalyticsComparisonMode.comparableWeekday ? 'Change from comparable weekday' : 'Change from preceding window',
        value - _sum(prior, 'grand_total'),
        explanation: (partial || e.query.comparisonMode == AnalyticsComparisonMode.none)
            ? (partial ? 'Unavailable for incomplete open-day coverage.' : 'No comparison selected.')
            : 'Absolute current minus ${e.query.comparisonMode == AnalyticsComparisonMode.comparableWeekday ? "comparable weekday" : "preceding equal"} selected-basis date-window recorded value.',
        unavailable: partial || e.query.comparisonMode == AnalyticsComparisonMode.none,
      ),
    ];
    final dimensions = <AnalyticsRow>[];
    for (final key in ['dining_type', 'cashier_id', 'shift_id']) {
      final groups = _group(valid, key);
      for (final group in groups.entries) {
        dimensions.add(AnalyticsRow(id: 'sales-$key-${group.key}', sourceType: 'orders', sourceId: group.value.map((o) => o['id']).join(','), cells: {'kind': 'Independent dimension', 'dimension': _label(key), 'dimension_value': group.key, 'orders': group.value.length, 'recorded_value_paisa': _sum(group.value, 'grand_total')}));
      }
    }
    for (final entry in _group(payments, 'payment_method').entries) {
      dimensions.add(AnalyticsRow(id: 'tender-${entry.key}', sourceType: 'order_payments', sourceId: entry.value.map((p) => p['id']).join(','), cells: {'kind': 'Tender breakdown', 'dimension': 'Payment method', 'dimension_value': entry.key, 'collected_paisa': entry.value.fold<int>(0, (sum, p) => sum + _money(p, 'amount_tendered') - _money(p, 'change_returned'))}));
    }
    for (final hour in _group(valid.map((o) => {...o, 'hour': _karachi(o['created_at'])?.hour}).toList(), 'hour').entries) {
      dimensions.add(AnalyticsRow(id: 'hour-${hour.key}', sourceType: 'orders', sourceId: hour.value.map((o) => o['id']).join(','), cells: {'kind': 'Hourly breakdown', 'dimension': 'Creation hour (Karachi)', 'dimension_value': hour.key, 'orders': hour.value.length, 'recorded_value_paisa': _sum(hour.value, 'grand_total')}));
    }
    return _section(AnalyticsFamily.sales, 'Sales', metrics, [
      ...daily,
      ...dimensions,
    ], ['kind', 'business_date', 'business_day_id', 'period_start', 'time_basis', 'grouping', 'dimension', 'dimension_value', 'orders', 'recorded_value_paisa', 'collected_paisa'], [_orderBasis, 'Period rows and chart use these identical values. Source IDs identify contributing Business Days or calendar-selected Orders; order detail is in Order operations.', 'Historical comparisons use the preceding equal selected-basis window with identical order filters. A zero prior baseline has no percentage.', 'Daily totals, each Dining Type/cashier/shift/hour breakdown and tender breakdown are independent views; never sum these different row kinds together.']);
  }

  List<AnalyticsRow> _orderPeriods() {
    final days = {for (final d in [...e.get('days'), ...e.get('order_days')]) d['id']: d};
    final groups = <String, List<_Record>>{};
    final starts = <String, String>{};
    final periodDays = <String, Set<Object?>>{};
    String? keyFor(_Record order) {
      final operational = e.query.timeBasis == AnalyticsTimeBasis.businessDay;
      final assignedDay = days[order['business_day_id']];
      final assignedOpening = assignedDay?['opened_at'];
      final time = _karachi(operational ? assignedOpening : order['created_at']);
      if (time == null) return null;
      final date = _date(time);
      final start = switch (e.query.grouping) {
        AnalyticsGrouping.day => date,
        AnalyticsGrouping.week => date.subtract(Duration(days: date.weekday - DateTime.monday)),
        AnalyticsGrouping.month => DateTime.utc(date.year, date.month),
      };
      final key = operational && e.query.grouping == AnalyticsGrouping.day
          ? 'day-${order['business_day_id']}' : _sqlDate(start);
      starts[key] = _sqlDate(start);
      periodDays.putIfAbsent(key, () => {}).add(order['business_day_id']);
      return key;
    }
    if (e.query.timeBasis == AnalyticsTimeBasis.businessDay) {
      for (final day in e.get('days')) {
        final key = keyFor({'business_day_id': day['id']});
        if (key != null) groups.putIfAbsent(key, () => []);
      }
    }
    for (final order in valid) {
      final key = keyFor(order);
      if (key != null) groups.putIfAbsent(key, () => []).add(order);
    }
    final keys = groups.keys.toList()..sort((a,b) {
      final date = starts[a]!.compareTo(starts[b]!);
      return date != 0 ? date : a.compareTo(b);
    });
    return [for (final key in keys) AnalyticsRow(id: 'order-period-$key',
      sourceType: e.query.timeBasis == AnalyticsTimeBasis.businessDay ? 'business_days' : 'orders',
      sourceId: e.query.timeBasis == AnalyticsTimeBasis.businessDay
          ? periodDays[key]!.join(',')
          : groups[key]!.map((o) => o['id']).join(','),
      cells: {'kind': 'Daily total', 'business_date': starts[key], 'period_start': starts[key],
        'business_day_id': key.startsWith('day-') ? int.parse(key.substring(4)) : null,
        'time_basis': e.query.timeBasis.name, 'grouping': e.query.grouping.name,
        'orders': groups[key]!.length, 'recorded_value_paisa': _sum(groups[key]!, 'grand_total')})];
  }

  AnalyticsSection _orders() {
    final daysById = {for (final d in [...e.get('days'), ...e.get('order_days')]) d['id']: d};
    final revisions = e.get('revisions');
    final revisedIds = revisions.map((r) => r['order_id']).toSet();
    final cancelled = {...orders.where((o) => ['CANCELLED', 'VOIDED', 'REFUNDED'].contains(o['payment_status'])).map((o) => o['id']), ...revisions.where((r) => r['action'] == 'CANCEL').map((r) => r['order_id'])};
    final refunds = e.get('payments').where((p) => _money(p, 'amount_tendered') < 0).toList();
    final paymentsByOrder = _group(e.get('payments'), 'order_id');
    var exposure = 0;
    for (final o in orders) {
      final payments = paymentsByOrder['${o['id']}'] ?? const <_Record>[];
      final retained = payments.fold<int>(0, (s, p) => s + _money(p, 'amount_tendered') - _money(p, 'change_returned'));
      final due = ['CANCELLED', 'VOIDED', 'REFUNDED'].contains(o['payment_status']) ? 0 : _money(o, 'grand_total');
      exposure += math.max(0, retained - due);
    }
    final statusEvents = e.get('order_status_events');
    final eventsByOrder = <int, List<_Record>>{};
    for (final ev in statusEvents) {
      final oid = ev['order_id'];
      if (oid is int) {
        eventsByOrder.putIfAbsent(oid, () => []).add(ev);
      }
    }
    final prepTimes = <double>[];
    int totalReworkCycles = 0;
    final orderPrepData = <int, Map<String, Object?>>{};
    for (final o in orders) {
      final oid = o['id'] as int;
      final oEvents = eventsByOrder[oid] ?? const [];
      final confirmedAt = _karachi(o['created_at']);
      final readyEvents = oEvents.where((ev) => ev['to_status'] == 'READY').toList();
      final reworkMoves = oEvents.where((ev) => ev['from_status'] == 'READY').length;
      final reworkCount = reworkMoves > 0 ? reworkMoves : (readyEvents.length > 1 ? readyEvents.length - 1 : 0);
      totalReworkCycles += reworkCount;

      if (readyEvents.isEmpty || confirmedAt == null) {
        orderPrepData[oid] = {
          'prep_duration_minutes': null,
          'prep_quality': 'Missing milestone',
          'rework_cycles': reworkCount,
        };
      } else {
        final firstReadyAt = _karachi(readyEvents.first['recorded_at']);
        if (firstReadyAt == null) {
          orderPrepData[oid] = {
            'prep_duration_minutes': null,
            'prep_quality': 'Missing milestone',
            'rework_cycles': reworkCount,
          };
        } else if (firstReadyAt.isBefore(confirmedAt)) {
          orderPrepData[oid] = {
            'prep_duration_minutes': null,
            'prep_quality': 'Invalid sequence',
            'rework_cycles': reworkCount,
          };
        } else {
          final durationMinutes = firstReadyAt.difference(confirmedAt).inSeconds / 60.0;
          prepTimes.add(durationMinutes);
          orderPrepData[oid] = {
            'prep_duration_minutes': durationMinutes,
            'prep_quality': 'Valid',
            'rework_cycles': reworkCount,
          };
        }
      }
    }
    prepTimes.sort();
    final metrics = <AnalyticsMetric>[
      _metric('committed_orders', 'Committed orders', orders.length, unit: AnalyticsUnit.count, explanation: 'All selected committed Orders, including cancellation states. Persisted current Holds are unconfirmed drafts outside Orders, Tokens and revenue.'),
      _metric('revised_orders', 'Orders revised', revisedIds.length, unit: AnalyticsUnit.count, explanation: 'Distinct selected order IDs with append-only revision evidence.'),
      _metric('revision_events', 'Revision events', revisions.length, unit: AnalyticsUnit.count, explanation: 'Revision events, separate from distinct revised order count.'),
      _metric('revision_delta', 'Revision price delta', _integers(revisions, 'money_delta_paisa'), explanation: 'Sum append-only revision money deltas for selected order cohort; event dates may differ.'),
      _metric('cancelled_orders', 'Cancelled/refunded orders', cancelled.length, unit: AnalyticsUnit.count, explanation: 'Distinct selected orders with CANCEL event or current cancelled/voided/refunded state.'),
      _rate('cancel_rate', 'Cancel/refund rate', cancelled.length, orders.length, 'Distinct cancelled/refunded orders / all committed selected orders; refunded states included.'),
      _metric('refunds', 'Explicit refunds', -_sum(refunds, 'amount_tendered'), explanation: 'Negative payment records only; cancellation does not itself disburse cash.'),
      _metric('refund_exposure', 'Retained funds above current payable', exposure, explanation: 'Per order max(0, net collected - current payable), using zero payable for cancelled/refunded orders. This is exposure, not a completed refund.'),
      _duration('prep_median', 'Median preparation time', _percentile(prepTimes, .5), prepTimes.length, orders.length),
      _duration('prep_p90', '90th percentile preparation', _percentile(prepTimes, .9), prepTimes.length, orders.length),
      _coverage('prep_coverage', 'Preparation milestone coverage', prepTimes.length, orders.length, 'Orders with verified confirmed-to-ready lifecycle milestones. Missing milestones are excluded rather than assumed zero.'),
      _metric('rework_cycles', 'Kitchen rework cycles', totalReworkCycles, unit: AnalyticsUnit.count, explanation: 'Observed kitchen return/re-prepare transitions after initial ready milestone.'),
      ..._HoldAging(e).metrics,
    ];
    for (final key in ['payment_status', 'token_status']) {
      for (final group in _group(orders, key).entries) {
        metrics.add(_metric('${key}_${group.key}', '${_label(key)}: ${group.key}', group.value.length, unit: AnalyticsUnit.count, explanation: 'Committed selected order count by current stored state.'));
      }
    }
    return _section(AnalyticsFamily.orders, 'Order operations', metrics, [

      ..._HoldAging(e).rows,
      ..._OrderWorkload(this).build(), ..._WeekdayOrderPeaks(this).build(),
      ...orders.map((o) {
        final prep = orderPrepData[o['id'] as int] ?? const {};
        return _row('orders', o, {
          'order_id': o['id'],
          'business_day_id': o['business_day_id'],
          'cashier_id': o['cashier_id'],
          'shift_id': o['shift_id'],
          'token': o['token_number'],
          'dining_type': o['dining_type'],
          'payment_status': o['payment_status'],
          'token_status': o['token_status'],
          'recorded_value_paisa': _money(o, 'grand_total'),
          'collection_due_paisa': o['payment_status'] == 'COLLECTION_DUE' ? o['collection_due_paisa'] : 0,
          'prep_duration_minutes': prep['prep_duration_minutes'],
          'prep_quality': prep['prep_quality'],
          'rework_cycles': prep['rework_cycles'],
          'created_at': o['created_at'],
          'assigned_business_date': _karachi(daysById[o['business_day_id']]?['opened_at']) == null ? null : _sqlDate(_karachi(daysById[o['business_day_id']]!['opened_at'])!),
        });
      }),
      ...revisions.map((r) => _row('order_revisions', r, {'order_id': r['order_id'], 'revision': r['revision_no'], 'action': r['action'], 'reason': _safeText(r['reason']), 'cashier_id': r['cashier_id'], 'delta_paisa': r['money_delta_paisa'], 'created_at': r['created_at_utc']})),
    ], ['order_id', 'business_day_id', 'assigned_business_date', 'token', 'cashier_id', 'shift_id', 'dining_type', 'payment_status', 'token_status', 'recorded_value_paisa', 'collection_due_paisa', 'prep_duration_minutes', 'prep_quality', 'rework_cycles', 'action', 'revision', 'delta_paisa', 'reason', 'created_at', 'hold_id', 'event_type', 'previous_hold_id', 'age_minutes'], [_orderBasis, _WeekdayOrderPeaks.note, 'Workload counts every confirmed Order once, including cancellations and refunds. Holds and revisions add no Orders. Daily and hourly rows are independent projections; never add them together. Rankings use count and eligible value independently; rank 1 includes every tie, shown chronologically. Hourly buckets are actual Asia/Karachi creation clock hours across the selected cohort, not a promise of trading in every hour. Observed cohort zeros differ from unavailable source/time evidence. Calendar dates without Orders or observed Business Days are not invented. Daily workload stays daily regardless of Sales grouping.', 'Order and revision source rows are separate kinds. Their counts/amounts must not be added together.', ..._HoldAging(e).notes]);

  }

  AnalyticsSection _delivery() {
    final deliveredOrders = valid.where((o) => o['dining_type'] == 'DELIVERY').toList();
    final attempts = e.get('attempts');
    final delivered = attempts.where((a) => a['status'] == 'DELIVERED').toList();
    final returned = attempts.where((a) => a['status'] == 'RETURNED').toList();
    final attemptsByOrder = <int, List<_Record>>{};
    for (final a in attempts) {
      final orderId = a['order_id'];
      if (orderId is int) {
        attemptsByOrder.putIfAbsent(orderId, () => []).add(a);
      }
    }
    final uniqueAttemptedOrders = attemptsByOrder.keys.length;
    final reattemptedOrders = attemptsByOrder.values.where((list) => list.length > 1).length;
    final totalReattempts = attempts.length - uniqueAttemptedOrders;
    final times = <double>[];
    for (final a in delivered) {
      final dispatch = _karachi(a['dispatched_at']);
      final end = _karachi(a['delivered_at']);
      final confirmed = _karachi(a['order_created_at']);
      if (dispatch != null && end != null && !end.isBefore(dispatch) && (confirmed == null || !end.isBefore(confirmed))) {
        times.add(end.difference(dispatch).inSeconds / 60);
      }
    }
    times.sort();
    int lateDeliveries = 0;
    int validDeliveredOrders = 0;
    final deliveredOrderIds = <int>{};
    for (final a in delivered) {
      final oid = a['order_id'];
      if (oid is! int || deliveredOrderIds.contains(oid)) continue;
      final end = _karachi(a['delivered_at']);
      final confirmed = _karachi(a['order_created_at']);
      final dispatch = _karachi(a['dispatched_at']);
      if (end == null || confirmed == null || dispatch == null || end.isBefore(dispatch) || end.isBefore(confirmed)) continue;
      deliveredOrderIds.add(oid);
      validDeliveredOrders++;
      final targetEta = (a['target_eta_minutes'] as num?)?.toDouble() ?? 45.0;
      final elapsed = end.difference(confirmed).inSeconds / 60.0;
      if (elapsed > targetEta) {
        lateDeliveries++;
      }
    }
    int finalDeliveryFailures = 0;
    for (final entry in attemptsByOrder.entries) {
      final oAttempts = entry.value;
      final hasDelivered = oAttempts.any((att) => att['status'] == 'DELIVERED');
      if (!hasDelivered) {
        final paymentStatus = oAttempts.first['order_payment_status'] as String? ?? '';
        final isCancelled = ['CANCELLED', 'VOIDED', 'REFUNDED'].contains(paymentStatus);
        final isExplicitFailure = oAttempts.any((att) {
          final notes = (att['notes'] as String? ?? '').toUpperCase();
          return notes.contains('CANCELLED_UNDELIVERED') || notes.contains('WASTED') || notes.contains('RESTOCKED');
        });
        if (isCancelled || isExplicitFailure) {
          finalDeliveryFailures++;
        }
      }
    }
    final trips = e.get('trips');
    final allTrips = e.get('all_trips');
    final allShifts = e.get('all_shifts');
    final shiftsById = {for (final s in allShifts) s['id']: s};
    int agingCurrentShiftPaisa = 0;
    int aging0to24hPaisa = 0;
    int aging1to3dPaisa = 0;
    int agingCriticalPaisa = 0;

    for (final t in allTrips.where((t) => t['status'] == 'RETURNED')) {
      final returnedAt = _karachi(t['returned_at']);
      final expectedPaisa = (t['cash_expected_paisa'] as num?)?.toInt() ?? 0;
      if (returnedAt == null || expectedPaisa <= 0) continue;
      final shift = shiftsById[t['shift_id']];
      if (shift != null && shift['status'] == 'OPEN') {
        agingCurrentShiftPaisa += expectedPaisa;
      } else {
        final ageHours = e.now.difference(returnedAt).inMinutes / 60.0;
        if (ageHours <= 24.0) {
          aging0to24hPaisa += expectedPaisa;
        } else if (ageHours <= 72.0) {
          aging1to3dPaisa += expectedPaisa;
        } else {
          agingCriticalPaisa += expectedPaisa;
        }
      }
    }
    final settledTripIds = allTrips.where((t) => t['status'] == 'SETTLED').map((t) => t['id']).toSet();
    final allEvents = e.get('payment_events');
    final activeCollections = allEvents.where((p) => p['kind'] == 'RIDER_COLLECTION' && !settledTripIds.contains(p['settlement_id'])).toList();
    final riderHeldCash = _integers(activeCollections, 'amount_paisa');
    final due = valid.where((o) => o['payment_status'] == 'COLLECTION_DUE').fold<int>(0, (sum, o) {
      final orderDue = (o['collection_due_paisa'] as int?) ?? 0;
      final collectedForOrder = activeCollections
          .where((p) => p['order_id'] == o['id'])
          .fold<int>(0, (s, p) => s + ((p['amount_paisa'] as int?) ?? 0));
      return sum + (orderDue > collectedForOrder ? orderDue - collectedForOrder : 0);
    });
    final receivingEvents = _receivingEvents();
    final handovers = receivingEvents.where((p) => p['kind'] == 'RIDER_HANDOVER');
    final acceptedDrawerCash = _integers(handovers, 'amount_paisa');
    final shortages = receivingEvents.where((p) => p['kind'] == 'RIDER_SHORTAGE');
    final riderShortages = _integers(shortages, 'amount_paisa');
    final metrics = <AnalyticsMetric>[
      _metric('delivery_orders', 'Delivery orders', deliveredOrders.length, unit: AnalyticsUnit.count, explanation: 'Eligible DELIVERY orders in filtered order cohort.'),
      _metric('delivery_fees', 'Recorded delivery fees', _integers(deliveredOrders, 'delivery_fee_paisa'), explanation: 'Eligible filtered delivery order fee snapshots.'),
      _metric('collection_due', 'Collection Due (customer debt)', due, explanation: 'Remaining payable less net tenders for uncollected COLLECTION_DUE eligible orders; delivery does not imply collection.'),
      _metric('all_collection_due', 'Collection Due (all outstanding)', _integers(e.get('all_due'), 'collection_due_paisa'), explanation: 'Current installation-wide COLLECTION_DUE orders across all Business Days; date/order filters do not apply.'),
      _metric('rider_held_cash', 'Rider-held cash (verified liability)', riderHeldCash, explanation: 'Confirmed customer collections held by riders prior to cashier drawer handover; distinct from drawer cash and customer debt.'),
      _metric('accepted_drawer_cash', 'Accepted rider drawer cash', acceptedDrawerCash, explanation: 'Actual physical currency accepted from rider pouch handovers into cashier drawers.'),
      _metric('rider_shortages', 'Rider settlement shortage', riderShortages, explanation: 'Recorded settlement cash shortages against expected cash.'),
      _metric('trips', 'Trips (whole selected days)', trips.length, unit: AnalyticsUnit.count, explanation: _globalBasis),
      _metric('unsettled_exposure', 'Unsettled expected COD (selected days)', _integers(trips.where((t) => ['DISPATCHED', 'RETURNED'].contains(t['status'])), 'cash_expected_paisa'), explanation: 'Expected COD in unsettled trips selected by trip Business Day, all orders. Exposure is not proof of customer collection or rider debt.'),
      _metric('all_unsettled_exposure', 'Unsettled expected COD (all outstanding)', _integers(allTrips.where((t) => ['DISPATCHED', 'RETURNED'].contains(t['status'])), 'cash_expected_paisa'), explanation: 'Current global expected COD for DISPATCHED/RETURNED trips; not verified cash collected.'),
      _metric('unique_attempted_orders', 'Unique delivery orders attempted', uniqueAttemptedOrders, unit: AnalyticsUnit.count, explanation: 'Distinct Order IDs with at least one dispatched delivery attempt.'),
      _metric('reattempted_orders', 'Reattempted orders', reattemptedOrders, unit: AnalyticsUnit.count, explanation: 'Distinct Order IDs with more than one dispatched attempt.'),
      _metric('total_reattempts', 'Total delivery reattempts', totalReattempts, unit: AnalyticsUnit.count, explanation: 'Attempts dispatched beyond the initial run (total attempts minus unique attempted orders).'),
      _rate('reattempt_rate', 'Delivery reattempt rate', reattemptedOrders, uniqueAttemptedOrders, 'Orders with >1 attempt / unique attempted orders.'),
      _metric('delivered_attempts', 'Delivered attempts', delivered.length, unit: AnalyticsUnit.count, explanation: 'Filtered order delivery-attempt rows with DELIVERED status.'),
      _metric('returned_attempts', 'Returned attempts', returned.length, unit: AnalyticsUnit.count, explanation: 'Filtered returned attempts, not final failed orders; later redelivery may succeed.'),
      _rate('returned_attempt_rate', 'Returned-attempt rate', returned.length, attempts.length, 'Returned attempt rows / dispatched attempt rows in selected filtered order cohort; not final failure rate.'),
      _duration('travel_mean', 'Mean travel time', times.isEmpty ? null : times.reduce((a, b) => a + b) / times.length, times.length, delivered.length),
      _duration('travel_median', 'Median travel time', _percentile(times, .5), times.length, delivered.length),
      _duration('travel_p90', '90th percentile travel', _percentile(times, .9), times.length, delivered.length),
      _metric('late_deliveries', 'Late delivery orders', lateDeliveries, unit: AnalyticsUnit.count, explanation: 'Delivered orders exceeding delivery area target ETA or 45-minute fallback SLA.'),
      _rate('late_delivery_rate', 'Late delivery rate', lateDeliveries, validDeliveredOrders, 'Orders exceeding area SLA target ETA (or 45m fallback) / delivered orders with valid delivery evidence.'),
      _metric('final_delivery_failures', 'Final delivery failures', finalDeliveryFailures, unit: AnalyticsUnit.count, explanation: 'Unique dispatched orders that reached terminal failed disposition; returned attempts that were redelivered are excluded.'),
      _rate('final_delivery_failure_rate', 'Final delivery failure rate', finalDeliveryFailures, uniqueAttemptedOrders, 'Unique dispatched delivery orders with final failed outcome / total unique dispatched delivery orders.'),
      _metric('cod_aging_current_shift_paisa', 'Unsettled COD: Current shift', agingCurrentShiftPaisa, explanation: 'Returned COD trips awaiting cashier shift handover.'),
      _metric('cod_aging_0_24h_paisa', 'Unsettled COD: Overdue (0-24h)', aging0to24hPaisa, explanation: 'Unsettled COD from closed shifts returned within 24 hours.'),
      _metric('cod_aging_1_3d_paisa', 'Unsettled COD: Aged (1-3 days)', aging1to3dPaisa, explanation: 'Unsettled COD carried across closed business days (1 to 3 days).'),
      _metric('cod_aging_critical_paisa', 'Unsettled COD: Critical (>3 days)', agingCriticalPaisa, explanation: 'Unsettled COD aged beyond 3 days requiring manager investigation.'),
    ];
    String reasonFor(Object? raw) {
      if (raw is String && raw.trim().isNotEmpty) return _safeText(raw.trim());
      return 'Absent historical reason evidence';
    }
    final returnReasons = <String, int>{};
    for (final a in returned) {
      final reason = reasonFor(a['notes']);
      returnReasons[reason] = (returnReasons[reason] ?? 0) + 1;
    }
    for (final entry in returnReasons.entries) {
      metrics.add(_metric('return_reason_${entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_]'), '_')}', 'Return reason: ${entry.key}', entry.value, unit: AnalyticsUnit.count, explanation: 'Returned attempts attributed to recorded reason. Legacy attempts without notes disclose absent historical evidence.'));
    }
    for (final group in _group(deliveredOrders, 'delivery_area_name_snapshot').entries) {
      metrics.add(_metric('area_${group.key}', '${group.key} delivery orders', group.value.length, unit: AnalyticsUnit.count, explanation: 'Eligible filtered order count by transaction-time area snapshot.'));
    }
    return _section(AnalyticsFamily.delivery, 'Delivery and riders', metrics, [
      ..._receivingEventRows(_receivingEvents().where((p) => p['settlement_id'] != null)),
      ...deliveredOrders.map((o) => _row('orders', o, {'order_id': o['id'], 'area': o['delivery_area_name_snapshot'] ?? 'Unknown area', 'fee_paisa': o['delivery_fee_paisa'], 'payment_status': o['payment_status']})),
      ...trips.map((t) => _row('rider_trips', t, {'trip_id': t['id'], 'rider_id': t['rider_staff_id'], 'shift_id': t['shift_id'], 'status': t['status'], 'selected_order_load': attempts.where((a) => a['trip_id'] == t['id']).length, 'expected_paisa': t['cash_expected_paisa'], 'counted_paisa': t['cash_collected_paisa'], 'dispatched_at': t['dispatched_at'], 'settled_at': t['settled_at_utc']})),
      ...attempts.map((a) {
        final orderAttempts = attemptsByOrder[a['order_id']] ?? const <_Record>[];
        final isReattempt = orderAttempts.isNotEmpty && a['id'] != orderAttempts.first['id'];
        final reason = a['status'] == 'RETURNED' ? reasonFor(a['notes']) : null;
        final dispatch = _karachi(a['dispatched_at']);
        final end = _karachi(a['delivered_at']);
        final confirmed = _karachi(a['order_created_at']);
        double? travelMinutes;
        String deliveryQuality;
        if (a['status'] == 'DELIVERED') {
          if (dispatch == null || end == null) {
            deliveryQuality = 'Missing milestone';
          } else if (end.isBefore(dispatch) || (confirmed != null && end.isBefore(confirmed))) {
            deliveryQuality = 'Invalid sequence';
          } else {
            travelMinutes = end.difference(dispatch).inSeconds / 60.0;
            deliveryQuality = 'Valid';
          }
        } else {
          deliveryQuality = 'Attempt not delivered';
        }
        return _row('rider_trip_orders', a, {
          'kind': 'Delivery attempt',
          'order_id': a['order_id'],
          'trip_id': a['trip_id'],
          'rider_id': a['rider_staff_id'],
          'area': a['delivery_area_name_snapshot'] ?? 'Unknown area',
          'status': a['status'],
          'is_reattempt': isReattempt ? 'Yes' : 'No',
          'return_reason': reason ?? 'N/A',
          'travel_minutes': travelMinutes,
          'delivery_quality': deliveryQuality,
          'dispatched_at': a['dispatched_at'],
          'delivered_at': a['delivered_at'],
          'returned_at': a['returned_at'],
        });
      }),
    ], ['kind', 'order_id', 'trip_id', 'rider_id', 'shift_id', 'selected_order_load', 'area', 'fee_paisa', 'payment_status', 'status', 'is_reattempt', 'return_reason', 'travel_minutes', 'delivery_quality', 'expected_paisa', 'counted_paisa', 'dispatched_at', 'delivered_at', 'returned_at', 'settled_at'], ['Order/attempt rows and selected-order load use order filters; trip rows and trip exposure use whole selected Business Days. All-outstanding measures explicitly ignore date/order filters.', 'Settlement event rows use receiving Shift/Business Day or actual calendar time, independently of the originating Order cohort. Counted handover is one linked custody transfer; COD settlement value is not verified customer collection. Legacy settled trips without events have unavailable receiving Shift, actors, confirmed collections and immutable recording time. Do not sum settlement attribution, digital receipt, rider-held collections and counted pouch rows.', 'Returned attempts are delivery run outcomes, not final order failures. Reattempts represent subsequent dispatch runs for the same order. Legacy returned attempts without recorded notes disclose absent historical reason evidence rather than inferring reasons. Delivered status is not proof of payment collection.', 'Confirmed customer collections held by riders are distinct from customer debt and cashier drawer cash. Expected pouch cash is exposure, not verified debt until independently confirmed.', 'Travel excludes invalid/missing timestamps and reports coverage. Percentiles interpolate sorted valid minutes. No final failure/reattempt or unrecorded failure-reason inference.']);
  }

  AnalyticsSection _customers() {
    final groups = <String, List<_Record>>{};
    var knownOrders = 0;
    for (final order in valid) {
      final identity = _phone(order['customer_phone']);
      if (identity == null) continue;
      knownOrders++;
      groups.putIfAbsent(identity, () => []).add(order);
    }
    final repeat = groups.values.where((list) => list.length >= 2).length;
    final knownValue = groups.values.fold<int>(0, (sum, list) => sum + _sum(list, 'grand_total'));
    final lifetimeFirstOrders = <String, _Record>{};
    for (final order in e.get('first_purchases')) {
      final phone = _phone(order['customer_phone']);
      if (phone != null) {
        final existing = lifetimeFirstOrders[phone];
        if (existing == null) {
          lifetimeFirstOrders[phone] = order;
        } else {
          final existingTime = _karachi(existing['created_at']);
          final thisTime = _karachi(order['created_at']);
          if (thisTime != null && (existingTime == null || thisTime.isBefore(existingTime))) {
            lifetimeFirstOrders[phone] = order;
          }
        }
      }
    }
    var firstTimeCount = 0;
    var returningCount = 0;
    final rows = <AnalyticsRow>[];
    for (final entry in groups.entries) {
      final customer = 'Customer •••${entry.key.substring(entry.key.length - 4)}';
      final value = _sum(entry.value, 'grand_total');
      final firstLifetime = lifetimeFirstOrders[entry.key];
      final firstLifetimeTime = _karachi(firstLifetime?['created_at']);
      final earliestInCohort = entry.value
          .map((o) => _karachi(o['created_at']))
          .whereType<DateTime>()
          .fold<DateTime?>(null, (earliest, t) => earliest == null || t.isBefore(earliest) ? t : earliest);
      final String classification;
      if (firstLifetimeTime != null && earliestInCohort != null) {
        if (firstLifetimeTime.isBefore(earliestInCohort)) {
          classification = 'Returning';
          returningCount++;
        } else {
          classification = 'First-time';
          firstTimeCount++;
        }
      } else {
        classification = 'Unavailable';
      }
      final firstOrderAtSource = firstLifetime != null ? firstLifetime['created_at'] : null;
      final firstOrderAtFormatted = firstOrderAtSource != null ? analyticsTimestamp(firstOrderAtSource) : 'Unavailable';

      rows.add(AnalyticsRow(id: 'customer-${entry.value.first['id']}', sourceType: 'orders',
        sourceId: entry.value.map((order) => order['id']).join(','), cells: {
          'kind': 'Customer aggregate', 'customer': customer,
          'orders_in_range': entry.value.length,
          'recorded_value_paisa': value, 'average_ticket_paisa': value / entry.value.length,
          'area': entry.value.first['delivery_area_name_snapshot'],
          'history_classification': classification,
          'first_order_at': firstOrderAtFormatted,
          if (firstOrderAtSource != null) 'first_order_at_source': firstOrderAtSource,
        }));
      rows.addAll(entry.value.map((order) => _row('orders', order, {
        'kind': 'Order history', 'customer': customer,
        'order_id': order['id'],
        'orders_in_range': entry.value.length, 'recorded_value_paisa': _money(order, 'grand_total'),
        'area': order['delivery_area_name_snapshot'],
        'history_classification': classification,
        'first_order_at': firstOrderAtSource,
        'created_at': order['created_at'],
      })));
    }
    return _section(AnalyticsFamily.customers, 'Customers', [
      _metric('known_customers', 'Known phone identities', groups.length, unit: AnalyticsUnit.count, explanation: 'Distinct normalized known phone proxies in eligible filtered orders; not guaranteed distinct people.'),
      _metric('first_time_customers', 'First-time customers', firstTimeCount, unit: AnalyticsUnit.count, explanation: 'Known phone identities whose very first eligible purchase across available history occurred within the selected range.'),
      _metric('returning_customers', 'Returning customers', returningCount, unit: AnalyticsUnit.count, explanation: 'Known phone identities who purchased in this period and had an earlier eligible purchase prior to this range.'),
      _metric('known_orders', 'Orders with known phone', knownOrders, unit: AnalyticsUnit.count, explanation: 'Eligible filtered orders with usable normalized phone identity.'),
      _average('known_customer_average_ticket', 'Known-customer average ticket', knownValue, knownOrders,
        AnalyticsUnit.paisa, 'Recorded eligible known-phone order value / eligible known-phone order count. Guests and cancelled/voided/refunded orders excluded; includes Collection Due. Denominator shown; this is order-weighted, not an average of customer means.'),
      _metric('guest_orders', 'Guest/unknown orders', valid.length - knownOrders, unit: AnalyticsUnit.count, explanation: 'Eligible orders without usable known phone; excluded from repeat and history classification.'),
      _rate('identity_coverage', 'Known identity coverage', knownOrders, valid.length, 'Known phone orders / eligible filtered orders.'),
      _rate('repeat_rate', 'Repeat-customer rate', repeat, groups.length, 'Known normalized phone proxies with at least two eligible selected orders / proxies with at least one. Guests excluded.'),
      _metric('single_order_customers', 'Single-order phone identities', groups.length - repeat, unit: AnalyticsUnit.count, explanation: 'One eligible order within selected range; distinct from first-time/returning lifetime classification.'),
    ], rows, ['kind', 'customer', 'order_id', 'orders_in_range', 'recorded_value_paisa', 'average_ticket_paisa', 'area', 'history_classification', 'first_order_at', 'created_at'], [
      _orderBasis,
      'Customer classification distinguishes first-time customers (whose first eligible purchase occurred in this selected window) from returning customers (who had an eligible purchase prior to this window across all available history). Earlier installation boundaries limit historical depth; guest orders without phone numbers cannot be classified.',
      'Phone normalization removes separators and unifies +92/0092/92 mobile prefixes with local 0. Shared numbers and masked suffix collisions are possible. Raw phones, names and addresses are excluded.',
      'Customer aggregate rows show each known identity’s eligible recorded value / its eligible order count, with all contributing order source IDs. Order history rows are a separate view; do not sum these different row kinds together. No known orders makes average ticket Not applicable.',
    ]);
  }

  AnalyticsSection _menu() {
    final items = soldItems;
    final validAllocations = e.get('allocations').where((a) => validIds.contains(a['order_id'])).toList();
    final allocatedOrderIds = validAllocations.map((a) => a['order_id'] as int).toSet();
    final allocatedCount = valid.where((o) => allocatedOrderIds.contains(o['id'])).length;
    final legacyOrders = valid.where((o) => !allocatedOrderIds.contains(o['id'])).toList();
    final legacyDiscountsPaisa = legacyOrders.fold<int>(0, (sum, o) => sum + _money(o, 'discount_amount'));

    // Index parent allocations (ITEM and DEAL_PARENT) by catalog key
    final allocationsByCatalogKey = <String, List<_Record>>{};
    for (final alloc in validAllocations) {
      if (alloc['line_kind'] == 'DEAL_COMPONENT') continue;
      final type = alloc['deal_id'] != null ? 'deal' : 'item';
      final id = alloc['deal_id'] ?? alloc['menu_item_id'];
      final key = '$type:${id ?? 'archived:${alloc['item_name_snapshot']}'}';
      allocationsByCatalogKey.putIfAbsent(key, () => []).add(alloc);
    }

    final rows = <AnalyticsRow>[];
    final sold = <String>{};
    final groups = <String, List<_Record>>{};
    for (final item in items) {
      final type = item['deal_id'] != null ? 'deal' : 'item';
      final key = '$type:${item['deal_id'] ?? item['menu_item_id'] ?? 'archived:${item['name']}'}';
      sold.add(key);
      groups.putIfAbsent(key, () => []).add(item);
    }

    final ranked = groups.entries.toList()..sort((a, b) {
      final quantity = _integers(b.value, 'quantity').compareTo(_integers(a.value, 'quantity'));
      return quantity != 0 ? quantity : a.key.compareTo(b.key);
    });

    var rank = 0;
    int? previousQuantity;
    for (var index = 0; index < ranked.length; index++) {
      final entry = ranked[index];
      final first = entry.value.first;
      final quantity = _integers(entry.value, 'quantity');
      if (quantity != previousQuantity) rank = index + 1;
      previousQuantity = quantity;

      final allocatedRows = allocationsByCatalogKey[entry.key] ?? const [];
      final lineGross = _sum(entry.value, 'total_price');
      final lineAllocatedDiscount = allocatedRows.isNotEmpty
          ? _integers(allocatedRows, 'allocated_discount_paisa')
          : 0;

      final unallocatedGross = entry.value
          .where((i) => !allocatedOrderIds.contains(i['order_id']))
          .fold<int>(0, (s, i) => s + _money(i, 'total_price'));

      final netSalesPaisa = allocatedRows.isNotEmpty
          ? (_integers(allocatedRows, 'net_sales_paisa') + unallocatedGross)
          : lineGross;

      final taxCarveOutPaisa = allocatedRows.isNotEmpty
          ? _integers(allocatedRows, 'tax_carve_out_paisa')
          : 0;

      final hasBom = allocatedRows.any((a) => a['bom_recipe_cost_paisa'] != null);
      final bomCostPaisa = hasBom ? _integers(allocatedRows, 'bom_recipe_cost_paisa') : null;
      final marginPaisa = (hasBom && bomCostPaisa != null)
          ? (_integers(allocatedRows, 'net_sales_paisa') - bomCostPaisa)
          : null;
      final marginRate = (marginPaisa != null && netSalesPaisa > 0)
          ? (marginPaisa / netSalesPaisa * 100)
          : null;

      rows.add(AnalyticsRow(
        id: 'menu-${entry.key}',
        sourceType: 'order_items',
        sourceId: entry.value.map((i) => i['id']).join(','),
        cells: {
          'kind': 'Item/deal aggregate',
          'catalog_kind': first['deal_id'] != null ? 'deal' : 'item',
          'catalog_id': first['deal_id'] ?? first['menu_item_id'],
          'deal_id': first['deal_id'],
          'name': entry.value.map((i) => _safeText(i['name'])).toSet().join(' / '),
          'quantity': quantity,
          'order_count': entry.value.map((i) => i['order_id']).toSet().length,
          'line_value_paisa': lineGross,
          'allocated_discount_paisa': lineAllocatedDiscount,
          'net_sales_paisa': netSalesPaisa,
          'tax_carve_out_paisa': taxCarveOutPaisa,
          'bom_recipe_cost_paisa': bomCostPaisa,
          'margin_paisa': marginPaisa,
          'margin_rate': marginRate,
          'popularity_rank': rank,
          'modifiers': entry.value.map((i) => _snapshotNames(i['modifiers_json'])).where((name) => name.isNotEmpty).toSet().join(' / '),
          'choices': entry.value.map((i) => _snapshotNames(i['deal_choices_json'])).where((name) => name.isNotEmpty).toSet().join(' / '),
        },
      ));
    }

    // Deal component expansion rows for deep menu engineering
    final componentAllocations = validAllocations.where((a) => a['line_kind'] == 'DEAL_COMPONENT').toList();
    final componentGroups = <String, List<_Record>>{};
    for (final comp in componentAllocations) {
      final key = '${comp['deal_id']}:${comp['component_menu_item_id'] ?? comp['item_name_snapshot']}';
      componentGroups.putIfAbsent(key, () => []).add(comp);
    }
    for (final compEntry in componentGroups.entries) {
      final first = compEntry.value.first;
      final compGross = _integers(compEntry.value, 'gross_sales_paisa');
      final compDiscount = _integers(compEntry.value, 'allocated_discount_paisa');
      final compNet = _integers(compEntry.value, 'net_sales_paisa');
      final compTax = _integers(compEntry.value, 'tax_carve_out_paisa');
      final hasBom = compEntry.value.any((a) => a['bom_recipe_cost_paisa'] != null);
      final compBom = hasBom ? _integers(compEntry.value, 'bom_recipe_cost_paisa') : null;
      final compMargin = (hasBom && compBom != null) ? (compNet - compBom) : null;
      final compMarginRate = (compMargin != null && compNet > 0) ? (compMargin / compNet * 100) : null;

      rows.add(AnalyticsRow(
        id: 'deal-comp-${compEntry.key}',
        sourceType: 'order_item_allocations',
        sourceId: compEntry.value.map((a) => a['id']).join(','),
        cells: {
          'kind': 'Deal component breakdown',
          'catalog_kind': 'component',
          'catalog_id': first['component_menu_item_id'],
          'deal_id': first['deal_id'],
          'name': _safeText(first['item_name_snapshot']),
          'quantity': _integers(compEntry.value, 'quantity'),
          'order_count': compEntry.value.map((a) => a['order_id']).toSet().length,
          'line_value_paisa': compGross,
          'allocated_discount_paisa': compDiscount,
          'net_sales_paisa': compNet,
          'tax_carve_out_paisa': compTax,
          'bom_recipe_cost_paisa': compBom,
          'margin_paisa': compMargin,
          'margin_rate': compMarginRate,
          'status': 'Expanded deal component',
        },
      ));
    }

    // Explicit Legacy Unallocated Order Discounts row (ADR-0021 Section 7)
    if (legacyDiscountsPaisa > 0 || legacyOrders.isNotEmpty) {
      rows.add(AnalyticsRow(
        id: 'menu-legacy-unallocated-discounts',
        sourceType: 'orders',
        sourceId: legacyOrders.where((o) => _money(o, 'discount_amount') > 0).map((o) => o['id']).join(','),
        cells: {
          'kind': 'Legacy unallocated summary',
          'catalog_kind': 'legacy',
          'catalog_id': null,
          'name': 'Legacy Unallocated Order Discounts',
          'quantity': 0,
          'order_count': legacyOrders.where((o) => _money(o, 'discount_amount') > 0).length,
          'line_value_paisa': 0,
          'allocated_discount_paisa': legacyDiscountsPaisa,
          'net_sales_paisa': -legacyDiscountsPaisa,
          'tax_carve_out_paisa': 0,
          'bom_recipe_cost_paisa': 0,
          'margin_paisa': -legacyDiscountsPaisa,
          'status': 'Legacy orders without verified line allocations',
        },
      ));
    }

    var zeroSellers = 0;
    for (final type in ['catalog', 'deals']) {
      for (final item in e.get(type)) {
        if (item['is_active'] != 1 || sold.contains('${type == 'deals' ? 'deal' : 'item'}:${item['id']}')) continue;
        zeroSellers++;
        rows.add(_row(
          type == 'deals' ? 'deals' : 'menu_items',
          item,
          {
            'kind': 'Current active zero seller',
            'catalog_kind': type == 'deals' ? 'deal' : 'item',
            'catalog_id': item['id'],
            'name': _safeText(item['name']),
            'quantity': 0,
            'order_count': 0,
            'line_value_paisa': 0,
            'allocated_discount_paisa': 0,
            'net_sales_paisa': 0,
            'tax_carve_out_paisa': 0,
            'bom_recipe_cost_paisa': 0,
            'margin_paisa': 0,
            'status': 'Zero recorded sales in selected cohort',
          },
        ));
      }
    }

    final discounted = valid.where((o) => _money(o, 'discount_amount') > 0).length;
    final parentAllocations = validAllocations.where((a) => a['line_kind'] != 'DEAL_COMPONENT').toList();
    final totalAllocatedNetSales = _integers(parentAllocations, 'net_sales_paisa');
    final totalAllocatedBomCost = parentAllocations.any((a) => a['bom_recipe_cost_paisa'] != null)
        ? _integers(parentAllocations, 'bom_recipe_cost_paisa')
        : 0;
    final totalAllocatedMargin = totalAllocatedNetSales - totalAllocatedBomCost;

    return _section(
      AnalyticsFamily.menu,
      'Menu and deals',
      [
        _metric('quantity', 'Recorded sold quantity', _integers(items, 'quantity'), unit: AnalyticsUnit.count, explanation: 'Sum current valid order line quantity, including deal counts; deal components are not separate sold lines.'),
        _metric('line_value', 'Recorded line value', _sum(items, 'total_price'), explanation: 'Stored eligible line totals before order-level discount/tax/fee allocation; not item net revenue.'),
        _coverage('allocation_coverage', 'Allocation coverage', allocatedCount, valid.length, 'Orders with verified line allocations / Total eligible orders in selected period.'),
        _metric('zero_sellers', 'Active zero sellers', zeroSellers, unit: AnalyticsUnit.count, explanation: 'Current active menu/deal entries with no matching eligible line in filtered range; catalog history incomplete.'),
        _rate('discount_use', 'Discount utilization', discounted, valid.length, 'Eligible selected orders with a positive stored discount / eligible orders.'),
        _average('quantity_per_order', 'Mean line quantity per order', _integers(items, 'quantity'), valid.length, AnalyticsUnit.decimal, 'Recorded eligible line quantity / eligible order count.'),
        allocatedCount > 0
            ? _metric('item_net_sales', 'Allocated item net sales', totalAllocatedNetSales, explanation: 'Net sales from orders with verified line allocations after proportional discount deduction.')
            : _missing('item_net_sales', 'Allocated item net sales', 'Order discount/tax/delivery allocation is not persisted; stored line value must not be mislabeled net sales.'),
        allocatedCount > 0
            ? _metric('item_margin', 'Historical item margin', totalAllocatedMargin, explanation: 'Allocated line net sales minus recipe BOM food cost at event-time ingredient rates.')
            : _missing('item_margin', 'Historical item margin', 'BOM quantity snapshots have no event-time ingredient cost layers.'),
      ],
      rows,
      [
        'kind',
        'catalog_kind',
        'catalog_id',
        'deal_id',
        'name',
        'quantity',
        'order_count',
        'line_value_paisa',
        'allocated_discount_paisa',
        'net_sales_paisa',
        'tax_carve_out_paisa',
        'bom_recipe_cost_paisa',
        'margin_paisa',
        'margin_rate',
        'popularity_rank',
        'modifiers',
        'choices',
        'status',
      ],
      [
        _orderBasis,
        'Item and deal net sales, allocated discounts, tax carve-outs, and BOM recipe costs are calculated in signed 64-bit Integer Paisa adhering to ADR-0021.',
        'Proportional discount allocation uses integer floor division; the zero-leak rounding residual is distributed by adding 1 paisa to lines with the highest gross subtotal.',
        'Deals are expanded across constituent components weighted by standalone regular catalog prices to determine component contribution margins.',
        'Orders created prior to line allocation capture disclose exact coverage ratio; legacy order discounts are isolated in the "Legacy Unallocated Order Discounts" row so totals reconcile to Order subtotal and grand total without retroactive estimation.',
        'Ascending quantity identifies slow sellers; zero sellers refer to current active catalog.',
      ],
    );
  }

  AnalyticsSection _inventory() {
    final ingredients = e.get('ingredients');
    final low = ingredients.where((i) => (i['current_stock'] as num) <= (i['low_stock_threshold'] as num)).length;
    final negative = ingredients.where((i) => (i['current_stock'] as num) < 0).length;
    final balances = {for (final b in e.get('balances')) b['ingredient_id']: b};

    final allMovements = e.rows['all_inventory_movements'] ?? e.get('inventory');
    final allPurchases = e.rows['all_mandi_purchases'] ?? e.get('purchases');
    final allCreditTxns = e.rows['all_vendor_transactions'] ?? e.get('vendor_events');
    final allWaste = e.rows['all_waste'] ?? e.get('waste');
    final allCostEvents = e.rows['all_cost_events'] ?? [];
    final allPhysicalCounts = e.rows['all_physical_counts'] ?? e.get('physical_counts');

    final intervalStart = _sqlTime(_karachi(analyticsWallClock(e.query.startDate).toIso8601String())!);
    final cutoffTime = e.query.live
        ? _sqlTime(_karachi(e.now.toIso8601String())!)
        : _sqlTime(_karachi(analyticsWallClock(e.query.endDateExclusive).toIso8601String())!);

    final bridgeRows = <AnalyticsRow>[];
    int reconciledIngredientsCount = 0;
    int openingEvidenceCount = 0;
    int missingOpeningCount = 0;
    int totalEndingValuationPaisa = 0;
    int coveredIngredientsCount = 0;
    int negativeBalanceCount = 0;

    for (final ing in ingredients) {
      final ingId = ing['id'] as int;
      final name = _safeText(ing['name']);
      final unit = ing['storage_unit'] as String? ?? 'unit';
      final currentStock = (ing['current_stock'] as num).toDouble();
      final threshold = (ing['low_stock_threshold'] as num).toDouble();
      final unitCostRate = ing['cost_per_recipe_unit'];

      // Movements before interval start
      final preMovements = allMovements.where((m) => m['ingredient_id'] == ingId && (m['recorded_at'] as String).compareTo(intervalStart) < 0).toList();
      double openingQty = 0.0;
      bool hasOpeningEvidence = false;
      String openingEvidenceAt = '';

      if (preMovements.isNotEmpty) {
        openingQty = (preMovements.last['balance_after'] as num).toDouble();
        hasOpeningEvidence = true;
        openingEvidenceAt = preMovements.last['recorded_at'] as String;
      } else {
        final ingMovements = allMovements.where((m) => m['ingredient_id'] == ingId).toList();
        if (ingMovements.isNotEmpty) {
          final firstMv = ingMovements.first;
          final firstMvTime = firstMv['recorded_at'] as String;
          if (firstMvTime.compareTo(intervalStart) >= 0 && firstMvTime.compareTo(cutoffTime) <= 0) {
            openingQty = (firstMv['balance_after'] as num).toDouble() - (firstMv['quantity_delta'] as num).toDouble();
            hasOpeningEvidence = firstMvTime.compareTo(intervalStart) == 0;
            openingEvidenceAt = 'First movement at $firstMvTime';
          } else {
            openingQty = 0.0;
            hasOpeningEvidence = false;
            openingEvidenceAt = 'Earliest movement after cutoff ($firstMvTime)';
          }
        } else {
          openingQty = currentStock;
          hasOpeningEvidence = false;
          openingEvidenceAt = 'Missing opening balance evidence; no movements recorded';
        }
      }

      if (hasOpeningEvidence) {
        openingEvidenceCount++;
      } else {
        missingOpeningCount++;
      }

      // Receipts in interval: Mandi procurements + supplier credit deliveries
      final mandiIn = allPurchases.where((p) => p['raw_ingredient_id'] == ingId &&
          (p['created_at'] as String).compareTo(intervalStart) >= 0 &&
          (p['created_at'] as String).compareTo(cutoffTime) <= 0).fold<double>(0.0, (sum, p) => sum + ((p['converted_quantity'] ?? p['quantity']) as num).toDouble());

      final vendorIn = allCreditTxns.where((t) => t['raw_ingredient_id'] == ingId && t['type'] == 'PURCHASE_CREDIT' &&
          (t['created_at'] as String).compareTo(intervalStart) >= 0 &&
          (t['created_at'] as String).compareTo(cutoffTime) <= 0).fold<double>(0.0, (sum, t) => sum + ((t['quantity'] ?? 0) as num).toDouble());

      final receiptsQty = mandiIn + vendorIn;

      // Waste in interval: kitchen wastage + order cooked waste
      final kitchenWasteIn = allWaste.where((w) => w['raw_ingredient_id'] == ingId &&
          (w['created_at'] as String).compareTo(intervalStart) >= 0 &&
          (w['created_at'] as String).compareTo(cutoffTime) <= 0).fold<double>(0.0, (sum, w) => sum + ((w['quantity'] ?? 0) as num).toDouble());

      final orderWasteIn = allCostEvents.where((c) => c['ingredient_id'] == ingId && c['kind'] == 'COOKED_WASTE' &&
          (c['recorded_at'] as String).compareTo(intervalStart) >= 0 &&
          (c['recorded_at'] as String).compareTo(cutoffTime) <= 0).fold<double>(0.0, (sum, c) => sum + ((c['quantity'] ?? 0) as num).toDouble());

      final wasteQty = kitchenWasteIn + orderWasteIn;

      // Consumption in interval: order cost events CONSUME or sold items BOM
      double consumptionQty = 0.0;
      final costEventsIn = allCostEvents.where((c) => c['ingredient_id'] == ingId && c['kind'] == 'CONSUME' &&
          (c['recorded_at'] as String).compareTo(intervalStart) >= 0 &&
          (c['recorded_at'] as String).compareTo(cutoffTime) <= 0).toList();
      if (costEventsIn.isNotEmpty) {
        consumptionQty = costEventsIn.fold<double>(0.0, (sum, c) => sum + ((c['quantity'] ?? 0) as num).toDouble());
      } else {
        for (final item in soldItems) {
          final bom = _jsonMap(item['bom_json']);
          if (bom != null && bom.containsKey('$ingId') && bom['$ingId'] is num) {
            consumptionQty += (bom['$ingId'] as num).toDouble();
          }
        }
      }

      // Returns in interval: order cost events RETURN
      final returnsQty = allCostEvents.where((c) => c['ingredient_id'] == ingId && c['kind'] == 'RETURN' &&
          (c['recorded_at'] as String).compareTo(intervalStart) >= 0 &&
          (c['recorded_at'] as String).compareTo(cutoffTime) <= 0).fold<double>(0.0, (sum, c) => sum + ((c['quantity'] ?? 0) as num).toDouble());

      // Physical count variances in interval
      final countAdjustments = allPhysicalCounts.where((c) => c['ingredient_id'] == ingId &&
          (c['created_at'] as String).compareTo(intervalStart) >= 0 &&
          (c['created_at'] as String).compareTo(cutoffTime) <= 0).fold<double>(0.0, (sum, c) => sum + ((c['variance'] ?? 0) as num).toDouble());

      // Recorded movement delta in inventory_movements for this interval
      final inMovements = allMovements.where((m) => m['ingredient_id'] == ingId &&
          (m['recorded_at'] as String).compareTo(intervalStart) >= 0 &&
          (m['recorded_at'] as String).compareTo(cutoffTime) <= 0).toList();
      final totalMovementDelta = inMovements.fold<double>(0.0, (sum, m) => sum + ((m['quantity_delta'] ?? 0) as num).toDouble());

      final movementsUpToCutoff = allMovements.where((m) => m['ingredient_id'] == ingId &&
          (m['recorded_at'] as String).compareTo(cutoffTime) <= 0).toList();
      final endingQty = movementsUpToCutoff.isNotEmpty
          ? (movementsUpToCutoff.last['balance_after'] as num).toDouble()
          : (openingQty + totalMovementDelta);

      final domainDelta = receiptsQty - consumptionQty - wasteQty + returnsQty + countAdjustments;
      final unexplainedVariance = inMovements.isNotEmpty ? (totalMovementDelta - domainDelta) : 0.0;
      final adjustmentsQty = countAdjustments;

      final calculatedEnding = openingQty + receiptsQty - consumptionQty - wasteQty + returnsQty + adjustmentsQty;
      final isReconciled = unexplainedVariance.abs() < 0.0001 && (calculatedEnding - endingQty).abs() < 0.0001;
      if (isReconciled) {
        reconciledIngredientsCount++;
      }

      // --- Moving WAC Calculation (ADR-0023 / Ticket #91) ---
      final ingPurchases = <_ProcurementReceipt>[];
      for (final p in allPurchases.where((p) => p['raw_ingredient_id'] == ingId &&
          (p['created_at'] as String).compareTo(cutoffTime) <= 0)) {
        final qty = ((p['converted_quantity'] ?? p['quantity']) as num).toDouble();
        final costPaisa = _money(p, 'total_cost');
        if (qty > 0) {
          ingPurchases.add(_ProcurementReceipt(
            timestamp: p['created_at'] as String,
            quantity: qty,
            costPaisa: costPaisa,
          ));
        }
      }
      for (final t in allCreditTxns.where((t) => t['raw_ingredient_id'] == ingId && t['type'] == 'PURCHASE_CREDIT' &&
          (t['created_at'] as String).compareTo(cutoffTime) <= 0)) {
        final qty = ((t['quantity'] ?? 0) as num).toDouble();
        final costPaisa = (t['amount_paisa'] as int?) ?? (t['amount'] != null ? ((t['amount'] as num) * 100).round() : 0);
        if (qty > 0) {
          ingPurchases.add(_ProcurementReceipt(
            timestamp: t['created_at'] as String,
            quantity: qty,
            costPaisa: costPaisa,
          ));
        }
      }
      ingPurchases.sort((a, b) => a.timestamp.compareTo(b.timestamp));

      final initialCostPaisa = (unitCostRate != null && (unitCostRate as num) > 0)
          ? PaisaEngine.rupeesToPaisa(unitCostRate as num)
          : 0;

      double runningWacPaisa = initialCostPaisa > 0 ? initialCostPaisa.toDouble() : 0.0;
      double lastKnownWacPaisa = runningWacPaisa;
      bool hasCostEvidence = initialCostPaisa > 0 || ingPurchases.isNotEmpty;

      // Chronologically advance WAC through purchases
      for (final p in ingPurchases) {
        final priorMovements = allMovements.where((m) => m['ingredient_id'] == ingId &&
            (m['recorded_at'] as String).compareTo(p.timestamp) < 0).toList();
        final stockBefore = priorMovements.isNotEmpty
            ? (priorMovements.last['balance_after'] as num).toDouble()
            : 0.0;

        final unitRate = p.costPaisa / p.quantity;
        if (stockBefore <= 0) {
          // Deficit covered at new purchase rate (ADR-0023 Section 2)
          runningWacPaisa = unitRate;
          lastKnownWacPaisa = unitRate;
        } else {
          if (runningWacPaisa > 0) {
            runningWacPaisa = ((stockBefore * runningWacPaisa) + p.costPaisa) / (stockBefore + p.quantity);
            lastKnownWacPaisa = runningWacPaisa;
          } else {
            runningWacPaisa = unitRate;
            lastKnownWacPaisa = unitRate;
          }
        }
      }

      int movingWacPaisa = runningWacPaisa.round();
      int? valuationPaisa;
      String valuationBadge;
      String costQuality;

      if (endingQty < 0) {
        valuationPaisa = 0;
        valuationBadge = 'Estimated valuation: item in temporary negative balance';
        costQuality = 'temporary_negative';
      } else if (endingQty == 0) {
        valuationPaisa = 0;
        valuationBadge = 'Zero stock balance';
        costQuality = 'verified';
      } else {
        if (hasCostEvidence && movingWacPaisa > 0) {
          valuationPaisa = (endingQty * movingWacPaisa).round();
          valuationBadge = 'Verified Moving WAC';
          costQuality = 'verified';
        } else {
          valuationPaisa = null;
          valuationBadge = 'Missing purchase cost evidence';
          costQuality = 'unknown';
        }
      }

      if (hasCostEvidence) {
        coveredIngredientsCount++;
      }
      if (endingQty < 0) {
        negativeBalanceCount++;
      }
      if (valuationPaisa != null) {
        totalEndingValuationPaisa += valuationPaisa;
      }

      bridgeRows.add(AnalyticsRow(
        id: 'stock-bridge-$ingId',
        sourceType: 'raw_ingredients',
        sourceId: '$ingId',
        cells: {
          'kind': 'Normalized stock bridge',
          'ingredient_id': ingId,
          'name': name,
          'unit': unit,
          'opening_qty': openingQty,
          'receipts_qty': receiptsQty,
          'consumption_qty': consumptionQty,
          'waste_qty': wasteQty,
          'returns_qty': returnsQty,
          'adjustments_qty': adjustmentsQty,
          'unexplained_variance': unexplainedVariance,
          'ending_qty': endingQty,
          'reconciliation_status': isReconciled ? 'Reconciled' : 'Discrepancy disclosed',
          'current_stock': currentStock,
          'threshold': threshold,
          'has_opening_evidence': hasOpeningEvidence ? 'Verified' : 'Missing opening evidence',
          'balance_evidence_at': openingEvidenceAt,
          'recorded_cost_rate': unitCostRate,
          'moving_wac_paisa': movingWacPaisa,
          'valuation_paisa': valuationPaisa,
          'valuation_policy': 'Moving Weighted Average Cost (WAC)',
          'valuation_badge': valuationBadge,
          'cost_quality': costQuality,
          'valuation_cutoff': cutoffTime,
          'status': currentStock < 0 ? 'Negative' : currentStock <= threshold ? 'Low' : 'Within threshold',
        },
      ));
    }

    final rows = <AnalyticsRow>[
      ...bridgeRows,
      ...ingredients.map((i) => _row('raw_ingredients', i, {'kind': 'Current position', 'ingredient_id': i['id'], 'name': _safeText(i['name']), 'unit': i['storage_unit'], 'current_stock': i['current_stock'], 'threshold': i['low_stock_threshold'], 'as_of_balance': balances[i['id']]?['balance_after'], 'balance_evidence_at': balances[i['id']]?['recorded_at'], 'status': (i['current_stock'] as num) < 0 ? 'Negative' : (i['current_stock'] as num) <= (i['low_stock_threshold'] as num) ? 'Low' : 'Within threshold'})),
      ...e.get('purchases').map((p) => _row('mandi_procurements', p, {
        'kind': 'Procurement receipt',
        'ingredient_id': p['raw_ingredient_id'],
        'unit': p['traditional_unit'],
        'quantity': p['converted_quantity'] ?? p['quantity'],
        'spend_paisa': _money(p, 'total_cost'),
        'recorded_at': p['created_at'],
      })),
      ...allCreditTxns.where((t) => t['raw_ingredient_id'] != null &&
          (t['created_at'] as String).compareTo(intervalStart) >= 0 &&
          (t['created_at'] as String).compareTo(cutoffTime) <= 0).map((t) => AnalyticsRow(
        id: 'credit-delivery-${t['id']}',
        sourceType: 'vendor_transactions',
        sourceId: '${t['id']}',
        cells: {
          'kind': 'Credit delivery receipt',
          'ingredient_id': t['raw_ingredient_id'],
          'unit': t['unit_snapshot'] ?? '',
          'quantity': t['quantity'],
          'spend_paisa': t['amount_paisa'] ?? (t['amount'] != null ? ((t['amount'] as num) * 100).round() : 0),
          'recorded_at': t['created_at'],
        },
      )),
      ...e.get('physical_counts').map((c) => AnalyticsRow(id: 'count-${c['count_id']}-${c['ingredient_id']}', sourceType: 'stock_count_lines', sourceId: '${c['count_id']}:${c['ingredient_id']}', cells: {
        'kind': 'Physical count', 'count_id': c['count_id'], 'ingredient_id': c['ingredient_id'], 'unit': c['unit'],
        'expected': c['expected'], 'counted': c['counted'], 'variance': c['variance'], 'estimated_cost_paisa': c['estimated_cost_paisa'], 'recorded_estimated_cost_paisa': c['recorded_estimated_cost_paisa'], 'valuation_policy': c['valuation_policy'],
        'movement_id': c['movement_id'], 'snapshot_sequence': c['snapshot_sequence'], 'status': c['status'],
        'created_by': c['created_by'], 'approved_by': c['approved_by'], 'posted_by': c['posted_by'], 'reason': _safeText(c['reason']), 'recorded_at': c['created_at']})),
      ...e.get('inventory').map((m) => _row('inventory_movements', m, {'kind': 'Movement', 'ingredient_id': m['ingredient_id'], 'quantity_delta': m['quantity_delta'], 'balance_after': m['balance_after'], 'recorded_at': m['recorded_at']})),
      ...e.get('waste').map((w) => _row('kitchen_wastage', w, {'kind': 'Recorded wastage', 'ingredient_id': w['raw_ingredient_id'], 'quantity': w['quantity'], 'loss_paisa': _money(w, 'cost_loss'), 'recorded_at': w['created_at']})),
    ];
    var bomCovered = 0;
    for (final item in soldItems) {
      final bom = _jsonMap(item['bom_json']);
      if (bom == null) continue;
      bomCovered++;
      for (final entry in bom.entries) {
        if (entry.value is! num) continue;
        rows.add(AnalyticsRow(id: 'order_items-${item['id']}-bom-${entry.key}', sourceType: 'order_items', sourceId: '${item['id']}', cells: {'kind': 'BOM quantity snapshot', 'order_id': item['order_id'], 'ingredient_id': entry.key, 'quantity': entry.value}));
      }
    }
    final valuationQuality = coveredIngredientsCount == ingredients.length && negativeBalanceCount == 0
        ? AnalyticsQuality.good
        : coveredIngredientsCount > 0
            ? AnalyticsQuality.estimated
            : AnalyticsQuality.missing;

    return _section(AnalyticsFamily.inventory, 'Inventory', [
      _metric('ingredients', 'Current ingredients', ingredients.length, unit: AnalyticsUnit.count, explanation: _currentBasis, isBalance: true),
      _metric('reconciled_ingredients', 'Reconciled stock bridges', reconciledIngredientsCount, unit: AnalyticsUnit.count, explanation: 'Ingredients whose opening + receipts - consumption - waste + returns + adjustments exactly equals ending quantity.'),
      _coverage('opening_evidence_coverage', 'Opening balance evidence coverage', openingEvidenceCount, ingredients.length, 'Ingredients with verified prior movement balance_after evidence. Missing opening evidence is disclosed rather than assumed zero.'),
      _metric('missing_opening_count', 'Missing opening balance evidence', missingOpeningCount, unit: AnalyticsUnit.count, explanation: 'Tracked ingredients lacking verified pre-interval balance evidence.', isBalance: true),
      _metric('low_stock', 'Current low stock', low, unit: AnalyticsUnit.count, explanation: 'Current quantity <= configured threshold in each ingredient base unit. $_currentBasis', isBalance: true),
      _metric('negative_stock', 'Current negative stock', negative, unit: AnalyticsUnit.count, explanation: 'Current quantity < 0; sales never blocked. $_currentBasis', isBalance: true),
      _rate('low_stock_share', 'Current low-stock share', low, ingredients.length, 'Low-stock ingredient count / current tracked ingredients. $_currentBasis', isBalance: true),
      _metric('movement_count', 'Recorded movements', e.get('inventory').length, unit: AnalyticsUnit.count, explanation: 'Movement rows attributed by Business Day FK since v14 capture; no fabricated pre-upgrade history.'),
      _coverage('as_of_coverage', 'As-of balance evidence coverage', balances.length, ingredients.length, 'Latest recorded balance_after no later than last selected close/refresh. No evidence means unknown, not opening balance zero.', isBalance: true),
      _coverage('bom_coverage', 'Sold-line BOM quantity coverage', bomCovered, soldItems.length, 'Valid sold lines with readable quantity snapshot. Quantity evidence is not event-time costing.'),
      _metric('stock_valuation', 'Historical stock valuation', totalEndingValuationPaisa, quality: valuationQuality, explanation: 'Ending inventory asset valuation under Moving Weighted Average Cost (WAC) at cutoff. Temporary negative stock balances contribute PKR 0.00 to balance-sheet assets.', unavailable: coveredIngredientsCount == 0),
      _coverage('valuation_coverage', 'Inventory valuation coverage', coveredIngredientsCount, ingredients.length, 'Tracked ingredients with verified acquisition cost layers under Moving WAC at cutoff.'),
      _metric('negative_stock_asset_value', 'Negative stock balance-sheet asset value', 0, explanation: 'Per ADR-0023, items with negative on-hand balance contribute PKR 0.00 to balance-sheet assets.'),
      _metric('physical_variance', 'Posted physical count lines', e.get('physical_counts').length, unit: AnalyticsUnit.count, explanation: 'Posted observations in selected Business Day intervals. Inspect per-ingredient variances below; incompatible units are never totaled.'),
      _metric('physical_variance_cost', 'Estimated physical variance value', _integers(e.get('physical_counts'), 'estimated_cost_paisa'), explanation: 'Signed event-time count estimates; unknown rates prevent a complete total.', unavailable: e.get('physical_counts').any((c) => c['estimated_cost_paisa'] == null)),
    ], rows, [
      'kind', 'ingredient_id', 'name', 'unit', 'opening_qty', 'receipts_qty', 'consumption_qty', 'waste_qty',
      'returns_qty', 'adjustments_qty', 'unexplained_variance', 'ending_qty', 'reconciliation_status',
      'moving_wac_paisa', 'valuation_paisa', 'valuation_policy', 'valuation_badge', 'cost_quality', 'valuation_cutoff',
      'current_stock', 'threshold', 'has_opening_evidence', 'balance_evidence_at', 'recorded_cost_rate',
      'as_of_balance', 'quantity_delta', 'balance_after', 'quantity', 'spend_paisa', 'loss_paisa', 'count_id',
      'expected', 'counted', 'variance', 'estimated_cost_paisa', 'recorded_estimated_cost_paisa',
      'movement_id', 'snapshot_sequence', 'created_by', 'approved_by', 'posted_by',
      'reason', 'status', 'recorded_at'
    ], [
      'Normalized stock bridges reconcile in each ingredient\'s base unit (g, ml, count); never sum quantities across different unit dimensions.',
      'Opening plus receipts minus consumption minus waste plus returns plus adjustments equals ending quantity without double counting.',
      'Inventory valuation method: Moving Weighted Average Cost (WAC) evaluated at cutoff $cutoffTime.',
      'Per ADR-0023, items with negative on-hand balance contribute PKR 0.00 asset value to the balance sheet with an explicit temporary negative balance badge.',
      'Historical acquisition-rate sales COGS is strictly preserved and never retroactively recalculated by subsequent procurement receipts or cost drift.',
      'Recorded unit cost rates represent historical master-data rate evidence; they are described separately from stock valuation.',
      'Missing opening balance evidence is disclosed rather than backfilled as zero.',
      _currentBasis,
      'Movement/BOM/waste rows have separate scopes. Never sum quantities across grams, liters or count units.',
      'Movement history begins with v14 capture; posted physical counts retain observation, approval and movement evidence. A zero-variance count has no adjusting movement. As-of is recorded balance evidence, not an invented beginning balance.',
    ]);
  }

  AnalyticsSection _procurement() {
    final purchases = e.get('purchases');
    final narrowed = e.query.domainFilters.keys.any((d) => [AnalyticsDimension.ingredient, AnalyticsDimension.supplier, AnalyticsDimension.acquisition].contains(d));
    final creditPurchases = e.get('vendor_events').where((t) => t['type'] == 'PURCHASE_CREDIT').toList();
    final procLinks = e.rows['procurement_links'] ?? [];
    final allReceiptEvidence = e.rows['all_receipt_evidence'] ?? [];
    final intervalReceiptEvidence = e.rows['interval_receipt_evidence'] ?? [];

    final ingredientNames = <int, String>{for (final i in e.get('ingredients')) i['id'] as int: _safeText(i['name'])};
    final ingredientUnits = <int, String>{for (final i in e.get('ingredients')) i['id'] as int: i['storage_unit'] as String? ?? 'g'};
    final vendorNames = <int, String>{for (final v in e.get('vendors')) v['id'] as int: _safeText(v['name'])};

    // 1. Stable link identification between Mandi procurements and Vendor Khata credit purchases
    final linkedMandiToTxn = <int, _Record>{};
    final linkedTxnToMandi = <int, _Record>{};

    for (final p in purchases) {
      final pId = p['id'] as int;
      _Record? matchedTxn;
      final txnId = p['vendor_transaction_id'] as int?;
      if (txnId != null) {
        matchedTxn = creditPurchases.where((t) => t['id'] == txnId).firstOrNull;
      }
      matchedTxn ??= creditPurchases.where((t) => t['procurement_id'] == pId).firstOrNull;
      if (matchedTxn == null) {
        final link = procLinks.where((l) => l['procurement_id'] == pId).firstOrNull;
        if (link != null) {
          final lTxnId = link['vendor_transaction_id'] as int?;
          matchedTxn = creditPurchases.where((t) => t['id'] == lTxnId).firstOrNull;
        }
      }
      if (matchedTxn != null) {
        linkedMandiToTxn[pId] = matchedTxn;
        linkedTxnToMandi[matchedTxn['id'] as int] = p;
      }
    }

    // Unified acquisition spend and count (counting linked purchases once)
    int unifiedSpend = 0;
    int linkedPurchasesCount = linkedMandiToTxn.length;
    int unlinkedMandiCount = 0;
    int unlinkedCreditCount = 0;

    for (final p in purchases) {
      final pId = p['id'] as int;
      final spend = _money(p, 'total_cost');
      unifiedSpend += spend;
      if (!linkedMandiToTxn.containsKey(pId)) {
        unlinkedMandiCount++;
      }
    }

    for (final t in creditPurchases) {
      final tId = t['id'] as int;
      if (!linkedTxnToMandi.containsKey(tId)) {
        unifiedSpend += _money(t, 'amount');
        unlinkedCreditCount++;
      }
    }

    final unlinkedPurchasesCount = unlinkedMandiCount + unlinkedCreditCount;
    final unifiedPurchaseCount = linkedPurchasesCount + unlinkedPurchasesCount;
    final selectedDaysCount = e.get('days').isNotEmpty ? e.get('days').length : 1;
    final purchaseFrequency = unifiedPurchaseCount / selectedDaysCount;

    // Supplier purchase counts for per-supplier frequency projection
    final purchasesBySupplier = <int?, int>{};
    for (final p in purchases) {
      final pId = p['id'] as int;
      final matchedTxn = linkedMandiToTxn[pId];
      final vendorId = p['vendor_id'] as int? ?? matchedTxn?['vendor_id'] as int?;
      purchasesBySupplier[vendorId] = (purchasesBySupplier[vendorId] ?? 0) + 1;
    }
    for (final t in creditPurchases) {
      final tId = t['id'] as int;
      if (!linkedTxnToMandi.containsKey(tId)) {
        final vendorId = t['vendor_id'] as int?;
        purchasesBySupplier[vendorId] = (purchasesBySupplier[vendorId] ?? 0) + 1;
      }
    }

    // 2. Receipt punctuality evaluation from evidence
    // Group all evidence by root commitment to handle amendments append-only
    final commitmentsByRoot = <int, List<_Record>>{};
    for (final ev in allReceiptEvidence) {
      final rootId = ev['amendment_of'] as int? ?? ev['id'] as int;
      var currentRoot = rootId;
      var parent = allReceiptEvidence.where((x) => x['id'] == currentRoot).firstOrNull;
      while (parent != null && parent['amendment_of'] != null) {
        currentRoot = parent['amendment_of'] as int;
        parent = allReceiptEvidence.where((x) => x['id'] == currentRoot).firstOrNull;
      }
      commitmentsByRoot.putIfAbsent(currentRoot, () => []).add(ev);
    }

    bool inInterval(String? ts) {
      if (ts == null) return false;
      final dt = _karachi(ts);
      if (dt == null) return false;
      for (final d in e.get('days')) {
        final open = _karachi(d['opened_at']);
        final close = d['closed_at'] != null ? _karachi(d['closed_at']) : e.now;
        if (open != null && close != null && !dt.isBefore(open) && dt.isBefore(close)) {
          return true;
        }
      }
      return false;
    }

    final intervalEvIds = intervalReceiptEvidence.map((ev) => ev['id'] as int).toSet();
    final intervalRootCommitments = <int, List<_Record>>{};
    for (final entry in commitmentsByRoot.entries) {
      final chain = entry.value;
      if (chain.any((ev) => intervalEvIds.contains(ev['id'] as int) ||
          inInterval(ev['recorded_at'] as String?) ||
          inInterval(ev['actual_at'] as String?) ||
          inInterval(ev['promised_at'] as String?))) {
        intervalRootCommitments[entry.key] = chain;
      }
    }

    int validSampleCount = 0;
    int punctualCount = 0;
    int lateCount = 0;
    int unknownPromisesCount = 0;
    int unknownReceiptsCount = 0;

    final evaluatedCommitments = <_EvaluatedCommitment>[];

    for (final entry in intervalRootCommitments.entries) {
      final chain = entry.value;
      chain.sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
      final root = chain.first;
      final latest = chain.last;

      final vendorId = root['vendor_id'] as int;
      final ingredientId = chain.map((ev) => ev['ingredient_id'] as int?).whereType<int>().lastOrNull ?? root['ingredient_id'] as int?;
      final procId = chain.map((ev) => ev['procurement_id'] as int?).whereType<int>().lastOrNull;
      final txnId = chain.map((ev) => ev['vendor_transaction_id'] as int?).whereType<int>().lastOrNull;

      final promisedAt = chain.map((ev) => ev['promised_at'] as String?).whereType<String>().lastOrNull;
      final actualAt = chain.map((ev) => ev['actual_at'] as String?).whereType<String>().lastOrNull;

      final amendmentCount = chain.length - 1;
      final recordedAt = latest['recorded_at'] as String? ?? root['recorded_at'] as String? ?? '';
      final recordedBy = latest['recorded_by'] as int? ?? root['recorded_by'] as int? ?? 1;

      int? delayMins;
      String status;

      if (promisedAt != null && actualAt != null) {
        final promDt = _karachi(promisedAt) ?? DateTime.tryParse(promisedAt);
        final actDt = _karachi(actualAt) ?? DateTime.tryParse(actualAt);
        if (promDt != null && actDt != null) {
          delayMins = actDt.difference(promDt).inMinutes;
          if (delayMins <= 0) {
            status = 'ON_TIME';
            punctualCount++;
          } else {
            status = 'LATE';
            lateCount++;
          }
          validSampleCount++;
        } else {
          status = 'UNKNOWN';
        }
      } else if (promisedAt == null && actualAt != null) {
        status = 'UNKNOWN_PROMISE';
        unknownPromisesCount++;
      } else if (promisedAt != null && actualAt == null) {
        status = 'UNKNOWN_RECEIPT';
        unknownReceiptsCount++;
      } else {
        status = 'UNKNOWN';
      }

      evaluatedCommitments.add(_EvaluatedCommitment(
        id: entry.key,
        vendorId: vendorId,
        ingredientId: ingredientId,
        procurementId: procId,
        vendorTransactionId: txnId,
        effectivePromisedAt: promisedAt,
        effectiveActualAt: actualAt,
        delayMinutes: delayMins,
        status: status,
        amendmentCount: amendmentCount,
        recordedAt: recordedAt,
        recordedBy: recordedBy,
        record: latest,
      ));
    }

    final totalCommitments = evaluatedCommitments.length;

    // Contributor rows
    final mandiRows = purchases.map((p) {
      final pId = p['id'] as int;
      final isLinked = linkedMandiToTxn.containsKey(pId);
      final matchedTxn = linkedMandiToTxn[pId];
      final vendorId = p['vendor_id'] as int? ?? matchedTxn?['vendor_id'] as int?;
      final ingId = p['raw_ingredient_id'] as int?;
      final convertedQty = (p['converted_quantity'] as num?)?.toDouble() ?? 0.0;
      final spend = _money(p, 'total_cost');
      final unitPricePaisa = convertedQty > 0 ? (spend / convertedQty).round() : null;

      return _row('mandi_procurements', p, {
        'kind': 'Mandi procurement',
        'purchase_id': pId,
        'vendor_transaction_id': p['vendor_transaction_id'] ?? matchedTxn?['id'],
        'supplier_id': vendorId,
        'supplier_name': vendorId != null ? (vendorNames[vendorId] ?? 'Supplier #$vendorId') : 'Mandi wholesale',
        'ingredient_id': ingId,
        'ingredient_name': ingId != null ? (ingredientNames[ingId] ?? 'Ingredient #$ingId') : 'Unknown ingredient',
        'purchase_unit': p['traditional_unit'],
        'purchase_quantity': p['quantity'],
        'base_quantity': p['converted_quantity'],
        'base_unit': ingId != null ? (ingredientUnits[ingId] ?? p['traditional_unit']) : p['traditional_unit'],
        'spend_paisa': spend,
        'unit_cost_rupees_per_base_unit': p['cost_per_recipe_unit'],
        'unit_price_paisa': unitPricePaisa,
        'is_linked': isLinked,
        'purchase_frequency': (purchasesBySupplier[vendorId] ?? 1) / selectedDaysCount,
        'promised_at': null,
        'actual_at': null,
        'delay_minutes': null,
        'punctuality_status': null,
        'amendment_count': null,
        'created_at': p['created_at'],
      });
    }).toList();

    final unlinkedCreditRows = creditPurchases.where((t) => !linkedTxnToMandi.containsKey(t['id'])).map((t) {
      final tId = t['id'] as int;
      final vendorId = t['vendor_id'] as int?;
      final ingId = t['raw_ingredient_id'] as int?;
      final qty = (t['quantity'] as num?)?.toDouble();
      final spend = _money(t, 'amount');
      final unitPricePaisa = (qty != null && qty > 0) ? (spend / qty).round() : null;

      return _row('vendor_transactions', t, {
        'kind': 'Supplier credit delivery',
        'purchase_id': null,
        'vendor_transaction_id': tId,
        'supplier_id': vendorId,
        'supplier_name': vendorId != null ? (vendorNames[vendorId] ?? 'Supplier #$vendorId') : 'Unknown supplier',
        'ingredient_id': ingId,
        'ingredient_name': ingId != null
            ? (ingredientNames[ingId] ?? 'Ingredient #$ingId')
            : (t['ingredient_name_snapshot'] as String? ?? 'Unlinked ingredient'),
        'purchase_unit': t['unit_snapshot'] ?? (ingId != null ? ingredientUnits[ingId] : null),
        'purchase_quantity': qty,
        'base_quantity': qty,
        'base_unit': ingId != null ? (ingredientUnits[ingId] ?? t['unit_snapshot']) : t['unit_snapshot'],
        'spend_paisa': spend,
        'unit_cost_rupees_per_base_unit': (qty != null && qty > 0) ? (spend / 100.0) / qty : null,
        'unit_price_paisa': unitPricePaisa,
        'is_linked': false,
        'purchase_frequency': (purchasesBySupplier[vendorId] ?? 1) / selectedDaysCount,
        'promised_at': null,
        'actual_at': null,
        'delay_minutes': null,
        'punctuality_status': null,
        'amendment_count': null,
        'created_at': t['created_at'],
      });
    }).toList();

    final receiptEvidenceRows = evaluatedCommitments.map((c) {
      return _row('supplier_receipt_evidence', c.record, {
        'kind': 'Supplier receipt evidence',
        'purchase_id': c.procurementId,
        'vendor_transaction_id': c.vendorTransactionId,
        'supplier_id': c.vendorId,
        'supplier_name': vendorNames[c.vendorId] ?? 'Supplier #${c.vendorId}',
        'ingredient_id': c.ingredientId,
        'ingredient_name': c.ingredientId != null ? (ingredientNames[c.ingredientId] ?? 'Ingredient #${c.ingredientId}') : null,
        'purchase_unit': null,
        'purchase_quantity': null,
        'base_quantity': null,
        'base_unit': null,
        'spend_paisa': null,
        'unit_cost_rupees_per_base_unit': null,
        'unit_price_paisa': null,
        'is_linked': null,
        'purchase_frequency': purchasesBySupplier[c.vendorId] != null ? purchasesBySupplier[c.vendorId]! / selectedDaysCount : null,
        'promised_at': c.effectivePromisedAt,
        'actual_at': c.effectiveActualAt,
        'delay_minutes': c.delayMinutes,
        'punctuality_status': c.status,
        'amendment_count': c.amendmentCount,
        'created_at': c.recordedAt,
      });
    }).toList();

    final allRows = [...mandiRows, ...unlinkedCreditRows, ...receiptEvidenceRows];

    final punctualityMetric = validSampleCount > 0
        ? _metric(
            'supplier_performance',
            'Supplier delivery performance',
            (punctualCount * 100.0 / validSampleCount).round(),
            unit: AnalyticsUnit.percent,
            explanation: '$punctualCount on-time receipts of $validSampleCount valid commitments with recorded promises and actual delivery times. $unknownPromisesCount unknown promises and $unknownReceiptsCount pending/unknown receipts disclosed separately; not classified as failed deliveries.',
            sampleCount: validSampleCount,
            populationCount: totalCommitments,
          )
        : _missing(
            'supplier_performance',
            'Supplier delivery performance',
            'No delivery commitments with both promised and actual delivery times recorded in selected interval.',
            unit: AnalyticsUnit.percent,
          );

    return _section(
      AnalyticsFamily.procurement,
      'Procurement',
      [
        _metric(
          'purchase_spend',
          'Recorded Mandi purchase spend',
          _sum(purchases, 'total_cost'),
          explanation: 'Mandi purchase records only; unlinked supplier credit deliveries are separate and not blindly added. $_intervalBasis',
          previous: narrowed ? null : _sum(e.get('previous_purchases'), 'total_cost'),
        ),
        _metric(
          'purchase_count',
          'Recorded purchases',
          purchases.length,
          unit: AnalyticsUnit.count,
          explanation: 'Mandi purchase rows in selected actual day intervals.',
          previous: narrowed ? null : e.get('previous_purchases').length,
        ),
        _metric(
          'purchased_ingredients',
          'Distinct purchased ingredients',
          purchases.map((p) => p['raw_ingredient_id']).toSet().length,
          unit: AnalyticsUnit.count,
          explanation: 'Distinct ingredient IDs in selected Mandi purchase records.',
        ),
        _metric(
          'unified_spend',
          'Unified acquisition spend',
          unifiedSpend,
          unit: AnalyticsUnit.paisa,
          explanation: 'Total acquisition spend across wholesale Mandi procurements and credit purchases, counting linked purchases once. $_intervalBasis',
        ),
        _metric(
          'unified_purchase_count',
          'Unified purchase events',
          unifiedPurchaseCount,
          unit: AnalyticsUnit.count,
          explanation: 'Total distinct acquisition events across Mandi wholesale and credit deliveries, counting linked purchases once.',
        ),
        _metric(
          'linked_purchases_count',
          'Linked supplier purchases',
          linkedPurchasesCount,
          unit: AnalyticsUnit.count,
          explanation: 'Purchases with verified stable links between Mandi procurement and Vendor Khata credit entries, counted once without double counting.',
        ),
        _metric(
          'unlinked_purchases_count',
          'Unlinked purchases',
          unlinkedPurchasesCount,
          unit: AnalyticsUnit.count,
          explanation: 'Purchases without cross-ledger links, disclosed honestly without guessing matches.',
        ),
        _metric(
          'purchase_frequency',
          'Purchase frequency',
          purchaseFrequency,
          unit: AnalyticsUnit.decimal,
          explanation: 'Average unified acquisition events per selected Business Day ($unifiedPurchaseCount purchases / $selectedDaysCount days).',
        ),
        _metric(
          'distinct_suppliers',
          'Active suppliers',
          purchasesBySupplier.keys.where((k) => k != null).length,
          unit: AnalyticsUnit.count,
          explanation: 'Distinct vendors and wholesale suppliers with recorded acquisitions in selected interval.',
        ),
        punctualityMetric,
        _metric(
          'valid_punctuality_sample',
          'Valid punctuality commitments',
          validSampleCount,
          unit: AnalyticsUnit.count,
          explanation: 'Commitments with both promised delivery deadline and actual receipt timestamp recorded.',
        ),
        _metric(
          'punctual_receipts',
          'Punctual receipts',
          punctualCount,
          unit: AnalyticsUnit.count,
          explanation: 'Deliveries received at or before promised deadline.',
        ),
        _metric(
          'late_receipts',
          'Late deliveries',
          lateCount,
          unit: AnalyticsUnit.count,
          explanation: 'Deliveries received strictly after promised deadline.',
        ),
        _metric(
          'unknown_promises',
          'Receipts with unknown promise',
          unknownPromisesCount,
          unit: AnalyticsUnit.count,
          explanation: 'Deliveries received without a recorded delivery promise; disclosed honestly and not classified as failed.',
        ),
        _metric(
          'unknown_receipts',
          'Pending or unknown receipts',
          unknownReceiptsCount,
          unit: AnalyticsUnit.count,
          explanation: 'Recorded delivery commitments without an actual receipt timestamp; disclosed honestly and not classified as failed.',
        ),
      ],
      allRows,
      [
        'kind', 'purchase_id', 'vendor_transaction_id', 'supplier_id', 'supplier_name',
        'ingredient_id', 'ingredient_name', 'purchase_unit', 'purchase_quantity',
        'base_quantity', 'base_unit', 'spend_paisa', 'unit_cost_rupees_per_base_unit',
        'unit_price_paisa', 'is_linked', 'purchase_frequency', 'promised_at', 'actual_at', 'delay_minutes',
        'punctuality_status', 'amendment_count', 'created_at'
      ],
      [
        _intervalBasis,
        _globalBasis,
        'Per-ingredient unit rates retain their recorded decimal PKR/base-unit precision (a rate, not a rounded monetary amount). Different base-unit dimensions must not be totaled. Purchase spend is not sales COGS.',
        'Normalized acquisition prices reconcile to ingredient base unit and integer paisa.',
        'Stable links between Mandi procurements and Vendor Khata credit deliveries prevent double-counting unified purchases.',
        'Unlinked purchases and unavailable units are disclosed honestly without guessing matches.',
        'Supplier receipt punctuality compares recorded commitments with actual receipt timestamps; unknown promises or receipts are disclosed separately and never classified as failed deliveries.',
        'Valid-sample coverage indicates commitments with both promised and actual receipt timestamps; no unapproved SLA or scoring formulas are used.',
      ],
    );
  }

  AnalyticsSection _suppliers() {
    final vendors = e.get('vendors');
    final events = e.get('vendor_events');
    final allTxns = e.rows['all_vendor_transactions'] ?? events;
    final allocations = e.rows['all_supplier_allocations'] ?? [];
    final openingAdjustments = e.rows['supplier_opening_adjustments'] ?? [];

    final intervalStart = _sqlTime(_karachi(analyticsWallClock(e.query.startDate).toIso8601String())!);
    final cutoffTime = e.query.live
        ? _sqlTime(_karachi(e.now.toIso8601String())!)
        : _sqlTime(_karachi(analyticsWallClock(e.query.endDateExclusive).toIso8601String())!);
    final cutoffDate = cutoffTime.substring(0, 10);

    final vendorNames = <int, String>{for (final v in vendors) v['id'] as int: _safeText(v['name'])};
    final vendorStatuses = <int, String>{for (final v in vendors) v['id'] as int: v['archived_at'] != null ? 'Archived' : 'Active'};

    int totalOpeningPayable = 0;
    int totalPurchasesInRange = 0;
    int totalPaymentsInRange = 0;
    int totalAdjsInRange = 0;
    int totalClosingPayable = 0;

    int totalCurrent = 0;
    int totalDays0to7 = 0;
    int totalDays8to30 = 0;
    int totalDays31to60 = 0;
    int totalOver60 = 0;
    int totalUnknownDue = 0;

    int activeCount = 0;
    int datedInvoiceCount = 0;
    int totalInvoicesCount = 0;

    final bridgeRows = <AnalyticsRow>[];

    for (final v in vendors) {
      final vId = v['id'] as int;
      final vName = _safeText(v['name']);
      final isArchived = v['archived_at'] != null;
      if (!isArchived) activeCount++;
      final status = isArchived ? 'Archived' : 'Active';
      final initOpeningPaisa = _money(v, 'opening_balance');
      final vCreated = v['created_at'] as String? ?? '';

      final vAdjs = openingAdjustments.where((a) => a['vendor_id'] == vId).toList();
      final adjsBeforeStart = vAdjs.where((a) => (a['recorded_at'] as String).compareTo(intervalStart) < 0).toList();
      final adjsInRange = vAdjs.where((a) => (a['recorded_at'] as String).compareTo(intervalStart) >= 0 && (a['recorded_at'] as String).compareTo(cutoffTime) <= 0).toList();

      final baseOpeningPaisa = vCreated.isNotEmpty && vCreated.compareTo(intervalStart) >= 0
          ? 0
          : (adjsBeforeStart.isNotEmpty ? adjsBeforeStart.last['opening_balance_paisa'] as int : initOpeningPaisa);

      final adjsInRangePaisa = adjsInRange.fold<int>(0, (sum, a) => sum + (a['opening_balance_paisa'] as int) - (a['previous_balance_paisa'] as int));

      final txnsBeforeStart = allTxns.where((t) => t['vendor_id'] == vId && (t['created_at'] as String).compareTo(intervalStart) < 0).toList();
      final txnsInRange = allTxns.where((t) => t['vendor_id'] == vId && (t['created_at'] as String).compareTo(intervalStart) >= 0 && (t['created_at'] as String).compareTo(cutoffTime) <= 0).toList();
      final txnsUpToCutoff = allTxns.where((t) => t['vendor_id'] == vId && (t['created_at'] as String).compareTo(cutoffTime) <= 0).toList();

      final purchasesBefore = txnsBeforeStart.where((t) => t['type'] == 'PURCHASE_CREDIT').fold<int>(0, (sum, t) => sum + _money(t, 'amount'));
      final paymentsBefore = txnsBeforeStart.where((t) => ['PAYMENT_DRAWER', 'PAYMENT_EXTERNAL'].contains(t['type'])).fold<int>(0, (sum, t) => sum + _money(t, 'amount'));
      final openingPayablePaisa = baseOpeningPaisa + purchasesBefore - paymentsBefore;

      final purchasesInRange = txnsInRange.where((t) => t['type'] == 'PURCHASE_CREDIT').fold<int>(0, (sum, t) => sum + _money(t, 'amount'));
      final paymentsInRange = txnsInRange.where((t) => ['PAYMENT_DRAWER', 'PAYMENT_EXTERNAL'].contains(t['type'])).fold<int>(0, (sum, t) => sum + _money(t, 'amount'));
      final closingPayablePaisa = openingPayablePaisa + purchasesInRange + adjsInRangePaisa - paymentsInRange;

      // Only include allocations created on or before cutoff
      final vAllocs = allocations.where((a) => a['vendor_id'] == vId && (a['created_at'] as String).compareTo(cutoffTime) <= 0).toList();
      final openingPaidAtCutoff = vAllocs.where((a) => a['invoice_id'] == null).fold<int>(0, (sum, a) => sum + (a['amount_paisa'] as int));
      final effectiveOpeningAtCutoff = (vAdjs.where((a) => (a['recorded_at'] as String).compareTo(cutoffTime) <= 0).isNotEmpty)
          ? vAdjs.where((a) => (a['recorded_at'] as String).compareTo(cutoffTime) <= 0).last['opening_balance_paisa'] as int
          : initOpeningPaisa;
      final openingDueAtCutoff = (vCreated.isNotEmpty && vCreated.compareTo(cutoffTime) > 0)
          ? 0
          : math.max(0, effectiveOpeningAtCutoff - openingPaidAtCutoff);

      int vCurrent = 0, vDays0to7 = 0, vDays8to30 = 0, vDays31to60 = 0, vOver60 = 0, vUnknownDue = openingDueAtCutoff;

      final invoicesUpToCutoff = txnsUpToCutoff.where((t) => t['type'] == 'PURCHASE_CREDIT').toList();
      totalInvoicesCount += invoicesUpToCutoff.length;

      for (final inv in invoicesUpToCutoff) {
        final invId = inv['id'] as int;
        final invAmount = _money(inv, 'amount');
        final paid = vAllocs.where((a) => a['invoice_id'] == invId).fold<int>(0, (sum, a) => sum + (a['amount_paisa'] as int));
        final due = invAmount - paid;
        final dueDateStr = inv['due_date'] as String?;
        if (dueDateStr != null && dueDateStr.trim().isNotEmpty) {
          datedInvoiceCount++;
        }
        if (due <= 0) continue;

        if (dueDateStr == null || dueDateStr.trim().isEmpty) {
          vUnknownDue += due;
        } else {
          final dueTrimmed = dueDateStr.trim().substring(0, 10);
          if (dueTrimmed.compareTo(cutoffDate) > 0) {
            vCurrent += due;
          } else {
            final dueDt = DateTime.tryParse(dueTrimmed);
            final cutoffDt = DateTime.tryParse(cutoffDate);
            if (dueDt == null || cutoffDt == null) {
              vUnknownDue += due;
            } else {
              final overdueDays = cutoffDt.difference(dueDt).inDays;
              if (overdueDays <= 7) {
                vDays0to7 += due;
              } else if (overdueDays <= 30) {
                vDays8to30 += due;
              } else if (overdueDays <= 60) {
                vDays31to60 += due;
              } else {
                vOver60 += due;
              }
            }
          }
        }
      }

      totalOpeningPayable += openingPayablePaisa;
      totalPurchasesInRange += purchasesInRange;
      totalPaymentsInRange += paymentsInRange;
      totalAdjsInRange += adjsInRangePaisa;
      totalClosingPayable += closingPayablePaisa;

      totalCurrent += vCurrent;
      totalDays0to7 += vDays0to7;
      totalDays8to30 += vDays8to30;
      totalDays31to60 += vDays31to60;
      totalOver60 += vOver60;
      totalUnknownDue += vUnknownDue;

      bridgeRows.add(AnalyticsRow(
        id: 'supplier-bridge-$vId',
        sourceType: 'vendor_khata',
        sourceId: '$vId',
        cells: {
          'kind': 'Vendor Khata bridge',
          'supplier_id': vId,
          'name': vName,
          'status': status,
          'opening_paisa': openingPayablePaisa,
          'purchases_paisa': purchasesInRange,
          'payments_paisa': paymentsInRange,
          'adjustments_paisa': adjsInRangePaisa,
          'closing_paisa': closingPayablePaisa,
          'aging_current_paisa': vCurrent,
          'aging_0_7_paisa': vDays0to7,
          'aging_8_30_paisa': vDays8to30,
          'aging_31_60_paisa': vDays31to60,
          'aging_over_60_paisa': vOver60,
          'aging_unknown_paisa': vUnknownDue,
          'due_date': null,
          'type': null,
          'amount_paisa': null,
          'created_at': vCreated,
        },
      ));
    }

    final payments = events.where((t) => ['PAYMENT_DRAWER', 'PAYMENT_EXTERNAL'].contains(t['type'])).toList();
    final paidIds = payments.map((t) => t['vendor_id']).toSet();

    return _section(AnalyticsFamily.suppliers, 'Supplier Khata', [
      _metric('khata_opening_payable', 'Vendor Khata opening payable', totalOpeningPayable, unit: AnalyticsUnit.paisa, explanation: 'Historical payable at start of selected interval based on pre-period evidence.', isBalance: true),
      _metric('credit_purchases', 'Recorded credit deliveries', totalPurchasesInRange, unit: AnalyticsUnit.paisa, explanation: 'Credit purchases in selected interval affecting stock/payable; not cash payments. $_intervalBasis'),
      _metric('khata_payments', 'Recorded supplier payments', totalPaymentsInRange, unit: AnalyticsUnit.paisa, explanation: 'Selected interval supplier settlements from cash drawer and external management accounts.'),
      _metric('khata_adjustments', 'Opening balance adjustments', totalAdjsInRange, unit: AnalyticsUnit.paisa, explanation: 'Net versioned opening balance adjustments in selected interval.'),
      _metric('khata_closing_payable', 'Vendor Khata closing payable', totalClosingPayable, unit: AnalyticsUnit.paisa, explanation: 'Opening + purchases + adjustments - payments reconciled at disclosed cutoff.', isBalance: true),
      _metric('aging_current', 'Current (not yet due) payable', totalCurrent, unit: AnalyticsUnit.paisa, explanation: 'Invoiced payable with due date strictly after disclosed cutoff date.', isBalance: true),
      _metric('aging_0_7', 'Payable overdue 0–7 days', totalDays0to7, unit: AnalyticsUnit.paisa, explanation: 'Invoiced payable 0 to 7 days past due date (including due today at cutoff).', isBalance: true),
      _metric('aging_8_30', 'Payable overdue 8–30 days', totalDays8to30, unit: AnalyticsUnit.paisa, explanation: 'Invoiced payable 8 to 30 days past due date as of cutoff.', isBalance: true),
      _metric('aging_31_60', 'Payable overdue 31–60 days', totalDays31to60, unit: AnalyticsUnit.paisa, explanation: 'Invoiced payable 31 to 60 days past due date as of cutoff.', isBalance: true),
      _metric('aging_over_60', 'Payable overdue over 60 days', totalOver60, unit: AnalyticsUnit.paisa, explanation: 'Invoiced payable more than 60 days past due date as of cutoff.', isBalance: true),
      _metric('aging_unknown', 'Payable with unknown due date', totalUnknownDue, unit: AnalyticsUnit.paisa, explanation: 'Undated invoices and unallocated opening balances without explicit due dates.', isBalance: true),
      _coverage('supplier_coverage', 'Active and archived supplier coverage', activeCount, vendors.length, 'Active suppliers vs total registered suppliers including archived historical vendors.'),
      _coverage('invoice_due_date_coverage', 'Invoice due-date coverage', datedInvoiceCount, totalInvoicesCount, 'Invoices with recorded due dates vs total credit invoices up to cutoff.'),
      _metric('current_payable', 'Current supplier payable', _sum(vendors, 'current_balance'), explanation: 'Stored current balances across existing suppliers. $_currentBasis', isBalance: true),
      _metric('drawer_payments', 'Supplier drawer payments', _sum(payments.where((t) => t['type'] == 'PAYMENT_DRAWER'), 'amount'), explanation: 'Selected interval supplier settlements from drawer; these are not operating expenses.'),
      _metric('external_payments', 'Supplier external payments', _sum(payments.where((t) => t['type'] == 'PAYMENT_EXTERNAL'), 'amount'), explanation: 'Selected interval supplier settlements from external management funds.'),
      _metric('no_payments_in_range', 'Suppliers with no payments in range', vendors.where((v) => !paidIds.contains(v['id'])).length, unit: AnalyticsUnit.count, explanation: 'Existing suppliers with no selected interval settlement.'),
    ], [
      ...bridgeRows,
      ...events.map((t) => _row('vendor_transactions', t, {
        'kind': 'Selected interval entry',
        'supplier_id': t['vendor_id'],
        'name': vendorNames[t['vendor_id']] ?? 'Unknown',
        'status': vendorStatuses[t['vendor_id']] ?? 'Active',
        'opening_paisa': null,
        'purchases_paisa': null,
        'payments_paisa': null,
        'adjustments_paisa': null,
        'closing_paisa': null,
        'aging_current_paisa': null,
        'aging_0_7_paisa': null,
        'aging_8_30_paisa': null,
        'aging_31_60_paisa': null,
        'aging_over_60_paisa': null,
        'aging_unknown_paisa': null,
        'due_date': t['due_date'],
        'type': t['type'],
        'amount_paisa': _money(t, 'amount'),
        'created_at': t['created_at'],
      })),
    ], [
      'kind', 'supplier_id', 'name', 'status', 'opening_paisa', 'purchases_paisa', 'payments_paisa',
      'adjustments_paisa', 'closing_paisa', 'aging_current_paisa', 'aging_0_7_paisa', 'aging_8_30_paisa',
      'aging_31_60_paisa', 'aging_over_60_paisa', 'aging_unknown_paisa', 'due_date', 'type', 'amount_paisa', 'created_at'
    ], [
      'Vendor Khata bridge: Opening + purchases/adjustments minus payments/credits reconciles to closing using evidence strictly available at the disclosed cutoff.',
      'Aging buckets are nonoverlapping; sum of aging buckets strictly equals closing payable.',
      'Historical balances use only allocations and payments recorded on or before the cutoff date; current/all-time allocations are not used as historical balances.',
      'Archived suppliers with historical activity or balances are retained and disclosed with Archived status.',
      _currentBasis, _intervalBasis,
    ]);
  }

  List<_Record> _receivingEvents() {
    final receivingIds = e.get('days').map((d) => d['id']).toSet();
    final receiptEvents = e.get('payment_events').where((p) {
      if (!['RECEIPT', 'REFUND', 'RIDER_HANDOVER', 'COD_SETTLEMENT', 'RIDER_COLLECTION', 'RIDER_SHORTAGE'].contains(p['kind'])) return false;
      if (e.query.timeBasis == AnalyticsTimeBasis.calendarTime) {
        final actual = _karachi(p['actual_at']);
        if (actual == null || actual.isBefore(analyticsWallClock(e.query.startDate)) || !actual.isBefore(analyticsWallClock(e.query.endDateExclusive))) return false;
      } else if (!receivingIds.contains(p['business_day_id'])) { return false; }
      return (e.query.shiftId == null || p['shift_id'] == e.query.shiftId) &&
          (e.query.cashierId == null || p['shift_owner_id'] == e.query.cashierId) &&
          (e.query.paymentMethod == null || p['payment_method'] == e.query.paymentMethod);
    }).toList();
    return receiptEvents;
  }

  List<AnalyticsRow> _receivingEventRows(Iterable<_Record> receiptEvents) => [
      ...receiptEvents.map((p) => _row('payment_events', p, {
        'kind': p['kind'] == 'RIDER_HANDOVER'
            ? 'Counted rider custody transfer (drawer cash)'
            : p['kind'] == 'COD_SETTLEMENT'
                ? 'Order settlement attribution (not collected cash)'
                : p['kind'] == 'RIDER_COLLECTION'
                    ? 'Confirmed customer collection (rider-held cash)'
                    : p['kind'] == 'RIDER_SHORTAGE'
                        ? 'Rider settlement shortage'
                        : 'Independent customer money event',
        'event_kind': p['kind'],
        'event_key': p['event_key'], 'amount_paisa': p['amount_paisa'],
        'payment_source': p['payment_source'], 'payment_method': p['payment_method'],
        'actual_at': p['actual_at'], 'recorded_at': p['recorded_at'],
        'receiving_business_day_id': p['business_day_id'], 'receiving_shift_id': p['shift_id'],
        'business_day_id': p['business_day_id'], 'shift_id': p['shift_id'],
        'originating_business_day_id': p['originating_business_day_id'], 'originating_shift_id': p['originating_shift_id'],
        'order_id': p['order_id'], 'tender_id': p['tender_id'], 'movement_id': p['movement_id'],
        'settlement_id': p['settlement_id'], 'trip_id': p['settlement_id'],
        if (p['settlement_id'] != null) 'customer_collection_evidence': p['kind'] == 'RIDER_COLLECTION'
            ? 'Confirmed customer collection recorded'
            : p['kind'] == 'RIDER_SHORTAGE'
                ? 'Rider settlement shortage recorded'
                : 'Customer-to-rider collection evidence unavailable; delivery and expected pouch are insufficient proof',
        if (p['kind'] == 'COD_SETTLEMENT') 'value_basis': 'Remaining contractual Order settlement, not allocated physical pouch cash',
        'recorded_by': p['recorded_by'], 'approved_by': p['approved_by'],
        'recorded_by_name_snapshot': p['recorded_by_name_snapshot'] == null ? null : _safeText(p['recorded_by_name_snapshot']), 'shift_owner_name_snapshot': p['shift_owner_name_snapshot'] == null ? null : _safeText(p['shift_owner_name_snapshot']),
        'change_paisa': p['change_paisa'], 'rounding_paisa': p['rounding_paisa'],
      })),
  ];

  AnalyticsSection _cash() => _ShiftCashBridge(this).build();

  AnalyticsSection _expenses() {
    final out = e.get('movements').where((m) => m['type'] != 'PAY_IN').toList();
    final finance = _FinanceTimeline(e);
    final metrics = <AnalyticsMetric>[
      ...finance.metrics,
      _metric('recorded_outflow', 'Recorded drawer outflow', _sum(out, 'amount'), explanation: 'All selected-shift PAY_OUT rows; not automatically operating expense. $_globalBasis'),
      _metric('outflow_count', 'Drawer outflow events', out.length, unit: AnalyticsUnit.count, explanation: _globalBasis),
      _metric('operating_expense', 'Recorded operating expense', _integers(e.get('expense_entries'), 'expense_delta_paisa'), explanation: 'Selected Business Day expense postings less reversals, across all funding sources. Legacy generic cash outflows are not inferred expenses.'),
    ];
    for (final entry in _group(out, 'category').entries) {
      metrics.add(_metric('category_${entry.key}', '${entry.key} drawer outflow', _sum(entry.value, 'amount'), explanation: 'Recorded PAY_OUT category/source only, not asserted operating expense.'));
    }
    return _section(AnalyticsFamily.expenses, 'Finance timeline and expenses', metrics, [
      ...finance.rows,
      ..._MoneyFlowPeaks(this).build(),
      ...e.get('expense_entries').map((x) => _row('expense_entries', x, {
        'kind': 'Expense ledger', 'business_day_id': x['business_day_id'],
        'category': _safeText(x['category_snapshot']), 'description': _safeText(x['description']),
        'payee': _safeText(x['payee']), 'amount_paisa': x['expense_delta_paisa'],
        'source': x['source'], 'reversal_of': x['reversal_of'], 'correction_of': x['correction_of'],
        'manager_id': x['manager_id'], 'reason': _safeText(x['reason']), 'created_at': x['created_at']})),
      ...out.map((m) => _row('cash_movements', m, {'kind': 'Drawer outflow', 'shift_id': m['shift_id'],
        'category': _safeText(m['category']), 'amount_paisa': _money(m, 'amount'),
        'source': 'Shift drawer', 'classification': 'Cash movement; do not add to expense ledger totals',
        'created_at': m['created_at']})),
    ], ['kind', ..._FinanceTimeline.keys, 'business_day_id', 'shift_id', 'category', 'description', 'payee', 'amount_paisa',
      'source', 'reversal_of', 'correction_of', 'manager_id', 'reason', 'classification', 'created_at'],
      [...finance.notes, ..._MoneyFlowPeaks.notes, _globalBasis, 'Expense entries retain category snapshots. Cash movements reconcile physical funds and must not be added to expense entries. Legacy outflows are not inferred expenses.']);
  }

  AnalyticsSection _staff() {
    final staff = e.get('staff');
    final payroll = _EarnedPayroll(e);
    return _section(AnalyticsFamily.staff, 'Staff and payroll', [
      _metric('staff_count', 'Current staff', staff.length, unit: AnalyticsUnit.count, explanation: _currentBasis, isBalance: true),
      _metric('active_staff', 'Current active staff', staff.where((s) => s['is_active'] == 1).length, unit: AnalyticsUnit.count, explanation: _currentBasis, isBalance: true),
      _metric('login_enabled', 'Current login-enabled staff', staff.where((s) => s['login_enabled'] == 1).length, unit: AnalyticsUnit.count, explanation: _currentBasis, isBalance: true),
      _metric('departments', 'Assigned departments', staff.map((s) => s['department_id']).toSet().length, unit: AnalyticsUnit.count, explanation: 'Distinct current assigned department IDs, not labor-cost allocations.', isBalance: true),
      _metric('job_roles', 'Assigned job roles', staff.where((s) => s['job_role_id'] != null).map((s) => s['job_role_id']).toSet().length, unit: AnalyticsUnit.count, explanation: 'Distinct current assigned job-role IDs.', isBalance: true),
      e.get('payroll_balances').isEmpty ? _missing('salary_due', 'Current recorded salary due', 'No payroll has been posted; legacy staff salary liabilities are unknown.') : _metric('salary_due', 'Current recorded salary due', _integers(e.get('payroll_balances'), 'payable_paisa') - _integers(e.get('payroll_balances'), 'advance_paisa'), explanation: 'Current accrued payable less outstanding advances. No unposted salary is inferred.', isBalance: true),
      _metric('labor_cost', 'Posted salary accruals', e.get('payroll_entries').fold<int>(0, (sum, p) => sum + (p['kind']=='ACCRUAL' || (p['kind']=='REVERSAL' && p['source']=='NONE' && p['advance_delta_paisa']==0) ? p['payable_delta_paisa'] as int : 0)), explanation: 'Salary accruals and their reversals posted in selected day intervals. Payments and advances never count as another expense; earned-period profit allocation remains separate.'),
      ...payroll.metrics,
      _missing('labor_productivity', 'Orders per labor hour', 'Cashier shift duration is not paid attendance or worked labor-hour evidence.', unit: AnalyticsUnit.decimal),
    ], [...payroll.rows, ...staff.map((s) => _row('staff', s, {'staff_id': s['id'], 'name': _safeText(s['name']), 'department': s['department'], 'job_role': s['job_role'], 'role': s['role'], 'active': s['is_active'] == 1 ? 'Active' : 'Inactive', 'login': s['login_enabled'] == 1 ? 'Enabled' : 'Disabled', 'selected_orders': orders.where((o) => o['cashier_id'] == s['id']).length, 'selected_shifts': e.get('shifts').where((sh) => sh['staff_id'] == s['id']).length}))], ['staff_id', 'name', 'department', 'job_role', 'role', 'active', 'login', 'selected_orders', 'selected_shifts'], [...payroll.notes, _currentBasis, 'Order activity uses selected order filters; shift activity is whole selected Business Days. Current role/department names are not historical snapshots. PIN hashes and credentials are never projected.']);
  }

  AnalyticsSection _profitability() {
    final payroll = _EarnedPayroll(e);
    final coverage = e.get('cost_coverage').map((c) => c['order_id']).toSet();
    final events = e.get('cost_events');
    final covered = orders.where((o) => coverage.contains(o['id'])).length;
    final complete = e.get('days').isNotEmpty && covered == orders.length && events.every((c) => c['cost_paisa'] != null);
    final cogs = events.fold<int>(0, (sum, c) => sum + orderCostSign(c['kind']) * ((c['cost_paisa'] as int?) ?? 0));
    final ordersById = {for (final o in orders) o['id']: o};

    var foodCogs = 0;
    var packagingCogs = 0;
    var unclassifiedCogs = 0;
    final foodByDining = <String, int>{'DINE_IN': 0, 'TAKEAWAY': 0, 'DELIVERY': 0};
    final packagingByDining = <String, int>{'DINE_IN': 0, 'TAKEAWAY': 0, 'DELIVERY': 0};
    final unclassifiedByDining = <String, int>{'DINE_IN': 0, 'TAKEAWAY': 0, 'DELIVERY': 0};

    for (final c in events) {
      final sign = orderCostSign(c['kind']);
      final paisa = (c['cost_paisa'] as int?) ?? 0;
      final signedCost = sign * paisa;
      final rawCls = c['classification'] as String?;
      final cls = (rawCls == null || rawCls.trim().isEmpty) ? 'UNCLASSIFIED' : rawCls.trim().toUpperCase();
      final order = ordersById[c['order_id']];
      final diningType = (order?['dining_type'] as String?) ?? 'UNKNOWN';

      if (cls == 'FOOD') {
        foodCogs += signedCost;
        foodByDining[diningType] = (foodByDining[diningType] ?? 0) + signedCost;
      } else if (cls == 'PACKAGING') {
        packagingCogs += signedCost;
        packagingByDining[diningType] = (packagingByDining[diningType] ?? 0) + signedCost;
      } else {
        unclassifiedCogs += signedCost;
        unclassifiedByDining[diningType] = (unclassifiedByDining[diningType] ?? 0) + signedCost;
      }
    }

    // Accrual at confirmation: include COD receivables; cancellation reduces the
    // stored total to zero. Delivery fees are earned with the order; tax is excluded.
    final revenue = _sum(valid, 'grand_total') - _sum(valid, 'tax_amount');
    final gross = revenue - cogs;
    final expenses = _integers(e.get('expense_entries'), 'expense_delta_paisa');
    final labor = e.get('payroll_entries').fold<int>(0, (sum, p) => sum + (p['kind'] == 'ACCRUAL' || (p['kind'] == 'REVERSAL' && p['source'] == 'NONE' && p['advance_delta_paisa'] == 0) ? p['payable_delta_paisa'] as int : 0));
    final rawWaste = _sum(e.get('waste').where((w) => w['reason'] != 'WASTED_COOKED'), 'cost_loss');
    final variance = _integers(e.get('physical_counts'), 'estimated_cost_paisa');
    final netAvailable = complete && !e.query.hasOrderFilters && !e.absent.contains('expense_entries') && !e.absent.contains('payroll_entries') &&
      e.get('physical_counts').every((c) => c['estimated_cost_paisa'] != null) &&
      e.get('waste').where((w) => w['reason'] != 'WASTED_COOKED').every((w) => _money(w, 'cost_loss') > 0);
    const policy = 'Recognition at order confirmation, including COD receivables and delivery fees, less stored tax carve-out. Cancellations/revisions use current order totals. Cost uses immutable event-time acquisition rates, with original-rate raw returns; cooked losses remain in consumed cost. Missing pre-upgrade orders/rates withhold complete profit.';
    return _section(AnalyticsFamily.profitability, 'Profitability and costing', [
      _metric('recorded_value', 'Recorded order value', _sum(valid, 'grand_total'), explanation: _orderBasis),
      _metric('recognized_revenue', 'Tax-exclusive recognized revenue', revenue, explanation: policy),
      _coverage('cost_coverage', 'Historical cost capture coverage', covered, orders.length, 'Orders with event-time cost capture. Unknown ingredient rates are separately disclosed in cost rows.'),
      _metric('waste_loss', 'Recorded waste loss', _sum(e.get('waste'), 'cost_loss'), explanation: 'Includes cooked loss already included in consumed cost; never subtract it twice.', previous: _sum(e.get('previous_waste'), 'cost_loss')),
      _metric('purchase_spend', 'Recorded Mandi purchase spend', _sum(e.get('purchases'), 'total_cost'), explanation: 'Inventory acquisition spend; not sales COGS.'),
      _metric('cogs', 'Historical realized COGS', cogs, explanation: policy, unavailable: !complete, unavailableQuality: AnalyticsQuality.missing),
      _metric('food_cogs', 'Historical food COGS', foodCogs, explanation: 'Realized food component of COGS from event-time acquisition rates; original returns subtract cost.', unavailable: !complete, unavailableQuality: AnalyticsQuality.missing),
      _metric('packaging_cogs', 'Historical packaging COGS', packagingCogs, explanation: 'Realized packaging component of COGS from event-time acquisition rates; original returns subtract cost.', unavailable: !complete, unavailableQuality: AnalyticsQuality.missing),
      _metric('unclassified_cogs', 'Legacy unclassified COGS', unclassifiedCogs, explanation: 'Pre-upgrade cost events without recorded food/packaging classification. Not retroactively classified.', unavailable: !complete, unavailableQuality: AnalyticsQuality.missing),
      _metric('food_cogs_dine_in', 'Dine-In food COGS', foodByDining['DINE_IN'] ?? 0, explanation: 'Realized food COGS for Dine-In orders.', unavailable: !complete, unavailableQuality: AnalyticsQuality.missing),
      _metric('packaging_cogs_dine_in', 'Dine-In packaging COGS', packagingByDining['DINE_IN'] ?? 0, explanation: 'Realized packaging COGS for Dine-In orders.', unavailable: !complete, unavailableQuality: AnalyticsQuality.missing),
      _metric('food_cogs_takeaway', 'Takeaway food COGS', foodByDining['TAKEAWAY'] ?? 0, explanation: 'Realized food COGS for Takeaway orders.', unavailable: !complete, unavailableQuality: AnalyticsQuality.missing),
      _metric('packaging_cogs_takeaway', 'Takeaway packaging COGS', packagingByDining['TAKEAWAY'] ?? 0, explanation: 'Realized packaging COGS for Takeaway orders.', unavailable: !complete, unavailableQuality: AnalyticsQuality.missing),
      _metric('food_cogs_delivery', 'Delivery food COGS', foodByDining['DELIVERY'] ?? 0, explanation: 'Realized food COGS for Delivery orders.', unavailable: !complete, unavailableQuality: AnalyticsQuality.missing),
      _metric('packaging_cogs_delivery', 'Delivery packaging COGS', packagingByDining['DELIVERY'] ?? 0, explanation: 'Realized packaging COGS for Delivery orders.', unavailable: !complete, unavailableQuality: AnalyticsQuality.missing),
      _metric('gross_profit', 'Actual gross profit', gross, explanation: policy, unavailable: !complete, unavailableQuality: AnalyticsQuality.missing),
      _metric('net_profit', 'Recorded net operating result', gross - expenses - labor - rawWaste + variance,
        explanation: 'Gross profit less posted operating expenses, salary accruals and raw waste, plus signed posted count valuation. Posting-period allocation; unposted liabilities and legacy generic drawer outflows are not inferred. Available only for whole Business Days with complete cost evidence.', unavailable: !netAvailable, unavailableQuality: AnalyticsQuality.missing),
      ...payroll.metrics.where((m) => m.id == 'earned_salary'),
      _metric('earned_payroll_net_profit', 'Operating result with earned payroll', gross - expenses - payroll.accrued - rawWaste + variance,
        explanation: 'Alternative to the posting-period result: replaces posted salary accruals with recorded earned-month accruals, never adds both. Other expenses retain posting scope. Whole calendar months in Business Day scope only; no complete historical payroll is inferred.',
        unavailable: !netAvailable || !payroll.supported || e.query.timeBasis != AnalyticsTimeBasis.businessDay,
        unavailableQuality: AnalyticsQuality.missing),
    ], [
      ...payroll.rows,
      ...events.map((c) {
        final rawCls = c['classification'] as String?;
        final cls = (rawCls == null || rawCls.trim().isEmpty) ? 'UNCLASSIFIED' : rawCls.trim().toUpperCase();
        final dining = ordersById[c['order_id']]?['dining_type'] ?? 'UNKNOWN';
        return _row('order_cost_events', c, {
          'kind': c['kind'],
          'order_id': c['order_id'],
          'dining_type': dining,
          'ingredient_id': c['ingredient_id'],
          'classification': cls,
          'revision': c['revision'],
          'quantity': c['quantity'],
          'unit_cost_rupees': c['unit_cost_rupees'],
          'cost_paisa': c['cost_paisa'],
          'source_event_id': c['source_event_id'],
          'created_at': c['recorded_at'],
        });
      }),
      ...e.get('waste').map((w) => _row('kitchen_wastage', w, {'kind': 'Waste evidence', 'ingredient_id': w['raw_ingredient_id'], 'quantity': w['quantity'], 'recorded_loss_paisa': _money(w, 'cost_loss'), 'reason': _safeText(w['reason']), 'created_at': w['created_at']})),
    ], ['kind', 'order_id', 'dining_type', 'ingredient_id', 'classification', 'revision', 'quantity', 'unit_cost_rupees', 'cost_paisa', 'source_event_id', 'recorded_loss_paisa', 'reason', 'created_at'], [...payroll.notes, policy, 'Unknown costs remain null. Current purchase rates never rewrite earlier cost events. No invented pre-upgrade profit.', 'Food and packaging COGS are snapshotted at event time. Legacy pre-classification cost events remain explicit as UNCLASSIFIED and are never retroactively estimated. Realized COGS equals food COGS plus packaging COGS plus any legacy unclassified COGS.', 'Recorded net result uses posting periods; it does not assert that all expenses or earned salary have been entered. Order filters withhold net result because overhead cannot be allocated reliably.']);
  }

  static const _safeConfigKeys = {
    'name', 'code', 'rate_paisa', 'percentage', 'min_order_paisa', 'max_discount_paisa',
    'is_active', 'is_percent', 'active', 'archived', 'database', 'theme', 'printer_name',
    'paper_width', 'tax_rate', 'delivery_fee', 'delivery_fee_paisa', 'currency',
    'business_name', 'address', 'phone', 'ntn', 'strn', 'header', 'footer',
    'backup_path', 'auto_backup', 'retention_days', 'sound_enabled', 'id',
  };

  static String _safeConfigSummary(String? kind, String? beforeJson, String? afterJson) {
    final cleanKind = _safeText(kind ?? 'CONFIG');
    try {
      final before = beforeJson != null ? jsonDecode(beforeJson) : null;
      final after = afterJson != null ? jsonDecode(afterJson) : null;
      final changedKeys = <String>{};
      if (after is Map) {
        for (final k in after.keys) {
          final sk = '$k';
          final lower = sk.toLowerCase();
          if (['pin', 'pin_hash', 'password', 'salt', 'secret', 'token'].any((s) => lower.contains(s))) continue;
          final isSafe = _safeConfigKeys.contains(lower) || RegExp(r'^(key_[a-z0-9_]+)$', caseSensitive: false).hasMatch(sk);
          if (!isSafe) continue;
          if (before is Map) {
            if (before[k] != after[k]) changedKeys.add(sk);
          } else {
            changedKeys.add(sk);
          }
        }
      }
      if (changedKeys.isEmpty) {
        return '$cleanKind settings updated';
      }
      return '$cleanKind updated: ${changedKeys.join(', ')}';
    } catch (_) {
      return '$cleanKind configuration change';
    }
  }

  static String _safeOperationsSummary(String? action, String? detailJson) {
    final cleanAction = _safeText(action ?? 'ACTION');
    try {
      final detail = detailJson != null ? jsonDecode(detailJson) : null;
      if (detail is Map) {
        final safePairs = <String>[];
        for (final entry in detail.entries) {
          final k = '${entry.key}'.toLowerCase();
          if (['pin', 'pin_hash', 'password', 'secret', 'token'].contains(k)) continue;
          if (['category', 'reason', 'amount_paisa', 'due_date', 'shift_id', 'employee_id', 'role', 'department', 'status', 'rate_paisa'].contains(k)) {
            safePairs.add('${entry.key}: ${_safeText(entry.value)}');
          }
        }
        if (safePairs.isNotEmpty) {
          return '$cleanAction (${safePairs.join(', ')})';
        }
      }
      return cleanAction;
    } catch (_) {
      return cleanAction;
    }
  }

  static String _safeBackupSummary(Map<String, Object?> b) {
    final primary = b['primary_status'] ?? 'UNKNOWN';
    final secondary = b['secondary_status'] ?? 'NOT_CONFIGURED';
    final category = b['failure_category'] as String?;
    final message = b['failure_message'] as String?;
    final buf = StringBuffer('Primary: $primary, Secondary: $secondary');
    if (category != null && category != 'NONE') {
      buf.write(' [$category]');
    }
    if (message != null && message.isNotEmpty) {
      buf.write(' - ${_safeText(message)}');
    }
    return buf.toString();
  }

  AnalyticsSection _audit() {
    final configEvents = e.get('configuration_audit');
    final opsEvents = e.get('operations_audit');
    final backupEvents = e.get('backup_attempts');
    final allBackupEvents = e.get('all_backup_attempts');
    final allVerifiedBackups = allBackupEvents.where((b) => b['verification_status'] == 'VERIFIED' && b['primary_status'] == 'SUCCESS').toList();
    final verifiedInInterval = backupEvents.where((b) => b['verification_status'] == 'VERIFIED' && b['primary_status'] == 'SUCCESS').toList();
    final failedInInterval = backupEvents.where((b) => b['primary_status'] == 'FAILED' || b['verification_status'] == 'FAILED').toList();
    final warningsInInterval = backupEvents.where((b) => b['primary_status'] == 'SUCCESS' && (b['secondary_status'] == 'WARNING' || b['secondary_status'] == 'FAILED')).toList();

    double? lastVerifiedAgeMinutes;
    if (allVerifiedBackups.isNotEmpty) {
      final lastTimeStr = allVerifiedBackups.first['attempted_at'] as String?;
      if (lastTimeStr != null) {
        final lastTime = analyticsKarachiTime(lastTimeStr);
        final currentKarachi = analyticsKarachiTime(e.now.toIso8601String()) ?? e.now;
        if (lastTime != null) {
          final diff = currentKarachi.difference(lastTime).inMinutes;
          lastVerifiedAgeMinutes = diff >= 0 ? diff.toDouble() : 0.0;
        }
      }
    }
    final rows = <AnalyticsRow>[
      ...e.get('revisions').map((r) => _row('order_revisions', r, {'kind': 'Order revision', 'order_id': r['order_id'], 'action': r['action'], 'reason': _safeText(r['reason']), 'staff_id': r['cashier_id'], 'delta_paisa': r['money_delta_paisa'], 'created_at': r['created_at_utc']})),
      ...e.get('token_audit').map((a) => _row('checkout_token_audit', a, {'kind': 'Immutable token audit', 'order_id': a['order_id'], 'token': a['token_number'], 'action': a['action'], 'status': a['payment_status'], 'revision': a['revision'], 'created_at': a['recorded_at']})),
      ...e.get('rounding').map((r) => _row('rounding_variance_ledger', r, {'kind': 'Rounding ledger', 'order_id': r['order_id'], 'shift_id': r['shift_id'], 'delta_paisa': r['cash_rounding_paisa'], 'created_at': r['created_at']})),
      ...e.get('reports').map((r) => _row('report_runs', r, {'kind': 'Sealed report', 'business_day_id': r['business_day_id'], 'hash': r['content_hash'], 'revision': 1, 'status': r['status'], 'staff_id': r['created_by'], 'created_at': r['created_at']})),
      ...e.get('outbox').map((r) => _row('report_outbox', r, {'kind': 'Report delivery', 'business_day_id': r['business_day_id'], 'channel': r['channel'], 'status': r['status'], 'attempts': r['retry_count'], 'created_at': r['created_at']})),
      ...e.get('delivery_audit').map((r) => _row('report_delivery_audit', r, {'kind': 'Delivery audit', 'action': r['action'], 'staff_id': r['staff_id'], 'created_at': r['created_at']})),
      ...e.get('stock_alerts').map((a) => AnalyticsRow(id: 'checkout-alert-${a['order_id']}-${a['ingredient_id']}', sourceType: 'checkout_stock_alerts', sourceId: '${a['order_id']}:${a['ingredient_id']}', cells: {'kind': 'Checkout stock alert', 'order_id': a['order_id'], 'ingredient_id': a['ingredient_id'], 'stock_at_checkout': a['stock_at_checkout'], 'created_at': a['created_at']})),
      ...configEvents.map((c) => _row('configuration_audit', c, {
        'kind': 'Configuration audit',
        'action': c['kind'],
        'staff_id': c['actor_id'],
        'reason': _safeConfigSummary(c['kind'] as String?, c['before_json'] as String?, c['after_json'] as String?),
        'created_at': c['created_at'],
      })),
      ...opsEvents.map((o) => _row('operations_audit', o, {
        'kind': 'Operations audit',
        'action': '${o['entity']}:${o['action']}',
        'staff_id': o['manager_id'],
        'reason': _safeOperationsSummary(o['action'] as String?, o['detail'] as String?),
        'created_at': o['created_at'],
      })),
      ...backupEvents.map((b) => _row('backup_attempts', b, {
        'kind': 'Database backup',
        'action': b['initiator'] ?? 'MANUAL',
        'status': b['verification_status'] == 'VERIFIED'
            ? (b['secondary_status'] == 'WARNING' ? 'WARNING' : 'VERIFIED')
            : (b['verification_status'] ?? 'UNKNOWN'),
        'staff_id': b['manager_id'],
        'reason': _safeBackupSummary(b),
        'created_at': b['attempted_at'] ?? b['created_at'],
        'primary_status': b['primary_status'],
        'secondary_status': b['secondary_status'],
        'failure_category': b['failure_category'],
        'primary_path': b['primary_path'],
        'secondary_path': b['secondary_path'],
      })),
    ];
    return _section(AnalyticsFamily.audit, 'Control and audit', [
      _metric('revision_events', 'Revision audit events', e.get('revisions').length, unit: AnalyticsUnit.count, explanation: 'Append-only revision evidence for filtered selected orders.'),
      _metric('token_events', 'Token audit events', e.get('token_audit').length, unit: AnalyticsUnit.count, explanation: 'Immutable allocation/status/revision events for filtered selected orders.'),
      _metric('rounding', 'Rounding variance ledger', _integers(e.get('rounding'), 'cash_rounding_paisa'), explanation: 'Sum signed rounding ledger entries for selected order cohort.'),
      _metric('report_runs', 'Sealed report runs', e.get('reports').length, unit: AnalyticsUnit.count, explanation: 'Stored selected-day report snapshots with original content hash and revision 1.'),
      _metric('failed_exports', 'Report exports awaiting completion', e.get('reports').where((r) => r['status'] != 'READY').length, unit: AnalyticsUnit.count, explanation: 'Selected-day report runs not READY; includes pending/generating rather than claiming all are permanent failures.'),
      _metric('delivery_attention', 'Report delivery requiring attention', e.get('outbox').where((r) => ['FAILED', 'AMBIGUOUS'].contains(r['status'])).length, unit: AnalyticsUnit.count, explanation: 'Selected-day outbox FAILED/AMBIGUOUS records; no recipient, payload, endpoint or credential projection.'),
      _metric('configuration_audit_events', 'Configuration audit events', configEvents.length, unit: AnalyticsUnit.count, explanation: 'Recorded configuration and settings change events within selected interval; safe allowlisted changes projected without raw payloads or secrets.'),
      _metric('operations_audit_events', 'Operations audit events', opsEvents.length, unit: AnalyticsUnit.count, explanation: 'Recorded management operations and finance adjustments within selected interval.'),
      _missing('authentication_event_history', 'Authentication and security event history', 'Login failures, session expirations and PIN reset audit history have no persisted event ledger; configuration and operations audits are projected above.', unit: AnalyticsUnit.count),
      allVerifiedBackups.isEmpty
          ? _missing('backup_history', 'Historical successful backups',
              'No verified backup attempts have been recorded. Configured backup destinations or schedules are not evidence of backup completion.',
              unit: AnalyticsUnit.count)
          : _metric('backup_history', 'Historical successful backups', verifiedInInterval.length,
              unit: AnalyticsUnit.count,
              explanation: 'Durable verified successful backup attempts within selected interval.'),
      _metric('failed_backups', 'Failed backup attempts', failedInInterval.length,
          unit: AnalyticsUnit.count,
          explanation: 'Recorded failed backup attempts within selected interval; failures are preserved and never overwritten.'),
      _metric('backup_secondary_warnings', 'Secondary backup warnings', warningsInInterval.length,
          unit: AnalyticsUnit.count,
          explanation: 'Backup attempts where primary backup succeeded but secondary destination produced a warning or failure.'),
      lastVerifiedAgeMinutes == null
          ? _missing('last_verified_backup_age', 'Last verified backup age',
              'No verified backup has been completed yet; configured settings do not establish backup health.',
              unit: AnalyticsUnit.minutes)
          : _metric('last_verified_backup_age', 'Last verified backup age', lastVerifiedAgeMinutes,
              unit: AnalyticsUnit.minutes,
              explanation: 'Minutes elapsed since the most recent verified successful backup snapshot.'),
    ], rows, ['kind', 'business_day_id', 'order_id', 'shift_id', 'ingredient_id', 'token', 'revision', 'action', 'reason', 'staff_id', 'delta_paisa', 'hash', 'channel', 'status', 'attempts', 'stock_at_checkout', 'created_at'], ['Order revisions/tokens/rounding/checkout alerts use filtered order cohort. Report runs/outbox use whole selected Business Days. Delivery audit uses selected actual intervals.', 'Configuration and operations audits project authorized management actions with safe field allowlisting. Raw JSON, credentials, PIN hashes, passwords and sensitive customer data are strictly excluded. Authentication events (login failures, PIN resets) have no persistent event ledger and remain disclosed as missing.', 'Immutable Z-report provenance is shown; this explorer never rewrites snapshots. Sensitive payloads, errors, recipients, credentials and raw customer contact fields are excluded.']);
  }

  AnalyticsMetric _metric(String id, String label, num value, {
    AnalyticsUnit unit = AnalyticsUnit.paisa,
    String? explanation,
    num? previous,
    bool unavailable = false,
    AnalyticsQuality unavailableQuality = AnalyticsQuality.notApplicable,
    int? sampleCount,
    int? populationCount,
    bool isBalance = false,
  }) {
    final hasComparison = !partial && !unavailable && !isBalance && e.query.comparisonMode != AnalyticsComparisonMode.none && previous != null;
    final difference = hasComparison ? value - previous : null;
    final prior = hasComparison ? previous : null;
    return AnalyticsMetric(
      id: id,
      label: label,
      value: unavailable ? null : value,
      unit: unit,
      explanation: explanation ?? _orderBasis,
      quality: unavailable ? unavailableQuality : AnalyticsQuality.complete,
      sampleCount: sampleCount,
      populationCount: populationCount,
      changeAbsolute: difference,
      changePercent: difference != null && previous != null && previous != 0 ? difference / previous.abs() * 100 : null,
      priorValue: prior,
      isBalance: isBalance,
    );
  }
  static AnalyticsMetric _missing(String id, String label, String explanation, {AnalyticsUnit unit = AnalyticsUnit.paisa}) => AnalyticsMetric(id: id, label: label, unit: unit, explanation: explanation, quality: AnalyticsQuality.missing);
  static AnalyticsMetric _average(String id, String label, num numerator, int count, AnalyticsUnit unit, String explanation) => AnalyticsMetric(id: id, label: label, value: count == 0 ? null : numerator / count, unit: unit, explanation: explanation, quality: count == 0 ? AnalyticsQuality.notApplicable : AnalyticsQuality.complete, sampleCount: count, populationCount: count);
  static AnalyticsMetric _rate(String id, String label, int sample, int population, String explanation, {bool isBalance = false}) => AnalyticsMetric(id: id, label: label, value: population == 0 ? null : sample / population * 100, unit: AnalyticsUnit.percent, explanation: explanation, quality: population == 0 ? AnalyticsQuality.notApplicable : AnalyticsQuality.complete, sampleCount: sample, populationCount: population, isBalance: isBalance);
  static AnalyticsMetric _coverage(String id, String label, int sample, int population, String explanation, {bool isBalance = false}) => AnalyticsMetric(id: id, label: label, value: population == 0 ? null : sample / population * 100, unit: AnalyticsUnit.percent, explanation: explanation, quality: population == 0 ? AnalyticsQuality.notApplicable : sample == population ? AnalyticsQuality.complete : AnalyticsQuality.estimated, sampleCount: sample, populationCount: population, isBalance: isBalance);
  static AnalyticsMetric _duration(String id, String label, double? value, int sample, int population) => AnalyticsMetric(id: id, label: label, value: value, unit: AnalyticsUnit.minutes, explanation: 'Per-order delivered_at minus containing trip dispatched_at in minutes. Missing/reversed timestamps excluded; coverage shown.', quality: value == null ? (population == 0 ? AnalyticsQuality.notApplicable : AnalyticsQuality.missing) : sample < population ? AnalyticsQuality.estimated : AnalyticsQuality.complete, sampleCount: sample, populationCount: population);
  static double? _percentile(List<double> sorted, double p) {
    if (sorted.isEmpty) return null;
    final index = (sorted.length - 1) * p;
    final lower = index.floor();
    final upper = index.ceil();
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - lower);
  }
  AnalyticsSection _section(AnalyticsFamily family, String title, List<AnalyticsMetric> metrics, List<AnalyticsRow> rows, List<String> keys, List<String> notes) {
    const sources = <AnalyticsFamily, List<String>>{
      AnalyticsFamily.sales: ['orders', 'order_payments'],
      AnalyticsFamily.orders: ['orders', 'order_revisions', 'order_payments'],
      AnalyticsFamily.delivery: ['orders', 'rider_trips', 'rider_trip_orders'],
      AnalyticsFamily.customers: ['orders'],
      AnalyticsFamily.menu: ['orders', 'order_items', 'menu_items', 'deals'],
      AnalyticsFamily.inventory: ['raw_ingredients', 'inventory_movements'],
      AnalyticsFamily.procurement: ['mandi_procurements'],
      AnalyticsFamily.suppliers: ['vendor_khata', 'vendor_transactions', 'supplier_payment_allocations'],
      AnalyticsFamily.cash: ['shifts', 'cash_movements', 'order_payments'],
      AnalyticsFamily.expenses: ['cash_movements', 'expense_entries'],
      AnalyticsFamily.staff: ['staff', 'payroll_entries'],
      AnalyticsFamily.profitability: ['orders', 'order_cost_coverage', 'order_cost_events', 'kitchen_wastage', 'expense_entries', 'payroll_entries', 'stock_count_lines'],
      AnalyticsFamily.audit: ['order_revisions', 'checkout_token_audit', 'report_runs', 'report_outbox'],
    };
    final absent = (sources[family] ?? const <String>[]).where(e.absent.contains).toList();
    final safeMetrics = absent.isEmpty ? metrics : metrics.map((m) => AnalyticsMetric(id: m.id, label: m.label, unit: m.unit, explanation: '${m.explanation} Missing source tables: ${absent.join(', ')}.', quality: AnalyticsQuality.missing)).toList();
    return AnalyticsSection(family: family, title: title, metrics: safeMetrics, rows: rows, columns: _columns({...keys, ...rows.expand((row) => row.cells.keys)}.toList()), notes: [...notes, ..._domainScopeNotes(e, family), if (absent.isNotEmpty) 'Missing source tables: ${absent.join(', ')}. Values withheld rather than asserted zero.']);
  }
  static List<AnalyticsColumn> _columns(List<String> keys) => keys.map((key) => AnalyticsColumn(key: key, label: _label(key), unit: key.endsWith('_paisa') ? AnalyticsUnit.paisa : key == 'unit_cost_rupees_per_base_unit' ? AnalyticsUnit.decimal : null)).toList();
  static String _label(String key) => key.replaceAll('_', ' ');
  AnalyticsRow _row(String source, _Record record, Map<String, Object?> cells) {
    final detail = <String, Object?>{...cells};
    final shiftId = source == 'shifts' ? record['id'] : record['shift_id'];
    final shift = [...e.get('shifts'), ...e.get('order_shifts'), ...e.get('event_shifts'), ...e.get('bridge_shifts')].where((s) => s['id'] == shiftId).firstOrNull;
    final dayId = source == 'business_days' ? record['id'] : record['business_day_id'] ?? shift?['business_day_id'];
    final day = [...e.get('days'), ...e.get('order_days'), ...e.get('event_days'), ...e.get('bridge_days')].where((d) => d['id'] == dayId).firstOrNull;
    if (dayId != null) detail['business_day_id'] = dayId;
    if (shiftId != null) detail['shift_id'] = shiftId;
    if (day != null) {
      detail['business_day_start'] = day['opened_at'];
      detail['business_day_end'] = day['closed_at'];
    }
    if (shift != null) {
      detail['shift_start'] = shift['opened_at'];
      detail['shift_end'] = shift['closed_at'];
    }
    void identity(String kind, Object? id, String table, {String? retained}) {
      if (id == null) return;
      final evidence = e.get('identity_snapshots').where((row) => row['source_table'] == source && row['source_id'] == record['id'] && row['identity_kind'] == kind).firstOrNull;
      final directory = table == 'staff' ? 'staff' : table == 'vendor_khata' ? 'vendors' : 'expense_categories';
      final current = e.get(directory).where((row) => row['id'] == id).firstOrNull;
      detail['${kind}_id'] = id;
      detail['${kind}_name_at_transaction'] = _safeText(retained ?? evidence?['name_snapshot'] ?? 'Unavailable historical name');
      detail['${kind}_name_current'] = _safeText(current?['name'] ?? 'Unavailable current name');
    }
    if (shift != null) {
      final retained = e.get('identity_snapshots').where((row) => row['source_table'] == 'shifts' && row['source_id'] == shiftId && row['identity_kind'] == 'shift_owner').firstOrNull;
      identity('shift_owner', shift['staff_id'], 'staff', retained: (record['shift_owner_name_snapshot'] ?? retained?['name_snapshot']) as String?);
    }
    if (source == 'orders') identity('order_cashier', record['cashier_id'], 'staff');
    if (source != 'shifts' && source != 'staff' && source != 'orders') {
      final actor = record['recorded_by'] ?? record['manager_id'] ?? record['staff_id'] ?? record['cashier_id'] ?? record['actor_id'];
      identity('recorded_by', actor, 'staff', retained: record['recorded_by_name_snapshot'] as String?);
      identity('approved_by', record['approved_by'], 'staff');
    }
    identity('supplier', record['vendor_id'], 'vendor_khata');
    identity('employee', record['employee_id'], 'staff');
    if (source == 'expense_entries') identity('category', record['category_id'], 'expense_categories', retained: record['category_snapshot'] as String?);
    // Only source timestamp fields, never derived periods or invented event times.
    for (final key in ['created_at', 'created_at_utc', 'actual_at', 'recorded_at', 'opened_at', 'closed_at', 'dispatched_at', 'settled_at', 'settled_at_utc', 'delivered_at', 'returned_at']) {
      if (record.containsKey(key) && !detail.containsKey(key)) detail[key] = record[key];
    }
    if (source == 'payment_events') {
      detail['event_time'] = record['actual_at'];
      detail['recording_time'] = record['recorded_at'];
    }
    for (final entry in detail.entries.toList()) {
      if (analyticsKarachiTime(entry.value) == null) continue;
      // Restrict conversion to timestamp keys, never date-like names or IDs.
      if (!RegExp(r'(_at|_utc|_time|_start|_end)$').hasMatch(entry.key)) continue;
      detail['${entry.key}_source'] = entry.value;
      detail[entry.key] = analyticsTimestamp(entry.value);
    }
    return AnalyticsRow(id: '$source-${record['id']}', sourceType: source, sourceId: '${record['id']}', cells: detail);
  }
  static Map<String, List<_Record>> _group(List<_Record> rows, String key) {
    final groups = <String, List<_Record>>{};
    for (final row in rows) { groups.putIfAbsent('${row[key] ?? 'Unknown'}', () => []).add(row); }
    return groups;
  }
  static String? _phone(Object? value) {
    if (value is! String) return null;
    var digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0092')) digits = '0${digits.substring(4)}';
    if (digits.startsWith('92')) digits = '0${digits.substring(2)}';
    return digits.length >= 7 && digits.length <= 15 ? digits : null;
  }
  static String _safeText(Object? value) => '${value ?? ''}'.replaceAll(RegExp(r'(?:\+?92[ -]?|0)3\d{2}[ -]?\d{7}'), '[phone masked]');
  static Map<String, Object?>? _jsonMap(Object? raw) {
    if (raw is! String) return null;
    try { final parsed = jsonDecode(raw); return parsed is Map<String, dynamic> ? Map<String, Object?>.from(parsed) : null; } on FormatException { return null; }
  }
  static String _snapshotNames(Object? raw) {
    if (raw is! String) return '';
    try {
      final parsed = jsonDecode(raw);
      if (parsed is List) return parsed.whereType<Map<String, dynamic>>().map((m) => _safeText(m['name'] ?? m['menu_item_name'] ?? m['menu_item_id'] ?? 'Snapshotted selection')).join(', ');
      return 'Snapshot present';
    } on FormatException { return 'Unreadable snapshot'; }
  }
}

class _EvaluatedCommitment {
  _EvaluatedCommitment({
    required this.id,
    required this.vendorId,
    this.ingredientId,
    this.procurementId,
    this.vendorTransactionId,
    this.effectivePromisedAt,
    this.effectiveActualAt,
    this.delayMinutes,
    required this.status,
    required this.amendmentCount,
    required this.recordedAt,
    required this.recordedBy,
    required this.record,
  });
  final int id;
  final int vendorId;
  final int? ingredientId;
  final int? procurementId;
  final int? vendorTransactionId;
  final String? effectivePromisedAt;
  final String? effectiveActualAt;
  final int? delayMinutes;
  final String status;
  final int amendmentCount;
  final String recordedAt;
  final int recordedBy;
  final _Record record;
}

class _ProcurementReceipt {
  _ProcurementReceipt({
    required this.timestamp,
    required this.quantity,
    required this.costPaisa,
  });
  final String timestamp;
  final double quantity;
  final int costPaisa;
}
