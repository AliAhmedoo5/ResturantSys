import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/manager_presets_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/auth/staff_role.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('ManagerPresetsService & Schema v28', () {
    late PosDatabase store;
    late Database db;
    late AuthService auth;
    late Staff manager1;
    late Staff manager2;
    late Staff cashier;
    late ManagerPresetsService service;

    setUp(() async {
      store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      db = await store.initialize();
      auth = AuthService(database: db);

      final staffRows = await db.query('staff');
      final managers = staffRows.where((r) => r['role'] == 'MANAGER').toList();
      manager1 = Staff.fromMap(managers[0]);

      // Insert second manager for sharing/ownership tests
      final mgr2Id = await db.insert('staff', {
        'name': 'Assistant Manager',
        'department_id': 1,
        'role': 'MANAGER',
        'pin_hash': 'synthetic_hash',
        'is_active': 1,
        'login_enabled': 1,
        'created_at': '2026-10-25 18:00:00',
      });
      manager2 = Staff(
        id: mgr2Id,
        name: 'Assistant Manager',
        departmentId: 1,
        pinHash: 'synthetic_hash',
        role: StaffRole.manager,
        isActive: true,
        loginEnabled: true,
        createdAt: DateTime.parse('2026-10-25 18:00:00'),
      );

      final cashierRow = staffRows.firstWhere((r) => r['role'] == 'CASHIER');
      cashier = Staff.fromMap(cashierRow);

      service = ManagerPresetsService(database: db, authService: auth);
    });

    tearDown(() async {
      await store.close();
    });

    test('Persists and lists private and shared presets with RBAC', () async {
      auth.session.login(manager1);

      // Manager 1 creates a private preset
      final privatePreset = await service.createPreset(
        name: 'My Daily Sales Audit',
        ownerStaffId: manager1.id,
        isShared: false,
        family: AnalyticsFamily.sales,
        periodKind: PresetPeriodKind.dynamic,
        dynamicPeriod: 'month_to_date',
        timeBasis: AnalyticsTimeBasis.businessDay,
        grouping: AnalyticsGrouping.day,
        filters: const {
          'cashierId': 2,
          'diningType': 'TAKEAWAY',
        },
      );

      expect(privatePreset.id, isNotNull);
      expect(privatePreset.name, 'My Daily Sales Audit');
      expect(privatePreset.isShared, isFalse);
      expect(privatePreset.periodKind, PresetPeriodKind.dynamic);
      expect(privatePreset.dynamicPeriod, 'month_to_date');

      // Manager 1 creates a shared preset
      final sharedPreset = await service.createPreset(
        name: 'Shared Kitchen Wastage',
        ownerStaffId: manager1.id,
        isShared: true,
        family: AnalyticsFamily.inventory,
        periodKind: PresetPeriodKind.fixed,
        startDate: DateTime.utc(2026, 10, 1),
        endDateExclusive: DateTime.utc(2026, 10, 20),
        timeBasis: AnalyticsTimeBasis.calendarTime,
        grouping: AnalyticsGrouping.week,
        filters: const {},
      );

      expect(sharedPreset.isShared, isTrue);

      // Manager 1 lists presets: sees both
      final mgr1Presets = await service.listPresets(staffId: manager1.id);
      expect(mgr1Presets.length, 2);

      // Manager 2 logs in: sees only the shared preset, NOT manager 1 private preset
      auth.session.login(manager2);
      final mgr2Presets = await service.listPresets(staffId: manager2.id);
      expect(mgr2Presets.length, 1);
      expect(mgr2Presets.first.id, sharedPreset.id);
      expect(mgr2Presets.first.name, 'Shared Kitchen Wastage');

      // Cashier logs in: denied access
      auth.session.login(cashier);
      expect(() => service.listPresets(staffId: cashier.id), throwsStateError);
      expect(
        () => service.createPreset(
          name: 'Hacked',
          ownerStaffId: cashier.id,
          isShared: false,
          family: AnalyticsFamily.sales,
          periodKind: PresetPeriodKind.dynamic,
          timeBasis: AnalyticsTimeBasis.businessDay,
          grouping: AnalyticsGrouping.day,
        ),
        throwsStateError,
      );
    });

    test('Only owning Manager can update or delete their preset', () async {
      auth.session.login(manager1);
      final preset = await service.createPreset(
        name: 'Shared Profitability Review',
        ownerStaffId: manager1.id,
        isShared: true,
        family: AnalyticsFamily.profitability,
        periodKind: PresetPeriodKind.dynamic,
        dynamicPeriod: 'today',
        timeBasis: AnalyticsTimeBasis.businessDay,
        grouping: AnalyticsGrouping.day,
      );

      // Manager 2 cannot update Manager 1's preset even if shared
      auth.session.login(manager2);
      final updatedAttempt = preset.copyWith(name: 'Tampered Name');
      expect(
        () => service.updatePreset(updatedAttempt, staffId: manager2.id),
        throwsStateError,
      );

      // Manager 2 cannot delete Manager 1's preset
      expect(
        () => service.deletePreset(presetId: preset.id!, staffId: manager2.id),
        throwsStateError,
      );

      // Manager 1 can update
      auth.session.login(manager1);
      final updated = await service.updatePreset(
        preset.copyWith(name: 'Updated Profitability Review', isShared: false),
        staffId: manager1.id,
      );
      expect(updated.name, 'Updated Profitability Review');
      expect(updated.isShared, isFalse);

      // Manager 1 can delete
      await service.deletePreset(presetId: preset.id!, staffId: manager1.id);
      final remaining = await service.listPresets(staffId: manager1.id);
      expect(remaining.any((p) => p.id == preset.id), isFalse);
    });

    test('Month to date operational shortcut calculates Karachi 1st of month to today', () {
      // Synthetic Karachi time: 31 October 2026, 17:30 (UTC: 12:30)
      final syntheticNow = DateTime.utc(2026, 10, 31, 12, 30);

      final preset = ManagerReportPreset(
        id: 1,
        name: 'MTD Sales',
        ownerStaffId: manager1.id,
        isShared: false,
        family: AnalyticsFamily.sales,
        periodKind: PresetPeriodKind.dynamic,
        dynamicPeriod: 'month_to_date',
        timeBasis: AnalyticsTimeBasis.businessDay,
        grouping: AnalyticsGrouping.day,
        filters: const {},
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
      );

      final query = service.resolvePresetQuery(preset, clock: () => syntheticNow);
      expect(query.live, isTrue);
      expect(query.startDate, DateTime(2026, 10, 1));
      // End date exclusive is start of tomorrow (November 1)
      expect(query.endDateExclusive, DateTime(2026, 11, 1));
      expect(query.timeBasis, AnalyticsTimeBasis.businessDay);
      expect(query.grouping, AnalyticsGrouping.day);
    });

    test('Dynamic relative dates vs fixed date ranges properly distinguished', () {
      final syntheticNow = DateTime.utc(2026, 10, 31, 12, 30);

      // Dynamic today
      final dynamicToday = ManagerReportPreset(
        id: 1,
        name: 'Today',
        ownerStaffId: manager1.id,
        isShared: false,
        family: AnalyticsFamily.sales,
        periodKind: PresetPeriodKind.dynamic,
        dynamicPeriod: 'today',
        timeBasis: AnalyticsTimeBasis.businessDay,
        grouping: AnalyticsGrouping.day,
        filters: const {},
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
      );
      final todayQuery = service.resolvePresetQuery(dynamicToday, clock: () => syntheticNow);
      expect(todayQuery.startDate, DateTime(2026, 10, 31));
      expect(todayQuery.endDateExclusive, DateTime(2026, 11, 1));
      expect(todayQuery.live, isFalse);

      // Dynamic yesterday
      final dynamicYesterday = dynamicToday.copyWith(dynamicPeriod: 'yesterday');
      final yesterdayQuery = service.resolvePresetQuery(dynamicYesterday, clock: () => syntheticNow);
      expect(yesterdayQuery.startDate, DateTime(2026, 10, 30));
      expect(yesterdayQuery.endDateExclusive, DateTime(2026, 10, 31));
      expect(yesterdayQuery.live, isFalse);

      // Fixed range
      final fixedPreset = ManagerReportPreset(
        id: 2,
        name: 'Historical Period',
        ownerStaffId: manager1.id,
        isShared: false,
        family: AnalyticsFamily.sales,
        periodKind: PresetPeriodKind.fixed,
        startDate: DateTime(2026, 9, 1),
        endDateExclusive: DateTime(2026, 9, 15),
        timeBasis: AnalyticsTimeBasis.calendarTime,
        grouping: AnalyticsGrouping.week,
        filters: const {},
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
      );
      final fixedQuery = service.resolvePresetQuery(fixedPreset, clock: () => syntheticNow);
      expect(fixedQuery.startDate, DateTime(2026, 9, 1));
      expect(fixedQuery.endDateExclusive, DateTime(2026, 9, 15));
      expect(fixedQuery.live, isFalse);
      expect(fixedQuery.timeBasis, AnalyticsTimeBasis.calendarTime);
      expect(fixedQuery.grouping, AnalyticsGrouping.week);
    });

    test('Revalidates filters and safely sanitizes unsupported or missing dimensions', () {
      final preset = ManagerReportPreset(
        id: 3,
        name: 'Filtered Audit',
        ownerStaffId: manager1.id,
        isShared: false,
        family: AnalyticsFamily.sales,
        periodKind: PresetPeriodKind.dynamic,
        dynamicPeriod: 'live',
        timeBasis: AnalyticsTimeBasis.businessDay,
        grouping: AnalyticsGrouping.day,
        filters: const {
          'cashierId': -5, // Invalid negative ID
          'shiftId': 10,
          'diningType': 'NON_EXISTENT_TYPE',
          'paymentMethod': 'CASH',
          'fundingStream': 'INVALID_STREAM',
          'domainFilters': {
            'menuCategory': '12',
            'unknown_dimension': '99',
            'customerSegment': 'malicious_segment',
          },
        },
        createdAt: DateTime.utc(2026, 10, 1),
        updatedAt: DateTime.utc(2026, 10, 1),
      );

      // Revalidation should not crash and should sanitize invalid fields
      final query = service.resolvePresetQuery(preset);
      expect(query.cashierId, isNull); // Dropped negative ID
      expect(query.shiftId, 10);
      expect(query.diningType, isNull); // Dropped unknown dining type
      expect(query.paymentMethod, 'CASH');
      expect(query.fundingStream, isNull); // Dropped invalid stream
      expect(query.domainFilters[AnalyticsDimension.menuCategory], '12');
      expect(query.domainFilters.containsKey(AnalyticsDimension.customerSegment), isFalse); // Sanitized
    });
  });
}
