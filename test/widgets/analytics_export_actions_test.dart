import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/widgets/supervisor/analytics_export_actions.dart';

void main() {
  testWidgets('local export cancels cleanly and rejects session lock while directory picker is open', (tester) async {
    final directory = Directory.systemTemp.createTempSync('analytics-actions-');
    addTearDown(() => directory.deleteSync(recursive: true));
    var allowed = true;
    var picker = Completer<String?>();
    final snapshot = AnalyticsSnapshot(query: AnalyticsQuery(startDate: DateTime(2026, 10, 1), endDateExclusive: DateTime(2026, 10, 2)), generatedAt: DateTime.utc(2026, 10, 1), businessDayIds: [42], sections: [AnalyticsSection(family: AnalyticsFamily.sales, title: 'Sales')]);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AnalyticsExportActions(snapshot: snapshot, family: AnalyticsFamily.sales, canExport: () => allowed, pickDirectory: () => picker.future))));
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
    picker = Completer<String?>();
    await tester.tap(find.text('CSV (this report)'));
    await tester.pump();
    picker.complete(null);
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(find.ancestor(of: find.text('CSV (this report)'), matching: find.byWidgetPredicate((w) => w is OutlinedButton))).onPressed, isNotNull);
    expect(directory.listSync(), isEmpty);
  });
}


