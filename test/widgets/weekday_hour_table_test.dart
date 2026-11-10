import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/supervisor/report_visualizations.dart';

void main() {
  testWidgets('weekday hour table labels operational basis, zeros, unavailable cells and source drill-down', (tester) async {
    final rows = [for (var weekday = 1; weekday <= 7; weekday++)
      for (var hour = 0; hour < 24; hour++) AnalyticsRow(id: '$weekday-$hour', sourceType: 'weekday_order_peaks',
        cells: {'kind': 'Weekday/hour workload', 'weekday': weekday, 'hour': hour,
          'weekday_basis': 'Operational Business Day weekday',
          'confirmed_orders': weekday == 3 ? (hour == 1 ? 2 : 0) : null,
          'coverage': weekday == 3 ? 'Observed completed Business Days' : 'Unavailable coverage'})];
    final inspected = <AnalyticsRow>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child:
      ReportVisualizations(section: AnalyticsSection(family: AnalyticsFamily.orders, title: 'Orders', rows: rows),
        onInspect: (title, source) => inspected.addAll(source))))));
    await tester.pumpAndSettle();
    expect(find.text('Weekday by hour · confirmed Orders'), findsOneWidget);
    expect(find.textContaining('Operational Business Day weekday · Asia/Karachi'), findsOneWidget);
    expect(find.byKey(const ValueKey('weekday_hour_3_1')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('weekday_hour_3_1')));
    await tester.tap(find.byKey(const ValueKey('weekday_hour_3_1')));
    expect(inspected.single.cells['confirmed_orders'], 2);
    expect(find.text('Unavailable'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('7x24 rush heatmap interpolates cell background color from Card Surface to Cartel Yellow', (tester) async {
    final rows = [
      for (var weekday = 1; weekday <= 7; weekday++)
        for (var hour = 0; hour < 24; hour++)
          AnalyticsRow(
            id: '$weekday-$hour',
            sourceType: 'weekday_order_peaks',
            cells: {
              'kind': 'Weekday/hour workload',
              'weekday': weekday,
              'hour': hour,
              'weekday_basis': 'Operational Business Day weekday',
              'confirmed_orders': weekday == 3 && hour == 1
                  ? 10 // Peak volume
                  : (weekday == 3 && hour == 2
                      ? 5 // 50% intensity
                      : (weekday == 3 && hour == 3
                          ? 0 // Zero volume
                          : null)), // Unavailable
              'coverage': 'Observed completed Business Days',
            },
          ),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: WarmCounterTheme.darkTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReportVisualizations(
            section: AnalyticsSection(family: AnalyticsFamily.orders, title: 'Orders', rows: rows),
            onInspect: (_, __) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Verify Peak cell (3, 1) has Cartel Yellow background
    final peakCell = tester.widget<Material>(find.byKey(const ValueKey('weekday_hour_cell_3_1')));
    expect(peakCell.color, StreetFoodMafiaColors.cartelYellow);

    // Verify 50% cell (3, 2) is linearly interpolated between Card Surface and Cartel Yellow
    final halfCell = tester.widget<Material>(find.byKey(const ValueKey('weekday_hour_cell_3_2')));
    final expectedHalfColor = Color.lerp(StreetFoodMafiaColors.cardSurface, StreetFoodMafiaColors.cartelYellow, 0.5);
    expect(halfCell.color, expectedHalfColor);

    // Verify 0 count cell (3, 3) has Card Surface background
    final zeroCell = tester.widget<Material>(find.byKey(const ValueKey('weekday_hour_cell_3_3')));
    expect(zeroCell.color, StreetFoodMafiaColors.cardSurface);

    // Verify heatmap density legend is visible
    expect(find.byKey(const ValueKey('rush_heatmap_legend')), findsOneWidget);
    expect(find.text('0 orders'), findsOneWidget);
    expect(find.text('10 orders (peak)'), findsOneWidget);
  });

  testWidgets('rush heatmap cell tooltip displays weekday, time range, order count, net sales and coverage', (tester) async {
    final rows = [
      for (var weekday = 1; weekday <= 7; weekday++)
        for (var hour = 0; hour < 24; hour++)
          AnalyticsRow(
            id: '$weekday-$hour',
            sourceType: 'weekday_order_peaks',
            cells: {
              'kind': 'Weekday/hour workload',
              'weekday': weekday,
              'hour': hour,
              'weekday_basis': 'Operational Business Day weekday',
              'confirmed_orders': weekday == 2 && hour == 14 ? 4 : 0,
              'net_sales_paisa': weekday == 2 && hour == 14 ? 350000 : 0,
              'coverage': 'Observed completed Business Days',
            },
          ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReportVisualizations(
            section: AnalyticsSection(family: AnalyticsFamily.orders, title: 'Orders', rows: rows),
            onInspect: (_, __) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final tooltip = tester.widget<Tooltip>(find.byKey(const ValueKey('weekday_hour_tooltip_2_14')));
    expect(tooltip.message, contains('Tuesday'));
    expect(tooltip.message, contains('14:00–15:00'));
    expect(tooltip.message, contains('4 orders'));
    expect(tooltip.message, contains('PKR 3,500.00'));
    expect(tooltip.message, contains('Observed completed Business Days'));
  });

  testWidgets('tapping rush heatmap cell with order_ids drills down into contributing order records', (tester) async {
    final rows = [
      for (var weekday = 1; weekday <= 7; weekday++)
        for (var hour = 0; hour < 24; hour++)
          AnalyticsRow(
            id: '$weekday-$hour',
            sourceType: 'weekday_order_peaks',
            cells: {
              'kind': 'Weekday/hour workload',
              'weekday': weekday,
              'hour': hour,
              'weekday_basis': 'Operational Business Day weekday',
              'confirmed_orders': weekday == 5 && hour == 20 ? 2 : 0,
              'order_ids': weekday == 5 && hour == 20 ? '101,102' : '',
              'coverage': 'Observed completed Business Days',
            },
          ),
      // Contributing order rows in the same section
      AnalyticsRow(
        id: 'orders-101',
        sourceType: 'orders',
        sourceId: '101',
        cells: {'order_id': 101, 'token': 'TK-101', 'recorded_value_paisa': 150000},
      ),
      AnalyticsRow(
        id: 'orders-102',
        sourceType: 'orders',
        sourceId: '102',
        cells: {'order_id': 102, 'token': 'TK-102', 'recorded_value_paisa': 200000},
      ),
      AnalyticsRow(
        id: 'orders-999',
        sourceType: 'orders',
        sourceId: '999',
        cells: {'order_id': 999, 'token': 'TK-999', 'recorded_value_paisa': 50000},
      ),
    ];

    List<AnalyticsRow>? inspectedRows;
    String? inspectedTitle;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReportVisualizations(
            section: AnalyticsSection(family: AnalyticsFamily.orders, title: 'Orders', rows: rows),
            onInspect: (title, rows) {
              inspectedTitle = title;
              inspectedRows = rows;
            },
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('weekday_hour_5_20')));
    await tester.tap(find.byKey(const ValueKey('weekday_hour_5_20')));
    await tester.pumpAndSettle();

    expect(inspectedTitle, contains('Friday 20:00'));
    expect(inspectedRows, isNotNull);
    expect(inspectedRows!.length, 2);
    expect(inspectedRows!.map((r) => r.cells['order_id']), containsAll([101, 102]));
    expect(inspectedRows!.map((r) => r.cells['order_id']), isNot(contains(999)));
  });

  for (final width in [1366.0, 1024.0, 390.0]) {
    testWidgets('7x24 rush heatmap scales responsively at ${width.toInt()}px width without overflow', (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final rows = [
        for (var weekday = 1; weekday <= 7; weekday++)
          for (var hour = 0; hour < 24; hour++)
            AnalyticsRow(
              id: '$weekday-$hour',
              sourceType: 'weekday_order_peaks',
              cells: {
                'kind': 'Weekday/hour workload',
                'weekday': weekday,
                'hour': hour,
                'weekday_basis': 'Operational Business Day weekday',
                'confirmed_orders': (weekday * hour) % 15,
                'coverage': 'Observed completed Business Days',
              },
            ),
      ];

      await tester.pumpWidget(MaterialApp(
        theme: WarmCounterTheme.darkTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReportVisualizations(
              section: AnalyticsSection(family: AnalyticsFamily.orders, title: 'Orders', rows: rows),
              onInspect: (_, __) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Weekday by hour · confirmed Orders'), findsOneWidget);
      expect(find.byKey(const ValueKey('rush_heatmap_matrix')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
