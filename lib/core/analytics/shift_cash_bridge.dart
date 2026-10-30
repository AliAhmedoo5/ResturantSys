part of 'analytics_service.dart';

/// One physical effect per stable event/movement link, over whole owning Shifts.
class _ShiftCashBridge {
  _ShiftCashBridge(this.builder);
  final _ReportBuilder builder;
  _Evidence get e => builder.e;

  AnalyticsSection build() {
    final shifts = e.get('bridge_shifts');
    final ids = shifts.map((s) => s['id']).toSet();
    final events = e.get('payment_events').where((p) => ids.contains(p['shift_id']) &&
      p['payment_source'] == 'DRAWER' && p['kind'] != 'COD_SETTLEMENT').toList();
    final movements = e.get('bridge_movements');
    final linked = events.map((p) => p['movement_id']).whereType<int>().toSet();
    final effects = <_Record>[];
    final gaps = <AnalyticsRow>[];
    for (final event in events) {
      final component = switch (event['kind']) {
        'RECEIPT' => 'customer_receipts', 'REFUND' => 'refunds',
        'RIDER_HANDOVER' => 'rider_handovers',
        'EXPENSE' || 'EXPENSE_REVERSAL' => 'expenses',
        'SUPPLIER_PAYMENT' => 'supplier_payments',
        'PAYROLL_PAYMENT' || 'PAYROLL_ADVANCE' || 'PAYROLL_REVERSAL' => 'payroll_advances',
        _ => 'other_flows',
      };
      effects.add({...event, 'component': component, 'source_type': 'payment_events'});
      final movementId = event['movement_id'];
      if (movementId != null) {
        final movement = movements.where((m) => m['id'] == movementId).firstOrNull;
        final signed = movement == null ? null : _money(movement, 'amount') * (movement['type'] == 'PAY_IN' ? 1 : -1);
        if (signed != event['amount_paisa'] || movement?['shift_id'] != event['shift_id']) {
          gaps.add(AnalyticsRow(id: 'bridge-link-${event['id']}', sourceType: 'payment_events',
            sourceId: '${event['id']}', cells: {'kind': 'Cash coverage gap', 'shift_id': event['shift_id'],
              'movement_id': movementId, 'coverage': 'Linked Cash Movement missing or inconsistent; expected balance withheld'}));
        }
      }
    }
    for (final move in movements.where((m) => !linked.contains(m['id']))) {
      final category = '${move['category']}'.toUpperCase();
      final payIn = move['type'] == 'PAY_IN';
      effects.add({...move, 'component': payIn ? 'other_pay_ins' : category.contains('DROP') ? 'cash_drops' : 'other_outflows',
        'amount_paisa': _money(move, 'amount') * (payIn ? 1 : -1),
        'source_type': 'cash_movements', 'payment_source': 'DRAWER',
        'movement_id': move['id'], 'recorded_by': move['staff_id'],
        'actual_at': null, 'recorded_at': move['created_at'],
        'time_coverage': 'Legacy/manual movement; actual time not retained independently'});
    }
    // An unlinked tender's originating Shift is not receiving evidence. Keep
    // its known value visible, but do not guess attribution or merge lookalikes.
    for (final payment in e.get('bridge_payments')) {
      if (payment['payment_method'] != 'CASH' || e.get('payment_events').any((p) => p['tender_id'] == payment['id'])) continue;
      gaps.add(AnalyticsRow(id: 'bridge-legacy-${payment['id']}', sourceType: 'order_payments', sourceId: '${payment['id']}', cells: {
        'kind': 'Cash coverage gap', 'order_id': payment['order_id'],
        'originating_shift_id': payment['originating_shift_id'],
        'unattributed_paisa': _money(payment, 'amount_tendered') - _money(payment, 'change_returned'),
        'coverage': 'Receiving Shift and actual time unavailable; no similarity deduplication; complete expected balance withheld',
      }));
    }
    final rows = <AnalyticsRow>[];
    int sum(String component) => effects.where((r) => r['component'] == component)
      .fold(0, (total, r) => total + (r['amount_paisa'] as int));
    final opening = _sum(shifts, 'opening_float');
    final evidenced = opening + effects.fold<int>(0, (total, r) => total + (r['amount_paisa'] as int));
    final missing = gaps.isNotEmpty || ['payment_events', 'cash_movements', 'order_payments'].any(e.absent.contains);
    final counted = shifts.where((s) => s['counted_cash'] != null).toList();
    final complete = !missing && shifts.isNotEmpty && counted.length == shifts.length;
    const scope = 'Whole selected owning/receiving Shifts, including collections from Orders outside the cohort. Dining Type, payment method and calendar event windows apply to separately labeled activity rows only.';
    AnalyticsMetric metric(String id, String label, num? value, {bool unavailable = false}) => AnalyticsMetric(
      id: id, label: label, value: unavailable ? null : value, unit: AnalyticsUnit.paisa,
      quality: unavailable ? AnalyticsQuality.missing : AnalyticsQuality.complete,
      explanation: '$scope Opening Float + signed physical effects. Linked event/tender/movement evidence contributes once.');
    for (final shift in shifts) {
      final expected = _money(shift, 'opening_float') + effects.where((r) => r['shift_id'] == shift['id']).fold<int>(0, (total, r) => total + (r['amount_paisa'] as int));
      rows.add(builder._row('shifts', shift, {'kind': 'Shift reconciliation', 'shift_id': shift['id'],
        'cashier_id': shift['staff_id'], 'status': shift['status'], 'opening_paisa': _money(shift, 'opening_float'),
        'evidenced_balance_paisa': expected, 'expected_paisa': missing ? null : expected,
        'counted_paisa': shift['counted_cash'] == null ? null : _money(shift, 'counted_cash'),
        'variance_paisa': missing || shift['counted_cash'] == null ? null : _money(shift, 'counted_cash') - expected,
        'review_status': shift['discrepancy_status'], 'coverage': missing ? 'Incomplete; complete balance withheld' : 'Reconciled retained evidence'}));
    }
    for (final effect in effects) {
      final detail = builder._row(effect['source_type'] as String, effect, {
        'kind': 'Physical cash effect', 'effect_source_id': effect['id'],
        for (final key in ['component', 'amount_paisa', 'payment_source', 'payment_method',
          'shift_id', 'business_day_id', 'order_id', 'originating_shift_id', 'originating_business_day_id',
          'tender_id', 'movement_id', 'settlement_id', 'recorded_by', 'approved_by',
          'actual_at', 'recorded_at', 'time_coverage']) key: effect[key],
        'category': _ReportBuilder._safeText(effect['category']),
        'linked_event_key': effect['event_key'],
      });
      // Physical contributors have a distinct row kind from activity evidence.
      rows.add(AnalyticsRow(id: 'cash-effect-${detail.id}', sourceType: 'cash_effect', sourceId: detail.sourceId, cells: {
        ...detail.cells, 'source_table': effect['source_type'],
      }));
    }
    return builder._section(AnalyticsFamily.cash, 'Cash and shifts', [
      metric('opening_float', 'Opening float', opening),
      metric('cash_receipts', 'Customer cash accepted', sum('customer_receipts')),
      metric('rider_handovers', 'Rider handovers', sum('rider_handovers')),
      metric('pay_in', 'Other pay-ins', sum('other_pay_ins')),
      metric('cash_refunds', 'Cash refunds', -sum('refunds')),
      metric('cash_expenses', 'Cash expenses (net of reversals)', -sum('expenses')),
      metric('cash_supplier_payments', 'Cash supplier payments', -sum('supplier_payments')),
      metric('cash_payroll_advances', 'Cash payroll/advances (net of reversals)', -sum('payroll_advances')),
      metric('cash_drops', 'Cash drops', -sum('cash_drops')),
      metric('other_outflows', 'Other drawer outflows', -sum('other_outflows')),
      metric('pay_out', 'Total physical outflow', -effects.where((r) => (r['amount_paisa'] as int) < 0).fold<int>(0, (total, r) => total + (r['amount_paisa'] as int))),
      metric('evidenced_balance', 'Balance from retained evidence (coverage required)', evidenced),
      metric('expected_drawer', 'Expected drawer', evidenced, unavailable: missing),
      metric('blind_count', 'Blind Count', _sum(counted, 'counted_cash'), unavailable: counted.length != shifts.length || shifts.isEmpty),
      metric('variance', 'Discrepancy (counted minus expected)', _sum(counted, 'counted_cash') - evidenced, unavailable: !complete),
      _ReportBuilder._coverage('count_coverage', 'Counted shift coverage', counted.length, shifts.length, 'Uncounted Shift variance is unavailable.'),
      builder._metric('cash_evidence_gaps', 'Cash evidence gaps', gaps.length, unit: AnalyticsUnit.count, explanation: 'Unlinked legacy tenders and inconsistent stable links; complete expected balances withheld.'),
      builder._metric('open_shifts', 'Open shifts', shifts.where((s) => s['status'] == 'OPEN').length, unit: AnalyticsUnit.count, explanation: scope),
      builder._metric('unresolved_discrepancies', 'Unresolved discrepancies', shifts.where((s) => s['discrepancy_status'] == 'FLAGGED').length, unit: AnalyticsUnit.count, explanation: scope),
    ], [
      ...rows, ...gaps, ...builder._receivingEventRows(builder._receivingEvents()),
      ...e.get('reports').map((r) => builder._row('report_runs', r, {'kind': 'Sealed Z-report provenance', 'hash': r['content_hash']})),
    ], ['kind', 'component', 'shift_id', 'business_day_id', 'amount_paisa', 'opening_paisa', 'expected_paisa', 'counted_paisa', 'variance_paisa'], [scope,
      'Physical cash effect rows alone explain the bridge. Independent customer money event and counted rider custody transfer rows are activity details, never additional inputs. COD settlement attribution is contractual, not cash. BANK/OWNER payments, salary accruals and unpaid purchases do not enter drawer cash.',
      'Unknown receiving attribution remains unavailable. No amount/time similarity deduplication. Legacy/manual movements retain custody evidence with unknown actual time. Unlinked historical tenders withhold complete expected cash and Discrepancy; evidenced balance is partial evidence only.',
      'Known event and recording times are displayed in Asia/Karachi with original UTC/offset source values. Shift owner and recorded-by actors remain distinct. Original sealed X/Z reports are not rewritten.',
    ]);
  }
}
