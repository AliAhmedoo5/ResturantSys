import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/widgets/supervisor/manager_analytics_workspace.dart';

import 'manager_analytics_workspace_test.dart' show SnapshotService;

void main() {
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
}
