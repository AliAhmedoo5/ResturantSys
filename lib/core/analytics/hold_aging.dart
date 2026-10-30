part of 'analytics_service.dart';

/// Current unconfirmed drafts, independent of historical Order populations.
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
  List<AnalyticsMetric> get metrics => [
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
  ];
  List<AnalyticsRow> get rows => [for (final hold in e.get('active_holds')) AnalyticsRow(
    id: 'held_carts-${hold['id']}', sourceType: 'held_carts', sourceId: '${hold['id']}', cells: {
      'kind': 'Current active Hold', 'hold_id': hold['id'], 'cashier_id': hold['cashier_id'],
      'cashier_name_current': _ReportBuilder._safeText(e.get('staff').where((s) => s['id'] == hold['cashier_id']).firstOrNull?['name'] ?? 'Unavailable current name'),
      'created_at': analyticsTimestamp(hold['created_at']), 'created_at_source': hold['created_at'],
      'age_minutes': _age(hold), 'stale_threshold_minutes': staleMinutes,
      'age_as_of': analyticsTimestamp(e.now.toIso8601String()),
      'aging_status': _age(hold) == null ? 'Unavailable creation evidence' : _age(hold)! >= staleMinutes ? 'Stale' : 'Below stale threshold',
      'scope': 'Current active Holds at snapshot cutoff; not historical activity',
    })];
  List<String> get notes => [
    'Current active Holds are selected by owning Cashier only. Date/time windows, Shift, Dining Type and payment filters do not apply: a Hold has no retained Business Day or Shift assignment. Holds never enter confirmed Order counts, Tokens, sales or workload charts.',
    'Hold age uses retained creation time to the snapshot cutoff in Asia/Karachi. Stale means at least $staleMinutes minutes. Original timestamp evidence is retained; naive legacy values assume Asia/Karachi, and missing/future creation evidence has unavailable age.',
    'Only active persisted Holds are visible. Deleted/recalled Hold lifecycle history is unavailable. Draft labels, items, customer contact and delivery details are excluded from reporting and exports. Cashier names are current directory values; historical names are unavailable.',
  ];
}
