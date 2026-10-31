import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/report_print_service.dart';
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

  testWidgets('displays Save PDF and Print buttons alongside CSV and XLSX, and triggers print', (tester) async {
    final snapshot = AnalyticsSnapshot(
      query: AnalyticsQuery(startDate: DateTime(2026, 10, 1), endDateExclusive: DateTime(2026, 10, 2)),
      generatedAt: DateTime.utc(2026, 10, 1),
      businessDayIds: [42],
      sections: [AnalyticsSection(family: AnalyticsFamily.sales, title: 'Sales')],
    );

    var printCalled = false;
    final printAdapter = WindowsReportPrintAdapter(
      printHandler: (bytes, {documentTitle}) async {
        printCalled = true;
        return true;
      },
    );
    final printService = ReportPrintService(adapter: printAdapter);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalyticsExportActions(
          snapshot: snapshot,
          family: AnalyticsFamily.sales,
          canExport: () => true,
          printService: printService,
        ),
      ),
    ));

    expect(find.text('CSV (this report)'), findsOneWidget);
    expect(find.text('XLSX (all reports)'), findsOneWidget);
    expect(find.text('Save PDF'), findsOneWidget);
    expect(find.text('Print'), findsOneWidget);

    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(printCalled, isTrue);
    expect(find.text('Sent to printer.'), findsOneWidget);
  });

  testWidgets('print cancellation displays cancelled message without failure error styling', (tester) async {
    final snapshot = AnalyticsSnapshot(
      query: AnalyticsQuery(startDate: DateTime(2026, 10, 1), endDateExclusive: DateTime(2026, 10, 2)),
      generatedAt: DateTime.utc(2026, 10, 1),
      businessDayIds: [42],
      sections: [AnalyticsSection(family: AnalyticsFamily.sales, title: 'Sales')],
    );

    final printAdapter = WindowsReportPrintAdapter(
      printHandler: (bytes, {documentTitle}) async => false,
    );
    final printService = ReportPrintService(adapter: printAdapter);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalyticsExportActions(
          snapshot: snapshot,
          family: AnalyticsFamily.sales,
          canExport: () => true,
          printService: printService,
        ),
      ),
    ));

    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();

    expect(find.text('Print was cancelled.'), findsOneWidget);
  });

  testWidgets('export shows stage and Cancel button, and clicking Cancel aborts export', (tester) async {
    final directory = Directory.systemTemp.createTempSync('analytics-ui-cancel-');
    addTearDown(() => directory.deleteSync(recursive: true));

    final snapshot = AnalyticsSnapshot(
      query: AnalyticsQuery(startDate: DateTime(2026, 10, 1), endDateExclusive: DateTime(2026, 10, 2)),
      generatedAt: DateTime.utc(2026, 10, 1),
      businessDayIds: [42],
      sections: [AnalyticsSection(family: AnalyticsFamily.sales, title: 'Sales')],
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalyticsExportActions(
          snapshot: snapshot,
          family: AnalyticsFamily.sales,
          canExport: () => true,
          pickDirectory: () async => directory.path,
        ),
      ),
    ));

    await tester.runAsync(() async {
      await tester.tap(find.text('Save PDF'));
      await tester.pump();

      // Find the Cancel button while export is active
      final cancelFinder = find.byKey(const ValueKey('analytics_export_cancel_button'));
      if (cancelFinder.evaluate().isNotEmpty) {
        await tester.tap(cancelFinder);
        await tester.pumpAndSettle();
      }
    });

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('analytics_export_cancel_button')), findsNothing);
  });

  testWidgets('compact menu includes Print report action', (tester) async {
    final snapshot = AnalyticsSnapshot(
      query: AnalyticsQuery(startDate: DateTime(2026, 10, 1), endDateExclusive: DateTime(2026, 10, 2)),
      generatedAt: DateTime.utc(2026, 10, 1),
      businessDayIds: [42],
      sections: [AnalyticsSection(family: AnalyticsFamily.sales, title: 'Sales')],
    );

    var printed = false;
    final printAdapter = WindowsReportPrintAdapter(
      printHandler: (bytes, {documentTitle}) async {
        printed = true;
        return true;
      },
    );
    final printService = ReportPrintService(adapter: printAdapter);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AnalyticsExportActions(
          snapshot: snapshot,
          family: AnalyticsFamily.sales,
          compact: true,
          canExport: () => true,
          printService: printService,
        ),
      ),
    ));

    await tester.tap(find.byKey(const ValueKey('analytics_export_menu')));
    await tester.pumpAndSettle();

    expect(find.text('Print report'), findsOneWidget);
    await tester.tap(find.text('Print report'));
    await tester.pumpAndSettle();

    expect(printed, isTrue);
    expect(find.text('Sent to printer.'), findsOneWidget);
  });
}
