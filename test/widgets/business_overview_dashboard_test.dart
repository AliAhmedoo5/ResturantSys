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
    final brand = FontLoader(WarmCounterTypography.brandFontFamily);
    brand.addFont(rootBundle.load('assets/fonts/knewave/Knewave-Regular.ttf'));
    await brand.load();
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
    await tester.tap(find.byKey(const ValueKey('analytics_filters_toggle')));
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
    await tester.tap(find.byKey(const ValueKey('analytics_filters_toggle')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Review shifts'));
    await tester.tap(find.text('Review shifts'));
    await tester.pumpAndSettle();
    expect(find.text('Cash and shifts'), findsOneWidget);
    expect(requested!.cashierId, 7);
    await tester.tap(find.byKey(const ValueKey('analytics_family')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overview').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Change period'));
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
    expect(find.text('Mon, 26 Oct 2026 • 12:01 PM'), findsOneWidget);
    final sourceButton = find.text('business_days #4');
    for (var attempt = 0; attempt < 12 && sourceButton.hitTestable().evaluate().isEmpty; attempt++) {
      await tester.drag(scrollable, const Offset(0, -140));
      await tester.pumpAndSettle();
    }
    expect(sourceButton.hitTestable(), findsOneWidget);
    await tester.tap(sourceButton.hitTestable());
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

  testWidgets('Executive Cockpit synthesizes the four commercial pillars', (tester) async {
    tester.view.physicalSize = const Size(1366, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: WarmCounterTheme.darkTheme,
      home: Scaffold(
        body: ManagerAnalyticsWorkspace(
          service: SnapshotService(onLoad: (query) async => richCockpitFixture(query)),
          clock: () => DateTime(2026, 10, 26, 21, 30),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Pillar 1: Executive KPI Scorecard
    expect(find.text('Executive KPI Scorecard'), findsOneWidget);
    expect(find.text('PKR 5,000.00'), findsWidgets); // Net sales
    expect(find.text('PKR 3,200.00'), findsWidgets); // Gross profit
    expect(find.text('PKR 500.00'), findsWidgets); // AOV

    // Pillar 2: Menu Margin Intelligence
    expect(find.text('Menu Margin Intelligence'), findsOneWidget);
    expect(find.text('Star Contributors'), findsOneWidget);
    expect(find.text('Triple Smasher'), findsOneWidget);
    expect(find.text('Food Cost Traps'), findsOneWidget);
    expect(find.text('Spicy Wings 10pc'), findsOneWidget);
    expect(find.text('Missing Recipe BOM'), findsWidgets);
    expect(find.text('Special Seasonal Shake'), findsOneWidget);

    // Pillar 3: Kitchen & Fulfillment Bottlenecks
    expect(find.text('Kitchen & Fulfillment Bottlenecks'), findsOneWidget);
    expect(find.textContaining('14.5m'), findsOneWidget); // p50
    expect(find.textContaining('28.0m'), findsOneWidget); // p90
    expect(find.textContaining('20:00'), findsOneWidget); // Peak rush hour
    expect(find.text('Inspect peak orders'), findsOneWidget);

    // Pillar 4: Risk & Leakage Radar
    expect(find.text('Risk & Leakage Radar'), findsOneWidget);
    expect(find.text('Unsettled COD > 24h'), findsOneWidget);
    expect(find.text('PKR 6,000.00'), findsWidgets); // 450000 + 150000 paisa
    expect(find.text('Unresolved Drawer Variances'), findsOneWidget);
    expect(find.text('Negative Stock Items'), findsOneWidget);

    // One-tap navigation from Bottlenecks to Order operations
    await tester.ensureVisible(find.text('Inspect peak orders'));
    await tester.tap(find.text('Inspect peak orders'));
    await tester.pumpAndSettle();
    expect(find.text('Order operations'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [1366.0, 1024.0, 390.0]) {
    testWidgets('Executive Cockpit adapts cleanly across ${width.toInt()}px', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: WarmCounterTheme.darkTheme,
        home: Scaffold(
          body: ManagerAnalyticsWorkspace(
            service: SnapshotService(onLoad: (query) async => richCockpitFixture(query)),
            clock: () => DateTime(2026, 10, 26, 21, 30),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Executive KPI Scorecard'), findsOneWidget);
      expect(find.text('Menu Margin Intelligence'), findsOneWidget);
      expect(find.text('Kitchen & Fulfillment Bottlenecks'), findsOneWidget);
      expect(find.text('Risk & Leakage Radar'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
    });
  }
}

AnalyticsSnapshot richCockpitFixture(AnalyticsQuery query) => AnalyticsSnapshot(
  query: query,
  generatedAt: DateTime(2026, 10, 26, 21, 30),
  businessDayIds: [4],
  sections: [
    AnalyticsSection(
      family: AnalyticsFamily.overview,
      title: 'Overview',
      metrics: const [
        AnalyticsMetric(id: 'recorded_value', label: 'Recorded order value', value: 500000,
          unit: AnalyticsUnit.paisa, explanation: 'Includes Collection Due.'),
        AnalyticsMetric(id: 'orders', label: 'Eligible orders', value: 10,
          unit: AnalyticsUnit.count, explanation: 'Eligible committed orders.'),
        AnalyticsMetric(id: 'average_ticket', label: 'Average ticket', value: 50000,
          unit: AnalyticsUnit.paisa, explanation: 'Per eligible order.'),
        AnalyticsMetric(id: 'collection_due', label: 'Collection Due (selected cohort)', value: 0,
          unit: AnalyticsUnit.paisa, explanation: 'Selected Business Days, filtered orders.'),
        AnalyticsMetric(id: 'all_collection_due', label: 'Collection Due (all outstanding)', value: 15000,
          unit: AnalyticsUnit.paisa, explanation: 'All Business Days, no order filters.'),
        AnalyticsMetric(id: 'expected_drawer', label: 'Expected drawer', value: 600000,
          unit: AnalyticsUnit.paisa, explanation: 'All shifts in selected Business Days.'),
        AnalyticsMetric(id: 'negative_stock', label: 'Current negative stock', value: 2,
          unit: AnalyticsUnit.count, explanation: 'Current installation-wide stock.'),
        AnalyticsMetric(id: 'gross_profit', label: 'Actual gross profit', value: 320000,
          unit: AnalyticsUnit.paisa, quality: AnalyticsQuality.complete,
          explanation: 'Required event-time cost data complete.'),
      ],
      columns: const [
        AnalyticsColumn(key: 'business_date', label: 'Business date'),
        AnalyticsColumn(key: 'opened_at', label: 'Opened at'),
        AnalyticsColumn(key: 'closed_at', label: 'Closed at'),
        AnalyticsColumn(key: 'status', label: 'Status'),
      ],
      rows: [
        AnalyticsRow(id: '4', sourceId: '4', sourceType: 'business_days', cells: {
          'business_date': '2026-10-26',
          'opened_at': '2026-10-26 12:01:00 +05:00 [Asia/Karachi]',
          'opened_at_source': '2026-10-26T07:01:00Z',
          'closed_at': null,
          'status': 'OPEN',
        }),
      ],
    ),
    AnalyticsSection(
      family: AnalyticsFamily.sales,
      title: 'Sales',
      metrics: const [
        AnalyticsMetric(id: 'recorded_value', label: 'Recorded order value', value: 500000, unit: AnalyticsUnit.paisa, explanation: 'Sales value'),
      ],
      rows: [
        AnalyticsRow(id: 'day4', sourceId: '4', sourceType: 'business_days', cells: {
          'business_date': '2026-10-26', 'orders': 10, 'recorded_value_paisa': 500000,
        }),
        AnalyticsRow(id: 'tender-CASH', sourceType: 'order_payments', sourceId: '1,2,3', cells: {
          'kind': 'Tender breakdown', 'dimension': 'Payment method', 'dimension_value': 'CASH', 'collected_paisa': 350000,
        }),
        AnalyticsRow(id: 'tender-DIGITAL', sourceType: 'order_payments', sourceId: '4,5', cells: {
          'kind': 'Tender breakdown', 'dimension': 'Payment method', 'dimension_value': 'DIGITAL', 'collected_paisa': 150000,
        }),
        AnalyticsRow(id: 'hour-20', sourceType: 'orders', sourceId: '1,2,3,4,5,6,7', cells: {
          'kind': 'Hourly breakdown', 'dimension': 'Creation hour (Karachi)', 'dimension_value': 20, 'orders': 7, 'recorded_value_paisa': 350000,
        }),
        AnalyticsRow(id: 'hour-21', sourceType: 'orders', sourceId: '8,9,10', cells: {
          'kind': 'Hourly breakdown', 'dimension': 'Creation hour (Karachi)', 'dimension_value': 21, 'orders': 3, 'recorded_value_paisa': 150000,
        }),
      ],
    ),
    AnalyticsSection(
      family: AnalyticsFamily.menu,
      title: 'Menu performance',
      rows: [
        AnalyticsRow(id: 'menu-item:1', sourceType: 'order_items', sourceId: '1', cells: {
          'kind': 'Item/deal aggregate',
          'name': 'Triple Smasher',
          'quantity': 20,
          'net_sales_paisa': 400000,
          'bom_recipe_cost_paisa': 120000,
          'margin_paisa': 280000,
          'margin_rate': 70.0,
        }),
        AnalyticsRow(id: 'menu-item:2', sourceType: 'order_items', sourceId: '2', cells: {
          'kind': 'Item/deal aggregate',
          'name': 'Mafia Loaded Fries',
          'quantity': 15,
          'net_sales_paisa': 250000,
          'bom_recipe_cost_paisa': 100000,
          'margin_paisa': 150000,
          'margin_rate': 60.0,
        }),
        AnalyticsRow(id: 'menu-item:3', sourceType: 'order_items', sourceId: '3', cells: {
          'kind': 'Item/deal aggregate',
          'name': 'Crispy Zinger',
          'quantity': 12,
          'net_sales_paisa': 260000,
          'bom_recipe_cost_paisa': 60000,
          'margin_paisa': 200000,
          'margin_rate': 76.9,
        }),
        AnalyticsRow(id: 'menu-item:4', sourceType: 'order_items', sourceId: '4', cells: {
          'kind': 'Item/deal aggregate',
          'name': 'Spicy Wings 10pc',
          'quantity': 40,
          'net_sales_paisa': 300000,
          'bom_recipe_cost_paisa': 180000,
          'margin_paisa': 50000,
          'margin_rate': 16.7,
        }),
        AnalyticsRow(id: 'menu-item:5', sourceType: 'order_items', sourceId: '5', cells: {
          'kind': 'Item/deal aggregate',
          'name': 'Double Beef Melt',
          'quantity': 25,
          'net_sales_paisa': 200000,
          'bom_recipe_cost_paisa': 110000,
          'margin_paisa': 90000,
          'margin_rate': 45.0,
        }),
        AnalyticsRow(id: 'menu-item:6', sourceType: 'order_items', sourceId: '6', cells: {
          'kind': 'Item/deal aggregate',
          'name': 'Special Seasonal Shake',
          'quantity': 8,
          'net_sales_paisa': 80000,
          'bom_recipe_cost_paisa': null,
          'margin_paisa': null,
          'margin_rate': null,
        }),
      ],
    ),
    AnalyticsSection(
      family: AnalyticsFamily.orders,
      title: 'Order operations',
      metrics: const [
        AnalyticsMetric(id: 'prep_median', label: 'Median preparation time', value: 14.5,
          unit: AnalyticsUnit.minutes, sampleCount: 10, populationCount: 10, explanation: 'Median prep time'),
        AnalyticsMetric(id: 'prep_p90', label: '90th percentile preparation', value: 28.0,
          unit: AnalyticsUnit.minutes, sampleCount: 10, populationCount: 10, explanation: 'p90 prep time'),
        AnalyticsMetric(id: 'prep_coverage', label: 'Preparation milestone coverage', value: 100,
          unit: AnalyticsUnit.percent, sampleCount: 10, populationCount: 10, explanation: 'Full coverage'),
        AnalyticsMetric(id: 'rework_cycles', label: 'Kitchen rework cycles', value: 1,
          unit: AnalyticsUnit.count, explanation: '1 rework cycle'),
      ],
    ),
    AnalyticsSection(
      family: AnalyticsFamily.delivery,
      title: 'Delivery fulfillment',
      metrics: const [
        AnalyticsMetric(id: 'travel_p90', label: '90th percentile travel', value: 22.0,
          unit: AnalyticsUnit.minutes, explanation: 'Transit p90'),
        AnalyticsMetric(id: 'late_deliveries', label: 'Late delivery orders', value: 2,
          unit: AnalyticsUnit.count, explanation: 'Exceeding target ETA'),
        AnalyticsMetric(id: 'cod_aging_1_3d_paisa', label: 'Unsettled COD: Aged (1-3 days)', value: 450000,
          unit: AnalyticsUnit.paisa, explanation: 'Carried over'),
        AnalyticsMetric(id: 'cod_aging_critical_paisa', label: 'Unsettled COD: Critical (>3 days)', value: 150000,
          unit: AnalyticsUnit.paisa, explanation: 'Critical aging'),
      ],
    ),
    AnalyticsSection(
      family: AnalyticsFamily.cash,
      title: 'Cash and shifts',
      metrics: const [
        AnalyticsMetric(id: 'count_coverage', label: 'Counted shift coverage', value: 50,
          unit: AnalyticsUnit.percent, sampleCount: 1, populationCount: 2, explanation: '1 of 2 shifts'),
        AnalyticsMetric(id: 'unresolved_discrepancies', label: 'Unresolved discrepancies', value: 2,
          unit: AnalyticsUnit.count, explanation: '2 flagged shifts'),
        AnalyticsMetric(id: 'variance', label: 'Discrepancy (counted minus expected)', value: -5000,
          unit: AnalyticsUnit.paisa, explanation: 'Under expected'),
      ],
      rows: [
        AnalyticsRow(id: '10', sourceId: '10', sourceType: 'shifts', cells: {
          'kind': 'Shift reconciliation', 'shift_id': 10, 'cashier_id': 7, 'status': 'FLAGGED',
        }),
      ],
    ),
    AnalyticsSection(
      family: AnalyticsFamily.inventory,
      title: 'Inventory balances',
      metrics: const [
        AnalyticsMetric(id: 'negative_stock', label: 'Current negative stock', value: 2,
          unit: AnalyticsUnit.count, explanation: '2 items negative'),
      ],
    ),
    AnalyticsSection(
      family: AnalyticsFamily.profitability,
      title: 'Profitability and costing',
      metrics: const [
        AnalyticsMetric(id: 'recorded_value', label: 'Recorded order value', value: 500000, unit: AnalyticsUnit.paisa, explanation: 'Total'),
        AnalyticsMetric(id: 'gross_profit', label: 'Actual gross profit', value: 320000, unit: AnalyticsUnit.paisa, explanation: 'Gross profit'),
        AnalyticsMetric(id: 'food_cogs', label: 'Historical food COGS', value: 180000, unit: AnalyticsUnit.paisa, explanation: 'Food COGS'),
        AnalyticsMetric(id: 'waste_loss', label: 'Recorded waste loss', value: 25000, unit: AnalyticsUnit.paisa, explanation: 'Waste loss'),
      ],
    ),
  ],
);
