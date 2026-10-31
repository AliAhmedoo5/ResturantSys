part of 'analytics_service.dart';

/// Current unconfirmed drafts, independent of historical Order populations,
/// and observed historical Hold lifecycle events.
class _HoldAging {
  _HoldAging(this.e);
  final _Evidence e;
  int get staleMinutes => e.query.holdStaleMinutes;

  double? _age(_Record hold) {
    final created = _karachi(hold['created_at']);
    final cutoff = _karachi(e.now.toIso8601String())!;
    if (created == null || created.isAfter(cutoff)) return null;
    return cutoff.difference(created).inSeconds / 60;
  }

  bool _inPeriod(_Record event) {
    if (e.query.cashierId != null && event['cashier_id'] != e.query.cashierId) {
      return false;
    }
    final recorded = _karachi(event['recorded_at']);
    if (recorded == null) return false;

    if (e.query.timeBasis == AnalyticsTimeBasis.calendarTime) {
      final start = analyticsWallClock(e.query.startDate);
      final end = analyticsWallClock(e.query.endDateExclusive);
      return !recorded.isBefore(start) && recorded.isBefore(end);
    } else {
      if (e.query.live) {
        final openDays = e.get('days').where((d) => d['status'] == 'OPEN');
        if (openDays.isEmpty) return false;
        return openDays.any((d) {
          final opened = _karachi(d['opened_at']);
          return opened != null && !recorded.isBefore(opened) && recorded.isBefore(e.now);
        });
      } else {
        final days = e.get('days');
        if (days.isEmpty) return false;
        return days.any((d) {
          final opened = _karachi(d['opened_at']);
          final closed = _karachi(d['closed_at']) ?? _karachi(e.now.toIso8601String())!;
          return opened != null && !recorded.isBefore(opened) && recorded.isBefore(closed);
        });
      }
    }
  }

  DateTime? _creationTimeOf(int holdId) {
    final createEv = e.get('hold_lifecycle_events').where((ev) => ev['hold_id'] == holdId && ev['event_type'] == 'CREATED').firstOrNull;
    if (createEv != null) {
      return _karachi(createEv['recorded_at']);
    }
    final active = e.get('active_holds').where((h) => h['id'] == holdId).firstOrNull;
    if (active != null) {
      return _karachi(active['created_at']);
    }
    return null;
  }

  double? _eventAge(_Record ev) {
    if (ev['event_type'] == 'CREATED') return 0.0;
    final created = _creationTimeOf(ev['hold_id'] as int);
    final recorded = _karachi(ev['recorded_at']);
    if (created == null || recorded == null || recorded.isBefore(created)) return null;
    return recorded.difference(created).inSeconds / 60.0;
  }

  List<AnalyticsMetric> get metrics {
    final periodEvents = e.get('hold_lifecycle_events').where(_inPeriod).toList();
    final created = periodEvents.where((ev) => ev['event_type'] == 'CREATED').toList();
    final recalled = periodEvents.where((ev) => ev['event_type'] == 'RECALLED').toList();
    final replaced = periodEvents.where((ev) => ev['event_type'] == 'REPLACED').toList();
    final discarded = periodEvents.where((ev) => ev['event_type'] == 'DISCARDED').toList();
    final converted = periodEvents.where((ev) => ev['event_type'] == 'CONVERTED').toList();

    final isMissingHistory = e.absent.contains('hold_lifecycle_events') || periodEvents.isEmpty;

    final double? conversionRate = created.isEmpty
        ? null
        : (converted.length / created.length * 100);

    final conversionAges = converted.map(_eventAge).whereType<double>().toList();
    final double? avgConversionMinutes = conversionAges.isEmpty
        ? null
        : (conversionAges.reduce((a, b) => a + b) / conversionAges.length);

    return [
      AnalyticsMetric(id: 'active_holds', label: 'Current active Holds',
        value: e.absent.contains('held_carts') ? null : e.get('active_holds').length,
        unit: AnalyticsUnit.count,
        quality: e.absent.contains('held_carts') ? AnalyticsQuality.missing : AnalyticsQuality.complete,
        explanation: 'Persisted current Holds at snapshot cutoff, scoped by owning Cashier only. No historical date, Shift, Dining Type or payment filtering. Outside confirmed Orders, Tokens and revenue.'),
      AnalyticsMetric(id: 'stale_holds', label: 'Current stale Holds (at least $staleMinutes minutes)',
        value: e.absent.contains('held_carts') ? null : e.get('active_holds').where((h) => (_age(h) ?? -1) >= staleMinutes).length,
        unit: AnalyticsUnit.count,
        quality: e.absent.contains('held_carts') ? AnalyticsQuality.missing : AnalyticsQuality.complete,
        explanation: 'Current retained creation times at least $staleMinutes minutes before snapshot cutoff. Unknown/future creation evidence is excluded from aging, never treated as fresh.'),
      _ReportBuilder._coverage('hold_age_coverage', 'Current Hold age coverage',
        e.get('active_holds').where((h) => _age(h) != null).length, e.get('active_holds').length,
        'Current Holds with valid retained creation evidence at/before cutoff. Missing/future creation times have unavailable age and stale classification.'),
      AnalyticsMetric(
        id: 'held_history',
        label: 'Historical Holds',
        value: isMissingHistory ? null : periodEvents.length,
        unit: AnalyticsUnit.count,
        quality: isMissingHistory ? AnalyticsQuality.missing : AnalyticsQuality.complete,
        explanation: isMissingHistory
            ? 'Current Holds are persisted. Complete deleted/recalled Hold lifecycle history is unavailable for unobserved periods; pre-feature legacy operations remain missing.'
            : 'Total observed Hold lifecycle operations (${periodEvents.length}) in selected period. Pre-feature legacy deleted/recalled Hold operations prior to schema v28 remain unavailable.',
      ),
      AnalyticsMetric(
        id: 'held_created',
        label: 'Holds created',
        value: e.absent.contains('hold_lifecycle_events') ? null : created.length,
        unit: AnalyticsUnit.count,
        quality: e.absent.contains('hold_lifecycle_events') ? AnalyticsQuality.missing : AnalyticsQuality.complete,
        explanation: 'Observed Hold CREATED events in selected period. Pre-feature legacy operations remain unobserved.',
      ),
      AnalyticsMetric(
        id: 'held_recalled',
        label: 'Holds recalled',
        value: e.absent.contains('hold_lifecycle_events') ? null : recalled.length,
        unit: AnalyticsUnit.count,
        quality: e.absent.contains('hold_lifecycle_events') ? AnalyticsQuality.missing : AnalyticsQuality.complete,
        explanation: 'Observed Hold RECALLED events in selected period. Pre-feature legacy operations remain unobserved.',
      ),
      AnalyticsMetric(
        id: 'held_replaced',
        label: 'Holds replaced',
        value: e.absent.contains('hold_lifecycle_events') ? null : replaced.length,
        unit: AnalyticsUnit.count,
        quality: e.absent.contains('hold_lifecycle_events') ? AnalyticsQuality.missing : AnalyticsQuality.complete,
        explanation: 'Observed Hold REPLACED events in selected period. Pre-feature legacy operations remain unobserved.',
      ),
      AnalyticsMetric(
        id: 'held_discarded',
        label: 'Holds discarded',
        value: e.absent.contains('hold_lifecycle_events') ? null : discarded.length,
        unit: AnalyticsUnit.count,
        quality: e.absent.contains('hold_lifecycle_events') ? AnalyticsQuality.missing : AnalyticsQuality.complete,
        explanation: 'Observed Hold DISCARDED events in selected period. Pre-feature legacy operations remain unobserved.',
      ),
      AnalyticsMetric(
        id: 'held_converted',
        label: 'Holds converted to orders',
        value: e.absent.contains('hold_lifecycle_events') ? null : converted.length,
        unit: AnalyticsUnit.count,
        quality: e.absent.contains('hold_lifecycle_events') ? AnalyticsQuality.missing : AnalyticsQuality.complete,
        explanation: 'Observed Hold CONVERTED events in selected period. Each conversion links to an eventual Order without counting the Hold as another Order or allocating extra Tokens.',
      ),
      AnalyticsMetric(
        id: 'hold_conversion_rate',
        label: 'Hold conversion rate',
        value: conversionRate,
        unit: AnalyticsUnit.percent,
        quality: conversionRate == null ? AnalyticsQuality.missing : AnalyticsQuality.complete,
        explanation: conversionRate == null
            ? 'No observed Hold creations in selected period; conversion rate is unavailable.'
            : 'Observed Hold conversions / observed creations in selected period (${converted.length} / ${created.length}).',
      ),
      AnalyticsMetric(
        id: 'hold_conversion_avg_age',
        label: 'Average conversion age',
        value: avgConversionMinutes,
        unit: AnalyticsUnit.minutes,
        quality: avgConversionMinutes == null ? AnalyticsQuality.missing : AnalyticsQuality.complete,
        explanation: avgConversionMinutes == null
            ? 'No observed Hold conversions with valid creation evidence in selected period.'
            : 'Average elapsed minutes from Hold creation to Order conversion for observed conversions in selected period.',
      ),
      _ReportBuilder._coverage(
        'hold_lifecycle_coverage',
        'Hold lifecycle coverage',
        periodEvents.where((ev) => _eventAge(ev) != null).length,
        periodEvents.length,
        'Observed Hold lifecycle events with verified recorded timestamps and creation linkages. Unretained legacy operations remain unobserved.',
      ),
    ];
  }

  List<AnalyticsRow> get rows {
    final periodEvents = e.get('hold_lifecycle_events').where(_inPeriod).toList();
    return [
      for (final hold in e.get('active_holds')) AnalyticsRow(
        id: 'held_carts-${hold['id']}',
        sourceType: 'held_carts',
        sourceId: '${hold['id']}',
        cells: {
          'kind': 'Current active Hold',
          'hold_id': hold['id'],
          'cashier_id': hold['cashier_id'],
          'cashier_name_current': _ReportBuilder._safeText(e.get('staff').where((s) => s['id'] == hold['cashier_id']).firstOrNull?['name'] ?? 'Unavailable current name'),
          'created_at': analyticsTimestamp(hold['created_at']),
          'created_at_source': hold['created_at'],
          'age_minutes': _age(hold),
          'stale_threshold_minutes': staleMinutes,
          'age_as_of': analyticsTimestamp(e.now.toIso8601String()),
          'aging_status': _age(hold) == null ? 'Unavailable creation evidence' : _age(hold)! >= staleMinutes ? 'Stale' : 'Below stale threshold',
          'scope': 'Current active Holds at snapshot cutoff; not historical activity',
        },
      ),
      for (final ev in periodEvents) AnalyticsRow(
        id: 'hold_lifecycle_events-${ev['id']}',
        sourceType: 'hold_lifecycle_events',
        sourceId: '${ev['id']}',
        cells: {
          'kind': 'Hold lifecycle: ${ev['event_type']}',
          'event_id': ev['id'],
          'hold_id': ev['hold_id'],
          'event_type': ev['event_type'],
          'cashier_id': ev['cashier_id'],
          'cashier_name_current': _ReportBuilder._safeText(e.get('staff').where((s) => s['id'] == ev['cashier_id']).firstOrNull?['name'] ?? 'Unavailable current name'),
          'order_id': ev['order_id'],
          'previous_hold_id': ev['previous_hold_id'],
          'recorded_at': analyticsTimestamp(ev['recorded_at']),
          'recorded_at_source': ev['recorded_at'],
          'age_minutes': _eventAge(ev),
          'scope': 'Observed historical Hold lifecycle event',
        },
      ),
    ];
  }

  List<String> get notes => [
    'Current active Holds are selected by owning Cashier only. Date/time windows, Shift, Dining Type and payment filters do not apply: a Hold has no retained Business Day or Shift assignment. Holds never enter confirmed Order counts, Tokens, sales or workload charts.',
    'Hold age uses retained creation time to the snapshot cutoff in Asia/Karachi. Stale means at least $staleMinutes minutes. Original timestamp evidence is retained; naive legacy values assume Asia/Karachi, and missing/future creation evidence has unavailable age.',
    'Historical Hold lifecycle events (created, recalled, replaced, discarded, converted) are recorded from observed operations with stable links to Cashiers and converted Orders. Pre-feature operations prior to schema v28 remain unobserved/missing.',
    'Draft labels, items, customer contact and delivery details are excluded from reporting and exports. Cashier names are current directory values; historical names are unavailable.',
  ];
}
