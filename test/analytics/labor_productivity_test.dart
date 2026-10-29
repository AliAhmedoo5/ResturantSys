import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/finance/operations_controller.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('Direct labor productivity matches ADR-0020 Example 2 with multi-department attendance', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);

    final staffRows = await db.query('staff');
    final manager = staffRows.firstWhere((r) => r['role'] != 'CASHIER');
    final cashier = staffRows.firstWhere((r) => r['role'] == 'CASHIER');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final operations = OperationsController(db);
    final shifts = ShiftAndCashController(database: db);

    // Business Day #45: Friday 2026-10-30
    final day = await shifts.openBusinessDay(openedByStaffId: manager['id'] as int);
    // Cashier Bilal opens register Shift #90 at 11:00 AM and closes at 11:00 PM (12 drawer hours)
    final shift = await shifts.openShift(staffId: cashier['id'] as int, openingFloat: 10000);

    final kitchenDept = (await db.query('departments', where: "name='Kitchen'")).first['id'] as int;
    final counterDept = (await db.query('departments', where: "name='Front Counter'")).first['id'] as int;
    final mgmtDept = (await db.query('departments', where: "name='Management'")).first['id'] as int;

    // Create staff matching ADR-0020 Example 2:
    // Farhan (Kitchen), Zahid (Kitchen), Bilal (Counter = existing cashier), Asif (Manager = existing manager)
    final farhan = await db.insert('staff', {
      'name': 'Chef Farhan',
      'department_id': kitchenDept,
      'pin_hash': 'farhan-pin',
      'role': 'CASHIER',
      'login_enabled': 0,
      'created_at': '2026-10-01',
    });
    final zahid = await db.insert('staff', {
      'name': 'Chef Zahid',
      'department_id': kitchenDept,
      'pin_hash': 'zahid-pin',
      'role': 'CASHIER',
      'login_enabled': 0,
      'created_at': '2026-10-01',
    });

    // 135 confirmed orders during the day
    for (var i = 1; i <= 135; i++) {
      await db.insert('orders', {
        'business_day_id': day.id,
        'shift_id': shift.id,
        'cashier_id': cashier['id'],
        'token_number': i,
        'dining_type': 'TAKEAWAY',
        'subtotal': 150,
        'grand_total': 150,
        'payment_status': 'SETTLED',
        'created_at': '2026-10-30 14:00:00',
      });
    }

    // Physical Attendance Logged (ADR-0020 Example 2):
    // - Farhan (Kitchen): 11:00 AM - 8:00 PM (1 hr break) = 8.0 worked hours (480 mins)
    // - Zahid (Kitchen): 2:00 PM - 11:00 PM (1 hr break) = 8.0 worked hours (480 mins)
    // - Bilal (Counter): 11:00 AM - 9:00 PM (1 hr break) = 9.0 worked hours (540 mins)
    // - Asif (Management): 10:00 AM - 7:00 PM (1 hr break) = 8.0 worked hours (480 mins)
    await operations.recordWorkedHours(
      managerId: manager['id'] as int,
      employeeId: farhan,
      departmentId: kitchenDept,
      workDate: '2026-10-30',
      clockIn: DateTime.utc(2026, 10, 30, 6, 0), // 11:00 AM PKT
      clockOut: DateTime.utc(2026, 10, 30, 15, 0), // 8:00 PM PKT
      breakMinutes: 60,
      reason: 'Cook shift',
      requestKey: 'hours-farhan',
    );
    await operations.recordWorkedHours(
      managerId: manager['id'] as int,
      employeeId: zahid,
      departmentId: kitchenDept,
      workDate: '2026-10-30',
      clockIn: DateTime.utc(2026, 10, 30, 9, 0), // 2:00 PM PKT
      clockOut: DateTime.utc(2026, 10, 30, 18, 0), // 11:00 PM PKT
      breakMinutes: 60,
      reason: 'Evening cook shift',
      requestKey: 'hours-zahid',
    );
    await operations.recordWorkedHours(
      managerId: manager['id'] as int,
      employeeId: cashier['id'] as int,
      departmentId: counterDept,
      workDate: '2026-10-30',
      clockIn: DateTime.utc(2026, 10, 30, 6, 0), // 11:00 AM PKT
      clockOut: DateTime.utc(2026, 10, 30, 16, 0), // 9:00 PM PKT
      breakMinutes: 60,
      reason: 'Front counter cashier shift',
      requestKey: 'hours-bilal',
    );
    await operations.recordWorkedHours(
      managerId: manager['id'] as int,
      employeeId: manager['id'] as int,
      departmentId: mgmtDept,
      workDate: '2026-10-30',
      clockIn: DateTime.utc(2026, 10, 30, 5, 0), // 10:00 AM PKT
      clockOut: DateTime.utc(2026, 10, 30, 14, 0), // 7:00 PM PKT
      breakMinutes: 60,
      reason: 'Manager supervisor shift',
      requestKey: 'hours-asif',
    );

    final service = AnalyticsService(database: db, authService: auth);
    final query = AnalyticsQuery(
      startDate: DateTime(2026, 10, 30),
      endDateExclusive: DateTime(2026, 10, 31),
    );
    final snapshot = await service.load(query);
    final staffSection = snapshot.section(AnalyticsFamily.staff);

    num? metricVal(String id) => staffSection.metrics.firstWhere((m) => m.id == id).value;
    AnalyticsMetric metricObj(String id) => staffSection.metrics.firstWhere((m) => m.id == id);

    // Direct Operational Hours = 8.0 (Farhan) + 8.0 (Zahid) + 9.0 (Bilal) = 25.0 hours
    // Management Hours = 8.0 hours
    // Total Hours = 33.0 hours
    // Direct Labor Productivity = 135 orders / 25.0 hours = 5.4 orders/labor hour
    expect(metricVal('worked_hours_direct'), 25.0);
    expect(metricVal('worked_hours_overhead'), 8.0);
    expect(metricVal('worked_hours_total'), 33.0);
    expect(metricVal('labor_productivity'), 5.4);
    expect(metricObj('labor_productivity').quality, AnalyticsQuality.complete);

    // Coverage metric exposed before productivity
    expect(metricVal('worked_hours_coverage'), isNotNull);
    final cov = metricObj('worked_hours_coverage');
    expect(cov.quality, AnalyticsQuality.complete);
    expect(cov.sampleCount, 4);

    // Reporting identity provenance snapshots are captured for worked_hours
    final identitySnapshots = await db.query('reporting_identity_snapshots', where: "source_table='worked_hours'");
    expect(identitySnapshots, isNotEmpty);
    expect(identitySnapshots.any((s) => s['identity_kind'] == 'recorded_by'), isTrue);
    expect(identitySnapshots.any((s) => s['identity_kind'] == 'employee'), isTrue);

    // Exports verify that coverage and labor productivity data are included in CSV, XLSX, and PDF
    final exportService = AnalyticsExportService();
    final csv = exportService.csv(snapshot, AnalyticsFamily.staff);
    expect(csv, contains('labor_productivity,Orders per labor hour,5.4'));
    expect(csv, contains('worked_hours_direct,Direct operational worked hours,25'));
    expect(csv, contains('worked_hours_overhead,Management & overhead hours,8'));
    expect(csv, contains('worked_hours_total,Total recorded worked hours,33'));

    final xlsxBytes = exportService.workbook(snapshot);
    final archive = ZipDecoder().decodeBytes(xlsxBytes);
    final staffSheetIdx = snapshot.sections.indexWhere((s) => s.family == AnalyticsFamily.staff) + 2;
    final xml = utf8.decode(archive.findFile('xl/worksheets/sheet$staffSheetIdx.xml')!.content as List<int>);
    expect(xml, contains('labor_productivity'));
    expect(xml, contains('5.4'));

    final pdfBytes = await exportService.pdf(snapshot, AnalyticsFamily.staff);
    expect(pdfBytes, isNotEmpty);
  });

  test('Cashier shift duration is never synthesized into worked hours when attendance is absent', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);

    final staffRows = await db.query('staff');
    final manager = staffRows.firstWhere((r) => r['role'] != 'CASHIER');
    final cashier = staffRows.firstWhere((r) => r['role'] == 'CASHIER');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final shifts = ShiftAndCashController(database: db);

    final day = await shifts.openBusinessDay(openedByStaffId: manager['id'] as int);
    // Register drawer open for 12 hours
    final shift = await shifts.openShift(staffId: cashier['id'] as int, openingFloat: 10000);
    await db.insert('orders', {
      'business_day_id': day.id,
      'shift_id': shift.id,
      'cashier_id': cashier['id'],
      'token_number': 1,
      'dining_type': 'TAKEAWAY',
      'subtotal': 100,
      'grand_total': 100,
      'payment_status': 'SETTLED',
      'created_at': '2026-10-30 14:00:00',
    });

    // Zero attendance logs in worked_hours!
    final service = AnalyticsService(database: db, authService: auth);
    final snapshot = await service.load(AnalyticsQuery(
      startDate: DateTime(2026, 10, 30),
      endDateExclusive: DateTime(2026, 10, 31),
    ));
    final staffSection = snapshot.section(AnalyticsFamily.staff);
    final productivity = staffSection.metrics.firstWhere((m) => m.id == 'labor_productivity');

    expect(productivity.value, isNull);
    expect(productivity.quality, AnalyticsQuality.missing);
    expect(productivity.explanation, contains('Cashier shift duration is not paid attendance or worked labor-hour evidence.'));

    final coverage = staffSection.metrics.firstWhere((m) => m.id == 'worked_hours_coverage');
    expect(coverage.value, 0.0);
    expect(coverage.quality, AnalyticsQuality.missing);

    final totalHours = staffSection.metrics.firstWhere((m) => m.id == 'worked_hours_total');
    expect(totalHours.value, isNull);
    expect(totalHours.quality, AnalyticsQuality.missing);
  });

  test('Distinguishes zero direct operational hours from absent evidence', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);

    final staffRows = await db.query('staff');
    final manager = staffRows.firstWhere((r) => r['role'] != 'CASHIER');
    final auth = AuthService(database: db)..session.login(Staff.fromMap(manager));
    final operations = OperationsController(db);
    final shifts = ShiftAndCashController(database: db);

    final day = await shifts.openBusinessDay(openedByStaffId: manager['id'] as int);
    final mgmtDept = (await db.query('departments', where: "name='Management'")).first['id'] as int;

    // Only Management hours are logged (0.0 direct operational hours)
    await operations.recordWorkedHours(
      managerId: manager['id'] as int,
      employeeId: manager['id'] as int,
      departmentId: mgmtDept,
      workDate: '2026-10-30',
      clockIn: DateTime.utc(2026, 10, 30, 5, 0),
      clockOut: DateTime.utc(2026, 10, 30, 13, 0),
      breakMinutes: 0,
      workedMinutes: 480, // 8.0 hrs
      requestKey: 'hours-mgmt-only',
    );

    final service = AnalyticsService(database: db, authService: auth);
    final snapshot = await service.load(AnalyticsQuery(
      startDate: DateTime(2026, 10, 30),
      endDateExclusive: DateTime(2026, 10, 31),
    ));
    final staffSection = snapshot.section(AnalyticsFamily.staff);

    final directHours = staffSection.metrics.firstWhere((m) => m.id == 'worked_hours_direct');
    expect(directHours.value, 0.0);
    expect(directHours.quality, AnalyticsQuality.complete);

    final overheadHours = staffSection.metrics.firstWhere((m) => m.id == 'worked_hours_overhead');
    expect(overheadHours.value, 8.0);

    final productivity = staffSection.metrics.firstWhere((m) => m.id == 'labor_productivity');
    expect(productivity.value, isNull);
    expect(productivity.quality, AnalyticsQuality.missing);
    expect(productivity.explanation, contains('0.0 direct operational hours logged in period'));
  });
}
