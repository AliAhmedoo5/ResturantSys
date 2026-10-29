import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/supervisor/manager_analytics_workspace.dart';

import 'manager_analytics_workspace_test.dart' show SnapshotService;

AnalyticsSnapshot overviewFixture(AnalyticsQuery query) => AnalyticsSnapshot(
  query: query, generatedAt: DateTime(2026, 10, 26, 13, 48), businessDayIds: [4],
  sections: [
    AnalyticsSection(family: AnalyticsFamily.overview, title: 'Overview', metrics: const [
      AnalyticsMetric(id: 'recorded_value', label: 'Recorded order value', value: 415000,
        unit: AnalyticsUnit.paisa, explanation: 'Includes Collection Due.'),
      AnalyticsMetric(id: 'orders', label: 'Eligible orders', value: 3,
        unit: AnalyticsUnit.count, explanation: 'Eligible committed orders.'),
      AnalyticsMetric(id: 'average_ticket', label: 'Average ticket', value: 138333,
        unit: AnalyticsUnit.paisa, explanation: 'Per eligible order.'),
      AnalyticsMetric(id: 'collection_due', label: 'Collection Due (selected cohort)', value: 0,
        unit: AnalyticsUnit.paisa, explanation: 'Selected Business Days, filtered orders.'),
      AnalyticsMetric(id: 'all_collection_due', label: 'Collection Due (all outstanding)', value: 138200,
        unit: AnalyticsUnit.paisa, explanation: 'All Business Days, no order filters.'),
      AnalyticsMetric(id: 'expected_drawer', label: 'Expected drawer', value: 1410200,
        unit: AnalyticsUnit.paisa, explanation: 'All shifts in selected Business Days.'),
      AnalyticsMetric(id: 'negative_stock', label: 'Current negative stock', value: 0,
        unit: AnalyticsUnit.count, explanation: 'Current installation-wide stock.'),
      AnalyticsMetric(id: 'gross_profit', label: 'Actual gross profit',
        unit: AnalyticsUnit.paisa, quality: AnalyticsQuality.missing,
        explanation: 'Required event-time cost data is missing.'),
    ], columns: const [
      AnalyticsColumn(key: 'business_date', label: 'Business date'),
      AnalyticsColumn(key: 'opened_at', label: 'Opened at'),
      AnalyticsColumn(key: 'closed_at', label: 'Closed at'),
      AnalyticsColumn(key: 'status', label: 'Status'),
    ], rows: [AnalyticsRow(id: '4', sourceId: '4', sourceType: 'business_days', cells: {
      'business_date': '2026-10-26', 'opened_at': '2026-10-26 12:01:00 +05:00 [Asia/Karachi]',
      'opened_at_source': '2026-10-26T07:01:00Z',
      'closed_at': null, 'status': 'OPEN',
    })]),
    AnalyticsSection(family: AnalyticsFamily.sales, title: 'Sales', rows: [
      AnalyticsRow(id: 'day4', sourceId: '4', sourceType: 'business_days', cells: {
        'business_date': '2026-10-26', 'orders': 3, 'recorded_value_paisa': 415000,
      }),
    ]),
    AnalyticsSection(family: AnalyticsFamily.cash, title: 'Cash and shifts', metrics: const [
      AnalyticsMetric(id: 'count_coverage', label: 'Counted shift coverage', value: 50,
        unit: AnalyticsUnit.percent, sampleCount: 1, populationCount: 2,
        explanation: 'One of two selected shifts has a recorded blind count.'),
    ], rows: [AnalyticsRow(id: '9', sourceId: '9', sourceType: 'shifts', cells: {
      'kind': 'Shift reconciliation', 'shift_id': 9, 'cashier_id': 7, 'status': 'OPEN',
    })]),
    AnalyticsSection(family: AnalyticsFamily.staff, title: 'Staff & payroll', rows: [
      AnalyticsRow(id: '7', sourceType: 'staff', cells: {
        'staff_id': 7, 'name': 'Ayesha', 'role': 'CASHIER',
      }),
    ]),
    AnalyticsSection(family: AnalyticsFamily.profitability, title: 'Profitability and costing'),
  ],
);

void main() {
  setUpAll(() async {
    if (Platform.environment['CAPTURE_DESKTOP'] != 'true') return;
    final font = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if (!await font.exists()) return;
    final loader = FontLoader(WarmCounterTypography.fontFamily)
      ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final width in [1366.0, 1024.0, 390.0]) {
    testWidgets('Business overview is readable and actionable at ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
        home: Scaffold(body: RepaintBoundary(key: const ValueKey('overview_preview'),
          child: ManagerAnalyticsWorkspace(service: SnapshotService(onLoad: (query) async => overviewFixture(query)),
            clock: () => DateTime(2026, 10, 26, 13, 48))))));
      await tester.pumpAndSettle();
      expect(find.text('Business overview'), findsOneWidget);
      expect(find.text('PKR 4,150.00'), findsWidgets);
      if (width >= 1000) {
        expect(find.text('Needs attention'), findsOneWidget);
        expect(find.text('Drawer count incomplete'), findsOneWidget);
        expect(find.text('Review shifts'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      if (Platform.environment['CAPTURE_DESKTOP'] == 'true') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('overview_preview')));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = await Directory('build/desktop-previews').create(recursive: true);
          await File('${directory.path}/business-overview-${width.toInt()}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Overview actions preserve filters, change period and open the relevant report', (tester) async {
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AnalyticsQuery? requested;
    await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
      home: Scaffold(body: ManagerAnalyticsWorkspace(service: SnapshotService(onLoad: (query) async {
        requested = query;
        return overviewFixture(query);
      }), clock: () => DateTime(2026, 10, 26)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('analytics_cashier_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ayesha').last);
    await tester.pumpAndSettle();
    expect(requested!.cashierId, 7);
    await tester.tap(find.byKey(const ValueKey('analytics_shift_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Shift #9 · OPEN').last);
    await tester.pumpAndSettle();
    expect(requested!.shiftId, 9);
    await tester.tap(find.byKey(const ValueKey('analytics_dining_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Takeaway').last);
    await tester.pumpAndSettle();
    expect(requested!.diningType, 'TAKEAWAY');
    await tester.tap(find.byKey(const ValueKey('analytics_payment_picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cash').last);
    await tester.pumpAndSettle();
    expect(requested!.paymentMethod, 'CASH');
    await tester.tap(find.text('Review shifts'));
    await tester.pumpAndSettle();
    expect(find.text('Cash and shifts'), findsOneWidget);
    expect(requested!.cashierId, 7);
    await tester.tap(find.byKey(const ValueKey('analytics_family')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overview').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change period'));
    await tester.pumpAndSettle();
    expect(requested!.live, isFalse);
    expect(requested!.endDateExclusive.difference(requested!.startDate).inDays, 7);
    expect(requested!.cashierId, 7);
    expect(requested!.shiftId, 9);
    expect(requested!.diningType, 'TAKEAWAY');
    expect(requested!.paymentMethod, 'CASH');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Business Day source details open and cost warnings drill into Profitability', (tester) async {
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
      home: Scaffold(body: ManagerAnalyticsWorkspace(service: SnapshotService(
        onLoad: (query) async => overviewFixture(query))))));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(of: find.byKey(const ValueKey('analytics_body')),
      matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.text('business_days #4'), 180, scrollable: scrollable);
    expect(find.text('26 Oct, 12:01'), findsOneWidget);
    await tester.ensureVisible(find.text('business_days #4'));
    await tester.tap(find.text('business_days #4'));
    await tester.pumpAndSettle();
    expect(find.text('Source IDs: 4'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.drag(scrollable, const Offset(0, 1000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review cost data'));
    await tester.tap(find.text('Review cost data'));
    await tester.pumpAndSettle();
    expect(find.text('Profitability and costing'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
