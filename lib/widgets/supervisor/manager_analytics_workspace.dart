import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';

import '../../core/analytics/analytics_models.dart';
import '../../core/analytics/analytics_service.dart';
import '../../core/auth/session_state.dart';
import '../../core/analytics/manager_report_controller.dart';
import '../../core/orders/dining_type.dart';
import '../../core/orders/payment_method.dart';
import '../../core/theme/theme.dart';
import 'business_overview_panel.dart';
import 'report_visualizations.dart';
import 'customer_information_panel.dart';

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
  late final ManagerReportController _reports;
  AnalyticsQuery get _query => _reports.query;
  AnalyticsSnapshot? get _snapshot => _reports.snapshot;
  bool get _busy => _reports.busy;
  String? get _error => _reports.error;
  bool get _authorized => _reports.authorized;
  AnalyticsSnapshot? _sourceSnapshot;
  DialogRoute<void>? _sourceRoute;
  AnalyticsFamily _family = AnalyticsFamily.overview;
  bool _filtersExpanded = false;
  String _preset = 'live';
  final _filtersKey = GlobalKey<FormState>();
  final _cashier = TextEditingController();
  final _shift = TextEditingController();
  String? _dining;
  String? _payment;

  DateTime get _now => widget.clock?.call() ??
      DateTime.now().toUtc().add(const Duration(hours: 5));
  DateTime get _today => DateTime(_now.year, _now.month, _now.day);
  @override
  void initState() {
    super.initState();
    _reports = ManagerReportController(service: widget.service, session: widget.session,
      query: AnalyticsQuery(startDate: _today,
        endDateExclusive: _today.add(const Duration(days: 1)), live: true),
      refreshInterval: widget.refreshInterval);
    _reports.addListener(_reportsChanged);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  void _reportsChanged() {
    if (!identical(_sourceSnapshot, _snapshot)) {
      _dismissSource();
      _sourceSnapshot = _snapshot;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant ManagerAnalyticsWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service || oldWidget.session != widget.session ||
        oldWidget.refreshInterval != widget.refreshInterval) {
      _reports.configure(service: widget.service, session: widget.session,
        refreshInterval: widget.refreshInterval);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _reports.setVisible(state == AppLifecycleState.resumed);

  Future<void> _load() => _reports.refresh();

  void _changeQuery(AnalyticsQuery query) {
    _dismissSource();
    _reports.changeQuery(query);
  }

  AnalyticsQuery _withDates(DateTime start, DateTime end, {required bool live}) =>
      AnalyticsQuery(startDate: start, endDateExclusive: end, live: live,
        cashierId: _query.cashierId, shiftId: _query.shiftId,
        diningType: _query.diningType, paymentMethod: _query.paymentMethod, timeBasis: _query.timeBasis, grouping: _query.grouping);

  Future<void> _selectPreset(String? value) async {
    if (value == null) return;
    if (value == 'custom') {
      final range = await showDateRangePicker(context: context,
        firstDate: DateTime(2000), lastDate: _today,
        initialDateRange: DateTimeRange(start: _query.startDate,
          end: _query.endDateExclusive.subtract(const Duration(days: 1))),
        helpText: _query.timeBasis == AnalyticsTimeBasis.businessDay ? 'Select Business Day opening dates (inclusive)' : 'Select Karachi calendar dates (inclusive)');
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
      diningType: _dining, paymentMethod: _payment, timeBasis: _query.timeBasis, grouping: _query.grouping));
  }

  void _selectReport(AnalyticsFamily family) {
    _dismissSource();
    setState(() => _family = family);
  }

  List<AnalyticsRow> _rows(AnalyticsFamily family) => _snapshot?.sections
      .where((section) => section.family == family)
      .expand((section) => section.rows).toList() ?? [];

  List<Widget> _quickFilterFields({bool compact = false}) {
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
    return [
      SizedBox(width: compact ? 130 : 190, child: DropdownButtonFormField<int>(
        key: const ValueKey('analytics_cashier_picker'), value: _query.cashierId,
        isExpanded: true, decoration: decoration('Cashier'),
        items: [DropdownMenuItem<int>(child: Text(compact ? 'All' : 'All cashiers')),
          for (final entry in cashiers.entries) DropdownMenuItem(value: entry.key,
            child: Text(entry.value, maxLines: 1, overflow: TextOverflow.ellipsis))],
        onChanged: (value) {
          _cashier.text = value?.toString() ?? '';
          _changeQuery(_query.copyWith(cashierId: value));
        },
      )),
      SizedBox(width: compact ? 130 : 200, child: DropdownButtonFormField<int>(
        key: const ValueKey('analytics_shift_picker'), value: _query.shiftId,
        isExpanded: true, decoration: decoration('Shift'),
        items: [DropdownMenuItem<int>(child: Text(compact ? 'All' : 'All shifts')),
          for (final entry in shifts.entries) DropdownMenuItem(value: entry.key,
            child: Text(entry.value, maxLines: 1, overflow: TextOverflow.ellipsis))],
        onChanged: (value) {
          _shift.text = value?.toString() ?? '';
          _changeQuery(_query.copyWith(shiftId: value));
        },
      )),
      SizedBox(width: compact ? 145 : 180, child: DropdownButtonFormField<String>(
        key: const ValueKey('analytics_dining_picker'), value: _query.diningType,
        isExpanded: true, decoration: decoration('Dining Type'),
        items: [DropdownMenuItem<String>(child: Text(compact ? 'All' : 'All dining types')),
          for (final type in DiningType.values) DropdownMenuItem(value: type.code, child: Text(type.displayName))],
        onChanged: (value) { setState(() => _dining = value); _changeQuery(_query.copyWith(diningType: value)); },
      )),
      SizedBox(width: compact ? 140 : 180, child: DropdownButtonFormField<String>(
        key: const ValueKey('analytics_payment_picker'), value: _query.paymentMethod,
        isExpanded: true, decoration: decoration('Payment method'),
        items: [DropdownMenuItem<String>(child: Text(compact ? 'All' : 'All payments')),
          for (final method in PaymentMethod.values.where((m) => m != PaymentMethod.split))
            DropdownMenuItem(value: method.code, child: Text(method.displayName))],
        onChanged: (value) { setState(() => _payment = value); _changeQuery(_query.copyWith(paymentMethod: value)); },
      )),
    ];
  }

  @override
  void dispose() {
    _dismissSource();
    _reports.removeListener(_reportsChanged);
    _reports.dispose();
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

  void _showChartSources(AnalyticsSection section, String title, List<AnalyticsRow> rows) {
    final snapshot = _snapshot;
    if (snapshot == null || !_authorized || rows.isEmpty) return;
    _dismissSource();
    final projection = AnalyticsSection(family: section.family, title: title,
      columns: section.columns, rows: rows);
    final route = DialogRoute<void>(context: context, builder: (context) {
      if (!mounted || !_authorized || !identical(_snapshot, snapshot)) return const SizedBox.shrink();
      return AlertDialog(title: Text(title),
        content: SizedBox(width: 900, height: 480, child: SingleChildScrollView(
          child: _SourceTable(section: projection, title: 'Chart source records',
            onShowSource: (row) => _showSource(section, row)))),
        actions: [TextButton(onPressed: _dismissSource, child: const Text('Close'))]);
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
            style: WarmCounterTypography.brandHeading.copyWith(fontSize: 28)),
          const SizedBox(height: 4),
          Text(_query.live ? 'Active Business Day${_activeDate(snapshot)}' : 'Business Day reporting · Historical exploration',
            style: const TextStyle(color: StreetFoodMafiaColors.secondaryText, fontSize: 13)),
        ]),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_error != null ? Icons.error_outline : _query.live ? Icons.circle : Icons.history,
            size: 10, color: _error != null ? StreetFoodMafiaColors.statusCanceled : StreetFoodMafiaColors.statusReady),
          const SizedBox(width: 7),
          Text('${_query.live ? 'Live' : 'Historical'}${snapshot == null ? '' : ' · updated ${DateFormat('HH:mm').format(snapshot.generatedAt.isUtc ? snapshot.generatedAt.add(const Duration(hours: 5)) : snapshot.generatedAt)}'}',
            style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
        ]),
        if (snapshot != null && _error == null && !_busy && widget.exportActionsBuilder != null)
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 240),
            child: widget.exportActionsBuilder!(context, snapshot, _family)),
      ]),
      const SizedBox(height: 18),
      Container(padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: StreetFoodMafiaColors.darkNavy,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: StreetFoodMafiaColors.border)),
        child: LayoutBuilder(builder: (context, constraints) {
          final compact = constraints.maxWidth >= 1100;
          return Wrap(spacing: 8, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SizedBox(width: compact ? 140 : 205, child: DropdownButtonFormField<AnalyticsFamily>(
          key: const ValueKey('analytics_family'), value: _family, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Report', isDense: true, border: OutlineInputBorder()),
          items: _familyLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (family) { if (family != null) _selectReport(family); },
        )),
        SizedBox(width: compact ? 155 : 190, child: DropdownButtonFormField<String>(
          key: const ValueKey('analytics_period'), value: _preset, isExpanded: true,
          decoration: InputDecoration(labelText: _query.timeBasis == AnalyticsTimeBasis.businessDay ? 'Business Day period' : 'Calendar Order period', isDense: true, border: const OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'live', child: Text('Active day')),
            DropdownMenuItem(value: 'today', child: Text('Today')),
            DropdownMenuItem(value: 'yesterday', child: Text('Previous day')),
            DropdownMenuItem(value: 'week', child: Text('Last 7 dates')),
            DropdownMenuItem(value: 'month', child: Text('Last 30 dates')),
            DropdownMenuItem(value: 'custom', child: Text('Custom range…')),
          ], onChanged: _selectPreset,
        )),
        SizedBox(width: 185, child: DropdownButtonFormField<AnalyticsTimeBasis>(
          key: const ValueKey('analytics_time_basis'), value: _query.timeBasis,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Order time basis', isDense: true, border: OutlineInputBorder()),
          items: const [DropdownMenuItem(value: AnalyticsTimeBasis.businessDay, child: Text('Business Day')),
            DropdownMenuItem(value: AnalyticsTimeBasis.calendarTime, child: Text('Calendar time'))],
          onChanged: (value) { if (value != null) _changeQuery(_query.copyWith(timeBasis: value)); },
        )),
        SizedBox(width: 140, child: DropdownButtonFormField<AnalyticsGrouping>(
          key: const ValueKey('analytics_grouping'), value: _query.grouping, isExpanded: true,
          decoration: const InputDecoration(labelText: 'Order grouping', isDense: true, border: OutlineInputBorder()),
          items: const [DropdownMenuItem(value: AnalyticsGrouping.day, child: Text('Day')),
            DropdownMenuItem(value: AnalyticsGrouping.week, child: Text('Week (Mon)')),
            DropdownMenuItem(value: AnalyticsGrouping.month, child: Text('Month'))],
          onChanged: (value) { if (value != null) _changeQuery(_query.copyWith(grouping: value)); },
        )),
        if (compact) ..._quickFilterFields(compact: true),
        IconButton.outlined(key: const ValueKey('analytics_refresh'), tooltip: 'Refresh analytics',
          onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh)),
        TextButton.icon(key: const ValueKey('analytics_filters_toggle'),
          onPressed: () => setState(() => _filtersExpanded = !_filtersExpanded),
          icon: const Icon(Icons.tune_rounded, size: 18), label: const Text('Filters')),
        if (!compact && constraints.maxWidth >= 600)
          SizedBox(width: constraints.maxWidth, child: Wrap(spacing: 10, runSpacing: 10, children: _quickFilterFields())),
        if (constraints.maxWidth < 600) Material(color: Colors.transparent,
          child: ExpansionTile(tilePadding: EdgeInsets.zero,
          title: const Text('Quick filters', style: TextStyle(fontSize: 13)),
          children: [Wrap(spacing: 10, runSpacing: 10, children: _quickFilterFields())])),
      ]);
      })),
      const SizedBox(height: 12),
      Text('${_query.live ? 'LIVE • refreshes every ${widget.refreshInterval.inSeconds}s' : 'Historical exploration'}'
        ' • Asia/Karachi • ${_query.live ? 'Active Business Day' : '${DateFormat('dd MMM yyyy').format(_query.startDate)} to ${DateFormat('dd MMM yyyy').format(_query.endDateExclusive)} (end exclusive)'}'
        '${snapshot == null ? '' : ' • ${snapshot.businessDayIds.length} Business Days'}',
        style: const TextStyle(color: StreetFoodMafiaColors.secondaryText, fontSize: 12)),
      Text('Order activity: ${_query.timeBasis == AnalyticsTimeBasis.businessDay ? 'assigned Business Day weekday' : 'actual calendar weekday'} � ${_query.grouping.name} � weeks start Monday � local calendar months. Other ledgers retain Business Day scope.', style: const TextStyle(fontSize: 12)),
      if (snapshot != null && _family != AnalyticsFamily.overview) Text(
        'Updated ${DateFormat('dd MMM yyyy HH:mm:ss').format(snapshot.generatedAt.isUtc ? snapshot.generatedAt.add(const Duration(hours: 5)) : snapshot.generatedAt)}'
        ' • ${snapshot.businessDayIds.length} Business Days in selection',
        style: const TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
      const SizedBox(height: 8),
      if (_busy) const LinearProgressIndicator(minHeight: 2),
        if (_filtersExpanded) _filterPanel(),
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
    initiallyExpanded: true,
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
      metricGrid: (metrics, columns) => _metricGrid(metrics, preferredColumns: columns, compact: true),
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
      if (section.family == AnalyticsFamily.customers)
        CustomerInformationPanel(key: const ValueKey('customer_information'), snapshotToken: snapshot,
          load: () => widget.service.loadCustomerDetails(snapshot.query)),
      if (section.family == AnalyticsFamily.overview)
        for (final sales in snapshot.sections.where((s) => s.family == AnalyticsFamily.sales))
          if (sales.rows.any((r) => r.cells['business_date'] != null && r.cells['recorded_value_paisa'] is num))
            _SalesTrend(rows: sales.rows),
      if (section.family == AnalyticsFamily.sales && section.rows.any((r) => r.cells['business_date'] != null && r.cells['recorded_value_paisa'] is num))
        _SalesTrend(rows: section.rows),
      if (section.family != AnalyticsFamily.overview && section.family != AnalyticsFamily.sales)
        ReportVisualizations(key: ValueKey('analytics_visuals_${section.family.name}'),
          section: section, onInspect: (title, rows) => _showChartSources(section, title, rows)),
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

  String _activeDate(AnalyticsSnapshot? snapshot) {
    final days = snapshot?.sections.where((s) => s.family == AnalyticsFamily.overview)
      .expand((s) => s.rows).where((r) => r.cells['status'] == 'OPEN').toList() ?? [];
    if (days.isEmpty) return '';
    final date = DateTime.tryParse(days.last.cells['business_date']?.toString() ?? '');
    return date == null ? '' : ' · ${DateFormat('dd MMM yyyy').format(date)}';
  }

  Widget _metricGrid(List<AnalyticsMetric> metrics, {int preferredColumns = 4, bool compact = false}) => LayoutBuilder(builder: (context, constraints) {
    final columns = constraints.maxWidth >= 1000 ? preferredColumns : constraints.maxWidth >= 680 ? 2 : 1;
    final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
    return Wrap(spacing: 16, runSpacing: 16, children: [
      for (final metric in metrics) SizedBox(width: width, child: _metricCard(metric, compact: compact)),
    ]);
  });

  Widget _metricCard(AnalyticsMetric metric, {bool compact = false}) {
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
    final summary = compact ? switch (metric.id) {
      'recorded_value' => 'Includes Collection Due',
      'orders' => 'Eligible committed orders',
      'average_ticket' => 'Per eligible order${metric.sampleCount == null ? '' : ' · ${metric.sampleCount} covered'}',
      'collection_due' => 'Selected filtered Business Days',
      'all_collection_due' => 'All Business Days',
      'expected_drawer' => 'All shifts in selected Business Days',
      'negative_stock' => 'Current inventory position',
      _ => metric.explanation,
    } : metric.explanation;
    return Container(constraints: BoxConstraints(minHeight: compact ? 124 : 134),
      decoration: BoxDecoration(color: StreetFoodMafiaColors.darkNavy,
        border: Border.all(color: StreetFoodMafiaColors.border),
        borderRadius: BorderRadius.circular(12)),
      child: Padding(padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 22, color: StreetFoodMafiaColors.cartelYellow),
          const SizedBox(width: 10),
          Expanded(child: Text(compact ? switch (metric.id) {
            'collection_due' => 'Collection Due',
            'all_collection_due' => 'Outstanding collections',
            'negative_stock' => 'Negative stock items',
            _ => metric.label,
          } : metric.label, style: const TextStyle(fontSize: 12,
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
        Tooltip(message: metric.explanation, child: Text(summary,
          maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, height: 1.5, color: StreetFoodMafiaColors.secondaryText))),
        if (metric.id == 'negative_stock' && metric.value == 0 && metric.quality == AnalyticsQuality.complete)
          const Padding(padding: EdgeInsets.only(top: 6), child: Row(children: [
            Icon(Icons.check_circle, size: 15, color: StreetFoodMafiaColors.statusReady),
            SizedBox(width: 6), Text('No negative stock', style: TextStyle(fontSize: 11,
              color: StreetFoodMafiaColors.statusReady)),
          ])),
        if (metric.sampleCount != null && !compact) Text('Coverage: ${metric.sampleCount}'
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
          if (onExploreSales != null) TextButton(onPressed: onExploreSales,
            style: TextButton.styleFrom(minimumSize: const Size(0, 24), padding: const EdgeInsets.symmetric(horizontal: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap), child: const Text('Explore sales')),
        ]),
        const SizedBox(height: 4),
        const Text('Recorded order value (PKR) • by Business Day opening date',
          style: TextStyle(fontSize: 12, color: StreetFoodMafiaColors.secondaryText)),
        const SizedBox(height: 12),
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
        if (onExploreSales == null) const Text('Daily totals include Collection Due. Hover or long press for exact values. Explore Sales for source records.',
          style: TextStyle(fontSize: 11, color: StreetFoodMafiaColors.secondaryText)),
        if (daily.length <= 1 && onChangePeriod != null) ...[
          const SizedBox(height: 14),
          Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(
            color: StreetFoodMafiaColors.cardSurface, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: StreetFoodMafiaColors.border)),
            child: Wrap(spacing: 12, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Icon(Icons.info_outline, size: 20, color: StreetFoodMafiaColors.secondaryText),
              const Text('Select multiple Business Days to see a trend', style: TextStyle(fontSize: 12)),
              TextButton.icon(onPressed: onChangePeriod, icon: const Icon(Icons.arrow_forward, size: 16),
                style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 4),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                label: const Text('Change period')),
            ])),
        ],
      ])));
  }

  Widget _singleDay(AnalyticsRow row) {
    final value = row.cells['recorded_value_paisa'] as num;
    final amount = _format(value, AnalyticsUnit.paisa);
    return Semantics(label: '${row.cells['business_date']}: $amount, ${row.cells['orders']} orders',
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(_chartDate(row.cells['business_date'].toString()), style: const TextStyle(fontSize: 12)),
            const Spacer(),
            Text(amount, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          Tooltip(message: '$amount · ${row.cells['orders']} orders',
            child: ClipRRect(borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(minHeight: 20, value: value > 0 ? 1 : 0,
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
      LayoutBuilder(builder: (context, constraints) =>
      SingleChildScrollView(scrollDirection: Axis.horizontal,
        child: ConstrainedBox(constraints: BoxConstraints(minWidth: constraints.maxWidth), child: DataTable(
        sortColumnIndex: _sortColumn, sortAscending: _ascending,
        columns: [for (var i = 0; i < section.columns.length; i++) DataColumn(
          label: Text(section.columns[i].label), numeric: section.columns[i].unit != null,
          onSort: (index, ascending) => setState(() { _sortColumn = index; _ascending = ascending; _page = 0; }),
        ), const DataColumn(label: Text('Source'))],
        rows: [for (final row in rows.sublist(start, end)) DataRow(cells: [
          for (final column in section.columns) DataCell(_cell(row, column)),
          DataCell(TextButton(onPressed: () => widget.onShowSource(row), child: Text(_sourceLabel(row)))),
        ])],
      )))),
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
