import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/widgets/supervisor/analytics_export_actions.dart';
import 'package:resturant_sys/widgets/supervisor/manager_analytics_workspace.dart';

class _TestAnalyticsService implements AnalyticsService {
  _TestAnalyticsService({this.onLoad});

  final Future<AnalyticsSnapshot> Function(AnalyticsQuery query)? onLoad;

  @override
  Future<AnalyticsSnapshot> load(AnalyticsQuery query) async {
    if (onLoad != null) return onLoad!(query);
    return _fixture(query);
  }

  static AnalyticsSnapshot _fixture(AnalyticsQuery query) => AnalyticsSnapshot(
        query: query,
        generatedAt: DateTime.utc(2026, 11, 2, 12),
        businessDayIds: [8],
        generatedByStaffId: 1,
        sections: [
          AnalyticsSection(
            family: AnalyticsFamily.overview,
            title: 'Overview',
            metrics: const [
              AnalyticsMetric(
                id: 'recorded',
                label: 'Recorded order value',
                value: 5000,
                unit: AnalyticsUnit.paisa,
                explanation: 'Test metric',
              ),
            ],
            columns: const [
              AnalyticsColumn(key: 'name', label: 'Name'),
            ],
            rows: [
              AnalyticsRow(
                id: '1',
                sourceType: 'test',
                sourceId: '1',
                cells: const {'name': 'Row 1'},
              ),
            ],
          ),
          AnalyticsSection(
            family: AnalyticsFamily.delivery,
            title: 'Delivery and riders',
            metrics: const [
              AnalyticsMetric(
                id: 'delivery_orders',
                label: 'Delivery orders',
                value: 1,
                unit: AnalyticsUnit.count,
                explanation: '1 delivery order',
              ),
            ],
            columns: const [
              AnalyticsColumn(key: 'fee', label: 'Delivery fee', unit: AnalyticsUnit.paisa),
            ],
            rows: [
              AnalyticsRow(
                id: '101',
                sourceType: 'orders',
                sourceId: '30',
                cells: const {'fee': 5000},
              ),
            ],
          ),
        ],
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('export actions remain mounted and save file even if background refresh occurs during picker', (tester) async {
    tester.view.physicalSize = const Size(1366, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final exportDir = Directory.systemTemp.createTempSync('export-lifecycle-test-');
    addTearDown(() => exportDir.deleteSync(recursive: true));

    final session = SessionState()
      ..login(const Staff(
        id: 1,
        name: 'Supervisor',
        departmentId: 1,
        pinHash: 'unused',
        role: StaffRole.manager,
        isActive: true,
        loginEnabled: true,
      ));
    addTearDown(session.dispose);

    final pickerCompleter = Completer<String?>();
    final refreshGate = Completer<void>();
    var loadCount = 0;

    final service = _TestAnalyticsService(onLoad: (query) async {
      loadCount++;
      if (loadCount == 2) {
        // Second load represents background refresh
        await refreshGate.future;
      }
      return _TestAnalyticsService._fixture(query);
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ManagerAnalyticsWorkspace(
          service: service,
          session: session,
          exportActionsBuilder: (context, snapshot, family) => AnalyticsExportActions(
            snapshot: snapshot,
            family: family,
            compact: true,
            pickDirectory: () => pickerCompleter.future,
            canExport: () {
              final actor = session.currentStaff;
              return actor != null &&
                  actor.isActive &&
                  actor.canAccessSupervisorPortal &&
                  actor.id == snapshot.generatedByStaffId;
            },
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();

    // 1. Export menu button is visible initially
    expect(find.byKey(const ValueKey('analytics_export_menu')), findsOneWidget);

    // 2. Open the export menu and trigger CSV export
    await tester.tap(find.byKey(const ValueKey('analytics_export_menu')));
    await tester.pumpAndSettle();

    expect(find.text('CSV (this report)'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('CSV (this report)'));
      await tester.pump();

      // 3. Trigger a background refresh while picker is open
      await tester.tap(find.byKey(const ValueKey('analytics_refresh')));
      await tester.pump();

      // Verify system is busy loading second snapshot
      expect(loadCount, 2);

      // CRITICAL: Does the export action stay mounted while busy?
      expect(
        find.byKey(const ValueKey('analytics_export_menu')),
        findsOneWidget,
        reason: 'Export menu must not vanish during background refresh',
      );

      // 4. Complete the background refresh
      refreshGate.complete();
      await tester.pump();

      // 5. User finally selects a folder in the picker
      pickerCompleter.complete(exportDir.path);

      for (var attempt = 0; attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await tester.pump();
        if (exportDir.listSync().whereType<File>().any((f) => f.path.endsWith('.csv'))) break;
      }
    });

    await tester.pump(const Duration(milliseconds: 200));

    // CRITICAL ASSERTION: The file was exported to the chosen directory
    final exportedFiles = exportDir.listSync().whereType<File>().where((f) => f.path.endsWith('.csv')).toList();
    expect(
      exportedFiles,
      isNotEmpty,
      reason: 'Export file must be created even if background refresh occurred while picking folder',
    );
    expect(exportedFiles.first.path, endsWith('.csv'));
  });
}
