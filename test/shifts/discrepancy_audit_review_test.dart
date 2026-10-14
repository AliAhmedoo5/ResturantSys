import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/shifts/shift.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Discrepancy Audit Review Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late AuthService authService;
    late ShiftAndCashController shiftController;
    late int businessDayId;
    late int supervisorId;
    late int cashierId;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_discrepancy_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}discrepancy_test.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      final db = await posDb.initialize();

      authService = AuthService(database: db);
      shiftController = ShiftAndCashController(database: db);

      final supervisor = (await authService.authenticateWithPin('1234'))!;
      supervisorId = supervisor.id;

      final cashier = (await authService.authenticateWithPin('1111'))!;
      cashierId = cashier.id;

      final bDay = await shiftController.openBusinessDay(openedByStaffId: supervisorId);
      businessDayId = bDay.id;
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('historical shifts flagged with discrepancies can be viewed and resolved with audit notes', () async {
      // 1. Open shift with 5,000 opening float
      final shift = await shiftController.openShift(
        staffId: cashierId,
        openingFloat: 5000.0,
      );

      // 2. Close shift with counted cash = 4,200 (expected = 5,000, variance = -800)
      // Discrepancy threshold is 100, so |-800| > 100 flags the shift
      final closedShift = await shiftController.closeShift(
        shiftId: shift.id,
        countedCash: 4200.0,
      );

      expect(closedShift.discrepancyStatus, equals(DiscrepancyStatus.flagged));
      expect(closedShift.discrepancy, equals(-800.0));

      // 3. Inspect historical discrepancy shifts
      final historyBefore = await shiftController.getHistoricalDiscrepancyShifts();
      expect(historyBefore.length, equals(1));
      final record = historyBefore.first;
      expect(record.staffId, equals(cashierId));
      expect(record.staffName, equals('Counter Cashier'));
      expect(record.discrepancy, equals(-800.0));
      expect(record.discrepancyStatus, equals(DiscrepancyStatus.flagged));
      expect(record.openedAt, isNotNull);
      expect(record.closedAt, isNotNull);
      expect(record.resolutionNotes, isNull);

      // Active flagged shifts queue has 1 shift
      expect((await shiftController.getFlaggedShifts()).length, equals(1));

      // 4. Resolve discrepancy with supervisor audit notes
      final resolved = await shiftController.resolveDiscrepancy(
        shiftId: shift.id,
        supervisorStaffId: supervisorId,
        resolutionNotes: 'Shortage audited: Cashier misplaced PKR 800 receipt; drawer verified and cleared.',
      );

      expect(resolved.discrepancyStatus, equals(DiscrepancyStatus.resolved));
      expect(resolved.resolvedByStaffId, equals(supervisorId));
      expect(resolved.resolutionNotes, contains('Shortage audited'));
      expect(resolved.resolvedAt, isNotNull);

      // Active flagged shifts queue is now clean
      expect((await shiftController.getFlaggedShifts()).length, equals(0));

      // 5. Historical log still includes the shift, now marked RESOLVED with audit notes
      final historyAfter = await shiftController.getHistoricalDiscrepancyShifts();
      expect(historyAfter.length, equals(1));
      final resolvedHistoryRecord = historyAfter.first;
      expect(resolvedHistoryRecord.discrepancyStatus, equals(DiscrepancyStatus.resolved));
      expect(resolvedHistoryRecord.resolutionNotes, contains('Shortage audited'));
    });
  });
}
