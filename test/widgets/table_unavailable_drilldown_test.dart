import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/theme/theme.dart';
import 'package:resturant_sys/widgets/supervisor/manager_analytics_workspace.dart';

class _FakeAnalyticsService implements AnalyticsService {
  _FakeAnalyticsService({required this.snapshot});
  final AnalyticsSnapshot snapshot;

  @override
  Future<AnalyticsSnapshot> load(AnalyticsQuery query) async => snapshot;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final manager = Staff(
    id: 1,
    name: 'Lead Manager',
    departmentId: 1,
    pinHash: 'synthetic_hash',
    role: StaffRole.manager,
    isActive: true,
    loginEnabled: true,
    createdAt: DateTime(2026, 10, 1),
  );

  final session = SessionState()..login(manager);

  group('Table Unavailable and Projection Drilldown Bug Repro', () {
    testWidgets('Chart source drill-down for BOM quantities shows name, unit and prunes irrelevant columns', (tester) async {
      tester.view.physicalSize = const Size(1366, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final inventorySection = AnalyticsSection(
        family: AnalyticsFamily.inventory,
        title: 'Inventory',
        metrics: const [
          AnalyticsMetric(id: 'ingredients', label: 'Current ingredients', value: 1, unit: AnalyticsUnit.count, explanation: 'Test'),
        ],
        columns: const [
          AnalyticsColumn(key: 'kind', label: 'Kind'),
          AnalyticsColumn(key: 'ingredient_id', label: 'Ingredient ID'),
          AnalyticsColumn(key: 'name', label: 'Name'),
          AnalyticsColumn(key: 'unit', label: 'Unit'),
          AnalyticsColumn(key: 'opening_qty', label: 'Opening Qty', unit: AnalyticsUnit.decimal),
          AnalyticsColumn(key: 'receipts_qty', label: 'Receipts Qty', unit: AnalyticsUnit.decimal),
          AnalyticsColumn(key: 'consumption_qty', label: 'Consumption Qty', unit: AnalyticsUnit.decimal),
          AnalyticsColumn(key: 'waste_qty', label: 'Waste Qty', unit: AnalyticsUnit.decimal),
          AnalyticsColumn(key: 'quantity', label: 'Quantity', unit: AnalyticsUnit.decimal),
        ],
        rows: [
          AnalyticsRow(
            id: 'pos-1',
            sourceType: 'raw_ingredients',
            sourceId: '1',
            cells: {
              'kind': 'Current position',
              'ingredient_id': 1,
              'name': 'Beef Patty',
              'unit': 'g',
              'current_stock': 500.0,
              'status': 'Within threshold',
            },
          ),
          AnalyticsRow(
            id: 'bom-1',
            sourceType: 'order_items',
            sourceId: '1',
            cells: {
              'kind': 'BOM quantity snapshot',
              'order_id': 1,
              'ingredient_id': 1,
              'quantity': 100.0,
            },
          ),
        ],
      );

      final snapshot = AnalyticsSnapshot(
        query: AnalyticsQuery(
          startDate: DateTime(2026, 10, 25),
          endDateExclusive: DateTime(2026, 10, 27),
          live: true,
        ),
        generatedAt: DateTime(2026, 10, 27, 12),
        businessDayIds: const [1],
        sections: [inventorySection],
      );

      await tester.pumpWidget(MaterialApp(
        theme: WarmCounterTheme.darkTheme,
        home: Scaffold(
          body: ManagerAnalyticsWorkspace(
            service: _FakeAnalyticsService(snapshot: snapshot),
            session: session,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Switch to Inventory family
      tester.widget<DropdownButtonFormField<AnalyticsFamily>>(
        find.byKey(const ValueKey('analytics_family'))).onChanged!(AnalyticsFamily.inventory);
      await tester.pumpAndSettle();

      // Find the chart point for BOM quantities
      final pointFinder = find.byKey(const ValueKey('chart_point_bom_g_0'));
      expect(pointFinder, findsOneWidget);
      await tester.scrollUntilVisible(
        pointFinder,
        200,
        scrollable: find.descendant(of: find.byKey(const ValueKey('analytics_body')), matching: find.byType(Scrollable)).first,
      );
      await tester.tap(pointFinder);
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);

      // Verify chart source records table does NOT show 'Unavailable' for name, unit, opening_qty, etc.
      // 1. Should not show column headers that have no data for these rows (e.g. Opening Qty)
      expect(find.descendant(of: dialog, matching: find.text('Opening Qty')), findsNothing);
      expect(find.descendant(of: dialog, matching: find.text('Receipts Qty')), findsNothing);
      expect(find.descendant(of: dialog, matching: find.text('Waste Qty')), findsNothing);

      // 2. Should show the ingredient name and unit
      expect(find.descendant(of: dialog, matching: find.text('Beef Patty')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Unavailable')), findsNothing);
    });

    testWidgets('KPI contributor dialog for Revision audit events filters to revision events and prunes empty columns', (tester) async {
      tester.view.physicalSize = const Size(1366, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final auditSection = AnalyticsSection(
        family: AnalyticsFamily.audit,
        title: 'Control and audit',
        metrics: const [
          AnalyticsMetric(
            id: 'revision_events',
            label: 'Revision audit events',
            value: 1,
            unit: AnalyticsUnit.count,
            explanation: 'Append-only revision evidence.',
          ),
        ],
        columns: const [
          AnalyticsColumn(key: 'kind', label: 'Kind'),
          AnalyticsColumn(key: 'business_day_id', label: 'Business Day ID'),
          AnalyticsColumn(key: 'order_id', label: 'Order ID'),
          AnalyticsColumn(key: 'shift_id', label: 'Shift ID'),
          AnalyticsColumn(key: 'ingredient_id', label: 'Ingredient ID'),
          AnalyticsColumn(key: 'token', label: 'Token'),
          AnalyticsColumn(key: 'revision', label: 'Revision'),
          AnalyticsColumn(key: 'action', label: 'Action'),
          AnalyticsColumn(key: 'delta_paisa', label: 'Delta', unit: AnalyticsUnit.paisa),
        ],
        rows: [
          AnalyticsRow(
            id: 'rev-1',
            sourceType: 'order_revisions',
            sourceId: '1',
            cells: {
              'kind': 'Order revision',
              'order_id': 1,
              'action': 'CHANGE',
              'delta_paisa': 0,
            },
          ),
          AnalyticsRow(
            id: 'token-1',
            sourceType: 'checkout_token_audit',
            sourceId: '1',
            cells: {
              'kind': 'Immutable token audit',
              'order_id': 1,
              'token': 1,
              'revision': 1,
              'action': 'ALLOCATED',
            },
          ),
        ],
      );

      final snapshot = AnalyticsSnapshot(
        query: AnalyticsQuery(
          startDate: DateTime(2026, 10, 25),
          endDateExclusive: DateTime(2026, 10, 27),
          live: true,
        ),
        generatedAt: DateTime(2026, 10, 27, 12),
        businessDayIds: const [1],
        sections: [auditSection],
      );

      await tester.pumpWidget(MaterialApp(
        theme: WarmCounterTheme.darkTheme,
        home: Scaffold(
          body: ManagerAnalyticsWorkspace(
            service: _FakeAnalyticsService(snapshot: snapshot),
            session: session,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Switch to Audit family
      tester.widget<DropdownButtonFormField<AnalyticsFamily>>(
        find.byKey(const ValueKey('analytics_family'))).onChanged!(AnalyticsFamily.audit);
      await tester.pumpAndSettle();

      // Tap Revision audit events metric card
      final kpiFinder = find.byKey(const ValueKey('metric_card_revision_events')).first;
      await tester.tap(kpiFinder);
      await tester.pumpAndSettle();

      final dialog = find.byKey(const ValueKey('kpi_contributor_dialog'));
      expect(dialog, findsOneWidget);

      // Should only show 1 contributing record, not 2
      expect(find.descendant(of: dialog, matching: find.text('1 records')), findsOneWidget);
      expect(find.descendant(of: dialog, matching: find.text('Immutable token audit')), findsNothing);

      // Should not show columns that have no values across contributing rows
      expect(find.descendant(of: dialog, matching: find.text('Business Day ID')), findsNothing);
      expect(find.descendant(of: dialog, matching: find.text('Shift ID')), findsNothing);
      expect(find.descendant(of: dialog, matching: find.text('Ingredient ID')), findsNothing);

      // Should not show 'Unavailable' text
      expect(find.descendant(of: dialog, matching: find.text('Unavailable')), findsNothing);
    });
  });
}
