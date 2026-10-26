import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';

import '../../core/analytics/analytics_models.dart';
import '../../core/analytics/analytics_service.dart';
import '../../core/auth/session_state.dart';
import '../../core/auth/staff_role.dart';
import '../../core/orders/dining_type.dart';
import '../../core/orders/payment_method.dart';
import '../../core/theme/theme.dart';

const _familyLabels = <AnalyticsFamily, String>{
  AnalyticsFamily.overview: 'Overview',
  AnalyticsFamily.sales: 'Sales',
  AnalyticsFamily.orders: 'Order operations',
  AnalyticsFamily.delivery: 'Delivery',
  AnalyticsFamily.customers: 'Customers',
  AnalyticsFamily.menu: 'Menu & deals',
  AnalyticsFamily.inventory: 'Inventory',
  AnalyticsFamily.procurement: 'Procurement',
  AnalyticsFamily.suppliers: 'Supplier Khata',
  AnalyticsFamily.cash: 'Cash & shifts',
  AnalyticsFamily.expenses: 'Expenses',
  AnalyticsFamily.staff: 'Staff & payroll',
  AnalyticsFamily.profitability: 'Profitability',
  AnalyticsFamily.audit: 'Control & audit',
};

/// Read-only reporting over one immutable, authorized SQLite snapshot.
class ManagerAnalyticsWorkspace extends StatefulWidget {
  const ManagerAnalyticsWorkspace({
    super.key,
    required this.service,
    this.session,
    this.clock,
    this.refreshInterval = const Duration(seconds: 30),
    this.exportActionsBuilder,
  });

  final AnalyticsService service;
  final SessionState? session;
  final DateTime Function()? clock;
  final Duration refreshInterval;

  /// Export controls consume precisely the snapshot displayed on screen.
  final Widget Function(BuildContext, AnalyticsSnapshot, AnalyticsFamily)? exportActionsBuilder;

  @override
  State<ManagerAnalyticsWorkspace> createState() => _ManagerAnalyticsWorkspaceState();
}

class _ManagerAnalyticsWorkspaceState extends State<ManagerAnalyticsWorkspace>
    with WidgetsBindingObserver {
  late AnalyticsQuery _query;
  AnalyticsSnapshot? _snapshot;
  DialogRoute<void>? _sourceRoute;
  AnalyticsFamily _family = AnalyticsFamily.overview;
  Timer? _timer;
  bool _busy = false;
  bool _queued = false;
  bool _visible = true;
  String? _error;
  int _revision = 0;
  String _preset = 'live';
  final _filtersKey = GlobalKey<FormState>();
  final _cashier = TextEditingController();
  final _shift = TextEditingController();
  String? _dining;
  String? _payment;

  DateTime get _now => widget.clock?.call() ??
      DateTime.now().toUtc().add(const Duration(hours: 5));
  DateTime get _today => DateTime(_now.year, _now.month, _now.day);
  bool get _authorized {
    if (widget.session == null) return true; // Service still authorizes every read.
    final staff = widget.session!.currentStaff;
    return staff != null && staff.role == StaffRole.manager &&
        staff.isActive && staff.loginEnabled;
  }

  @override
  void initState() {
    super.initState();
    _query = AnalyticsQuery(startDate: _today,
      endDateExclusive: _today.add(const Duration(days: 1)), live: true);
    WidgetsBinding.instance.addObserver(this);
    widget.session?.addListener(_sessionChanged);
    _startTimer();
    _load();
  }

  @override
  void didUpdateWidget(covariant ManagerAnalyticsWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session) {
      oldWidget.session?.removeListener(_sessionChanged);
      widget.session?.addListener(_sessionChanged);
    }
    if (oldWidget.service != widget.service || oldWidget.session != widget.session) {
      _sessionChanged();
    }
    if (oldWidget.refreshInterval != widget.refreshInterval) _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    if (!_authorized || !_visible || !_query.live) return;
    _timer = Timer.periodic(widget.refreshInterval, (_) => _load());
  }

  void _sessionChanged() {
    _dismissSource();
    _revision++;
    _queued = false;
    setState(() { _snapshot = null; _error = null; });
    _startTimer();
    if (_authorized) _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    _startTimer();
    if (_visible && _authorized && _query.live) _load();
  }

  Future<void> _load() async {
    if (!_authorized || !_visible) return;
    if (_busy) { _queued = true; return; }
    final revision = _revision;
    final query = _query;
    setState(() { _busy = true; _error = null; });
    try {
      final snapshot = await widget.service.load(query);
      if (mounted && revision == _revision && _authorized) {
        _dismissSource();
        setState(() => _snapshot = snapshot);
      }
    } catch (_) {
      if (mounted && revision == _revision && _authorized) {
        _dismissSource();
        setState(() {
          // The service may reject a persisted role change before the session
          // notifier knows about it. Never retain financial data after rejection.
          _snapshot = null;
          _error = 'Unable to load analytics. Check your Manager session and retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_queued) { _queued = false; _load(); }
      }
    }
  }

  void _changeQuery(AnalyticsQuery query) {
    _dismissSource();
    _revision++;
    setState(() { _query = query; _snapshot = null; _error = null; });
    _startTimer();
    _load();
  }

  AnalyticsQuery _withDates(DateTime start, DateTime end, {required bool live}) =>
      AnalyticsQuery(startDate: start, endDateExclusive: end, live: live,
        cashierId: _query.cashierId, shiftId: _query.shiftId,
        diningType: _query.diningType, paymentMethod: _query.paymentMethod);

  Future<void> _selectPreset(String? value) async {
    if (value == null) return;
    if (value == 'custom') {
      final range = await showDateRangePicker(context: context,
        firstDate: DateTime(2000), lastDate: _today,
        initialDateRange: DateTimeRange(start: _query.startDate,
          end: _query.endDateExclusive.subtract(const Duration(days: 1))),
        helpText: 'Select Business Day opening dates (inclusive)');
      if (range == null || !mounted) return;
      setState(() => _preset = value);
      _changeQuery(_withDates(range.start, range.end.add(const Duration(days: 1)), live: false));
      return;
    }
    setState(() => _preset = value);
    final days = value == 'week' ? 7 : value == 'month' ? 30 : 1;
    final end = value == 'yesterday' ? _today : _today.add(const Duration(days: 1));
    _changeQuery(_withDates(end.subtract(Duration(days: days)), end, live: value == 'live'));
  }

  void _applyFilters() {
    if (!_filtersKey.currentState!.validate()) return;
    _changeQuery(AnalyticsQuery(startDate: _query.startDate,
      endDateExclusive: _query.endDateExclusive, live: _query.live,
      cashierId: int.tryParse(_cashier.text.trim()), shiftId: int.tryParse(_shift.text.trim()),
      diningType: _dining, paymentMethod: _payment));
  }

  @override
  void dispose() {
    _dismissSource();
    _revision++;
    _timer?.cancel();
    widget.session?.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _cashier.dispose();
    _shift.dispose();
    super.dispose();
  }

  // The route belongs to this authorized snapshot, rather than to the root
  // Navigator. Remove this exact route even when another dialog is above it.
  void _dismissSource() {
    final route = _sourceRoute;
    _sourceRoute = null;
    if (route == null) return;
    void remove() {
      final navigator = route.navigator;
      if (navigator != null && navigator.mounted && route.isActive) {
        navigator.removeRoute(route);
      }
    }
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => remove());
    } else {
      remove();
    }
  }

  void _showSource(AnalyticsSection section, AnalyticsRow row) {
    final snapshot = _snapshot;
    if (snapshot == null || !_authorized) return;
    _dismissSource();
    final route = DialogRoute<void>(context: context, builder: (context) {
      if (!mounted || !_authorized || !identical(_snapshot, snapshot)) {
        return const SizedBox.shrink();
      }
      return AlertDialog(
        title: Text(_sourceLabel(row)),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('Safe reporting projection • source values from this snapshot'),
            SelectableText('Source IDs: ${row.sourceId ?? row.id}'),
            const SizedBox(height: 12),
            for (final column in section.columns) Padding(padding: const EdgeInsets.only(bottom: 8),
              child: SelectableText('${column.label}: ${_format(row.cells[column.key], column.unit)}')),
          ]))),
        actions: [TextButton(onPressed: _dismissSource, child: const Text('Close'))],
      );
    });
    _sourceRoute = route;
    Navigator.of(context, rootNavigator: true).push(route).whenComplete(() {
      if (identical(_sourceRoute, route)) _sourceRoute = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_authorized) {
      return const Center(child: Text('Manager session required. Sign in to view analytics.'));
    }
    final snapshot = _snapshot;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Text('Business intelligence', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        SizedBox(width: 205, child: DropdownButtonFormField<AnalyticsFamily>(
          key: const ValueKey('analytics_family'), value: _family, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Report', isDense: true, border: OutlineInputBorder()),
          items: _familyLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (family) {
            if (family != null) { _dismissSource(); setState(() => _family = family); }
          },
        )),
        SizedBox(width: 190, child: DropdownButtonFormField<String>(
          key: const ValueKey('analytics_period'), value: _preset, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Business Day period', isDense: true, border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'live', child: Text('Live • active day')),
            DropdownMenuItem(value: 'today', child: Text('Today')),
            DropdownMenuItem(value: 'yesterday', child: Text('Previous day')),
            DropdownMenuItem(value: 'week', child: Text('Last 7 dates')),
            DropdownMenuItem(value: 'month', child: Text('Last 30 dates')),
            DropdownMenuItem(value: 'custom', child: Text('Custom range…')),
          ], onChanged: _selectPreset,
        )),
        OutlinedButton.icon(key: const ValueKey('analytics_refresh'),
          onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh),
          label: Text(_busy ? 'Refreshing…' : 'Refresh')),
        if (snapshot != null && _error == null && !_busy && widget.exportActionsBuilder != null)
          widget.exportActionsBuilder!(context, snapshot, _family),
      ]),
      const SizedBox(height: 8),
      Text('${_query.live ? 'Live local committed data • automatic refresh every ${widget.refreshInterval.inSeconds}s' : 'Historical exploration'}'
        ' • Asia/Karachi • ${_query.live ? 'active Business Day cohort (may open on an earlier date)' : '${DateFormat('dd MMM yyyy').format(_query.startDate)} to ${DateFormat('dd MMM yyyy').format(_query.endDateExclusive)} (end exclusive)'}',
        style: const TextStyle(color: StreetFoodMafiaColors.secondaryText, fontSize: 12)),
      if (snapshot != null) Text(
        'Last successful refresh: '
        '${DateFormat('dd MMM yyyy HH:mm:ss').format(snapshot.generatedAt.isUtc ? snapshot.generatedAt.add(const Duration(hours: 5)) : snapshot.generatedAt)} • Business Days: '
        '${snapshot.businessDayIds.isEmpty ? 'none in selection' : snapshot.businessDayIds.join(', ')}',
        style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
      const SizedBox(height: 8),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
      Expanded(child: ListView(key: const ValueKey('analytics_body'), padding: const EdgeInsets.only(top: 8), children: [
        _filterPanel(),
        if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Wrap(
          spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_error!, style: const TextStyle(color: StreetFoodMafiaColors.statusCanceled)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ]))),
        if (snapshot == null && !_busy && _error == null) const Text('No analytics snapshot available.'),
        if (snapshot != null) ...[
          for (final note in snapshot.notes) _note(note),
          if (snapshot.businessDayIds.isEmpty) _note('No Business Days match this selection. Current-state datasets may still be available.'),
          ..._report(snapshot),
        ],
      ])),
    ]);
  }

  Widget _filterPanel() => ExpansionTile(
    key: const ValueKey('analytics_filters'), tilePadding: EdgeInsets.zero,
    title: const Text('Order cohort filters'),
    subtitle: Text(_query.cashierId == null && _query.shiftId == null && _query.diningType == null && _query.paymentMethod == null
      ? 'All cashiers, shifts, Dining Types and payment methods' : 'Filters applied • inspect each report’s scope notes'),
    children: [Form(key: _filtersKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Applies to order-based measures only. Inventory, procurement, Khata, staff and cash ledgers retain their stated scope.',
        style: TextStyle(color: StreetFoodMafiaColors.secondaryText, fontSize: 12)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _idInput(_cashier, 'Cashier ID', 'analytics_cashier'),
        _idInput(_shift, 'Shift ID', 'analytics_shift'),
        SizedBox(width: 160, child: DropdownButtonFormField<String>(
          key: const ValueKey('analytics_dining'), value: _dining, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Dining Type', border: OutlineInputBorder(), isDense: true),
          items: [const DropdownMenuItem<String>(value: null, child: Text('All')),
            for (final type in DiningType.values)
              DropdownMenuItem(value: type.code, child: Text(type.displayName))],
          onChanged: (value) => setState(() => _dining = value),
        )),
        SizedBox(width: 180, child: DropdownButtonFormField<String>(
          key: const ValueKey('analytics_payment'), value: _payment, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Payment method', border: OutlineInputBorder(), isDense: true),
          items: [const DropdownMenuItem<String>(value: null, child: Text('All')),
            for (final method in PaymentMethod.values.where((method) => method != PaymentMethod.split))
              DropdownMenuItem(value: method.code, child: Text(method.displayName))],
          onChanged: (value) => setState(() => _payment = value),
        )),
        FilledButton(key: const ValueKey('analytics_apply_filters'), onPressed: _applyFilters, child: const Text('Apply')),
        TextButton(onPressed: () {
          _cashier.clear(); _shift.clear();
          setState(() { _dining = null; _payment = null; });
          _applyFilters();
        }, child: const Text('Clear')),
      ]),
      const SizedBox(height: 12),
    ]))],
  );

  Widget _idInput(TextEditingController controller, String label, String key) => SizedBox(width: 135,
    child: TextFormField(key: ValueKey(key), controller: controller, keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, hintText: 'All', border: const OutlineInputBorder(), isDense: true),
      validator: (value) => value == null || value.trim().isEmpty ||
        (int.tryParse(value.trim()) != null && int.parse(value.trim()) > 0) ? null : 'Positive ID required',
    ));

  List<Widget> _report(AnalyticsSnapshot snapshot) {
    final sections = snapshot.sections.where((s) => s.family == _family).toList();
    if (sections.isEmpty) return [_note('This report has no source dataset available in this snapshot.')];
    return [for (final section in sections) ...[
      Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(section.title,
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
      for (final note in section.notes) _note(note),
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth < 480 ? constraints.maxWidth :
          (constraints.maxWidth - 24) / (constraints.maxWidth >= 1050 ? 4 : constraints.maxWidth >= 760 ? 3 : 2);
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final metric in section.metrics) SizedBox(width: width, child: _metricCard(metric)),
        ]);
      }),
      if (section.family == AnalyticsFamily.sales && section.rows.any((r) => r.cells['business_date'] != null && r.cells['recorded_value_paisa'] is num))
        _SalesTrend(rows: section.rows),
      const SizedBox(height: 12),
      if (section.columns.isNotEmpty && section.rows.isNotEmpty)
        _SourceTable(key: ValueKey('table_${section.family.name}_${snapshot.generatedAt.toIso8601String()}_${section.title}'),
          section: section, onShowSource: (row) => _showSource(section, row))
      else _note(section.rows.isEmpty ? 'No source rows match this report. Missing inputs are explained above.' : 'Source detail unavailable for this dataset.'),
      const SizedBox(height: 16),
    ]];
  }

  Widget _metricCard(AnalyticsMetric metric) {
    final quality = switch (metric.quality) {
      AnalyticsQuality.complete => 'Complete',
      AnalyticsQuality.estimated => 'Estimated',
      AnalyticsQuality.missing => 'Missing data',
      AnalyticsQuality.notApplicable => 'Not applicable',
    };
    return Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(metric.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        SelectableText(_format(metric.value, metric.unit),
          style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700, color: StreetFoodMafiaColors.cartelYellow)),
        const SizedBox(height: 6),
        Text(quality, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: metric.quality == AnalyticsQuality.complete ? StreetFoodMafiaColors.statusReady : StreetFoodMafiaColors.burntGold)),
        Text(metric.explanation, style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
        Text('Unit: ${switch (metric.unit) { AnalyticsUnit.paisa => 'PKR (stored as integer paisa)', AnalyticsUnit.percent => 'percent', AnalyticsUnit.minutes => 'minutes', AnalyticsUnit.count => 'count', AnalyticsUnit.decimal => 'decimal; see formula' }}',
          style: const TextStyle(fontSize: 11, color: StreetFoodMafiaColors.secondaryText)),
        if (metric.sampleCount != null) Text('Coverage: ${metric.sampleCount}'
          '${metric.populationCount == null ? ' valid samples' : ' / ${metric.populationCount}'}', style: const TextStyle(fontSize: 12)),
        if (metric.changeAbsolute != null) Text('Change: ${metric.changeAbsolute! >= 0 ? '+' : ''}'
          '${_format(metric.changeAbsolute, metric.unit)} vs preceding comparable period', style: const TextStyle(fontSize: 12)),
        if (metric.changePercent != null) Text('${metric.changePercent! >= 0 ? '+' : ''}'
          '${metric.changePercent!.toStringAsFixed(1)}% vs preceding comparable period', style: const TextStyle(fontSize: 12)),
      ])));
  }

  Widget _note(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 5),
    child: Text(text, style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)));
}

String _format(Object? value, AnalyticsUnit? unit) {
  if (value == null) return 'Unavailable';
  if (value is! num) return value.toString();
  return switch (unit) {
    AnalyticsUnit.paisa => 'PKR ${NumberFormat('#,##0.00').format(value / 100)}',
    AnalyticsUnit.percent => '${value.toStringAsFixed(1)}%',
    AnalyticsUnit.minutes => '${value.toStringAsFixed(1)} min',
    AnalyticsUnit.decimal => NumberFormat('#,##0.########').format(value),
    _ => NumberFormat('#,##0.##').format(value),
  };
}

class _SalesTrend extends StatelessWidget {
  const _SalesTrend({required this.rows});
  final List<AnalyticsRow> rows;

  @override
  Widget build(BuildContext context) {
    final daily = rows.where((r) => r.cells['business_date'] != null && r.cells['recorded_value_paisa'] is num).toList();
    final maximum = daily.fold<double>(0, (max, row) {
      final value = (row.cells['recorded_value_paisa'] as num).toDouble();
      return value > max ? value : max;
    });
    return Card(margin: const EdgeInsets.only(top: 12), child: Padding(padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Sales trend • recorded order value (PKR)', style: TextStyle(fontWeight: FontWeight.w700)),
        const Text('By Business Day opening date. The same source rows appear in the accessible detail table below.',
          style: TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
        const SizedBox(height: 12),
        SizedBox(height: 170, child: SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [for (final row in daily)
            SizedBox(width: 120, child: Semantics(label: '${row.cells['business_date']}: '
              '${_format(row.cells['recorded_value_paisa'], AnalyticsUnit.paisa)}, ${row.cells['orders']} orders',
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(_format(row.cells['recorded_value_paisa'], AnalyticsUnit.paisa), style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 4),
                Container(width: 30, height: maximum == 0 ? 1 :
                  ((row.cells['recorded_value_paisa'] as num).toDouble() / maximum * 110).clamp(1, 110).toDouble(),
                  decoration: BoxDecoration(color: StreetFoodMafiaColors.cartelYellow, borderRadius: BorderRadius.circular(3))),
                const SizedBox(height: 6),
                Text('${row.cells['business_date']}', style: const TextStyle(fontSize: 11)),
              ]))),
          ]))),
      ])));
  }
}

class _SourceTable extends StatefulWidget {
  const _SourceTable({super.key, required this.section, required this.onShowSource});
  final AnalyticsSection section;
  final void Function(AnalyticsRow) onShowSource;
  @override
  State<_SourceTable> createState() => _SourceTableState();
}

class _SourceTableState extends State<_SourceTable> {
  int _page = 0;
  int? _sortColumn;
  bool _ascending = true;
  static const _pageSize = 10;

  @override
  Widget build(BuildContext context) {
    final section = widget.section;
    final rows = List<AnalyticsRow>.of(section.rows);
    if (_sortColumn != null) {
      final key = section.columns[_sortColumn!].key;
      rows.sort((a, b) {
        final left = a.cells[key];
        final right = b.cells[key];
        final order = left is num && right is num ? left.compareTo(right) :
          (left?.toString() ?? '').compareTo(right?.toString() ?? '');
        return _ascending ? order : -order;
      });
    }
    final start = _page * _pageSize;
    final end = (start + _pageSize).clamp(0, rows.length).toInt();
    return Card(margin: EdgeInsets.zero, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(padding: EdgeInsets.all(12), child: Text('Source detail • table alternative', style: TextStyle(fontWeight: FontWeight.w700))),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
        sortColumnIndex: _sortColumn, sortAscending: _ascending,
        columns: [for (var i = 0; i < section.columns.length; i++) DataColumn(
          label: Text(section.columns[i].label), numeric: section.columns[i].unit != null,
          onSort: (index, ascending) => setState(() { _sortColumn = index; _ascending = ascending; _page = 0; }),
        ), const DataColumn(label: Text('Source'))],
        rows: [for (final row in rows.sublist(start, end)) DataRow(cells: [
          for (final column in section.columns) DataCell(Text(_format(row.cells[column.key], column.unit))),
          DataCell(TextButton(onPressed: () => widget.onShowSource(row), child: Text(_sourceLabel(row)))),
        ])],
      )),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Wrap(alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
          Text('${start + 1}–$end of ${rows.length} source rows'),
          IconButton(tooltip: 'Previous page', onPressed: _page == 0 ? null : () => setState(() => _page--), icon: const Icon(Icons.chevron_left)),
          IconButton(tooltip: 'Next page', onPressed: end >= rows.length ? null : () => setState(() => _page++), icon: const Icon(Icons.chevron_right)),
        ])),
    ]));
  }
}

String _sourceLabel(AnalyticsRow row) {
  final source = row.sourceId ?? row.id;
  final ids = source.split(',');
  return ids.length > 1
      ? '${row.sourceType} • ${ids.length} records'
      : '${row.sourceType} #$source';
}
