import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/supervisor/manager_analytics_workspace.dart';
import 'package:resturant_sys/widgets/supervisor/report_visualizations.dart';

import 'manager_analytics_workspace_test.dart' show SnapshotService;

AnalyticsRow evidence(String source, String id, Map<String, Object?> cells) =>
  AnalyticsRow(id: id, sourceId: id, sourceType: source, cells: cells);

AnalyticsSection expenseFixture() => AnalyticsSection(family: AnalyticsFamily.expenses,
  title: 'Expenses and outflows', columns: const [
    AnalyticsColumn(key: 'category', label: 'Category'),
    AnalyticsColumn(key: 'amount_paisa', label: 'Amount', unit: AnalyticsUnit.paisa),
    AnalyticsColumn(key: 'created_at', label: 'Posted at'),
  ], rows: [
    evidence('expense_entries', '1', {'category': 'Utilities', 'amount_paisa': 150000, 'created_at': '2026-10-27 12:00:00'}),
    evidence('expense_entries', '2', {'category': 'Rent', 'amount_paisa': 500000, 'created_at': '2026-10-28 12:00:00'}),
    evidence('expense_entries', '3', {'category': 'Utilities', 'amount_paisa': -25000, 'created_at': '2026-10-28 13:00:00'}),
    evidence('cash_movements', '4', {'category': 'Supplier payment', 'amount_paisa': 300000, 'created_at': '2026-10-28 14:00:00'}),
  ]);

void main() {
  setUpAll(() async {
    if (Platform.environment['CAPTURE_DESKTOP'] != 'true') return;
    final file = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if (!await file.exists()) return;
    final font = FontLoader(WarmCounterTypography.fontFamily)
      ..addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));
    await font.load();
    final icons = FontLoader('MaterialIcons')..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final family in AnalyticsFamily.values.where((f) =>
      f != AnalyticsFamily.overview && f != AnalyticsFamily.sales)) {
    testWidgets('${family.name} report exposes scoped visual analysis', (tester) async {
      tester.view.physicalSize = const Size(1366, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManagerAnalyticsWorkspace(
        service: SnapshotService(onLoad: (query) async => AnalyticsSnapshot(
          query: query, generatedAt: DateTime(2026, 10, 28), businessDayIds: [1],
          sections: [AnalyticsSection(family: family, title: '${family.name} evidence',
            metrics: const [AnalyticsMetric(id: 'fixture', label: 'Recorded evidence',
              value: 2, unit: AnalyticsUnit.count, explanation: 'Synthetic report fixture')])],
        )),
      ))));
      await tester.pumpAndSettle();
      // Exercise the actual report-selection callback; dropdown navigation is
      // independently covered by the dashboard and analytics workspace tests.
      tester.widget<DropdownButtonFormField<AnalyticsFamily>>(
        find.byKey(const ValueKey('analytics_family'))).onChanged!(family);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('analytics_visuals_${family.name}')), findsOneWidget);
      expect(find.text('Visual analysis'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Chart drill-down shows only contributing records and is revoked on session lock', (tester) async {
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = SessionState()..login(const Staff(id: 1, name: 'Manager', departmentId: 1,
      pinHash: 'fixture', role: StaffRole.manager, isActive: true));
    addTearDown(session.dispose);
    await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
      home: Scaffold(body: ManagerAnalyticsWorkspace(session: session,
        service: SnapshotService(onLoad: (query) async => AnalyticsSnapshot(query: query,
          generatedAt: DateTime(2026, 10, 28), businessDayIds: [1], sections: [expenseFixture()]))))));
    await tester.pumpAndSettle();
    tester.widget<DropdownButtonFormField<AnalyticsFamily>>(
      find.byKey(const ValueKey('analytics_family'))).onChanged!(AnalyticsFamily.expenses);
    await tester.pumpAndSettle();
    final point = find.byKey(const ValueKey('chart_point_expense_categories_1'));
    await tester.ensureVisible(point);
    await tester.tap(point);
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('Chart source records')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('expense_entries #1')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('expense_entries #3')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('expense_entries #2')), findsNothing);
    expect(find.descendant(of: dialog, matching: find.text('cash_movements #4')), findsNothing);
    session.lock();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Manager session required'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Chart pages expose every ranked value and preserve evidence on the next page', (tester) async {
    List<AnalyticsRow>? inspected;
    final section = AnalyticsSection(family: AnalyticsFamily.suppliers, title: 'Supplier Khata', rows: [
      for (var id = 1; id <= 12; id++) evidence('vendor_khata', '$id', {
        'name': 'Supplier $id', 'current_paisa': (13 - id) * 10000,
      }),
    ]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: ReportVisualizations(section: section, onInspect: (_, rows) => inspected = rows)))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Next chart values'));
    await tester.tap(find.byTooltip('Next chart values'));
    await tester.pumpAndSettle();
    expect(find.text('9–12 of 12'), findsOneWidget);
    final point = find.byKey(const ValueKey('chart_point_supplier_payable_8'));
    await tester.ensureVisible(point);
    await tester.tap(point);
    expect(inspected!.single.sourceId, '9');
    expect(tester.takeException(), isNull);
  });

  for (final width in [1366.0, 390.0]) {
    testWidgets('Recorded expense charts render at ${width.toInt()}px and large text', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(width < 600 ? 1.3 : 1)), child: child!),
        home: Scaffold(body: RepaintBoundary(key: const ValueKey('report_visual_preview'),
          child: SingleChildScrollView(padding: const EdgeInsets.all(20),
            child: ReportVisualizations(section: expenseFixture(), onInspect: (_, __) {}))))));
      await tester.pumpAndSettle();
      expect(find.text('Operating expenses by category'), findsOneWidget);
      expect(find.text('PKR 1,250.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (Platform.environment['CAPTURE_DESKTOP'] == 'true') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('report_visual_preview')));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = await Directory('build/desktop-previews').create(recursive: true);
          await File('${directory.path}/expense-visuals-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  testWidgets('Cash charts render negative variance and unavailable blind counts without overflow', (tester) async {
    final section = AnalyticsSection(family: AnalyticsFamily.cash, title: 'Cash and shifts', rows: [
      evidence('shifts', '1', {'kind': 'Shift reconciliation', 'shift_id': 1,
        'expected_paisa': 10000, 'counted_paisa': 9000, 'variance_paisa': -1000}),
      evidence('shifts', '2', {'kind': 'Shift reconciliation', 'shift_id': 2,
        'expected_paisa': 0, 'counted_paisa': null, 'variance_paisa': null}),
    ]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: ReportVisualizations(section: section, onInspect: (_, __) {})))));
    await tester.pumpAndSettle();
    expect(find.text('PKR -10.00'), findsOneWidget);
    expect(find.text('Unavailable'), findsNWidgets(2));
    expect(find.text('PKR 0.00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final family in [AnalyticsFamily.inventory, AnalyticsFamily.profitability]) {
    testWidgets('${family.name} charts distinguish current units and incomplete cost evidence', (tester) async {
      tester.view.physicalSize = const Size(1366, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final section = family == AnalyticsFamily.inventory
        ? AnalyticsSection(family: family, title: 'Inventory', rows: [
            evidence('raw_ingredients', '1', {'kind': 'Current position', 'ingredient_id': 1,
              'name': 'Synthetic flour', 'unit': 'g', 'current_stock': 4200, 'status': 'Within threshold'}),
            evidence('raw_ingredients', '2', {'kind': 'Current position', 'ingredient_id': 2,
              'name': 'Synthetic oil', 'unit': 'ml', 'current_stock': 250, 'status': 'Low'}),
            evidence('order_items', '3', {'kind': 'BOM quantity snapshot', 'ingredient_id': '1', 'quantity': 800}),
            evidence('order_items', '4', {'kind': 'BOM quantity snapshot', 'ingredient_id': '2', 'quantity': 120}),
          ])
        : AnalyticsSection(family: family, title: 'Profitability', metrics: const [
            AnalyticsMetric(id: 'recognized_revenue', label: 'Tax-exclusive recognized revenue', value: 500000,
              unit: AnalyticsUnit.paisa, explanation: 'Recorded eligible orders'),
            AnalyticsMetric(id: 'cogs', label: 'Historical realized COGS', unit: AnalyticsUnit.paisa,
              quality: AnalyticsQuality.missing, explanation: 'Some historical cost evidence is missing'),
            AnalyticsMetric(id: 'gross_profit', label: 'Actual gross profit', unit: AnalyticsUnit.paisa,
              quality: AnalyticsQuality.missing, explanation: 'Some historical cost evidence is missing'),
            AnalyticsMetric(id: 'net_profit', label: 'Recorded net operating result', unit: AnalyticsUnit.paisa,
              quality: AnalyticsQuality.notApplicable, explanation: 'Overhead cannot be allocated to filtered orders'),
          ], rows: [
            evidence('order_cost_events', '1', {'kind': 'CONSUME', 'cost_paisa': 150000, 'created_at': '2026-10-27 12:00:00'}),
            evidence('order_cost_events', '2', {'kind': 'RETURN', 'cost_paisa': 10000, 'created_at': '2026-10-27 13:00:00'}),
            evidence('order_cost_events', '3', {'kind': 'CONSUME', 'cost_paisa': null, 'created_at': '2026-10-28 12:00:00'}),
          ]);
      await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme, home: Scaffold(
        body: RepaintBoundary(key: const ValueKey('chart_scope_preview'),
          child: SingleChildScrollView(padding: const EdgeInsets.all(20),
            child: ReportVisualizations(section: section, onInspect: (_, __) {}))))));
      await tester.pumpAndSettle();
      if (family == AnalyticsFamily.inventory) {
        expect(find.text('4,200 g'), findsOneWidget);
        expect(find.text('250 ml'), findsOneWidget);
        expect(find.text('Recorded BOM quantities (g)'), findsOneWidget);
      } else {
        expect(find.text('Unavailable'), findsNWidgets(3));
        expect(find.text('Not applicable'), findsOneWidget);
        expect(find.text('PKR 0.00'), findsNothing);
      }
      expect(tester.takeException(), isNull);
      if (Platform.environment['CAPTURE_DESKTOP'] == 'true') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('chart_scope_preview')));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = await Directory('build/desktop-previews').create(recursive: true);
          await File('${directory.path}/${family.name}-visuals-1366.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }
}
