import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Ticket #82: Expose stored configuration and operations audit safely', () {
    late Directory tempDir;
    late String dbPath;
    late PosDatabase posDb;
    late Database db;
    late AuthService authService;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('audit_test_');
      dbPath = '${tempDir.path}${Platform.pathSeparator}pos_test.db';
      posDb = PosDatabase(factory: databaseFactoryFfi, customPath: dbPath);
      db = await posDb.initialize();

      authService = AuthService(database: db);
      final manager = (await db.query('staff', where: 'id = 1')).single;
      authService.session.login(Staff.fromMap(manager));

      // Open a business day so interval queries match
      await db.insert('business_days', {
        'opened_at': '2026-10-25 08:00:00',
        'closed_at': '2026-10-25 23:00:00',
        'status': 'CLOSED',
        'opened_by_staff_id': 1,
      });

      // Insert configuration audit with sensitive data
      await db.insert('configuration_audit', {
        'actor_id': 1,
        'kind': 'SHORTCUTS',
        'before_json': jsonEncode({'KEY_F1': 'PAY'}),
        'after_json': jsonEncode({'KEY_F1': 'VOID', 'pin_hash': 'LEAKED_SECRET_HASH_999'}),
        'created_at': '2026-10-25 10:00:00',
      });

      // Insert operations audit with sensitive data
      await db.insert('operations_audit', {
        'manager_id': 1,
        'entity': 'STAFF',
        'entity_id': 2,
        'action': 'UPDATE_SALARY',
        'detail': jsonEncode({
          'rate_paisa': 4500000,
          'category': 'Kitchen',
          'reason': 'Annual revision',
          'pin': '9876_SECRET_PIN',
        }),
        'created_at': '2026-10-25 11:00:00',
      });
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Audit projects configuration and operations evidence with safe field allowlisting and secret redaction', () async {
      final query = AnalyticsQuery(
        startDate: DateTime(2026, 10, 25),
        endDateExclusive: DateTime(2026, 10, 26),
      );

      final service = AnalyticsService(database: db, authService: authService);
      final snapshot = await service.load(query);

      final auditSection = snapshot.section(AnalyticsFamily.audit);
      AnalyticsMetric metric(String id) => auditSection.metrics.firstWhere((m) => m.id == id);

      expect(metric('configuration_audit_events').value, 1);
      expect(metric('operations_audit_events').value, 1);
      expect(metric('authentication_event_history').quality, AnalyticsQuality.missing);

      // Verify rows
      final configRows = auditSection.rows.where((r) => r.sourceType == 'configuration_audit').toList();
      expect(configRows.length, 1);
      expect(configRows.single.cells['action'], 'SHORTCUTS');
      expect(configRows.single.cells['reason'], contains('KEY_F1'));
      // Secret pin_hash MUST NOT be leaked
      expect(configRows.single.cells['reason'], isNot(contains('LEAKED_SECRET_HASH_999')));

      final opsRows = auditSection.rows.where((r) => r.sourceType == 'operations_audit').toList();
      expect(opsRows.length, 1);
      expect(opsRows.single.cells['action'], 'STAFF:UPDATE_SALARY');
      expect(opsRows.single.cells['reason'], contains('rate_paisa'));
      expect(opsRows.single.cells['reason'], contains('Annual revision'));
      // Secret pin MUST NOT be leaked
      expect(opsRows.single.cells['reason'], isNot(contains('9876_SECRET_PIN')));

      // Entire audit row collection must not contain secrets
      final allAuditCells = auditSection.rows.map((r) => r.cells.toString()).join();
      expect(allAuditCells, isNot(contains('LEAKED_SECRET_HASH_999')));
      expect(allAuditCells, isNot(contains('9876_SECRET_PIN')));

      // CSV export parity
      final csv = AnalyticsExportService().csv(snapshot, AnalyticsFamily.audit);
      expect(csv, contains('Configuration audit events'));
      expect(csv, contains('Operations audit events'));
      expect(csv, contains('SHORTCUTS'));
      expect(csv, contains('STAFF:UPDATE_SALARY'));
      expect(csv, isNot(contains('LEAKED_SECRET_HASH_999')));
      expect(csv, isNot(contains('9876_SECRET_PIN')));
    });
  });
}
