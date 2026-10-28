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
import 'business_overview_panel.dart';

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

  void _selectReport(AnalyticsFamily family) {
    _dismissSource();
    setState(() => _family = family);
  }

  List<AnalyticsRow> _rows(AnalyticsFamily family) => _snapshot?.sections
      .where((section) => section.family == family)
      .expand((section) => section.rows).toList() ?? [];

  Widget _quickFilters() {
    final cashiers = <int, String>{
      for (final row in _rows(AnalyticsFamily.staff))
        if (row.cells['role'] == 'CASHIER' && row.cells['staff_id'] is int)
          row.cells['staff_id'] as int: row.cells['name']?.toString() ?? 'Cashier #${row.cells['staff_id']}',
    };
    final shifts = <int, String>{
      for (final row in _rows(AnalyticsFamily.cash))
        if (row.cells['kind'] == 'Shift reconciliation' && row.cells['shift_id'] is int)
          row.cells['shift_id'] as int: 'Shift #${row.cells['shift_id']} · ${row.cells['status']}',
    };
    if (_query.cashierId != null) cashiers.putIfAbsent(_query.cashierId!, () => 'Cashier #${_query.cashierId}');
    if (_query.shiftId != null) shifts.putIfAbsent(_query.shiftId!, () => 'Shift #${_query.shiftId}');
    InputDecoration decoration(String label) => InputDecoration(labelText: label,
      isDense: true, border: const OutlineInputBorder());
    return Wrap(spacing: 10, runSpacing: 10, children: [
      SizedBox(width: 190, child: DropdownButtonFormField<int>(
        key: const ValueKey('analytics_cashier_picker'), value: _query.cashierId,
        isExpanded: true, decoration: decoration('Cashier'),
        items: [const DropdownMenuItem<int>(child: Text('All cashiers')),
          for (final entry in cashiers.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
        onChanged: (value) {
          _cashier.text = value?.toString() ?? '';
          _changeQuery(_query.copyWith(cashierId: value));
        },
      )),
      SizedBox(width: 200, child: DropdownButtonFormField<int>(
        key: const ValueKey('analytics_shift_picker'), value: _query.shiftId,
        isExpanded: true, decoration: decoration('Shift'),
        items: [const DropdownMenuItem<int>(child: Text('All shifts')),
          for (final entry in shifts.entries) DropdownMenuItem(value: entry.key, child: Text(entry.value))],
        onChanged: (value) {
          _shift.text = value?.toString() ?? '';
          _changeQuery(_query.copyWith(shiftId: value));
        },
      )),
      SizedBox(width: 180, child: DropdownButtonFormField<String>(
        key: const ValueKey('analytics_dining_picker'), value: _query.diningType,
        isExpanded: true, decoration: decoration('Dining Type'),
        items: [const DropdownMenuItem<String>(child: Text('All dining types')),
          for (final type in DiningType.values) DropdownMenuItem(value: type.code, child: Text(type.displayName))],
        onChanged: (value) { setState(() => _dining = value); _changeQuery(_query.copyWith(diningType: value)); },
      )),
      SizedBox(width: 180, child: DropdownButtonFormField<String>(
        key: const ValueKey('analytics_payment_picker'), value: _query.paymentMethod,
        isExpanded: true, decoration: decoration('Payment method'),
        items: [const DropdownMenuItem<String>(child: Text('All payments')),
          for (final method in PaymentMethod.values.where((m) => m != PaymentMethod.split))
            DropdownMenuItem(value: method.code, child: Text(method.displayName))],
        onChanged: (value) { setState(() => _payment = value); _changeQuery(_query.copyWith(paymentMethod: value)); },
      )),
    ]);
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
    return ListView(key: const ValueKey('analytics_body'),
      padding: const EdgeInsets.all(20), children: [
      Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_family == AnalyticsFamily.overview ? 'Business overview' : _familyLabels[_family]!,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
          const SizedBox(height: 4),
          Text(_query.live ? 'Active Business Day · Local business intelligence' : 'Business Day reporting · Historical exploration',
            style: const TextStyle(color: StreetFoodMafiaColors.secondaryText, fontSize: 13)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_error != null ? Icons.error_outline : _query.live ? Icons.circle : Icons.history,
            size: 10, color: _error != null ? StreetFoodMafiaColors.statusCanceled : StreetFoodMafiaColors.statusReady),
          const SizedBox(width: 7),
          Text('${_query.live ? 'Live' : 'Historical'}${snapshot == null ? '' : ' · updated ${DateFormat('HH:mm').format(snapshot.generatedAt.isUtc ? snapshot.generatedAt.add(const Duration(hours: 5)) : snapshot.generatedAt)}'}',
            style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
        ]),
      ]),
      const SizedBox(height: 18),
      Container(padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: StreetFoodMafiaColors.darkNavy,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: StreetFoodMafiaColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: 205, child: DropdownButtonFormField<AnalyticsFamily>(
          key: const ValueKey('analytics_family'), value: _family, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Report', isDense: true, border: OutlineInputBorder()),
          items: _familyLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (family) { if (family != null) _selectReport(family); },
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
      const SizedBox(height: 12),
      _quickFilters(),
      ])),
      const SizedBox(height: 12),
      Text('${_query.live ? 'LIVE • refreshes every ${widget.refreshInterval.inSeconds}s' : 'Historical exploration'}'
        ' • Asia/Karachi • ${_query.live ? 'Active Business Day' : '${DateFormat('dd MMM yyyy').format(_query.startDate)} to ${DateFormat('dd MMM yyyy').format(_query.endDateExclusive)} (end exclusive)'}',
        style: const TextStyle(color: StreetFoodMafiaColors.secondaryText, fontSize: 12)),
      if (snapshot != null) Text(
        'Updated ${DateFormat('dd MMM yyyy HH:mm:ss').format(snapshot.generatedAt.isUtc ? snapshot.generatedAt.add(const Duration(hours: 5)) : snapshot.generatedAt)}'
        ' • ${snapshot.businessDayIds.length} Business Days in selection',
        style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
      const SizedBox(height: 8),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
        _filterPanel(),
        if (_error != null) Card(child: Padding(padding: const EdgeInsets.all(12), child: Wrap(
          spacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(_error!, style: const TextStyle(color: StreetFoodMafiaColors.statusCanceled)),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ]))),
        if (snapshot == null && !_busy && _error == null) const Text('No analytics snapshot available.'),
        if (snapshot != null) ...[
          if (snapshot.businessDayIds.isEmpty) _note('No Business Days match this selection. Current-state datasets may still be available.'),
          if (_family == AnalyticsFamily.overview) _overview(snapshot) else ..._report(snapshot),
          ExpansionTile(tilePadding: EdgeInsets.zero,
            title: const Text('Reporting scope & methodology', style: TextStyle(fontSize: 13)),
            children: [
              _note('Business Day IDs: ${snapshot.businessDayIds.join(', ')}'),
              for (final note in snapshot.notes) _note(note),
            ]),
        ],
    ]);
  }

  Widget _filterPanel() => ExpansionTile(
    key: const ValueKey('analytics_filters'), tilePadding: EdgeInsets.zero,
    dense: true,
    leading: const Icon(Icons.tune_rounded, size: 18),
    title: const Text('Order cohort filters', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
    subtitle: Text(_query.cashierId == null && _query.shiftId == null && _query.diningType == null && _query.paymentMethod == null
      ? 'All cashiers, shifts, Dining Types and payment methods' : 'Filters applied • inspect each report’s scope notes',
      style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
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

  Widget _overview(AnalyticsSnapshot snapshot) {
    final sections = snapshot.sections.where((s) => s.family == AnalyticsFamily.overview).toList();
    final sales = snapshot.sections.where((s) => s.family == AnalyticsFamily.sales).toList();
    final overview = sections.isEmpty ? null : sections.first;
    return BusinessOverviewPanel(snapshot: snapshot,
      metricGrid: (metrics, columns) => _metricGrid(metrics, preferredColumns: columns),
      salesChart: _SalesTrend(rows: sales.expand((s) => s.rows).toList(),
        onChangePeriod: () => _selectPreset('week'),
        onExploreSales: () => _selectReport(AnalyticsFamily.sales)),
      dayDetails: overview == null || overview.rows.isEmpty
        ? _note('No Business Day details match this selection.')
        : _SourceTable(key: ValueKey('overview_days_${snapshot.generatedAt.toIso8601String()}'),
            title: 'Business Day details', section: overview,
            onShowSource: (row) => _showSource(overview, row)),
      onReport: _selectReport,
    );
  }

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
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(section.title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
      _metricGrid(section.metrics.take(4).toList()),
      if (section.family == AnalyticsFamily.overview)
        for (final sales in snapshot.sections.where((s) => s.family == AnalyticsFamily.sales))
          if (sales.rows.any((r) => r.cells['business_date'] != null && r.cells['recorded_value_paisa'] is num))
            _SalesTrend(rows: sales.rows),
      if (section.family == AnalyticsFamily.sales && section.rows.any((r) => r.cells['business_date'] != null && r.cells['recorded_value_paisa'] is num))
        _SalesTrend(rows: section.rows),
      if (section.metrics.length > 4) ...[
        const Padding(padding: EdgeInsets.only(top: 24, bottom: 12),
          child: Text('Additional measures', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        _metricGrid(section.metrics.skip(4).toList()),
      ],
      if (section.notes.isNotEmpty)
        ExpansionTile(tilePadding: EdgeInsets.zero,
          title: const Text('Measure definitions & scope', style: TextStyle(fontSize: 13)),
          children: [for (final note in section.notes) _note(note)]),
      const SizedBox(height: 12),
      if (section.columns.isNotEmpty && section.rows.isNotEmpty)
        _SourceTable(key: ValueKey('table_${section.family.name}_${snapshot.generatedAt.toIso8601String()}_${section.title}'),
          section: section, onShowSource: (row) => _showSource(section, row))
      else _note(section.rows.isEmpty ? 'No source rows match this report. Missing inputs are explained above.' : 'Source detail unavailable for this dataset.'),
      const SizedBox(height: 16),
    ]];
  }

  Widget _metricGrid(List<AnalyticsMetric> metrics, {int preferredColumns = 4}) => LayoutBuilder(builder: (context, constraints) {
    final columns = constraints.maxWidth >= 1000 ? preferredColumns : constraints.maxWidth >= 680 ? 2 : 1;
    final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
    return Wrap(spacing: 16, runSpacing: 16, children: [
      for (final metric in metrics) SizedBox(width: width, child: _metricCard(metric)),
    ]);
  });

  Widget _metricCard(AnalyticsMetric metric) {
    final quality = switch (metric.quality) {
      AnalyticsQuality.complete => 'Complete',
      AnalyticsQuality.estimated => 'Estimated',
      AnalyticsQuality.missing => 'Missing data',
      AnalyticsQuality.notApplicable => 'Not applicable',
    };
    final available = metric.value != null;
    final icon = switch (metric.id) {
      'recorded_value' => Icons.monetization_on_outlined,
      'orders' => Icons.receipt_long_outlined,
      'average_ticket' => Icons.bar_chart_rounded,
      'negative_stock' => Icons.inventory_2_outlined,
      'expected_drawer' => Icons.point_of_sale_rounded,
      _ => switch (metric.unit) {
      AnalyticsUnit.paisa => Icons.account_balance_wallet_outlined,
      AnalyticsUnit.percent => Icons.percent_rounded,
      AnalyticsUnit.minutes => Icons.schedule_rounded,
      _ => Icons.bar_chart_rounded,
      },
    };
    return Container(constraints: const BoxConstraints(minHeight: 134),
      decoration: BoxDecoration(color: StreetFoodMafiaColors.darkNavy,
        border: Border.all(color: StreetFoodMafiaColors.border),
        borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 22, color: StreetFoodMafiaColors.cartelYellow),
          const SizedBox(width: 10),
          Expanded(child: Text(metric.label, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600, color: StreetFoodMafiaColors.secondaryText))),
          const SizedBox(width: 8),
          Tooltip(message: metric.explanation, child: const Icon(Icons.info_outline,
            size: 16, color: StreetFoodMafiaColors.secondaryText)),
        ]),
        const SizedBox(height: 12),
        SelectableText(_format(metric.value, metric.unit),
          style: TextStyle(fontSize: available ? 25 : 22, height: 1.2,
            letterSpacing: -0.6, fontWeight: FontWeight.w700, color: StreetFoodMafiaColors.offWhite)),
        if (metric.quality != AnalyticsQuality.complete) ...[
          const SizedBox(height: 8),
          Text(quality, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
            color: StreetFoodMafiaColors.burntGold)),
        ],
        const SizedBox(height: 8),
        Tooltip(message: metric.explanation, child: Text(metric.explanation,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, height: 1.5, color: StreetFoodMafiaColors.secondaryText))),
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
  const _SalesTrend({required this.rows, this.onChangePeriod, this.onExploreSales});
  final List<AnalyticsRow> rows;
  final VoidCallback? onChangePeriod, onExploreSales;

  @override
  Widget build(BuildContext context) {
    final daily = rows.where((r) => r.cells['business_date'] != null && r.cells['recorded_value_paisa'] is num).toList();
    final maximum = daily.fold<double>(0, (max, row) {
      final value = (row.cells['recorded_value_paisa'] as num).toDouble();
      return value > max ? value : max;
    });
    return Container(
      decoration: BoxDecoration(color: StreetFoodMafiaColors.darkNavy,
        borderRadius: BorderRadius.circular(12), border: Border.all(color: StreetFoodMafiaColors.border)),
      child: Padding(padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          const Icon(Icons.bar_chart_rounded, color: StreetFoodMafiaColors.cartelYellow, size: 23),
          const Text('Sales performance', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (onExploreSales != null) TextButton(onPressed: onExploreSales, child: const Text('Explore sales')),
        ]),
        const SizedBox(height: 4),
        const Text('Recorded order value (PKR) • by Business Day opening date',
          style: TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
        const SizedBox(height: 24),
        if (daily.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 18),
          child: Text('No sales data for this selection. Try another Business Day period.',
            style: TextStyle(color: StreetFoodMafiaColors.secondaryText)))
        else if (daily.length == 1) _singleDay(daily.single)
        else LayoutBuilder(builder: (context, constraints) {
          final minimumWidth = daily.length * 56.0;
          final plotWidth = (constraints.maxWidth - 64).clamp(minimumWidth, double.infinity).toDouble();
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 64, height: 160, child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [for (final fraction in [1.0, 0.5, 0.0])
                Text(NumberFormat.compact().format(maximum / 100 * fraction),
                  style: const TextStyle(fontSize: 11, color: StreetFoodMafiaColors.secondaryText))],
            )),
            Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal,
              child: SizedBox(width: plotWidth, height: 194, child: Stack(children: [
                for (final offset in [0.0, 80.0, 160.0])
                  Positioned(top: offset, left: 0, right: 0,
                    child: Container(height: 1, color: StreetFoodMafiaColors.border)),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [for (final row in daily)
                  Expanded(child: Tooltip(message: '${row.cells['business_date']}\n'
                    '${_format(row.cells['recorded_value_paisa'], AnalyticsUnit.paisa)} • ${row.cells['orders']} orders',
                    child: Semantics(label: '${row.cells['business_date']}: '
                      '${_format(row.cells['recorded_value_paisa'], AnalyticsUnit.paisa)}, ${row.cells['orders']} orders',
                      child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Container(width: 22, height: maximum == 0 ? 0 :
                          ((row.cells['recorded_value_paisa'] as num).toDouble() / maximum * 160).clamp(0, 160).toDouble(),
                          decoration: BoxDecoration(
                            color: StreetFoodMafiaColors.cartelYellow,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)))),
                        SizedBox(height: 34, child: Center(child: Text(
                          _chartDate(row.cells['business_date'].toString()),
                          style: const TextStyle(fontSize: 10, color: StreetFoodMafiaColors.secondaryText)))),
                      ])))),
                ]),
              ])))),
          ]);
        }),
        const SizedBox(height: 12),
        const Text('Daily totals include Collection Due. Hover or long press for exact values. Explore Sales for source records.',
          style: TextStyle(fontSize: 11, color: StreetFoodMafiaColors.secondaryText)),
        if (daily.length <= 1 && onChangePeriod != null) ...[
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(
            color: StreetFoodMafiaColors.cardSurface, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: StreetFoodMafiaColors.border)),
            child: Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Icon(Icons.info_outline, size: 20, color: StreetFoodMafiaColors.secondaryText),
              const Text('Select multiple Business Days to see a trend', style: TextStyle(fontSize: 12)),
              OutlinedButton.icon(onPressed: onChangePeriod, icon: const Icon(Icons.arrow_forward, size: 16),
                label: const Text('Change period')),
            ])),
        ],
      ])));
  }

  Widget _singleDay(AnalyticsRow row) {
    final value = row.cells['recorded_value_paisa'] as num;
    final amount = _format(value, AnalyticsUnit.paisa);
    return Semantics(label: '${row.cells['business_date']}: $amount, ${row.cells['orders']} orders',
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(_chartDate(row.cells['business_date'].toString()), style: const TextStyle(fontSize: 12)),
            const Spacer(),
            Text(amount, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          Tooltip(message: '$amount · ${row.cells['orders']} orders',
            child: ClipRRect(borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(minHeight: 24, value: value > 0 ? 1 : 0,
                color: StreetFoodMafiaColors.cartelYellow, backgroundColor: StreetFoodMafiaColors.cardSurface))),
          const SizedBox(height: 8),
          Text('${row.cells['orders']} eligible orders',
            style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
        ])));
  }

  String _chartDate(String value) {
    final date = DateTime.tryParse(value);
    return date == null ? value : DateFormat('dd MMM').format(date);
  }
}

class _SourceTable extends StatefulWidget {
  const _SourceTable({super.key, required this.section, required this.onShowSource,
    this.title = 'Source detail • table alternative'});
  final AnalyticsSection section;
  final String title;
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
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        if (widget.title == 'Business Day details') ...[
          const Icon(Icons.calendar_month_outlined, size: 20), const SizedBox(width: 10),
        ],
        Expanded(child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700))),
        Text('${rows.length} records', style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
      ])),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: DataTable(
        sortColumnIndex: _sortColumn, sortAscending: _ascending,
        columns: [for (var i = 0; i < section.columns.length; i++) DataColumn(
          label: Text(section.columns[i].label), numeric: section.columns[i].unit != null,
          onSort: (index, ascending) => setState(() { _sortColumn = index; _ascending = ascending; _page = 0; }),
        ), const DataColumn(label: Text('Source'))],
        rows: [for (final row in rows.sublist(start, end)) DataRow(cells: [
          for (final column in section.columns) DataCell(_cell(row, column)),
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

  Widget _cell(AnalyticsRow row, AnalyticsColumn column) {
    final value = row.cells[column.key];
    if (row.sourceType == 'business_days' && column.key == 'status') {
      final open = value == 'OPEN';
      final color = open ? StreetFoodMafiaColors.statusReady : StreetFoodMafiaColors.secondaryText;
      return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: StreetFoodMafiaColors.cardSurface, borderRadius: BorderRadius.circular(16)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(open ? Icons.circle : Icons.lock_outline, size: 10, color: color),
          const SizedBox(width: 6), Text(open ? 'Open' : 'Closed', style: TextStyle(color: color, fontSize: 12)),
        ]));
    }
    if (row.sourceType == 'business_days' && ['business_date', 'opened_at', 'closed_at'].contains(column.key)) {
      final date = DateTime.tryParse(value?.toString() ?? '');
      final local = date?.isUtc == true ? date!.add(const Duration(hours: 5)) : date;
      return Text(local == null ? '—' : DateFormat(column.key == 'business_date'
        ? 'dd MMM yyyy' : 'dd MMM, HH:mm').format(local));
    }
    return Text(_format(value, column.unit));
  }
}

String _sourceLabel(AnalyticsRow row) {
  final source = row.sourceId ?? row.id;
  final ids = source.split(',');
  return ids.length > 1
      ? '${row.sourceType} • ${ids.length} records'
      : '${row.sourceType} #$source';
}
