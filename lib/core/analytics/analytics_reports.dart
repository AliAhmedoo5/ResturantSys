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
    ], rows: e.get('days').map((d) => _row('business_days', d, {'business_date': _sqlDate(_karachi(d['opened_at'])!), 'opened_at': d['opened_at'], 'closed_at': d['closed_at'], 'status': d['status']})).toList(), columns: _columns(['business_date', 'opened_at', 'closed_at', 'status']), notes: [
      'Overview combines explicitly labeled order-cohort, selected-day and current global measures. See each formula for scope.',
      if (e.query.live && !e.get('days').any((d) => d['status'] == 'OPEN')) 'No Business Day is currently open. Historical reporting remains available.',
    ]);
    return AnalyticsSnapshot(query: e.query, generatedAt: e.now, generatedByStaffId: e.actor, businessDayIds: {...e.get('days').map((d) => d['id'] as int), ...e.get('order_days').map((d) => d['id'] as int)}.toList(), sections: [overview, ...sections], notes: [
      'Order time basis: ${e.query.timeBasis.name}; grouping: ${e.query.grouping.name}; Asia/Karachi (UTC+05:00). Start inclusive; end exclusive. Business Day weekday uses assigned opening date; calendar weekday uses actual creation date. Weeks start Monday; months use local calendar months.',
      'Non-order ledgers and drawer reconciliation retain Business Day opening-date scope. Calendar Order activity does not change their scope or Order assignments.',
      'Exploratory view over current committed local records. Immutable sealed Z-reports retain their original content hash and revision.',
      'Legacy REAL rupees are normalized once per source amount through PaisaEngine; integer-paisa columns are preferred. Historical floating-point precision is not restored.',
      _intervalBasis,
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
      final time = _karachi(operational ? days[order['business_day_id']]?['opened_at'] : order['created_at']);
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
      ...orders.map((o) => _row('orders', o, {'order_id': o['id'], 'business_day_id': o['business_day_id'], 'cashier_id': o['cashier_id'], 'shift_id': o['shift_id'], 'token': o['token_number'], 'dining_type': o['dining_type'], 'payment_status': o['payment_status'], 'token_status': o['token_status'], 'recorded_value_paisa': _money(o, 'grand_total'), 'created_at': o['created_at'], 'assigned_business_date': _karachi(daysById[o['business_day_id']]?['opened_at']) == null ? null : _sqlDate(_karachi(daysById[o['business_day_id']]!['opened_at'])!)})),
      ...revisions.map((r) => _row('order_revisions', r, {'order_id': r['order_id'], 'revision': r['revision_no'], 'action': r['action'], 'reason': _safeText(r['reason']), 'cashier_id': r['cashier_id'], 'delta_paisa': r['money_delta_paisa'], 'created_at': r['created_at_utc']})),
    ], ['order_id', 'business_day_id', 'assigned_business_date', 'token', 'cashier_id', 'shift_id', 'dining_type', 'payment_status', 'token_status', 'recorded_value_paisa', 'action', 'revision', 'delta_paisa', 'reason', 'created_at'], [_orderBasis, 'Order and revision source rows are separate kinds. Their counts/amounts must not be added together.']);
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
    final due = _sum(valid.where((o) => o['payment_status'] == 'COLLECTION_DUE'), 'grand_total');
    final metrics = <AnalyticsMetric>[
      _metric('delivery_orders', 'Delivery orders', deliveredOrders.length, unit: AnalyticsUnit.count, explanation: 'Eligible DELIVERY orders in filtered order cohort.'),
      _metric('delivery_fees', 'Recorded delivery fees', _integers(deliveredOrders, 'delivery_fee_paisa'), explanation: 'Eligible filtered delivery order fee snapshots.'),
      _metric('collection_due', 'Collection Due (selected cohort)', due, explanation: 'Current COLLECTION_DUE eligible order value within selected filtered order Business Days; delivery does not imply collection.'),
      _metric('all_collection_due', 'Collection Due (all outstanding)', _sum(e.get('all_due'), 'grand_total'), explanation: 'Current installation-wide COLLECTION_DUE orders across all Business Days; date/order filters do not apply.'),
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
      ...deliveredOrders.map((o) => _row('orders', o, {'order_id': o['id'], 'area': o['delivery_area_name_snapshot'] ?? 'Unknown area', 'fee_paisa': o['delivery_fee_paisa'], 'payment_status': o['payment_status']})),
      ...trips.map((t) => _row('rider_trips', t, {'trip_id': t['id'], 'rider_id': t['rider_staff_id'], 'shift_id': t['shift_id'], 'status': t['status'], 'selected_order_load': attempts.where((a) => a['trip_id'] == t['id']).length, 'expected_paisa': t['cash_expected_paisa'], 'counted_paisa': t['cash_collected_paisa'], 'dispatched_at': t['dispatched_at'], 'settled_at': t['settled_at_utc']})),
      ...attempts.map((a) => _row('rider_trip_orders', a, {'order_id': a['order_id'], 'trip_id': a['trip_id'], 'rider_id': a['rider_staff_id'], 'status': a['status'], 'dispatched_at': a['dispatched_at'], 'delivered_at': a['delivered_at'], 'returned_at': a['returned_at']})),
    ], ['order_id', 'trip_id', 'rider_id', 'shift_id', 'selected_order_load', 'area', 'fee_paisa', 'payment_status', 'status', 'expected_paisa', 'counted_paisa', 'dispatched_at', 'delivered_at', 'returned_at', 'settled_at'], ['Order/attempt rows and selected-order load use order filters; trip rows and trip exposure use whole selected Business Days. All-outstanding measures explicitly ignore date/order filters.', 'Travel excludes invalid/missing timestamps and reports coverage. Percentiles interpolate sorted valid minutes. No final failure/reattempt or unrecorded failure-reason inference.']);
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
    final rows = <AnalyticsRow>[
      ...ingredients.map((i) => _row('raw_ingredients', i, {'kind': 'Current position', 'ingredient_id': i['id'], 'name': _safeText(i['name']), 'unit': i['storage_unit'], 'current_stock': i['current_stock'], 'threshold': i['low_stock_threshold'], 'as_of_balance': balances[i['id']]?['balance_after'], 'balance_evidence_at': balances[i['id']]?['recorded_at'], 'status': (i['current_stock'] as num) < 0 ? 'Negative' : (i['current_stock'] as num) <= (i['low_stock_threshold'] as num) ? 'Low' : 'Within threshold'})),
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
      _metric('low_stock', 'Current low stock', low, unit: AnalyticsUnit.count, explanation: 'Current quantity <= configured threshold in each ingredient base unit. $_currentBasis'),
      _metric('negative_stock', 'Current negative stock', negative, unit: AnalyticsUnit.count, explanation: 'Current quantity < 0; sales never blocked. $_currentBasis'),
      _rate('low_stock_share', 'Current low-stock share', low, ingredients.length, 'Low-stock ingredient count / current tracked ingredients. $_currentBasis'),
      _metric('movement_count', 'Recorded movements', e.get('inventory').length, unit: AnalyticsUnit.count, explanation: 'Movement rows attributed by Business Day FK since v14 capture; no fabricated pre-upgrade history.'),
      _coverage('as_of_coverage', 'As-of balance evidence coverage', balances.length, ingredients.length, 'Latest recorded balance_after no later than last selected close/refresh. No evidence means unknown, not opening balance zero.'),
      _coverage('bom_coverage', 'Sold-line BOM quantity coverage', bomCovered, soldItems.length, 'Valid sold lines with readable quantity snapshot. Quantity evidence is not event-time costing.'),
      _missing('stock_valuation', 'Historical stock valuation', 'No historical cost layers. Current unit cost cannot rewrite past valuation.'),
      _metric('physical_variance', 'Posted physical count lines', e.get('physical_counts').length, unit: AnalyticsUnit.count, explanation: 'Posted observations in selected Business Day intervals. Inspect per-ingredient variances below; incompatible units are never totaled.'),
      _metric('physical_variance_cost', 'Estimated physical variance value', _integers(e.get('physical_counts'), 'estimated_cost_paisa'), explanation: 'Signed event-time count estimates; unknown rates prevent a complete total.', unavailable: e.get('physical_counts').any((c) => c['estimated_cost_paisa'] == null)),
    ], rows, ['kind', 'ingredient_id', 'name', 'unit', 'current_stock', 'threshold', 'as_of_balance', 'balance_evidence_at', 'quantity_delta', 'balance_after', 'quantity', 'loss_paisa', 'count_id', 'expected', 'counted', 'variance', 'estimated_cost_paisa', 'recorded_estimated_cost_paisa', 'valuation_policy', 'movement_id', 'snapshot_sequence', 'created_by', 'approved_by', 'posted_by', 'reason', 'status', 'recorded_at'], [_currentBasis, 'Movement/BOM/waste rows have separate scopes. Never sum quantities across grams, liters or count units.', 'Movement history begins with v14 capture; posted physical counts retain observation, approval and movement evidence. A zero-variance count has no adjusting movement. As-of is recorded balance evidence, not an invented beginning balance.']);
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
    final payments = events.where((t) => ['PAYMENT_DRAWER', 'PAYMENT_EXTERNAL'].contains(t['type'])).toList();
    final paidIds = payments.map((t) => t['vendor_id']).toSet();
    return _section(AnalyticsFamily.suppliers, 'Supplier Khata', [
      _metric('current_payable', 'Current supplier payable', _sum(vendors, 'current_balance'), explanation: 'Stored current balances across existing suppliers. $_currentBasis'),
      _metric('opening_balances', 'Configured opening balances', _sum(vendors, 'opening_balance'), explanation: 'Current configured opening balances; historical edits are not versioned. $_currentBasis'),
      _metric('credit_purchases', 'Recorded credit deliveries', _sum(events.where((t) => t['type'] == 'PURCHASE_CREDIT'), 'amount'), explanation: 'Credit purchases in selected day intervals affect stock/payable; not cash payments. $_intervalBasis'),
      _metric('drawer_payments', 'Supplier drawer payments', _sum(payments.where((t) => t['type'] == 'PAYMENT_DRAWER'), 'amount'), explanation: 'Selected interval supplier settlements from drawer; these are not operating expenses.'),
      _metric('external_payments', 'Supplier external payments', _sum(payments.where((t) => t['type'] == 'PAYMENT_EXTERNAL'), 'amount'), explanation: 'Selected interval supplier settlements from external management funds.'),
      _metric('no_payments_in_range', 'Suppliers with no payments in range', vendors.where((v) => !paidIds.contains(v['id'])).length, unit: AnalyticsUnit.count, explanation: 'Existing suppliers with no selected interval settlement. Does not claim no lifetime payments.'),
      _metric('overdue', 'Current overdue invoiced payable', _integers(e.get('invoice_balances').where((i) => i['due_date'] != null && (i['due_date'] as String).compareTo(_sqlDate(_karachi(e.now.toIso8601String())!)) < 0), 'due_paisa'), explanation: 'Current allocated invoice balances with known due dates. Undated legacy invoices and opening balances are excluded; this is not a historical aging snapshot.'),
      _missing('historical_payable', 'Reconstructed historical payable', 'Mutable opening balances and supplier cascade deletion limit historical reconstruction; current balances remain labeled current.'),
    ], [
      ...vendors.map((v) => _row('vendor_khata', v, {'kind': 'Current supplier', 'supplier_id': v['id'], 'name': _safeText(v['name']), 'opening_paisa': _money(v, 'opening_balance'), 'current_paisa': _money(v, 'current_balance'), 'payment_activity': paidIds.contains(v['id']) ? 'Payments in selected interval' : 'No payments in selected interval'})),
      ...events.map((t) => _row('vendor_transactions', t, {'kind': 'Selected interval entry', 'supplier_id': t['vendor_id'], 'type': t['type'], 'amount_paisa': _money(t, 'amount'), 'ingredient_id': t['raw_ingredient_id'], 'quantity': t['quantity'], 'shift_id': t['shift_id'], 'created_at': t['created_at']})),
    ], ['kind', 'supplier_id', 'name', 'opening_paisa', 'current_paisa', 'payment_activity', 'type', 'amount_paisa', 'ingredient_id', 'quantity', 'shift_id', 'created_at'], [_currentBasis, _intervalBasis, 'Supplier directory balances and selected interval entries are different views; do not add their amounts together.']);
  }

  AnalyticsSection _cash() {
    final shifts = e.get('shifts');
    final receivingIds = e.get('days').map((d) => d['id']).toSet();
    final receiptEvents = e.get('payment_events').where((p) => ['RECEIPT', 'REFUND'].contains(p['kind']) && receivingIds.contains(p['business_day_id'])).toList();
    final moves = e.get('movements');
    final payments = e.get('cash_payments');
    final receipts = payments.where((p) => p['payment_method'] == 'CASH' && _money(p, 'amount_tendered') > 0).toList();
    int receiptsFor(Iterable<_Record> rows) => rows.fold(0, (sum, p) => sum + _money(p, 'amount_tendered') - _money(p, 'change_returned'));
    final payIn = _sum(moves.where((m) => m['type'] == 'PAY_IN'), 'amount');
    final payOut = _sum(moves.where((m) => m['type'] != 'PAY_IN'), 'amount');
    final expected = _sum(shifts, 'opening_float') + receiptsFor(receipts) + payIn - payOut;
    final counted = shifts.where((s) => s['counted_cash'] != null).toList();
    final complete = shifts.isNotEmpty && counted.length == shifts.length;
    return _section(AnalyticsFamily.cash, 'Cash and shifts', [
      _metric('opening_float', 'Opening float', _sum(shifts, 'opening_float'), explanation: _globalBasis),
      _metric('cash_receipts', 'Positive customer cash receipts', receiptsFor(receipts), explanation: 'Positive CASH tender minus change. Refund payment negatives excluded here because their PAY_OUT already reduces the drawer. COD rider handover uses PAY_IN once. $_globalBasis'),
      _metric('cash_refunds', 'Explicit cash refunds', -_sum(payments.where((p) => p['payment_method'] == 'CASH' && _money(p, 'amount_tendered') < 0), 'amount_tendered'), explanation: 'Negative CASH tender rows shown for audit; drawer uses corresponding PAY_OUT only.'),
      _metric('pay_in', 'Drawer pay-ins', payIn, explanation: 'Includes recorded rider settlement pouches; no second COD addition. $_globalBasis'),
      _metric('pay_out', 'Drawer pay-outs', payOut, explanation: 'All non-PAY_IN recorded drawer outflows, including refunds/supplier settlements/drops.'),
      _metric('expected_drawer', 'Expected drawer', expected, explanation: 'Float + positive customer cash receipts + PAY_IN - PAY_OUT; cash refund never subtracted twice. $_globalBasis'),
      AnalyticsMetric(id: 'variance', label: 'Counted variance', value: complete ? _sum(counted, 'counted_cash') - expected : null, unit: AnalyticsUnit.paisa, explanation: 'Physical count minus expected across all selected shifts; missing blind count means unknown.', quality: shifts.isEmpty ? AnalyticsQuality.notApplicable : complete ? AnalyticsQuality.complete : AnalyticsQuality.missing, sampleCount: counted.length, populationCount: shifts.length),
      _coverage('count_coverage', 'Counted shift coverage', counted.length, shifts.length, 'Shifts with a recorded blind count / selected shifts; open uncounted shifts remain unknown.'),
      _metric('open_shifts', 'Open shifts', shifts.where((s) => s['status'] == 'OPEN').length, unit: AnalyticsUnit.count, explanation: _globalBasis),
      _metric('unresolved_discrepancies', 'Unresolved discrepancies', shifts.where((s) => s['discrepancy_status'] == 'FLAGGED').length, unit: AnalyticsUnit.count, explanation: 'Selected shifts with stored FLAGGED review status.'),
    ], [
      ...receiptEvents.map((p) => _row('payment_events', p, {
        'kind': 'Independent customer money event', 'event_kind': p['kind'],
        'event_key': p['event_key'], 'amount_paisa': p['amount_paisa'],
        'payment_source': p['payment_source'], 'payment_method': p['payment_method'],
        'actual_at': p['actual_at'], 'recorded_at': p['recorded_at'],
        'receiving_business_day_id': p['business_day_id'], 'receiving_shift_id': p['shift_id'],
        'business_day_id': p['business_day_id'], 'shift_id': p['shift_id'],
        'originating_business_day_id': p['originating_business_day_id'], 'originating_shift_id': p['originating_shift_id'],
        'order_id': p['order_id'], 'tender_id': p['tender_id'], 'movement_id': p['movement_id'],
        'recorded_by': p['recorded_by'], 'approved_by': p['approved_by'],
        'recorded_by_name_snapshot': p['recorded_by_name_snapshot'], 'shift_owner_name_snapshot': p['shift_owner_name_snapshot'],
        'change_paisa': p['change_paisa'], 'rounding_paisa': p['rounding_paisa'],
      })),
      ...shifts.map((s) {
        final shiftMoves = moves.where((m) => m['shift_id'] == s['id']);
        final expectedShift = _money(s, 'opening_float') + receiptsFor(receipts.where((p) => p['shift_id'] == s['id'])) + _sum(shiftMoves.where((m) => m['type'] == 'PAY_IN'), 'amount') - _sum(shiftMoves.where((m) => m['type'] != 'PAY_IN'), 'amount');
        return _row('shifts', s, {'kind': 'Shift reconciliation', 'shift_id': s['id'], 'cashier_id': s['staff_id'], 'status': s['status'], 'opening_paisa': _money(s, 'opening_float'), 'expected_paisa': expectedShift, 'counted_paisa': s['counted_cash'] == null ? null : _money(s, 'counted_cash'), 'variance_paisa': s['counted_cash'] == null ? null : _money(s, 'counted_cash') - expectedShift, 'review_status': s['discrepancy_status']});
      }),
      ...moves.map((m) => _row('cash_movements', m, {'kind': 'Drawer movement', 'shift_id': m['shift_id'], 'cashier_id': m['staff_id'], 'type': m['type'], 'category': _safeText(m['category']), 'amount_paisa': _money(m, 'amount'), 'created_at': m['created_at']})),
      ...e.get('reports').map((r) => _row('report_runs', r, {'kind': 'Sealed Z-report provenance', 'business_day_id': r['business_day_id'], 'status': r['status'], 'hash': r['content_hash'], 'created_at': r['created_at']})),
    ], ['event_kind', 'event_key', 'payment_source', 'payment_method', 'actual_at', 'recorded_at', 'receiving_business_day_id', 'receiving_shift_id', 'originating_business_day_id', 'originating_shift_id', 'order_id', 'tender_id', 'movement_id', 'recorded_by', 'approved_by', 'recorded_by_name_snapshot', 'shift_owner_name_snapshot', 'change_paisa', 'rounding_paisa', 'kind', 'business_day_id', 'shift_id', 'cashier_id', 'status', 'opening_paisa', 'expected_paisa', 'counted_paisa', 'variance_paisa', 'review_status', 'type', 'category', 'amount_paisa', 'hash', 'created_at'], [_globalBasis, 'Legacy payments lack receipt timestamps: customer collections are by source order Business Day/shift, not actual collection-event date. Shift rows are exploratory X-report inputs; sealed Z-report hashes remain original.']);
  }

  AnalyticsSection _expenses() {
    final out = e.get('movements').where((m) => m['type'] != 'PAY_IN').toList();
    final metrics = <AnalyticsMetric>[
      _metric('recorded_outflow', 'Recorded drawer outflow', _sum(out, 'amount'), explanation: 'All selected-shift PAY_OUT rows; not automatically operating expense. $_globalBasis'),
      _metric('outflow_count', 'Drawer outflow events', out.length, unit: AnalyticsUnit.count, explanation: _globalBasis),
      _metric('operating_expense', 'Recorded operating expense', _integers(e.get('expense_entries'), 'expense_delta_paisa'), explanation: 'Selected Business Day expense postings less reversals, across all funding sources. Legacy generic cash outflows are not inferred expenses.'),
    ];
    for (final entry in _group(out, 'category').entries) {
      metrics.add(_metric('category_${entry.key}', '${entry.key} drawer outflow', _sum(entry.value, 'amount'), explanation: 'Recorded PAY_OUT category/source only, not asserted operating expense.'));
    }
    return _section(AnalyticsFamily.expenses, 'Expenses and outflows', metrics, [
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
    ], ['kind', 'business_day_id', 'shift_id', 'category', 'description', 'payee', 'amount_paisa',
      'source', 'reversal_of', 'correction_of', 'manager_id', 'reason', 'classification', 'created_at'],
      [_globalBasis, 'Expense entries retain category snapshots. Cash movements reconcile physical funds and must not be added to expense entries. Legacy outflows are not inferred expenses.']);
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

  AnalyticsMetric _metric(String id, String label, num value, {AnalyticsUnit unit = AnalyticsUnit.paisa, String explanation = _orderBasis, num? previous, bool unavailable = false, AnalyticsQuality unavailableQuality = AnalyticsQuality.notApplicable}) {
    final difference = !partial && !unavailable && previous != null ? value - previous : null;
    return AnalyticsMetric(id: id, label: label, value: unavailable ? null : value, unit: unit, explanation: explanation,
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
    return AnalyticsSection(family: family, title: title, metrics: safeMetrics, rows: rows, columns: _columns(keys), notes: [...notes, if (absent.isNotEmpty) 'Missing source tables: ${absent.join(', ')}. Values withheld rather than asserted zero.']);
  }
  static List<AnalyticsColumn> _columns(List<String> keys) => keys.map((key) => AnalyticsColumn(key: key, label: _label(key), unit: key.endsWith('_paisa') ? AnalyticsUnit.paisa : key == 'unit_cost_rupees_per_base_unit' ? AnalyticsUnit.decimal : null)).toList();
  static String _label(String key) => key.replaceAll('_', ' ');
  static AnalyticsRow _row(String source, _Record record, Map<String, Object?> cells) => AnalyticsRow(id: '$source-${record['id']}', sourceType: source, sourceId: '${record['id']}', cells: cells);
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

