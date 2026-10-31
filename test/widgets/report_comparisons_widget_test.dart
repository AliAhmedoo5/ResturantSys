import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/widgets/supervisor/manager_analytics_workspace.dart';

class _FakeAnalyticsService implements AnalyticsService {
  _FakeAnalyticsService({required this.snapshotBuilder});
  final AnalyticsSnapshot Function(AnalyticsQuery query) snapshotBuilder;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #load) {
      final query = invocation.positionalArguments.first as AnalyticsQuery;
      return Future.value(snapshotBuilder(query));
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  testWidgets('Manager can choose comparison mode and inspect comparator details', (tester) async {
    AnalyticsQuery? lastQuery;
    final fakeService = _FakeAnalyticsService(
      snapshotBuilder: (query) {
        lastQuery = query;
        return AnalyticsSnapshot(
          query: query,
          generatedAt: DateTime(2026, 10, 26, 12),
          businessDayIds: [1],
          sections: [
            AnalyticsSection(
              family: AnalyticsFamily.sales,
              title: 'Sales',
              metrics: [
                AnalyticsMetric(
                  id: 'recorded_value',
                  label: 'Recorded order value',
                  value: 50000,
                  unit: AnalyticsUnit.paisa,
                  explanation: 'Sales flow',
                  priorValue: query.comparisonMode == AnalyticsComparisonMode.none ? null : 30000,
                  changeAbsolute: query.comparisonMode == AnalyticsComparisonMode.none ? null : 20000,
                  changePercent: query.comparisonMode == AnalyticsComparisonMode.none ? null : 66.7,
                ),
                const AnalyticsMetric(
                  id: 'negative_stock',
                  label: 'Negative stock',
                  value: 0,
                  unit: AnalyticsUnit.count,
                  explanation: 'Snapshot balance',
                  isBalance: true,
                ),
              ],
            ),
          ],
        );
      },
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ManagerAnalyticsWorkspace(
          service: fakeService,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Verify comparison dropdown exists
    final dropdownFinder = find.byKey(const ValueKey('analytics_comparison_mode'));
    expect(dropdownFinder, findsOneWidget);

    // Initial query has comparison mode dropdown
    expect(find.text('Preceding period'), findsWidgets);

    // Switch comparison mode to 'Comparable weekday'
    await tester.tap(dropdownFinder);
    await tester.pumpAndSettle();

    final comparableOption = find.text('Comparable weekday').last;
    await tester.tap(comparableOption);
    await tester.pumpAndSettle();

    expect(lastQuery?.comparisonMode, AnalyticsComparisonMode.comparableWeekday);

    // Flow metric shows prior value, change, and percentage
    expect(find.textContaining('Prior: PKR 300.00'), findsOneWidget);
    expect(find.textContaining('Change: +PKR 200.00'), findsOneWidget);
    expect(find.textContaining('+66.7% vs comparable weekday'), findsOneWidget);

    // Balance metric shows not applicable
    expect(find.text('Comparison: Not applicable (snapshot balance)'), findsOneWidget);
  });
}
