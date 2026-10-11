import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/shifts/cash_movement.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/shifts/x_report.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('XReport Generation & Formatting Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late ShiftAndCashController controller;
    late int cashierId;
    late int supervisorId;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_xreport_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}xreport_test.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      db = await posDb.initialize();
      controller = ShiftAndCashController(database: db);

      final supervisor = await db.query('staff', where: "role = 'SUPERVISOR'", limit: 1);
      supervisorId = supervisor.first['id'] as int;
      final cashier = await db.query('staff', where: "role = 'CASHIER'", limit: 1);
      cashierId = cashier.first['id'] as int;

      await controller.openBusinessDay(openedByStaffId: supervisorId);
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('generates interim X-Report while shift is still open', () async {
      final shift = await controller.openShift(staffId: cashierId, openingFloat: 5000.0);

      await controller.recordCashMovement(
        shiftId: shift.id,
        staffId: cashierId,
        type: CashMovementType.payIn,
        amount: 1000.0,
        category: 'Petty Cash',
        notes: 'Change replenishment',
      );

      final xReport = await controller.generateXReport(shift.id);

      expect(xReport.shiftId, equals(shift.id));
      expect(xReport.cashierName, isNotEmpty);
      expect(xReport.openingFloat, equals(5000.0));
      expect(xReport.totalPayIn, equals(1000.0));
      expect(xReport.totalPayOut, equals(0.0));
      expect(xReport.cashSales, equals(0.0));
      expect(xReport.expectedDrawerCash, equals(6000.0));
      expect(xReport.isInterim, isTrue);

      final printable = xReport.toPrintableString();
      expect(printable, contains('INTERIM X-REPORT'));
      expect(printable, contains('Opening Float:'));
      expect(printable, contains('5,000.00'));
      expect(printable, contains('Pay-Ins:'));
      expect(printable, contains('Expected Drawer:'));
    });

    test('generates closing X-Report with counted cash and discrepancy after blind close', () async {
      final shift = await controller.openShift(staffId: cashierId, openingFloat: 4000.0);

      await controller.recordCashMovement(
        shiftId: shift.id,
        staffId: cashierId,
        type: CashMovementType.payOut,
        amount: 250.0,
        category: 'Supplies',
        notes: 'Ice bag',
      );

      // Expected = 4000 - 250 = 3750.0. Cashier counts 3700.0 (-50 discrepancy)
      await controller.closeShift(shiftId: shift.id, countedCash: 3700.0);

      final xReport = await controller.generateXReport(shift.id);

      expect(xReport.isInterim, isFalse);
      expect(xReport.openingFloat, equals(4000.0));
      expect(xReport.totalPayOut, equals(250.0));
      expect(xReport.expectedDrawerCash, equals(3750.0));
      expect(xReport.countedCash, equals(3700.0));
      expect(xReport.discrepancy, equals(-50.0));

      final printable = xReport.toPrintableString();
      expect(printable, contains('SHIFT CLOSING X-REPORT'));
      expect(printable, contains('Counted Cash:'));
      expect(printable, contains('3,700.00'));
      expect(printable, contains('Variance:'));
      expect(printable, contains('-50.00'));
    });
  });
}
