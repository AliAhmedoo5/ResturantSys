import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/widgets/supervisor/manager_analytics_workspace.dart';

// The screen consumes immutable snapshots at the confirmed reporting seam.
class SnapshotService implements AnalyticsService {
  @override
  Future<AnalyticsSnapshot> load(AnalyticsQuery query) async => AnalyticsSnapshot(
    query: query,
    generatedAt: DateTime(2026, 10, 26, 12),
    businessDayIds: [1],
    sections: [
      AnalyticsSection(family: AnalyticsFamily.overview, title: 'Overview', metrics: [
        AnalyticsMetric(id: 'recorded', label: 'Recorded order value', value: 123450,
          unit: AnalyticsUnit.paisa, explanation: 'Eligible orders including Collection Due.'),
      ]),
      AnalyticsSection(family: AnalyticsFamily.profitability, title: 'Profitability', metrics: [
        AnalyticsMetric(id: 'profit', label: 'Historical net profit', unit: AnalyticsUnit.paisa,
          quality: AnalyticsQuality.missing, explanation: 'Event-time costs are not recorded.'),
      ]),
    ],
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Manager can explore reports and distinguish missing profit from zero', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManagerAnalyticsWorkspace(
      service: SnapshotService(), clock: () => DateTime(2026, 10, 26, 12),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('PKR 1,234.50'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('analytics_family')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profitability').last);
    await tester.pumpAndSettle();
    expect(find.text('Historical net profit'), findsOneWidget);
    expect(find.text('Missing data'), findsOneWidget);
    expect(find.text('Event-time costs are not recorded.'), findsOneWidget);
    expect(find.text('PKR 0.00'), findsNothing);
  });
}
