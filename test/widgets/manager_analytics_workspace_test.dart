import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/supervisor/manager_analytics_workspace.dart';

// The screen consumes immutable snapshots at the confirmed reporting seam.
class SnapshotService implements AnalyticsService {
  SnapshotService({this.onLoad});
  final Future<AnalyticsSnapshot> Function(AnalyticsQuery)? onLoad;

  @override
  Future<AnalyticsSnapshot> load(AnalyticsQuery query) async =>
    onLoad != null ? onLoad!(query) : fixture(query);

  static AnalyticsSnapshot fixture(AnalyticsQuery query, {String? marker}) => AnalyticsSnapshot(
    query: query,
    generatedAt: DateTime(2026, 10, 26, 12),
    businessDayIds: [1],
    sections: [
      AnalyticsSection(family: AnalyticsFamily.overview, title: 'Overview', metrics: [
        AnalyticsMetric(id: 'recorded', label: marker ?? 'Recorded order value', value: 123450,
          unit: AnalyticsUnit.paisa, explanation: 'Eligible orders including Collection Due.', changeAbsolute: 123450),
      ]),
      AnalyticsSection(family: AnalyticsFamily.sales, title: 'Sales', metrics: [
        const AnalyticsMetric(id: 'total', label: 'Recorded order value', value: 123450,
          unit: AnalyticsUnit.paisa, explanation: 'Current eligible committed order totals; includes Collection Due.'),
        const AnalyticsMetric(id: 'orders', label: 'Eligible orders', value: 12,
          unit: AnalyticsUnit.count, explanation: 'Excludes cancelled, voided and refunded orders.'),
        const AnalyticsMetric(id: 'ticket', label: 'Average ticket', value: 10287.5,
          unit: AnalyticsUnit.paisa, explanation: 'Recorded order value / 12 eligible orders.', sampleCount: 12),
        const AnalyticsMetric(id: 'due', label: 'Collection Due', value: 32500,
          unit: AnalyticsUnit.paisa, explanation: 'Uncollected orders in the selected Business Day cohort.'),
      ], columns: const [
        AnalyticsColumn(key: 'business_date', label: 'Business date'),
        AnalyticsColumn(key: 'orders', label: 'Orders', unit: AnalyticsUnit.count),
        AnalyticsColumn(key: 'recorded_value_paisa', label: 'Recorded order value', unit: AnalyticsUnit.paisa),
      ], rows: [
        for (var i = 0; i < 12; i++) AnalyticsRow(id: '$i', sourceType: 'business_day', sourceId: '${i + 1}',
          cells: {'business_date': '2026-10-${14 + i}', 'orders': i + 1, 'recorded_value_paisa': 10000 + i * 1000}),
      ], notes: ['Synthetic example • current records, not a sealed Z-report.',
        'Order filters apply to this report; inventory and staff retain their own scope.']),
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
  testWidgets('Order time basis survives period and grouping changes', (tester) async {
    final queries = <AnalyticsQuery>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManagerAnalyticsWorkspace(
      service: SnapshotService(onLoad: (query) async {
        queries.add(query);
        return SnapshotService.fixture(query);
      }), clock: () => DateTime(2026, 10, 30, 12),
    ))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('analytics_time_basis')));
    await tester.tap(find.byKey(const ValueKey('analytics_time_basis')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar time').last);
    await tester.pumpAndSettle();
    expect(queries.last.timeBasis, AnalyticsTimeBasis.calendarTime);
    await tester.tap(find.byKey(const ValueKey('analytics_grouping')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Month').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('analytics_period')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 7 dates').last);
    await tester.pumpAndSettle();
    expect(queries.last.timeBasis, AnalyticsTimeBasis.calendarTime);
    expect(queries.last.grouping, AnalyticsGrouping.month);
    expect(queries.last.live, isFalse);
  });

  setUpAll(() async {
    final file = File('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf');
    if (Platform.environment['CAPTURE_DESKTOP'] == 'true' && await file.exists()) {
      final loader = FontLoader(WarmCounterTypography.fontFamily);
      loader.addFont(Future.value(ByteData.sublistView(await file.readAsBytes())));
      await loader.load();
      final icons = FontLoader('MaterialIcons');
      icons.addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
    }
    final brand = FontLoader(WarmCounterTypography.brandFontFamily);
    brand.addFont(rootBundle.load('assets/fonts/knewave/Knewave-Regular.ttf'));
    await brand.load();
  });

  testWidgets('Manager can explore reports and distinguish missing profit from zero', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManagerAnalyticsWorkspace(
      service: SnapshotService(), clock: () => DateTime(2026, 10, 26, 12),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('PKR 1,234.50'), findsOneWidget);
    expect(find.text('Change: +PKR 1,234.50 vs preceding comparable period'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('analytics_family')));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Profitability').last);
    await tester.pumpAndSettle();
    expect(find.text('Historical net profit'), findsOneWidget);
    expect(find.text('Missing data'), findsOneWidget);
    expect(find.text('Event-time costs are not recorded.'), findsOneWidget);
    expect(find.text('PKR 0.00'), findsNothing);
  });

  testWidgets('Date changes discard stale totals and publish only the newest cohort', (tester) async {
    final first = Completer<AnalyticsSnapshot>();
    AnalyticsQuery? original;
    final service = SnapshotService(onLoad: (query) {
      if (original == null) { original = query; return first.future; }
      return Future.value(SnapshotService.fixture(query, marker: 'New historical cohort'));
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManagerAnalyticsWorkspace(
      service: service, clock: () => DateTime(2026, 10, 26, 12),
    ))));
    await tester.tap(find.byKey(const ValueKey('analytics_period')));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Previous day').last);
    await tester.pump(const Duration(milliseconds: 400));
    first.complete(SnapshotService.fixture(original!, marker: 'Stale live cohort'));
    await tester.pumpAndSettle();
    expect(find.text('Stale live cohort'), findsNothing);
    expect(find.text('New historical cohort'), findsOneWidget);
    expect(find.textContaining('25 Oct 2026 to 26 Oct 2026'), findsOneWidget);
  });

  testWidgets('A failed load is recoverable through Retry', (tester) async {
    var fail = true;
    final service = SnapshotService(onLoad: (query) async {
      if (fail) throw StateError('fixture failure');
      return SnapshotService.fixture(query);
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManagerAnalyticsWorkspace(service: service))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Unable to load analytics'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('PKR 1,234.50'), findsOneWidget);
    expect(find.textContaining('Unable to load analytics'), findsNothing);
  });

  testWidgets('A rejected refresh clears previously visible financial data', (tester) async {
    var authorized = true;
    final service = SnapshotService(onLoad: (query) async {
      if (!authorized) throw StateError('Manager access is no longer enabled.');
      return SnapshotService.fixture(query);
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManagerAnalyticsWorkspace(service: service))));
    await tester.pumpAndSettle();
    expect(find.text('PKR 1,234.50'), findsOneWidget);
    authorized = false;
    await tester.tap(find.byKey(const ValueKey('analytics_refresh')));
    await tester.pumpAndSettle();
    expect(find.text('PKR 1,234.50'), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
  });

  for (final invalidation in ['session lock', 'rejected refresh', 'workspace disposal']) {
    testWidgets('Open source detail is revoked after $invalidation without closing unrelated routes', (tester) async {
      tester.view.physicalSize = const Size(1366, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = SessionState()..login(const Staff(id: 1, name: 'Manager', departmentId: 1,
        pinHash: 'unused', role: StaffRole.manager, isActive: true));
      final showWorkspace = ValueNotifier(true);
      addTearDown(session.dispose);
      addTearDown(showWorkspace.dispose);
      var reject = false;
      final service = SnapshotService(onLoad: (query) async {
        if (reject) throw StateError('Manager access revoked.');
        return SnapshotService.fixture(query);
      });
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: Scaffold(
        body: ValueListenableBuilder<bool>(valueListenable: showWorkspace, builder: (context, show, _) => show
          ? ManagerAnalyticsWorkspace(service: service, session: session)
          : const Text('Workspace closed')),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('analytics_family')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sales').last);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Source detail • table alternative'), 250,
        scrollable: find.descendant(of: find.byKey(const ValueKey('analytics_body')), matching: find.byType(Scrollable)).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('business_day #1'));
      await tester.pumpAndSettle();
      expect(find.text('Source IDs: 1'), findsOneWidget);
      // A separate root dialog must survive removal of the source route beneath it.
      navigator.currentState!.push(DialogRoute<void>(context: navigator.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Unrelated notification'))));
      await tester.pumpAndSettle();
      if (invalidation == 'session lock') {
        session.lock();
      } else if (invalidation == 'rejected refresh') {
        reject = true;
        await tester.pump(const Duration(seconds: 30));
      } else {
        showWorkspace.value = false;
      }
      await tester.pumpAndSettle();
      expect(find.text('Source IDs: 1', skipOffstage: false), findsNothing);
      expect(find.text('Unrelated notification'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Session lock immediately hides financial data and rejects a pending refresh', (tester) async {
    final session = SessionState()..login(const Staff(id: 1, name: 'Manager', departmentId: 1,
      pinHash: 'unused', role: StaffRole.manager, isActive: true));
    addTearDown(session.dispose);
    final pending = Completer<AnalyticsSnapshot>();
    AnalyticsQuery? request;
    var initial = true;
    final service = SnapshotService(onLoad: (query) {
      request = query;
      if (initial) { initial = false; return Future.value(SnapshotService.fixture(query)); }
      return pending.future;
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManagerAnalyticsWorkspace(service: service, session: session))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('analytics_refresh')));
    await tester.pump();
    session.lock();
    await tester.pump();
    expect(find.text('PKR 1,234.50'), findsNothing);
    expect(find.textContaining('Manager session required'), findsOneWidget);
    pending.complete(SnapshotService.fixture(request!));
    await tester.pumpAndSettle();
    expect(find.text('PKR 1,234.50'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Live refresh publishes a new snapshot and stops when the screen closes', (tester) async {
    var refreshed = false;
    final service = SnapshotService(onLoad: (query) async => SnapshotService.fixture(query,
      marker: refreshed ? 'Fresh local facts' : 'Initial local facts'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManagerAnalyticsWorkspace(
      service: service, refreshInterval: const Duration(seconds: 30),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('Initial local facts'), findsOneWidget);
    refreshed = true;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(find.text('Fresh local facts'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Order filters validate IDs and apply and clear the selected cohort', (tester) async {
    tester.view.physicalSize = const Size(1366, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AnalyticsQuery? requested;
    final service = SnapshotService(onLoad: (query) async {
      requested = query;
      return SnapshotService.fixture(query);
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ManagerAnalyticsWorkspace(service: service))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('analytics_filters_toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('analytics_cashier')), '-1');
    await tester.ensureVisible(find.byKey(const ValueKey('analytics_apply_filters')));
    await tester.tap(find.byKey(const ValueKey('analytics_apply_filters')));
    await tester.pumpAndSettle();
    expect(find.text('Positive ID required'), findsOneWidget);
    expect(requested!.cashierId, isNull);
    await tester.enterText(find.byKey(const ValueKey('analytics_cashier')), '7');
    await tester.ensureVisible(find.byKey(const ValueKey('analytics_apply_filters')));
    await tester.tap(find.byKey(const ValueKey('analytics_apply_filters')));
    await tester.pumpAndSettle();
    expect(requested!.cashierId, 7);
    expect(find.textContaining('Filters applied'), findsOneWidget);
    await tester.ensureVisible(find.text('Clear'));
    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    expect(requested!.hasOrderFilters, isFalse);
    expect(find.text('All cashiers, shifts, Dining Types and payment methods'), findsOneWidget);
  });

  for (final width in [1366.0, 390.0]) {
    testWidgets('Sales dashboard fits ${width.toInt()}px with accessible source table', (tester) async {
      tester.view.physicalSize = Size(width, 768);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme, home: Scaffold(
        body: RepaintBoundary(key: const ValueKey('analytics_preview'), child: Padding(
          padding: const EdgeInsets.all(16), child: ManagerAnalyticsWorkspace(service: SnapshotService(),
            clock: () => DateTime(2026, 10, 26, 12)),
        )),
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('analytics_family')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sales').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.environment['CAPTURE_DESKTOP'] == 'true') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('analytics_preview')));
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final directory = await Directory('build/desktop-previews').create(recursive: true);
          await File('${directory.path}/manager-analytics-${width.toInt()}.png').writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.scrollUntilVisible(find.text('Source detail • table alternative'), 250,
        scrollable: find.descendant(of: find.byKey(const ValueKey('analytics_body')), matching: find.byType(Scrollable)).first);
      await tester.pumpAndSettle();
      expect(find.text('Source detail • table alternative'), findsOneWidget);
      if (width > 1000) {
        await tester.tap(find.text('Business date'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('business_day #1'));
        await tester.pumpAndSettle();
        expect(find.text('Safe reporting projection • source values from this snapshot'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Next page'));
        await tester.pumpAndSettle();
        expect(find.text('11–12 of 12 source rows'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Overview exposes a real sales chart and preserves missing-data labels at larger text size', (tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: WarmCounterTheme.darkTheme,
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(1.3)), child: child!),
      home: Scaffold(body: ManagerAnalyticsWorkspace(service: SnapshotService()))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sales performance'), 200,
      scrollable: find.descendant(of: find.byKey(const ValueKey('analytics_body')),
        matching: find.byType(Scrollable)).first);
    expect(find.text('Sales performance'), findsOneWidget);
    expect(find.text('Recorded order value (PKR) • by Business Day opening date'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
