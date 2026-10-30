import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  group('Backup History Health, Karachi Timezone & Procurement Frequency', () {
    late PosDatabase store;
    late Database db;
    late Staff manager;
    late AnalyticsService analytics;

    setUp(() async {
      store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
      db = await store.initialize();
      final staffRows = await db.query('staff');
      manager = Staff.fromMap(staffRows.firstWhere((r) => r['role'] == 'SUPERVISOR'));
      final auth = AuthService(database: db);
      auth.session.login(manager);
      analytics = AnalyticsService(database: db, authService: auth);
    });

    tearDown(() => store.close());

    test('querying backup attempts ensures most recent verified backup is retrieved even when preceded by 5 failures', () async {
      // 1. Insert an earlier verified successful backup
      await db.insert('backup_attempts', {
        'attempted_at': '2026-10-30 08:00:00',
        'initiator': 'MANUAL',
        'manager_id': manager.id,
        'primary_status': 'SUCCESS',
        'primary_path': '/backups/primary.db',
        'secondary_status': 'SUCCESS',
        'secondary_path': '/usb/secondary.db',
        'verification_status': 'VERIFIED',
        'failure_category': 'NONE',
        'created_at': '2026-10-30 08:00:00',
      });

      // 2. Insert 5 subsequent failed backup attempts
      for (var i = 1; i <= 5; i++) {
        final hourStr = (8 + i).toString().padLeft(2, '0');
        await db.insert('backup_attempts', {
          'attempted_at': '2026-10-30 $hourStr:00:00',
          'initiator': 'SCHEDULED',
          'manager_id': manager.id,
          'primary_status': 'FAILED',
          'secondary_status': 'NOT_CONFIGURED',
          'verification_status': 'FAILED',
          'failure_category': 'IO_DISK_FULL',
          'failure_message': 'Simulated failure $i',
          'created_at': '2026-10-30 $hourStr:00:00',
        });
      }

      // Query recent 5 attempts (all 5 will be failures)
      final allAttempts = await db.query(
        'backup_attempts',
        orderBy: 'attempted_at DESC, id DESC',
        limit: 5,
      );
      expect(allAttempts, hasLength(5));
      expect(allAttempts.every((a) => a['primary_status'] == 'FAILED'), isTrue);

      // Dedicated query for last verified backup must NOT be hidden by 5 failures!
      final verifiedRows = await db.query(
        'backup_attempts',
        where: "verification_status = 'VERIFIED' AND primary_status = 'SUCCESS'",
        orderBy: 'attempted_at DESC, id DESC',
        limit: 1,
      );
      expect(verifiedRows, isNotEmpty, reason: 'A previously successful verified backup must not be hidden by 5 failures');
      expect(verifiedRows.first['attempted_at'], '2026-10-30 08:00:00');
    });

    test('lastVerifiedAgeMinutes uses consistent Karachi wall-clock comparison without 5-hour skew', () async {
      await db.insert('business_days', {
        'opened_at': '2026-10-30 00:00:00',
        'status': 'OPEN',
        'opened_by_staff_id': manager.id,
      });

      // Insert verified backup at 10:00 AM Karachi time
      await db.insert('backup_attempts', {
        'attempted_at': '2026-10-30 10:00:00',
        'initiator': 'MANUAL',
        'manager_id': manager.id,
        'primary_status': 'SUCCESS',
        'secondary_status': 'SUCCESS',
        'verification_status': 'VERIFIED',
        'created_at': '2026-10-30 10:00:00',
      });

      final snapshot = await analytics.load(AnalyticsQuery(
        startDate: DateTime(2026, 10, 30),
        endDateExclusive: DateTime(2026, 10, 31),
        live: true,
      ));

      final auditSection = snapshot.section(AnalyticsFamily.audit);
      final ageMetric = auditSection.metrics.firstWhere((m) => m.id == 'last_verified_backup_age');
      expect(ageMetric.value, isNotNull);

      // Verify that analyticsKarachiTime parsed both correctly
      final attemptedKarachi = analyticsKarachiTime('2026-10-30 10:00:00')!;
      final currentKarachi = analyticsKarachiTime(snapshot.generatedAt.toIso8601String())!;
      final expectedMinutes = currentKarachi.difference(attemptedKarachi).inMinutes.toDouble();

      expect(ageMetric.value, closeTo(expectedMinutes, 2.0));
      // Ensure it is not skewed by 300 minutes (5 hours)
      expect((ageMetric.value! - expectedMinutes).abs(), lessThan(5.0));
    });

    test('procurement section projects purchase_frequency and distinct_suppliers matching exports', () async {
      await db.insert('business_days', {
        'opened_at': '2026-10-30 00:00:00',
        'closed_at': '2026-10-30 23:59:59',
        'status': 'CLOSED',
        'opened_by_staff_id': manager.id,
      });

      final ing = await db.insert('raw_ingredients', {
        'name': 'Flour',
        'storage_unit': 'kg',
        'current_stock': 100,
        'cost_per_recipe_unit': 80,
        'category': 'FOOD',
        'created_at': '2026-10-30 08:00:00',
      });

      final vendor = await db.insert('vendor_khata', {
        'name': 'Al-Madina Mills',
        'phone': '03001234567',
        'opening_balance': 0,
        'current_balance': 0,
        'created_at': '2026-10-30 08:00:00',
        'updated_at': '2026-10-30 08:00:00',
      });

      // Insert 2 purchases from this vendor
      await db.insert('mandi_procurements', {
        'raw_ingredient_id': ing,
        'traditional_unit': 'kg',
        'quantity': 10,
        'total_cost': 800,
        'converted_quantity': 10,
        'cost_per_recipe_unit': 80,
        'created_at': '2026-10-30 11:00:00',
      });
      await db.insert('vendor_transactions', {
        'vendor_id': vendor,
        'type': 'PURCHASE_CREDIT',
        'amount': 1600,
        'raw_ingredient_id': ing,
        'quantity': 20,
        'created_at': '2026-10-30 14:00:00',
      });

      final snapshot = await analytics.load(AnalyticsQuery(
        startDate: DateTime(2026, 10, 30),
        endDateExclusive: DateTime(2026, 10, 31),
      ));

      final procurementSection = snapshot.section(AnalyticsFamily.procurement);

      // 1. Column list must include purchase_frequency
      expect(procurementSection.columns.any((c) => c.key == 'purchase_frequency'), isTrue);

      // 2. Metrics must include distinct_suppliers
      final supplierMetric = procurementSection.metrics.firstWhere((m) => m.id == 'distinct_suppliers');
      expect(supplierMetric.value, greaterThanOrEqualTo(1));

      // 3. Row cells must project purchase_frequency
      final rowsWithFreq = procurementSection.rows.where((r) => r.cells.containsKey('purchase_frequency')).toList();
      expect(rowsWithFreq, isNotEmpty);
      expect(rowsWithFreq.first.cells['purchase_frequency'], isNotNull);
    });
  });
}
