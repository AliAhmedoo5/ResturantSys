import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/widgets/supervisor/analytics_domain_filters.dart';

void main() {
  testWidgets('readable stable-ID domain selection and reset preserve period and Hold threshold', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final start = DateTime(2026, 10, 1);
    var query = AnalyticsQuery(startDate: start, endDateExclusive: DateTime(2026, 11),
      holdStaleMinutes: 60, fundingStream: 'BANK',
      domainFilters: {AnalyticsDimension.supplier: '1'});
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: StatefulBuilder(builder: (context, setState) => AnalyticsDomainFilters(
        query: query, options: const [
          AnalyticsFilterOption(dimension: AnalyticsDimension.supplier, id: '1', label: 'Selected supplier'),
          AnalyticsFilterOption(dimension: AnalyticsDimension.supplier, id: '2', label: 'Other supplier'),
        ], onChanged: (value) => setState(() => query = value))),
    ))));
    await tester.tap(find.text('Domain filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('analytics_domain_supplier_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other supplier [2]').last);
    await tester.pumpAndSettle();
    expect(query.domainFilters[AnalyticsDimension.supplier], '2');
    expect(find.text('Supplier: Other supplier'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('analytics_reset_domains')));
    await tester.pumpAndSettle();
    expect(query.domainFilters, isEmpty);
    expect(query.fundingStream, isNull);
    expect(query.startDate, start);
    expect(query.holdStaleMinutes, 60);
    expect(tester.takeException(), isNull);
  });
}
