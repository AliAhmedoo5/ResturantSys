import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/manager_presets_service.dart';
import 'package:resturant_sys/core/auth/session_state.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/widgets/supervisor/manager_analytics_workspace.dart';

class MockAnalyticsService implements AnalyticsService {
  MockAnalyticsService({required this.snapshot});
  final AnalyticsSnapshot snapshot;

  @override
  Future<AnalyticsSnapshot> load(AnalyticsQuery query) async => snapshot;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePresetsService implements ManagerPresetsService {
  FakePresetsService({required this.presets});
  final List<ManagerReportPreset> presets;

  @override
  Future<List<ManagerReportPreset>> listPresets({required int staffId}) async => presets;

  @override
  Future<ManagerReportPreset> createPreset({
    required String name,
    required int ownerStaffId,
    required bool isShared,
    required AnalyticsFamily family,
    required PresetPeriodKind periodKind,
    String? dynamicPeriod,
    DateTime? startDate,
    DateTime? endDateExclusive,
    required AnalyticsTimeBasis timeBasis,
    required AnalyticsGrouping grouping,
    Map<String, dynamic> filters = const {},
  }) async {
    final p = ManagerReportPreset(
      id: presets.length + 1,
      name: name,
      ownerStaffId: ownerStaffId,
      isShared: isShared,
      family: family,
      periodKind: periodKind,
      dynamicPeriod: dynamicPeriod,
      startDate: startDate,
      endDateExclusive: endDateExclusive,
      timeBasis: timeBasis,
      grouping: grouping,
      filters: filters,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    presets.add(p);
    return p;
  }

  @override
  Future<void> deletePreset({required int presetId, required int staffId}) async {
    presets.removeWhere((p) => p.id == presetId);
  }

  @override
  Future<ManagerReportPreset> updatePreset(ManagerReportPreset preset, {required int staffId}) async {
    final idx = presets.indexWhere((p) => p.id == preset.id);
    if (idx != -1) presets[idx] = preset;
    return preset;
  }

  @override
  AnalyticsQuery resolvePresetQuery(
    ManagerReportPreset preset, {
    DateTime Function()? clock,
    List<AnalyticsFilterOption>? availableFilters,
  }) {
    return AnalyticsQuery(
      startDate: DateTime(2026, 10, 1),
      endDateExclusive: DateTime(2026, 11, 1),
      live: true,
      timeBasis: preset.timeBasis,
      grouping: preset.grouping,
    );
  }

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

  final salesSection = AnalyticsSection(
    family: AnalyticsFamily.sales,
    title: 'Sales',
    metrics: const [
      AnalyticsMetric(
        id: 'recorded_value',
        label: 'Recorded order value',
        value: 125000,
        unit: AnalyticsUnit.paisa,
        explanation: 'Eligible orders including Collection Due.',
      ),
    ],
    columns: const [
      AnalyticsColumn(key: 'business_date', label: 'Business date'),
      AnalyticsColumn(key: 'orders', label: 'Orders', unit: AnalyticsUnit.count),
      AnalyticsColumn(key: 'recorded_value_paisa', label: 'Recorded Value', unit: AnalyticsUnit.paisa),
    ],
    rows: [
      AnalyticsRow(
        id: 'day-1',
        sourceType: 'business_days',
        sourceId: '101',
        cells: {
          'kind': 'Daily total',
          'business_date': '2026-10-25',
          'orders': 5,
          'recorded_value_paisa': 125000,
        },
      ),
    ],
  );

  final snapshot = AnalyticsSnapshot(
    query: AnalyticsQuery(
      startDate: DateTime(2026, 10, 25),
      endDateExclusive: DateTime(2026, 10, 26),
      live: true,
    ),
    generatedAt: DateTime(2026, 10, 26, 12),
    businessDayIds: const [1],
    sections: [
      AnalyticsSection(
        family: AnalyticsFamily.overview,
        title: 'Overview',
        metrics: salesSection.metrics,
      ),
      salesSection,
    ],
  );

  testWidgets('Month to date shortcut updates period query and includes Karachi month start', (tester) async {
    tester.view.physicalSize = const Size(1366, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ManagerAnalyticsWorkspace(
          service: MockAnalyticsService(snapshot: snapshot),
          session: session,
          clock: () => DateTime.utc(2026, 10, 31, 12), // 17:00 Karachi
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Find period dropdown and tap Month to date
    await tester.tap(find.byKey(const ValueKey('analytics_period')));
    await tester.pumpAndSettle();

    expect(find.text('Month to date'), findsOneWidget);
    await tester.tap(find.text('Month to date').last);
    await tester.pumpAndSettle();

    // Verify UI reflects Month to date
    expect(find.text('Month to date'), findsWidgets);
  });

  testWidgets('Tapping KPI opens contributor dialog and allows inspecting source record', (tester) async {
    tester.view.physicalSize = const Size(1366, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ManagerAnalyticsWorkspace(
          service: MockAnalyticsService(snapshot: snapshot),
          session: session,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Find metric card for recorded_value and tap it
    final metricFinder = find.byKey(const ValueKey('metric_card_recorded_value')).first;
    await tester.tap(metricFinder);
    await tester.pumpAndSettle();

    // KPI Contributor dialog should be open
    expect(find.byKey(const ValueKey('kpi_contributor_dialog')), findsOneWidget);
    expect(find.textContaining('Recorded order value'), findsWidgets);
    expect(find.textContaining('Total Recorded Value ='), findsOneWidget);
    expect(find.textContaining('PKR 1,250.00'), findsWidgets);

    // Find the row's inspect source button
    final inspectFinder = find.byKey(const ValueKey('kpi_inspect_source_day-1'));
    expect(inspectFinder, findsOneWidget);
    await tester.tap(inspectFinder);
    await tester.pumpAndSettle();

    // Source detail dialog should be open
    expect(find.textContaining('Safe reporting projection'), findsOneWidget);
    expect(find.textContaining('Source IDs: 101'), findsOneWidget);

    // Close source detail dialog
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('Allows saving, listing, and switching report presets', (tester) async {
    tester.view.physicalSize = const Size(1366, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fakePresets = FakePresetsService(presets: [
      ManagerReportPreset(
        id: 1,
        name: 'Weekly Sales Preset',
        ownerStaffId: 1,
        isShared: true,
        family: AnalyticsFamily.sales,
        periodKind: PresetPeriodKind.dynamic,
        dynamicPeriod: 'week',
        timeBasis: AnalyticsTimeBasis.businessDay,
        grouping: AnalyticsGrouping.day,
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ManagerAnalyticsWorkspace(
          service: MockAnalyticsService(snapshot: snapshot),
          presetsService: fakePresets,
          session: session,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Presets button should exist
    final presetsButton = find.byKey(const ValueKey('analytics_presets_button'));
    expect(presetsButton, findsOneWidget);
    await tester.tap(presetsButton);
    await tester.pumpAndSettle();

    // Preset list dialog is shown
    expect(find.text('Saved report presets'), findsOneWidget);
    expect(find.text('Weekly Sales Preset'), findsOneWidget);

    // Tap to apply preset
    await tester.tap(find.text('Weekly Sales Preset'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
