import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/backup_attempts_schema.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Ticket #85: Analytics backup history and health audit', () {
    late Directory tempDir;
    late String dbPath;
    late PosDatabase posDb;
    late Database db;
    late AuthService authService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('backup_analytics_test_');
      dbPath = '${tempDir.path}${Platform.pathSeparator}pos_test.db';
      posDb = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
      db = await posDb.initialize();

      authService = AuthService(database: db);
      final manager = (await db.query('staff', where: 'id = 1')).single;
      authService.session.login(Staff.fromMap(manager));

      // Open a business day so interval queries match
      await db.insert('business_days', {
        'opened_at': '2026-10-30 08:00:00',
        'closed_at': '2026-10-30 23:00:00',
        'status': 'CLOSED',
        'opened_by_staff_id': 1,
      });

      // Ensure backup_attempts schema is present
      await createBackupAttemptsSchema(db);
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('AnalyticsService projects missing backup history when backup_attempts has no verified success', () async {
      final query = AnalyticsQuery(
        startDate: DateTime(2026, 10, 30),
        endDateExclusive: DateTime(2026, 10, 31),
      );

      final service = AnalyticsService(database: db, authService: authService);
      final snapshot = await service.load(query);

      final auditSection = snapshot.section(AnalyticsFamily.audit);
      AnalyticsMetric metric(String id) => auditSection.metrics.firstWhere((m) => m.id == id);

      final backupHistory = metric('backup_history');
      expect(backupHistory.quality, AnalyticsQuality.missing);
      expect(backupHistory.explanation, contains('No verified backup attempts have been recorded'));

      final lastVerifiedAge = metric('last_verified_backup_age');
      expect(lastVerifiedAge.quality, AnalyticsQuality.missing);
    });

    test('AnalyticsService projects durable backup history, failed attempts, and secondary warnings in AnalyticsFamily.audit', () async {
      // Insert a verified backup
      await db.insert('backup_attempts', {
        'attempted_at': '2026-10-30T10:00:00.000Z',
        'initiator': 'MANUAL',
        'manager_id': 1,
        'primary_status': 'SUCCESS',
        'primary_path': 'C:/Backups/pos_backup_1.zip',
        'secondary_status': 'NOT_CONFIGURED',
        'secondary_path': null,
        'verification_status': 'VERIFIED',
        'failure_category': 'NONE',
        'failure_message': null,
        'created_at': '2026-10-30 10:00:00',
      });

      // Insert a secondary warning backup
      await db.insert('backup_attempts', {
        'attempted_at': '2026-10-30T12:00:00.000Z',
        'initiator': 'Z_CLOSE',
        'manager_id': 1,
        'primary_status': 'SUCCESS',
        'primary_path': 'C:/Backups/pos_backup_2.zip',
        'secondary_status': 'WARNING',
        'secondary_path': null,
        'verification_status': 'VERIFIED',
        'failure_category': 'STORAGE_UNAVAILABLE',
        'failure_message': 'Secondary target disconnected',
        'created_at': '2026-10-30 12:00:00',
      });

      // Insert a failed backup
      await db.insert('backup_attempts', {
        'attempted_at': '2026-10-30T14:00:00.000Z',
        'initiator': 'SCHEDULED',
        'manager_id': null,
        'primary_status': 'FAILED',
        'primary_path': null,
        'secondary_status': 'FAILED',
        'secondary_path': null,
        'verification_status': 'FAILED',
        'failure_category': 'MEDIA_CORRUPTED',
        'failure_message': 'Referenced catalog photo is missing',
        'created_at': '2026-10-30 14:00:00',
      });

      final query = AnalyticsQuery(
        startDate: DateTime(2026, 10, 30),
        endDateExclusive: DateTime(2026, 10, 31),
      );

      final service = AnalyticsService(database: db, authService: authService);
      final snapshot = await service.load(query);

      final auditSection = snapshot.section(AnalyticsFamily.audit);
      AnalyticsMetric metric(String id) => auditSection.metrics.firstWhere((m) => m.id == id);

      expect(metric('backup_history').value, 2);
      expect(metric('backup_history').quality, AnalyticsQuality.complete);
      expect(metric('failed_backups').value, 1);
      expect(metric('backup_secondary_warnings').value, 1);
      expect(metric('last_verified_backup_age').quality, AnalyticsQuality.complete);

      // Verify backup_attempts rows projection
      final backupRows = auditSection.rows.where((r) => r.sourceType == 'backup_attempts').toList();
      expect(backupRows, hasLength(3));

      final manualRow = backupRows.firstWhere((r) => r.cells['action'] == 'MANUAL');
      expect(manualRow.cells['kind'], 'Database backup');
      expect(manualRow.cells['status'], 'VERIFIED');
      expect(manualRow.cells['staff_id'], 1);
      expect(manualRow.cells['primary_status'], 'SUCCESS');
      expect(manualRow.cells['secondary_status'], 'NOT_CONFIGURED');

      final warningRow = backupRows.firstWhere((r) => r.cells['action'] == 'Z_CLOSE');
      expect(warningRow.cells['status'], 'WARNING');
      expect(warningRow.cells['secondary_status'], 'WARNING');
      expect(warningRow.cells['reason'], contains('Secondary target disconnected'));

      final failedRow = backupRows.firstWhere((r) => r.cells['action'] == 'SCHEDULED');
      expect(failedRow.cells['status'], 'FAILED');
      expect(failedRow.cells['primary_status'], 'FAILED');
      expect(failedRow.cells['failure_category'], 'MEDIA_CORRUPTED');
      expect(failedRow.cells['reason'], contains('Referenced catalog photo is missing'));

      // CSV export parity
      final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.audit);
      expect(csv, contains('Historical successful backups'));
      expect(csv, contains('Failed backup attempts'));
      expect(csv, contains('Secondary backup warnings'));
      expect(csv, contains('Database backup'));
      expect(csv, contains('MANUAL'));
      expect(csv, contains('Z_CLOSE'));
      expect(csv, contains('SCHEDULED'));
      expect(csv, contains('MEDIA_CORRUPTED'));
    });
  });
}
