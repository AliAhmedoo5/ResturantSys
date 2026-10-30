part of 'analytics_service.dart';

class _WeekdayOrderPeaks {
  _WeekdayOrderPeaks(this.builder);
  final _ReportBuilder builder;
  static const names = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  List<AnalyticsRow> build() {
    final e = builder.e;
    final operational = e.query.timeBasis == AnalyticsTimeBasis.businessDay;
    if (!operational) return [];
    final cutoff = _karachi(e.now.toIso8601String())!;
    final days = e.get('days');
    bool completed(_Record day) {
      final end = _karachi(day['closed_at']);
      return day['status'] == 'CLOSED' && end != null && !end.isAfter(cutoff);
    }
    final rows = <AnalyticsRow>[];
    for (var weekday = 1; weekday <= 7; weekday++) {
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
    return rows;
  }
}
