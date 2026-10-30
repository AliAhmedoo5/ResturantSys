import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
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
}
