import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/widgets/supervisor/analytics_export_actions.dart';

void main() {
  testWidgets('Compact export menu saves the displayed report as CSV', (tester) async {
    final directory = Directory.systemTemp.createTempSync('dashboard-export-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final snapshot = AnalyticsSnapshot(query: AnalyticsQuery(startDate: DateTime(2026, 10, 26),
      endDateExclusive: DateTime(2026, 10, 27)), generatedAt: DateTime.utc(2026, 10, 26),
      businessDayIds: [4], sections: [AnalyticsSection(family: AnalyticsFamily.overview, title: 'Overview',
        metrics: const [AnalyticsMetric(id: 'recorded_value', label: 'Recorded order value', value: 415000,
          unit: AnalyticsUnit.paisa, explanation: 'Selected Business Day fixture')])]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AnalyticsExportActions(
      snapshot: snapshot, family: AnalyticsFamily.overview, compact: true,
      canExport: () => true, pickDirectory: () async => directory.path))));
    await tester.tap(find.byKey(const ValueKey('analytics_export_menu')));
    await tester.pumpAndSettle();
    expect(find.text('XLSX (all reports)'), findsOneWidget);
    expect(find.text('PDF (this report)'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.text('CSV (this report)'));
      for (var attempt = 0; attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await tester.pump();
        if (find.textContaining('Saved CSV').evaluate().isNotEmpty) break;
      }
    });
    await tester.pumpAndSettle();
    final file = directory.listSync().whereType<File>().single;
    expect(file.readAsStringSync(), contains('415000'));
    expect(find.textContaining('Saved CSV'), findsOneWidget);
  });

  testWidgets('local export cancels cleanly and rejects session lock while directory picker is open', (tester) async {
    final directory = Directory.systemTemp.createTempSync('analytics-actions-');
    addTearDown(() => directory.deleteSync(recursive: true));
    var allowed = true;
    var picker = Completer<String?>();
    final snapshot = AnalyticsSnapshot(query: AnalyticsQuery(startDate: DateTime(2026, 10, 1), endDateExclusive: DateTime(2026, 10, 2)), generatedAt: DateTime.utc(2026, 10, 1), businessDayIds: [42], sections: [AnalyticsSection(family: AnalyticsFamily.sales, title: 'Sales')]);
    Widget view() => MaterialApp(home: Scaffold(body: AnalyticsExportActions(snapshot: snapshot, family: AnalyticsFamily.sales, canExport: () => allowed, pickDirectory: () => picker.future)));
    await tester.pumpWidget(view());
    await tester.tap(find.text('CSV (this report)'));
    await tester.pump();
    expect(tester.widget<OutlinedButton>(find.ancestor(of: find.text('XLSX (all reports)'), matching: find.byWidgetPredicate((w) => w is OutlinedButton))).onPressed, isNull);
    picker.complete(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not'), findsNothing);
    expect(directory.listSync(), isEmpty);
    picker = Completer<String?>();
    await tester.tap(find.text('CSV (this report)'));
    await tester.pump();
    allowed = false;
    picker.complete(directory.path);
    await tester.pumpAndSettle();
    expect(directory.listSync(), isEmpty);
    allowed = true;
    await tester.pumpWidget(view());
    picker = Completer<String?>();
    await tester.tap(find.text('CSV (this report)'));
    await tester.pump();
    picker.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.ancestor(of: find.text('CSV (this report)'), matching: find.byWidgetPredicate((w) => w is OutlinedButton))).onPressed, isNotNull);
    expect(directory.listSync(), isEmpty);
  });
}
