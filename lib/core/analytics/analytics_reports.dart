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
    final sections = [_sales(), _orders(), _delivery(), _customers(), _menu(), _inventory(), _procurement(), _suppliers(), _cash(), _expenses(), _staff(), _profitability(), _audit()];
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
    return AnalyticsSnapshot(query: e.query, generatedAt: e.now, generatedByStaffId: e.actor, sourceSchemaVersion: e.sourceSchemaVersion, businessDayIds: {...e.get('days').map((d) => d['id'] as int), ...e.get('order_days').map((d) => d['id'] as int), ...e.get('event_days').map((d) => d['id'] as int)}.toList(), sections: [overview, ...sections], notes: [
      'Analytics formula version 2; PKR; Order time basis: ${e.query.timeBasis.name}; grouping: ${e.query.grouping.name}; Asia/Karachi (UTC+05:00). Start inclusive; end exclusive. Business Day weekday uses assigned opening date; calendar weekday uses actual creation date. Weeks start Monday; months use local calendar months.',
      'Non-order ledgers and drawer reconciliation retain Business Day opening-date scope. Calendar Order activity does not change their scope or Order assignments.',

      'Exploratory view over current committed local records. Immutable sealed Z-reports retain their original content hash and revision.',
      'Legacy REAL rupees are normalized once per source amount through PaisaEngine; integer-paisa columns are preferred. Historical floating-point precision is not restored.',
      _intervalBasis,
      'Source schema version: ${e.sourceSchemaVersion ?? "unavailable"}; snapshot cutoff ${e.now.toIso8601String()}. Event time and immutable recording time are separate where stored. Missing evidence stays unavailable.',
      'Naive legacy timestamps are assumed Asia/Karachi; original values and explicit UTC/offset evidence remain in source details. Historical names are captured only from migration onward; current names are separate context.',
      if (e.query.hasOrderFilters) 'Order filters affect sales/orders/customers/menu, related delivery attempts and order audits. Current inventory/staff/Khata and whole-day cash/procurement/expense totals keep their labeled scope.',
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
      _metric('recorded_value_change', 'Change from preceding window', value - _sum(prior, 'grand_total'), explanation: partial ? 'Unavailable for incomplete open-day coverage.' : 'Absolute current minus preceding equal selected-basis date-window recorded value.', unavailable: partial),
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
    final metrics = <AnalyticsMetric>[
      _metric('committed_orders', 'Committed orders', orders.length, unit: AnalyticsUnit.count, explanation: 'All selected committed orders, including cancellation states; no historical in-memory holds.'),
      _metric('revised_orders', 'Orders revised', revisedIds.length, unit: AnalyticsUnit.count, explanation: 'Distinct selected order IDs with append-only revision evidence.'),
      _metric('revision_events', 'Revision events', revisions.length, unit: AnalyticsUnit.count, explanation: 'Revision events, separate from distinct revised order count.'),
      _metric('revision_delta', 'Revision price delta', _integers(revisions, 'money_delta_paisa'), explanation: 'Sum append-only revision money deltas for selected order cohort; event dates may differ.'),
      _metric('cancelled_orders', 'Cancelled/refunded orders', cancelled.length, unit: AnalyticsUnit.count, explanation: 'Distinct selected orders with CANCEL event or current cancelled/voided/refunded state.'),
      _rate('cancel_rate', 'Cancel/refund rate', cancelled.length, orders.length, 'Distinct cancelled/refunded orders / all committed selected orders; refunded states included.'),
      _metric('refunds', 'Explicit refunds', -_sum(refunds, 'amount_tendered'), explanation: 'Negative payment records only; cancellation does not itself disburse cash.'),
      _metric('refund_exposure', 'Retained funds above current payable', exposure, explanation: 'Per order max(0, net collected - current payable), using zero payable for cancelled/refunded orders. This is exposure, not a completed refund.'),
      _missing('prep_time', 'Preparation time', 'No persisted confirmed/preparing/ready lifecycle timestamps. Current state cannot establish historical durations.', unit: AnalyticsUnit.minutes),
      _missing('held_history', 'Historical holds', 'Holds are in memory and cannot be reconstructed as historical records.', unit: AnalyticsUnit.count),
    ];
    for (final key in ['payment_status', 'token_status']) {
      for (final group in _group(orders, key).entries) {
        metrics.add(_metric('${key}_${group.key}', '${_label(key)}: ${group.key}', group.value.length, unit: AnalyticsUnit.count, explanation: 'Committed selected order count by current stored state.'));
      }
    }
    return _section(AnalyticsFamily.orders, 'Order operations', metrics, [
      ..._OrderWorkload(this).build(),
      ...orders.map((o) => _row('orders', o, {'order_id': o['id'], 'business_day_id': o['business_day_id'], 'cashier_id': o['cashier_id'], 'shift_id': o['shift_id'], 'token': o['token_number'], 'dining_type': o['dining_type'], 'payment_status': o['payment_status'], 'token_status': o['token_status'], 'recorded_value_paisa': _money(o, 'grand_total'), 'collection_due_paisa': o['payment_status'] == 'COLLECTION_DUE' ? o['collection_due_paisa'] : 0, 'created_at': o['created_at'], 'assigned_business_date': _karachi(daysById[o['business_day_id']]?['opened_at']) == null ? null : _sqlDate(_karachi(daysById[o['business_day_id']]!['opened_at'])!)})),
      ...revisions.map((r) => _row('order_revisions', r, {'order_id': r['order_id'], 'revision': r['revision_no'], 'action': r['action'], 'reason': _safeText(r['reason']), 'cashier_id': r['cashier_id'], 'delta_paisa': r['money_delta_paisa'], 'created_at': r['created_at_utc']})),
    ], ['order_id', 'business_day_id', 'assigned_business_date', 'token', 'cashier_id', 'shift_id', 'dining_type', 'payment_status', 'token_status', 'recorded_value_paisa', 'collection_due_paisa', 'action', 'revision', 'delta_paisa', 'reason', 'created_at'], [_orderBasis, 'Workload counts every confirmed Order once, including cancellations and refunds. Holds and revisions add no Orders. Daily and hourly rows are independent projections; never add them together. Rankings use count and eligible value independently; rank 1 includes every tie, shown chronologically. Hourly buckets are actual Asia/Karachi creation clock hours across the selected cohort, not a promise of trading in every hour. Observed cohort zeros differ from unavailable source/time evidence. Calendar dates without Orders or observed Business Days are not invented. Daily workload stays daily regardless of Sales grouping.', 'Order and revision source rows are separate kinds. Their counts/amounts must not be added together.']);
  }

  AnalyticsSection _delivery() {
    final deliveredOrders = valid.where((o) => o['dining_type'] == 'DELIVERY').toList();
    final attempts = e.get('attempts');
    final delivered = attempts.where((a) => a['status'] == 'DELIVERED').toList();
    final returned = attempts.where((a) => a['status'] == 'RETURNED').toList();
    final times = <double>[];
    for (final a in delivered) {
      final dispatch = _karachi(a['dispatched_at']);
      final end = _karachi(a['delivered_at']);
      if (dispatch != null && end != null && !end.isBefore(dispatch)) times.add(end.difference(dispatch).inSeconds / 60);
    }
    times.sort();
    final trips = e.get('trips');
    final due = _integers(valid.where((o) => o['payment_status'] == 'COLLECTION_DUE'), 'collection_due_paisa');
    final metrics = <AnalyticsMetric>[
      _metric('delivery_orders', 'Delivery orders', deliveredOrders.length, unit: AnalyticsUnit.count, explanation: 'Eligible DELIVERY orders in filtered order cohort.'),
      _metric('delivery_fees', 'Recorded delivery fees', _integers(deliveredOrders, 'delivery_fee_paisa'), explanation: 'Eligible filtered delivery order fee snapshots.'),
      _metric('collection_due', 'Collection Due (selected cohort)', due, explanation: 'Remaining payable less net tenders for current COLLECTION_DUE eligible orders within the selected cohort; delivery does not imply collection.'),
      _metric('all_collection_due', 'Collection Due (all outstanding)', _integers(e.get('all_due'), 'collection_due_paisa'), explanation: 'Current installation-wide COLLECTION_DUE orders across all Business Days; date/order filters do not apply.'),
      _metric('trips', 'Trips (whole selected days)', trips.length, unit: AnalyticsUnit.count, explanation: _globalBasis),
      _metric('unsettled_exposure', 'Unsettled expected COD (selected days)', _integers(trips.where((t) => ['DISPATCHED', 'RETURNED'].contains(t['status'])), 'cash_expected_paisa'), explanation: 'Expected COD in unsettled trips selected by trip Business Day, all orders. Exposure is not proof of customer collection or rider debt.'),
      _metric('all_unsettled_exposure', 'Unsettled expected COD (all outstanding)', _integers(e.get('all_trips'), 'cash_expected_paisa'), explanation: 'Current global expected COD for DISPATCHED/RETURNED trips; not verified cash collected.'),
      _metric('delivered_attempts', 'Delivered attempts', delivered.length, unit: AnalyticsUnit.count, explanation: 'Filtered order delivery-attempt rows with DELIVERED status.'),
      _metric('returned_attempts', 'Returned attempts', returned.length, unit: AnalyticsUnit.count, explanation: 'Filtered returned attempts, not final failed orders; later redelivery may succeed.'),
      _rate('returned_attempt_rate', 'Returned-attempt rate', returned.length, attempts.length, 'Returned attempt rows / dispatched attempt rows in selected filtered order cohort; not final failure rate.'),
      _duration('travel_mean', 'Mean travel time', times.isEmpty ? null : times.reduce((a, b) => a + b) / times.length, times.length, delivered.length),
      _duration('travel_median', 'Median travel time', _percentile(times, .5), times.length, delivered.length),
      _duration('travel_p90', '90th percentile travel', _percentile(times, .9), times.length, delivered.length),
      _missing('rider_verified_debt', 'Verified rider cash debt', 'Expected COD does not establish actual customer collection. No separate confirmed-collected-but-unremitted ledger exists.'),
    ];
    for (final group in _group(deliveredOrders, 'delivery_area_name_snapshot').entries) {
      metrics.add(_metric('area_${group.key}', '${group.key} delivery orders', group.value.length, unit: AnalyticsUnit.count, explanation: 'Eligible filtered order count by transaction-time area snapshot.'));
    }
    return _section(AnalyticsFamily.delivery, 'Delivery and riders', metrics, [
      ..._receivingEventRows(_receivingEvents().where((p) => p['settlement_id'] != null)),
      ...deliveredOrders.map((o) => _row('orders', o, {'order_id': o['id'], 'area': o['delivery_area_name_snapshot'] ?? 'Unknown area', 'fee_paisa': o['delivery_fee_paisa'], 'payment_status': o['payment_status']})),
      ...trips.map((t) => _row('rider_trips', t, {'trip_id': t['id'], 'rider_id': t['rider_staff_id'], 'shift_id': t['shift_id'], 'status': t['status'], 'selected_order_load': attempts.where((a) => a['trip_id'] == t['id']).length, 'expected_paisa': t['cash_expected_paisa'], 'counted_paisa': t['cash_collected_paisa'], 'dispatched_at': t['dispatched_at'], 'settled_at': t['settled_at_utc']})),
      ...attempts.map((a) => _row('rider_trip_orders', a, {'order_id': a['order_id'], 'trip_id': a['trip_id'], 'rider_id': a['rider_staff_id'], 'status': a['status'], 'dispatched_at': a['dispatched_at'], 'delivered_at': a['delivered_at'], 'returned_at': a['returned_at']})),
    ], ['order_id', 'trip_id', 'rider_id', 'shift_id', 'selected_order_load', 'area', 'fee_paisa', 'payment_status', 'status', 'expected_paisa', 'counted_paisa', 'dispatched_at', 'delivered_at', 'returned_at', 'settled_at'], ['Order/attempt rows and selected-order load use order filters; trip rows and trip exposure use whole selected Business Days. All-outstanding measures explicitly ignore date/order filters.', 'Settlement event rows use receiving Shift/Business Day or actual calendar time, independently of the originating Order cohort. Counted handover is one linked custody transfer; COD settlement value is not verified customer collection. Legacy settled trips without events have unavailable receiving Shift, actors and immutable recording time. Do not sum settlement attribution, digital receipt and counted pouch rows.', 'Travel excludes invalid/missing timestamps and reports coverage. Percentiles interpolate sorted valid minutes. No final failure/reattempt or unrecorded failure-reason inference.']);
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
    final rows = <AnalyticsRow>[];
    for (final entry in groups.entries) {
      final customer = 'Customer •••${entry.key.substring(entry.key.length - 4)}';
      final value = _sum(entry.value, 'grand_total');
      rows.add(AnalyticsRow(id: 'customer-${entry.value.first['id']}', sourceType: 'orders',
        sourceId: entry.value.map((order) => order['id']).join(','), cells: {
          'kind': 'Customer aggregate', 'customer': customer, 'orders_in_range': entry.value.length,
          'recorded_value_paisa': value, 'average_ticket_paisa': value / entry.value.length,
        }));
      rows.addAll(entry.value.map((order) => _row('orders', order, {
        'kind': 'Order history', 'customer': customer, 'order_id': order['id'],
        'orders_in_range': entry.value.length, 'recorded_value_paisa': _money(order, 'grand_total'),
        'area': order['delivery_area_name_snapshot'], 'created_at': order['created_at'],
      })));
    }
    return _section(AnalyticsFamily.customers, 'Customers', [
      _metric('known_customers', 'Known phone identities', groups.length, unit: AnalyticsUnit.count, explanation: 'Distinct normalized known phone proxies in eligible filtered orders; not guaranteed distinct people.'),
      _metric('known_orders', 'Orders with known phone', knownOrders, unit: AnalyticsUnit.count, explanation: 'Eligible filtered orders with usable normalized phone identity.'),
      _average('known_customer_average_ticket', 'Known-customer average ticket', knownValue, knownOrders,
        AnalyticsUnit.paisa, 'Recorded eligible known-phone order value / eligible known-phone order count. Guests and cancelled/voided/refunded orders excluded; includes Collection Due. Denominator shown; this is order-weighted, not an average of customer means.'),
      _metric('guest_orders', 'Guest/unknown orders', valid.length - knownOrders, unit: AnalyticsUnit.count, explanation: 'Eligible orders without usable known phone; excluded from repeat denominator.'),
      _rate('identity_coverage', 'Known identity coverage', knownOrders, valid.length, 'Known phone orders / eligible filtered orders.'),
      _rate('repeat_rate', 'Repeat-customer rate', repeat, groups.length, 'Known normalized phone proxies with at least two eligible selected orders / proxies with at least one. Guests excluded.'),
      _metric('single_order_customers', 'Single-order phone identities', groups.length - repeat, unit: AnalyticsUnit.count, explanation: 'One eligible order within selected range; cannot be called a new lifetime customer.'),
    ], rows, ['kind', 'customer', 'order_id', 'orders_in_range', 'recorded_value_paisa', 'average_ticket_paisa', 'area', 'created_at'], [
      _orderBasis,
      'Phone normalization removes separators and unifies +92/0092/92 mobile prefixes with local 0. Shared numbers and masked suffix collisions are possible. Raw phones, names and addresses are excluded.',
      'Customer aggregate rows show each known identity’s eligible recorded value / its eligible order count, with all contributing order source IDs. Order history rows are a separate view; do not sum these different row kinds together. No known orders makes average ticket Not applicable.',
    ]);
  }

  AnalyticsSection _menu() {
    final items = soldItems;
    final rows = <AnalyticsRow>[];
    final sold = <String>{};
    final groups = <String, List<_Record>>{};
    for (final item in items) {
      final type = item['deal_id'] != null ? 'deal' : 'item';
      // Deleted catalog IDs can become NULL. Preserve their snapshotted names
      // rather than merging every archived item into one anonymous product.
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
      rows.add(AnalyticsRow(id: 'menu-${entry.key}', sourceType: 'order_items', sourceId: entry.value.map((i) => i['id']).join(','), cells: {
        'kind': 'Item/deal aggregate',
        'catalog_kind': first['deal_id'] != null ? 'deal' : 'item',
        'catalog_id': first['deal_id'] ?? first['menu_item_id'],
        'name': entry.value.map((i) => _safeText(i['name'])).toSet().join(' / '),
        'quantity': quantity,
        'order_count': entry.value.map((i) => i['order_id']).toSet().length,
        'line_value_paisa': _sum(entry.value, 'total_price'),
        'popularity_rank': rank,
        'modifiers': entry.value.map((i) => _snapshotNames(i['modifiers_json'])).where((name) => name.isNotEmpty).toSet().join(' / '),
        'choices': entry.value.map((i) => _snapshotNames(i['deal_choices_json'])).where((name) => name.isNotEmpty).toSet().join(' / '),
      }));
    }
    var zeroSellers = 0;
    for (final type in ['catalog', 'deals']) {
      for (final item in e.get(type)) {
        if (item['is_active'] != 1 || sold.contains('${type == 'deals' ? 'deal' : 'item'}:${item['id']}')) continue;
        zeroSellers++;
        rows.add(_row(type == 'deals' ? 'deals' : 'menu_items', item, {'kind': 'Current active zero seller', 'catalog_kind': type == 'deals' ? 'deal' : 'item', 'catalog_id': item['id'], 'name': _safeText(item['name']), 'quantity': 0, 'order_count': 0, 'line_value_paisa': 0, 'status': 'Zero recorded sales in selected cohort'}));
      }
    }
    final discounted = valid.where((o) => _money(o, 'discount_amount') > 0).length;
    return _section(AnalyticsFamily.menu, 'Menu and deals', [
      _metric('quantity', 'Recorded sold quantity', _integers(items, 'quantity'), unit: AnalyticsUnit.count, explanation: 'Sum current valid order line quantity, including deal counts; deal components are not separate sold lines.'),
      _metric('line_value', 'Recorded line value', _sum(items, 'total_price'), explanation: 'Stored eligible line totals before order-level discount/tax/fee allocation; not item net revenue.'),
      _metric('zero_sellers', 'Active zero sellers', zeroSellers, unit: AnalyticsUnit.count, explanation: 'Current active menu/deal entries with no matching eligible line in filtered range; catalog history incomplete.'),
      _rate('discount_use', 'Discount utilization', discounted, valid.length, 'Eligible selected orders with a positive stored discount / eligible orders.'),
      _average('quantity_per_order', 'Mean line quantity per order', _integers(items, 'quantity'), valid.length, AnalyticsUnit.decimal, 'Recorded eligible line quantity / eligible order count.'),
      _missing('item_net_sales', 'Allocated item net sales', 'Order discount/tax/delivery allocation is not persisted; stored line value must not be mislabeled net sales.'),
      _missing('item_margin', 'Historical item margin', 'BOM quantity snapshots have no event-time ingredient cost layers.'),
    ], rows, ['kind', 'catalog_kind', 'catalog_id', 'name', 'quantity', 'order_count', 'line_value_paisa', 'popularity_rank', 'modifiers', 'choices', 'status'], [_orderBasis, 'Item/deal aggregate quantity and stored line value combine all eligible lines by catalog identity; order_count is distinct contributing orders. Popularity rank uses quantity descending with equal ranks for ties. Each aggregate retains every contributing order_item source ID.', 'Ascending quantity identifies slow sellers; zero sellers refer to current active catalog. Snapshotted modifier/choice names are source evidence, not inferred upsell profitability.']);
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
    return _section(AnalyticsFamily.inventory, 'Inventory', [
      _metric('ingredients', 'Current ingredients', ingredients.length, unit: AnalyticsUnit.count, explanation: _currentBasis),
      _metric('reconciled_ingredients', 'Reconciled stock bridges', reconciledIngredientsCount, unit: AnalyticsUnit.count, explanation: 'Ingredients whose opening + receipts - consumption - waste + returns + adjustments exactly equals ending quantity.'),
      _coverage('opening_evidence_coverage', 'Opening balance evidence coverage', openingEvidenceCount, ingredients.length, 'Ingredients with verified prior movement balance_after evidence. Missing opening evidence is disclosed rather than assumed zero.'),
      _metric('missing_opening_count', 'Missing opening balance evidence', missingOpeningCount, unit: AnalyticsUnit.count, explanation: 'Tracked ingredients lacking verified pre-interval balance evidence.'),
      _metric('low_stock', 'Current low stock', low, unit: AnalyticsUnit.count, explanation: 'Current quantity <= configured threshold in each ingredient base unit. $_currentBasis'),
      _metric('negative_stock', 'Current negative stock', negative, unit: AnalyticsUnit.count, explanation: 'Current quantity < 0; sales never blocked. $_currentBasis'),
      _rate('low_stock_share', 'Current low-stock share', low, ingredients.length, 'Low-stock ingredient count / current tracked ingredients. $_currentBasis'),
      _metric('movement_count', 'Recorded movements', e.get('inventory').length, unit: AnalyticsUnit.count, explanation: 'Movement rows attributed by Business Day FK since v14 capture; no fabricated pre-upgrade history.'),
      _coverage('as_of_coverage', 'As-of balance evidence coverage', balances.length, ingredients.length, 'Latest recorded balance_after no later than last selected close/refresh. No evidence means unknown, not opening balance zero.'),
      _coverage('bom_coverage', 'Sold-line BOM quantity coverage', bomCovered, soldItems.length, 'Valid sold lines with readable quantity snapshot. Quantity evidence is not event-time costing.'),
      _missing('stock_valuation', 'Historical stock valuation', 'No historical cost layers. Current unit cost cannot rewrite past valuation.'),
      _metric('physical_variance', 'Posted physical count lines', e.get('physical_counts').length, unit: AnalyticsUnit.count, explanation: 'Posted observations in selected Business Day intervals. Inspect per-ingredient variances below; incompatible units are never totaled.'),
      _metric('physical_variance_cost', 'Estimated physical variance value', _integers(e.get('physical_counts'), 'estimated_cost_paisa'), explanation: 'Signed event-time count estimates; unknown rates prevent a complete total.', unavailable: e.get('physical_counts').any((c) => c['estimated_cost_paisa'] == null)),
    ], rows, [
      'kind', 'ingredient_id', 'name', 'unit', 'opening_qty', 'receipts_qty', 'consumption_qty', 'waste_qty',
      'returns_qty', 'adjustments_qty', 'unexplained_variance', 'ending_qty', 'reconciliation_status',
      'current_stock', 'threshold', 'has_opening_evidence', 'balance_evidence_at', 'recorded_cost_rate',
      'as_of_balance', 'quantity_delta', 'balance_after', 'quantity', 'spend_paisa', 'loss_paisa', 'count_id',
      'expected', 'counted', 'variance', 'estimated_cost_paisa', 'recorded_estimated_cost_paisa',
      'valuation_policy', 'movement_id', 'snapshot_sequence', 'created_by', 'approved_by', 'posted_by',
      'reason', 'status', 'recorded_at'
    ], [
      'Normalized stock bridges reconcile in each ingredient\'s base unit (g, ml, count); never sum quantities across different unit dimensions.',
      'Opening plus receipts minus consumption minus waste plus returns plus adjustments equals ending quantity without double counting.',
      'Recorded unit cost rates represent historical master-data rate evidence; they are described separately from stock valuation.',
      'Missing opening balance evidence is disclosed rather than backfilled as zero.',
      _currentBasis,
      'Movement/BOM/waste rows have separate scopes. Never sum quantities across grams, liters or count units.',
      'Movement history begins with v14 capture; posted physical counts retain observation, approval and movement evidence. A zero-variance count has no adjusting movement. As-of is recorded balance evidence, not an invented beginning balance.',
    ]);
  }

  AnalyticsSection _procurement() {
    final purchases = e.get('purchases');
    return _section(AnalyticsFamily.procurement, 'Procurement', [
      _metric('purchase_spend', 'Recorded Mandi purchase spend', _sum(purchases, 'total_cost'), explanation: 'Mandi purchase records only; unlinked supplier credit deliveries are separate and not blindly added. $_intervalBasis', previous: _sum(e.get('previous_purchases'), 'total_cost')),
      _metric('purchase_count', 'Recorded purchases', purchases.length, unit: AnalyticsUnit.count, explanation: 'Mandi purchase rows in selected actual day intervals.', previous: e.get('previous_purchases').length),
      _metric('purchased_ingredients', 'Distinct purchased ingredients', purchases.map((p) => p['raw_ingredient_id']).toSet().length, unit: AnalyticsUnit.count, explanation: 'Distinct ingredient IDs in selected Mandi purchase records.'),
      _missing('supplier_performance', 'Supplier delivery performance', 'Mandi purchase records lack supplier link and promised/actual delivery performance timestamps.', unit: AnalyticsUnit.percent),
    ], purchases.map((p) => _row('mandi_procurements', p, {'ingredient_id': p['raw_ingredient_id'], 'purchase_unit': p['traditional_unit'], 'purchase_quantity': p['quantity'], 'base_quantity': p['converted_quantity'], 'spend_paisa': _money(p, 'total_cost'), 'unit_cost_rupees_per_base_unit': p['cost_per_recipe_unit'], 'created_at': p['created_at']})).toList(), ['ingredient_id', 'purchase_unit', 'purchase_quantity', 'base_quantity', 'spend_paisa', 'unit_cost_rupees_per_base_unit', 'created_at'], [_intervalBasis, _globalBasis, 'Per-ingredient unit rates retain their recorded decimal PKR/base-unit precision (a rate, not a rounded monetary amount). Different base-unit dimensions must not be totaled. Purchase spend is not sales COGS.']);
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
      _metric('khata_opening_payable', 'Vendor Khata opening payable', totalOpeningPayable, unit: AnalyticsUnit.paisa, explanation: 'Historical payable at start of selected interval based on pre-period evidence.'),
      _metric('credit_purchases', 'Recorded credit deliveries', totalPurchasesInRange, unit: AnalyticsUnit.paisa, explanation: 'Credit purchases in selected interval affecting stock/payable; not cash payments. $_intervalBasis'),
      _metric('khata_payments', 'Recorded supplier payments', totalPaymentsInRange, unit: AnalyticsUnit.paisa, explanation: 'Selected interval supplier settlements from cash drawer and external management accounts.'),
      _metric('khata_adjustments', 'Opening balance adjustments', totalAdjsInRange, unit: AnalyticsUnit.paisa, explanation: 'Net versioned opening balance adjustments in selected interval.'),
      _metric('khata_closing_payable', 'Vendor Khata closing payable', totalClosingPayable, unit: AnalyticsUnit.paisa, explanation: 'Opening + purchases + adjustments - payments reconciled at disclosed cutoff.'),
      _metric('aging_current', 'Current (not yet due) payable', totalCurrent, unit: AnalyticsUnit.paisa, explanation: 'Invoiced payable with due date strictly after disclosed cutoff date.'),
      _metric('aging_0_7', 'Payable overdue 0–7 days', totalDays0to7, unit: AnalyticsUnit.paisa, explanation: 'Invoiced payable 0 to 7 days past due date (including due today at cutoff).'),
      _metric('aging_8_30', 'Payable overdue 8–30 days', totalDays8to30, unit: AnalyticsUnit.paisa, explanation: 'Invoiced payable 8 to 30 days past due date as of cutoff.'),
      _metric('aging_31_60', 'Payable overdue 31–60 days', totalDays31to60, unit: AnalyticsUnit.paisa, explanation: 'Invoiced payable 31 to 60 days past due date as of cutoff.'),
      _metric('aging_over_60', 'Payable overdue over 60 days', totalOver60, unit: AnalyticsUnit.paisa, explanation: 'Invoiced payable more than 60 days past due date as of cutoff.'),
      _metric('aging_unknown', 'Payable with unknown due date', totalUnknownDue, unit: AnalyticsUnit.paisa, explanation: 'Undated invoices and unallocated opening balances without explicit due dates.'),
      _coverage('supplier_coverage', 'Active and archived supplier coverage', activeCount, vendors.length, 'Active suppliers vs total registered suppliers including archived historical vendors.'),
      _coverage('invoice_due_date_coverage', 'Invoice due-date coverage', datedInvoiceCount, totalInvoicesCount, 'Invoices with recorded due dates vs total credit invoices up to cutoff.'),
      _metric('current_payable', 'Current supplier payable', _sum(vendors, 'current_balance'), explanation: 'Stored current balances across existing suppliers. $_currentBasis'),
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
      if (!['RECEIPT', 'REFUND', 'RIDER_HANDOVER', 'COD_SETTLEMENT'].contains(p['kind'])) return false;
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
        'kind': p['kind'] == 'RIDER_HANDOVER' ? 'Counted rider custody transfer' : p['kind'] == 'COD_SETTLEMENT' ? 'Order settlement attribution (not collected cash)' : 'Independent customer money event', 'event_kind': p['kind'],
        'event_key': p['event_key'], 'amount_paisa': p['amount_paisa'],
        'payment_source': p['payment_source'], 'payment_method': p['payment_method'],
        'actual_at': p['actual_at'], 'recorded_at': p['recorded_at'],
        'receiving_business_day_id': p['business_day_id'], 'receiving_shift_id': p['shift_id'],
        'business_day_id': p['business_day_id'], 'shift_id': p['shift_id'],
        'originating_business_day_id': p['originating_business_day_id'], 'originating_shift_id': p['originating_shift_id'],
        'order_id': p['order_id'], 'tender_id': p['tender_id'], 'movement_id': p['movement_id'],
        'settlement_id': p['settlement_id'], 'trip_id': p['settlement_id'],
        if (p['settlement_id'] != null) 'customer_collection_evidence': 'Customer-to-rider collection evidence unavailable; delivery and expected pouch are insufficient proof',
        if (p['kind'] == 'COD_SETTLEMENT') 'value_basis': 'Remaining contractual Order settlement, not allocated physical pouch cash',
        'recorded_by': p['recorded_by'], 'approved_by': p['approved_by'],
        'recorded_by_name_snapshot': p['recorded_by_name_snapshot'], 'shift_owner_name_snapshot': p['shift_owner_name_snapshot'],
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
      [...finance.notes, _globalBasis, 'Expense entries retain category snapshots. Cash movements reconcile physical funds and must not be added to expense entries. Legacy outflows are not inferred expenses.']);
  }

  AnalyticsSection _staff() {
    final staff = e.get('staff');
    return _section(AnalyticsFamily.staff, 'Staff and payroll', [
      _metric('staff_count', 'Current staff', staff.length, unit: AnalyticsUnit.count, explanation: _currentBasis),
      _metric('active_staff', 'Current active staff', staff.where((s) => s['is_active'] == 1).length, unit: AnalyticsUnit.count, explanation: _currentBasis),
      _metric('login_enabled', 'Current login-enabled staff', staff.where((s) => s['login_enabled'] == 1).length, unit: AnalyticsUnit.count, explanation: _currentBasis),
      _metric('departments', 'Assigned departments', staff.map((s) => s['department_id']).toSet().length, unit: AnalyticsUnit.count, explanation: 'Distinct current assigned department IDs, not labor-cost allocations.'),
      _metric('job_roles', 'Assigned job roles', staff.where((s) => s['job_role_id'] != null).map((s) => s['job_role_id']).toSet().length, unit: AnalyticsUnit.count, explanation: 'Distinct current assigned job-role IDs.'),
      e.get('payroll_balances').isEmpty ? _missing('salary_due', 'Current recorded salary due', 'No payroll has been posted; legacy staff salary liabilities are unknown.') : _metric('salary_due', 'Current recorded salary due', _integers(e.get('payroll_balances'), 'payable_paisa') - _integers(e.get('payroll_balances'), 'advance_paisa'), explanation: 'Current accrued payable less outstanding advances. No unposted salary is inferred.'),
      _metric('labor_cost', 'Posted salary accruals', e.get('payroll_entries').fold<int>(0, (sum, p) => sum + (p['kind']=='ACCRUAL' || (p['kind']=='REVERSAL' && p['source']=='NONE' && p['advance_delta_paisa']==0) ? p['payable_delta_paisa'] as int : 0)), explanation: 'Salary accruals and their reversals posted in selected day intervals. Payments and advances never count as another expense; earned-period profit allocation remains separate.'),
      _missing('labor_productivity', 'Orders per labor hour', 'Cashier shift duration is not paid attendance or worked labor-hour evidence.', unit: AnalyticsUnit.decimal),
    ], staff.map((s) => _row('staff', s, {'staff_id': s['id'], 'name': _safeText(s['name']), 'department': s['department'], 'job_role': s['job_role'], 'role': s['role'], 'active': s['is_active'] == 1 ? 'Active' : 'Inactive', 'login': s['login_enabled'] == 1 ? 'Enabled' : 'Disabled', 'selected_orders': orders.where((o) => o['cashier_id'] == s['id']).length, 'selected_shifts': e.get('shifts').where((sh) => sh['staff_id'] == s['id']).length})).toList(), ['staff_id', 'name', 'department', 'job_role', 'role', 'active', 'login', 'selected_orders', 'selected_shifts'], [_currentBasis, 'Order activity uses selected order filters; shift activity is whole selected Business Days. Current role/department names are not historical snapshots. PIN hashes and credentials are never projected.']);
  }

  AnalyticsSection _profitability() {
    final coverage = e.get('cost_coverage').map((c) => c['order_id']).toSet();
    final events = e.get('cost_events');
    final covered = orders.where((o) => coverage.contains(o['id'])).length;
    final complete = e.get('days').isNotEmpty && covered == orders.length && events.every((c) => c['cost_paisa'] != null);
    final cogs = events.fold<int>(0, (sum, c) => sum + orderCostSign(c['kind']) * ((c['cost_paisa'] as int?) ?? 0));
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
      _metric('gross_profit', 'Actual gross profit', gross, explanation: policy, unavailable: !complete, unavailableQuality: AnalyticsQuality.missing),
      _metric('net_profit', 'Recorded net operating result', gross - expenses - labor - rawWaste + variance,
        explanation: 'Gross profit less posted operating expenses, salary accruals and raw waste, plus signed posted count valuation. Posting-period allocation; unposted liabilities and legacy generic drawer outflows are not inferred. Available only for whole Business Days with complete cost evidence.', unavailable: !netAvailable, unavailableQuality: AnalyticsQuality.missing),
    ], [
      ...events.map((c) => _row('order_cost_events', c, {'kind': c['kind'], 'order_id': c['order_id'], 'ingredient_id': c['ingredient_id'], 'revision': c['revision'], 'quantity': c['quantity'], 'unit_cost_rupees': c['unit_cost_rupees'], 'cost_paisa': c['cost_paisa'], 'source_event_id': c['source_event_id'], 'created_at': c['recorded_at']})),
      ...e.get('waste').map((w) => _row('kitchen_wastage', w, {'kind': 'Waste evidence', 'ingredient_id': w['raw_ingredient_id'], 'quantity': w['quantity'], 'recorded_loss_paisa': _money(w, 'cost_loss'), 'reason': _safeText(w['reason']), 'created_at': w['created_at']})),
    ], ['kind', 'order_id', 'ingredient_id', 'revision', 'quantity', 'unit_cost_rupees', 'cost_paisa', 'source_event_id', 'recorded_loss_paisa', 'reason', 'created_at'], [policy, 'Unknown costs remain null. Current purchase rates never rewrite earlier cost events. No invented pre-upgrade profit.', 'Recorded net result uses posting periods; it does not assert that all expenses or earned salary have been entered. Order filters withhold net result because overhead cannot be allocated reliably.']);
  }

  AnalyticsSection _audit() {
    final rows = <AnalyticsRow>[
      ...e.get('revisions').map((r) => _row('order_revisions', r, {'kind': 'Order revision', 'order_id': r['order_id'], 'action': r['action'], 'reason': _safeText(r['reason']), 'staff_id': r['cashier_id'], 'delta_paisa': r['money_delta_paisa'], 'created_at': r['created_at_utc']})),
      ...e.get('token_audit').map((a) => _row('checkout_token_audit', a, {'kind': 'Immutable token audit', 'order_id': a['order_id'], 'token': a['token_number'], 'action': a['action'], 'status': a['payment_status'], 'revision': a['revision'], 'created_at': a['recorded_at']})),
      ...e.get('rounding').map((r) => _row('rounding_variance_ledger', r, {'kind': 'Rounding ledger', 'order_id': r['order_id'], 'shift_id': r['shift_id'], 'delta_paisa': r['cash_rounding_paisa'], 'created_at': r['created_at']})),
      ...e.get('reports').map((r) => _row('report_runs', r, {'kind': 'Sealed report', 'business_day_id': r['business_day_id'], 'hash': r['content_hash'], 'revision': 1, 'status': r['status'], 'staff_id': r['created_by'], 'created_at': r['created_at']})),
      ...e.get('outbox').map((r) => _row('report_outbox', r, {'kind': 'Report delivery', 'business_day_id': r['business_day_id'], 'channel': r['channel'], 'status': r['status'], 'attempts': r['retry_count'], 'created_at': r['created_at']})),
      ...e.get('delivery_audit').map((r) => _row('report_delivery_audit', r, {'kind': 'Delivery audit', 'action': r['action'], 'staff_id': r['staff_id'], 'created_at': r['created_at']})),
      ...e.get('stock_alerts').map((a) => AnalyticsRow(id: 'checkout-alert-${a['order_id']}-${a['ingredient_id']}', sourceType: 'checkout_stock_alerts', sourceId: '${a['order_id']}:${a['ingredient_id']}', cells: {'kind': 'Checkout stock alert', 'order_id': a['order_id'], 'ingredient_id': a['ingredient_id'], 'stock_at_checkout': a['stock_at_checkout'], 'created_at': a['created_at']})),
    ];
    return _section(AnalyticsFamily.audit, 'Control and audit', [
      _metric('revision_events', 'Revision audit events', e.get('revisions').length, unit: AnalyticsUnit.count, explanation: 'Append-only revision evidence for filtered selected orders.'),
      _metric('token_events', 'Token audit events', e.get('token_audit').length, unit: AnalyticsUnit.count, explanation: 'Immutable allocation/status/revision events for filtered selected orders.'),
      _metric('rounding', 'Rounding variance ledger', _integers(e.get('rounding'), 'cash_rounding_paisa'), explanation: 'Sum signed rounding ledger entries for selected order cohort.'),
      _metric('report_runs', 'Sealed report runs', e.get('reports').length, unit: AnalyticsUnit.count, explanation: 'Stored selected-day report snapshots with original content hash and revision 1.'),
      _metric('failed_exports', 'Report exports awaiting completion', e.get('reports').where((r) => r['status'] != 'READY').length, unit: AnalyticsUnit.count, explanation: 'Selected-day report runs not READY; includes pending/generating rather than claiming all are permanent failures.'),
      _metric('delivery_attention', 'Report delivery requiring attention', e.get('outbox').where((r) => ['FAILED', 'AMBIGUOUS'].contains(r['status'])).length, unit: AnalyticsUnit.count, explanation: 'Selected-day outbox FAILED/AMBIGUOUS records; no recipient, payload, endpoint or credential projection.'),
      _missing('security_events', 'Security/configuration audit', 'No broad login-failure, PIN-reset/configuration audit event ledger exists.', unit: AnalyticsUnit.count),
      _missing('backup_history', 'Historical successful backups', 'Current settings are not evidence of historical backup success.', unit: AnalyticsUnit.count),
    ], rows, ['kind', 'business_day_id', 'order_id', 'shift_id', 'ingredient_id', 'token', 'revision', 'action', 'reason', 'staff_id', 'delta_paisa', 'hash', 'channel', 'status', 'attempts', 'stock_at_checkout', 'created_at'], ['Order revisions/tokens/rounding/checkout alerts use filtered order cohort. Report runs/outbox use whole selected Business Days. Delivery audit uses selected actual intervals.', 'Immutable Z-report provenance is shown; this explorer never rewrites snapshots. Sensitive payloads, errors, recipients, credentials and raw customer contact fields are excluded.']);
  }

  AnalyticsMetric _metric(String id, String label, num value, {AnalyticsUnit unit = AnalyticsUnit.paisa, String? explanation, num? previous, bool unavailable = false, AnalyticsQuality unavailableQuality = AnalyticsQuality.notApplicable}) {
    final difference = !partial && !unavailable && previous != null ? value - previous : null;
    return AnalyticsMetric(id: id, label: label, value: unavailable ? null : value, unit: unit, explanation: explanation ?? _orderBasis,
      quality: unavailable ? unavailableQuality : AnalyticsQuality.complete,
      changeAbsolute: difference,
      changePercent: difference != null && previous != null && previous != 0 ? difference / previous.abs() * 100 : null);
  }
  static AnalyticsMetric _missing(String id, String label, String explanation, {AnalyticsUnit unit = AnalyticsUnit.paisa}) => AnalyticsMetric(id: id, label: label, unit: unit, explanation: explanation, quality: AnalyticsQuality.missing);
  static AnalyticsMetric _average(String id, String label, num numerator, int count, AnalyticsUnit unit, String explanation) => AnalyticsMetric(id: id, label: label, value: count == 0 ? null : numerator / count, unit: unit, explanation: explanation, quality: count == 0 ? AnalyticsQuality.notApplicable : AnalyticsQuality.complete, sampleCount: count, populationCount: count);
  static AnalyticsMetric _rate(String id, String label, int sample, int population, String explanation) => AnalyticsMetric(id: id, label: label, value: population == 0 ? null : sample / population * 100, unit: AnalyticsUnit.percent, explanation: explanation, quality: population == 0 ? AnalyticsQuality.notApplicable : AnalyticsQuality.complete, sampleCount: sample, populationCount: population);
  static AnalyticsMetric _coverage(String id, String label, int sample, int population, String explanation) => AnalyticsMetric(id: id, label: label, value: population == 0 ? null : sample / population * 100, unit: AnalyticsUnit.percent, explanation: explanation, quality: population == 0 ? AnalyticsQuality.notApplicable : sample == population ? AnalyticsQuality.complete : AnalyticsQuality.estimated, sampleCount: sample, populationCount: population);
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
    return AnalyticsSection(family: family, title: title, metrics: safeMetrics, rows: rows, columns: _columns({...keys, ...rows.expand((row) => row.cells.keys)}.toList()), notes: [...notes, if (absent.isNotEmpty) 'Missing source tables: ${absent.join(', ')}. Values withheld rather than asserted zero.']);
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
      final actor = record['recorded_by'] ?? record['manager_id'] ?? record['staff_id'] ?? record['cashier_id'];
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

