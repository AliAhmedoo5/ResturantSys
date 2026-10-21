import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/shifts/business_day.dart';
import 'package:resturant_sys/core/shifts/shift.dart';
import 'package:resturant_sys/core/shifts/cash_movement.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ShiftAndCashController & Domain Lifecycle Tests', () {
    late Directory tempDir;
    late String testDbPath;
    late PosDatabase posDb;
    late Database db;
    late ShiftAndCashController controller;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('pos_shift_test_');
      testDbPath = '${tempDir.path}${Platform.pathSeparator}shift_test.db';
      posDb = PosDatabase(
        factory: databaseFactoryFfi,
        customPath: testDbPath,
      );
      db = await posDb.initialize();
      controller = ShiftAndCashController(database: db);
    });

    tearDown(() async {
      await posDb.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    group('Business Day Lifecycle', () {
      test('supervisor can open a new Business Day', () async {
        final supervisor = await db.query('staff', where: "role = 'SUPERVISOR'", limit: 1);
        final supervisorId = supervisor.first['id'] as int;

        final day = await controller.openBusinessDay(openedByStaffId: supervisorId);

        expect(day.id, isNotNull);
        expect(day.status, equals(BusinessDayStatus.open));
        expect(day.openedByStaffId, equals(supervisorId));
        expect(day.closedAt, isNull);

        final activeDay = await controller.getActiveBusinessDay();
        expect(activeDay?.id, equals(day.id));
      });

      test('rejects opening a Business Day when another is already open', () async {
        final supervisor = await db.query('staff', where: "role = 'SUPERVISOR'", limit: 1);
        final supervisorId = supervisor.first['id'] as int;

        await controller.openBusinessDay(openedByStaffId: supervisorId);

        expect(
          () => controller.openBusinessDay(openedByStaffId: supervisorId),
          throwsA(isA<StateError>()),
        );
      });

      test('supports Business Day operations crossing midnight', () async {
        final supervisor = await db.query('staff', where: "role = 'SUPERVISOR'", limit: 1);
        final supervisorId = supervisor.first['id'] as int;

        final yesterday = DateTime.now().subtract(const Duration(hours: 14));
        final day = await controller.openBusinessDay(
          openedByStaffId: supervisorId,
          openedAt: yesterday,
        );

        expect(day.status, equals(BusinessDayStatus.open));
        expect(day.openedAt.isBefore(DateTime.now()), isTrue);

        final activeDay = await controller.getActiveBusinessDay();
        expect(activeDay?.id, equals(day.id));
        expect(activeDay?.status, equals(BusinessDayStatus.open));
      });

      test('supervisor can close an active Business Day', () async {
        final supervisor = await db.query('staff', where: "role = 'SUPERVISOR'", limit: 1);
        final supervisorId = supervisor.first['id'] as int;

        final day = await controller.openBusinessDay(openedByStaffId: supervisorId);
        final closedDay = await controller.closeBusinessDay(closedByStaffId: supervisorId);

        expect(closedDay.id, equals(day.id));
        expect(closedDay.status, equals(BusinessDayStatus.closed));
        expect(closedDay.closedByStaffId, equals(supervisorId));
        expect(closedDay.closedAt, isNotNull);

        expect(await controller.getActiveBusinessDay(), isNull);
      });

      test('rejects closing Business Day if an active shift is still open', () async {
        final supervisor = await db.query('staff', where: "role = 'SUPERVISOR'", limit: 1);
        final supervisorId = supervisor.first['id'] as int;
        final cashier = await db.query('staff', where: "role = 'CASHIER'", limit: 1);
        final cashierId = cashier.first['id'] as int;

        await controller.openBusinessDay(openedByStaffId: supervisorId);
        await controller.openShift(staffId: cashierId, openingFloat: 2000.0);

        expect(
          () => controller.closeBusinessDay(closedByStaffId: supervisorId),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('Cashier Shift Lifecycle & Cash Movements', () {
      late int cashierId;
      late int supervisorId;

      setUp(() async {
        final supervisor = await db.query('staff', where: "role = 'SUPERVISOR'", limit: 1);
        supervisorId = supervisor.first['id'] as int;
        final cashier = await db.query('staff', where: "role = 'CASHIER'", limit: 1);
        cashierId = cashier.first['id'] as int;

        await controller.openBusinessDay(openedByStaffId: supervisorId);
      });

      test('cashier can open a shift with an initial opening cash float', () async {
        final shift = await controller.openShift(
          staffId: cashierId,
          openingFloat: 3500.00,
        );

        expect(shift.id, isNotNull);
        expect(shift.staffId, equals(cashierId));
        expect(shift.openingFloat, equals(3500.00));
        expect(shift.status, equals(ShiftStatus.open));
        expect(shift.discrepancyStatus, equals(DiscrepancyStatus.clean));

        final activeShift = await controller.getActiveShift();
        expect(activeShift?.id, equals(shift.id));
      });

      test('rejects opening shift without an active Business Day', () async {
        await controller.closeBusinessDay(closedByStaffId: supervisorId);

        expect(
          () => controller.openShift(staffId: cashierId, openingFloat: 1000.0),
          throwsA(isA<StateError>()),
        );
      });

      test('rejects opening shift when another shift is already active', () async {
        await controller.openShift(staffId: cashierId, openingFloat: 1000.0);

        expect(
          () => controller.openShift(staffId: cashierId, openingFloat: 2000.0),
          throwsA(isA<StateError>()),
        );
      });

      test('rejects negative opening float', () async {
        expect(
          () => controller.openShift(staffId: cashierId, openingFloat: -50.0),
          throwsA(isA<ArgumentError>()),
        );
      });

      test('records mid-shift Pay-In and Pay-Out with mandatory notes and amounts', () async {
        final shift = await controller.openShift(staffId: cashierId, openingFloat: 5000.0);

        final payIn = await controller.recordCashMovement(
          shiftId: shift.id,
          staffId: cashierId,
          type: CashMovementType.payIn,
          amount: 1500.00,
          category: 'Change Float Addition',
          notes: 'Added extra 100 and 50 rupee notes for change',
        );

        final payOut = await controller.recordCashMovement(
          shiftId: shift.id,
          staffId: cashierId,
          type: CashMovementType.payOut,
          amount: 450.00,
          category: 'Milk & Ice Purchase',
          notes: 'Purchased 2 packs of milk and 1 ice block from grocery',
        );

        expect(payIn.id, isNotNull);
        expect(payIn.type, equals(CashMovementType.payIn));
        expect(payIn.amount, equals(1500.00));

        expect(payOut.id, isNotNull);
        expect(payOut.type, equals(CashMovementType.payOut));
        expect(payOut.amount, equals(450.00));

        final movements = await controller.getCashMovements(shift.id);
        expect(movements.length, equals(2));
      });

      test('rejects cash movement with zero or negative amount, or blank notes', () async {
        final shift = await controller.openShift(staffId: cashierId, openingFloat: 5000.0);

        expect(
          () => controller.recordCashMovement(
            shiftId: shift.id,
            staffId: cashierId,
            type: CashMovementType.payIn,
            amount: 0.0,
            category: 'Petty Cash',
            notes: 'Valid note',
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(
          () => controller.recordCashMovement(
            shiftId: shift.id,
            staffId: cashierId,
            type: CashMovementType.payOut,
            amount: 100.0,
            category: 'Petty Cash',
            notes: '   ',
          ),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('Shift Math, Blind Handover, and Non-Blocking Discrepancy Policy', () {
      late int cashierId;
      late int supervisorId;

      setUp(() async {
        final supervisor = await db.query('staff', where: "role = 'SUPERVISOR'", limit: 1);
        supervisorId = supervisor.first['id'] as int;
        final cashier = await db.query('staff', where: "role = 'CASHIER'", limit: 1);
        cashierId = cashier.first['id'] as int;

        await controller.openBusinessDay(openedByStaffId: supervisorId);
      });

      test('computes clean discrepancy when blind counted cash equals expected drawer cash', () async {
        final shift = await controller.openShift(staffId: cashierId, openingFloat: 5000.0);

        await controller.recordCashMovement(
          shiftId: shift.id,
          staffId: cashierId,
          type: CashMovementType.payIn,
          amount: 1500.0,
          category: 'Petty Cash',
          notes: 'Added change float',
        );

        await controller.recordCashMovement(
          shiftId: shift.id,
          staffId: cashierId,
          type: CashMovementType.payOut,
          amount: 400.0,
          category: 'Supplies',
          notes: 'Milk purchase',
        );

        // Expected Cash = 5000 (float) + 1500 (in) - 400 (out) = 6100.0
        final closedShift = await controller.closeShift(
          shiftId: shift.id, staffId: shift.staffId,
          countedCash: 6100.0,
        );

        expect(closedShift.status, equals(ShiftStatus.closed));
        expect(closedShift.expectedCash, equals(6100.0));
        expect(closedShift.countedCash, equals(6100.0));
        expect(closedShift.discrepancy, equals(0.0));
        expect(closedShift.discrepancyStatus, equals(DiscrepancyStatus.clean));
      });

      test('applies non-blocking discrepancy policy when shortage exceeds threshold', () async {
        // Default threshold is 100.0
        final shift = await controller.openShift(staffId: cashierId, openingFloat: 5000.0);

        await controller.recordCashMovement(
          shiftId: shift.id,
          staffId: cashierId,
          type: CashMovementType.payIn,
          amount: 1000.0,
          category: 'Petty Cash',
          notes: 'Float add',
        );

        // Expected cash = 6000.0. Cashier counts 5800.0 (shortage of 200.0, > 100.0 threshold)
        final closedShift = await controller.closeShift(
          shiftId: shift.id, staffId: shift.staffId,
          countedCash: 5800.0,
        );

        expect(closedShift.status, equals(ShiftStatus.closed));
        expect(closedShift.expectedCash, equals(6000.0));
        expect(closedShift.countedCash, equals(5800.0));
        expect(closedShift.discrepancy, equals(-200.0));
        expect(closedShift.discrepancyStatus, equals(DiscrepancyStatus.flagged));

        // Non-blocking verification: active shift is null, and next cashier can open shift immediately!
        expect(await controller.getActiveShift(), isNull);

        final nextCashier = await controller.openShift(
          staffId: cashierId,
          openingFloat: 3000.0,
        );
        expect(nextCashier.status, equals(ShiftStatus.open));
        expect(nextCashier.id, isNot(equals(shift.id)));
      });

      test('applies non-blocking discrepancy policy when overage exceeds threshold', () async {
        final shift = await controller.openShift(staffId: cashierId, openingFloat: 4000.0);

        // Expected = 4000.0. Cashier counts 4250.0 (+250 overage, > 100 threshold)
        final closedShift = await controller.closeShift(
          shiftId: shift.id, staffId: shift.staffId,
          countedCash: 4250.0,
        );

        expect(closedShift.discrepancy, equals(250.0));
        expect(closedShift.discrepancyStatus, equals(DiscrepancyStatus.flagged));
      });

      test('supervisor can review and resolve flagged discrepancy shifts asynchronously', () async {
        final shift = await controller.openShift(staffId: cashierId, openingFloat: 5000.0);
        await controller.closeShift(shiftId: shift.id, staffId: shift.staffId, countedCash: 4800.0); // 200 shortage

        final flaggedList = await controller.getFlaggedShifts();
        expect(flaggedList.any((s) => s.id == shift.id), isTrue);

        final resolvedShift = await controller.resolveDiscrepancy(
          shiftId: shift.id,
          supervisorStaffId: supervisorId,
          resolutionNotes: 'Shortage audited: Cashier accepted counterfeit 200 note, verbal warning logged.',
        );

        expect(resolvedShift.discrepancyStatus, equals(DiscrepancyStatus.resolved));

        final flaggedAfter = await controller.getFlaggedShifts();
        expect(flaggedAfter.any((s) => s.id == shift.id), isFalse);
      });

      test('cashier can record autonomous PAY_IN and PAY_OUT with approved_by = NULL', () async {
        final shift = await controller.openShift(staffId: cashierId, openingFloat: 5000.0);

        final payIn = await controller.recordCashMovement(
          shiftId: shift.id,
          staffId: cashierId,
          type: CashMovementType.payIn,
          amount: 1200.0,
          category: 'Counter Change Replenishment',
          notes: 'Replenished change coins',
        );

        final payOut = await controller.recordCashMovement(
          shiftId: shift.id,
          staffId: cashierId,
          type: CashMovementType.payOut,
          amount: 300.0,
          category: 'Milk',
          notes: 'Tea milk expense',
        );

        expect(payIn.approvedBy, isNull);
        expect(payOut.approvedBy, isNull);

        // Verify approved_by is NULL in raw database rows
        final rows = await db.query('cash_movements', where: 'shift_id = ?', whereArgs: [shift.id]);
        expect(rows.length, equals(2));
        for (final r in rows) {
          expect(r['approved_by'], isNull);
        }
      });

      test('manager credentials are strictly blocked from cashier movements and shift operations (ADR-0009)', () async {
        final shift = await controller.openShift(staffId: cashierId, openingFloat: 5000.0);

        // Manager cannot record drawer cash movements on cashier shifts
        expect(
          () => controller.recordCashMovement(
            shiftId: shift.id,
            staffId: supervisorId,
            type: CashMovementType.payIn,
            amount: 500.0,
            category: 'Petty Cash',
            notes: 'Manager drawer movement attempt',
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Manager credentials cannot operate cashier shifts'),
          )),
        );

        // Manager cannot open cashier shifts
        expect(
          () => controller.openShift(staffId: supervisorId, openingFloat: 3000.0),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Manager credentials cannot open or operate cashier shifts'),
          )),
        );

        // Manager cannot close cashier shifts
        expect(
          () => controller.closeShift(shiftId: shift.id, staffId: supervisorId, countedCash: 5000.0),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Only an active Cashier can close a cashier shift'),
          )),
        );
      });

      test('manager can configure discrepancy threshold; cashier is blocked', () async {
        // Manager successfully updates threshold
        await controller.setDiscrepancyThreshold(250.0, managerStaffId: supervisorId);
        expect(await controller.getDiscrepancyThreshold(), equals(250.0));

        // Cashier is strictly blocked from updating threshold
        expect(
          () => controller.setDiscrepancyThreshold(50.0, managerStaffId: cashierId),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Only Managers can configure the discrepancy threshold'),
          )),
        );

        // Negative threshold rejected
        expect(
          () => controller.setDiscrepancyThreshold(-10.0, managerStaffId: supervisorId),
          throwsA(isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('cannot be negative'),
          )),
        );
      });

      test('discrepancy flagging correctly evaluates variance against manager-configured threshold', () async {
        // Set threshold to 150.0
        await controller.setDiscrepancyThreshold(150.0, managerStaffId: supervisorId);

        // 1. Variance <= threshold (+100 overage) -> CLEAN
        final shift1 = await controller.openShift(staffId: cashierId, openingFloat: 3000.0);
        final closed1 = await controller.closeShift(shiftId: shift1.id, staffId: cashierId, countedCash: 3100.0);
        expect(closed1.discrepancy, equals(100.0));
        expect(closed1.discrepancyStatus, equals(DiscrepancyStatus.clean));

        // 2. Variance <= threshold (-150 shortage, exactly on boundary) -> CLEAN
        final shift2 = await controller.openShift(staffId: cashierId, openingFloat: 3000.0);
        final closed2 = await controller.closeShift(shiftId: shift2.id, staffId: cashierId, countedCash: 2850.0);
        expect(closed2.discrepancy, equals(-150.0));
        expect(closed2.discrepancyStatus, equals(DiscrepancyStatus.clean));

        // 3. Shortage > threshold (-160 shortage) -> FLAGGED
        final shift3 = await controller.openShift(staffId: cashierId, openingFloat: 3000.0);
        final closed3 = await controller.closeShift(shiftId: shift3.id, staffId: cashierId, countedCash: 2840.0);
        expect(closed3.discrepancy, equals(-160.0));
        expect(closed3.discrepancyStatus, equals(DiscrepancyStatus.flagged));

        // 4. Overage > threshold (+175 overage) -> FLAGGED
        final shift4 = await controller.openShift(staffId: cashierId, openingFloat: 3000.0);
        final closed4 = await controller.closeShift(shiftId: shift4.id, staffId: cashierId, countedCash: 3175.0);
        expect(closed4.discrepancy, equals(175.0));
        expect(closed4.discrepancyStatus, equals(DiscrepancyStatus.flagged));
      });

      test('only manager can resolve discrepancy; cashier is blocked and shift figures remain immutable', () async {
        final shift = await controller.openShift(staffId: cashierId, openingFloat: 5000.0);
        final closed = await controller.closeShift(shiftId: shift.id, staffId: cashierId, countedCash: 4500.0);
        expect(closed.discrepancyStatus, equals(DiscrepancyStatus.flagged));
        expect(closed.discrepancy, equals(-500.0));
        expect(closed.expectedCash, equals(5000.0));
        expect(closed.countedCash, equals(4500.0));

        // Cashier cannot resolve discrepancy
        expect(
          () => controller.resolveDiscrepancy(
            shiftId: closed.id,
            supervisorStaffId: cashierId,
            resolutionNotes: 'Cashier attempt to self-resolve',
          ),
          throwsA(isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Only Managers can resolve shift discrepancies'),
          )),
        );

        // Manager resolves discrepancy
        final resolved = await controller.resolveDiscrepancy(
          shiftId: closed.id,
          supervisorStaffId: supervisorId,
          resolutionNotes: 'Shortage reviewed and approved by manager after examining camera footage',
        );

        expect(resolved.discrepancyStatus, equals(DiscrepancyStatus.resolved));
        expect(resolved.resolvedByStaffId, equals(supervisorId));
        expect(resolved.resolutionNotes, contains('camera footage'));
        expect(resolved.resolvedAt, isNotNull);

        // Core financial figures remain completely immutable
        expect(resolved.discrepancy, equals(-500.0));
        expect(resolved.expectedCash, equals(5000.0));
        expect(resolved.countedCash, equals(4500.0));
        expect(resolved.openingFloat, equals(5000.0));
      });

      test('generating X-Report and closing shifts NEVER closes the Business Day', () async {
        final activeDayBefore = await controller.getActiveBusinessDay();
        expect(activeDayBefore, isNotNull);
        expect(activeDayBefore!.isOpen, isTrue);

        final shift = await controller.openShift(staffId: cashierId, openingFloat: 4000.0);

        // Generate Interim X-Report
        final interimXReport = await controller.generateXReport(shift.id);
        expect(interimXReport.isInterim, isTrue);
        expect(interimXReport.openingFloat, equals(4000.0));

        // Business Day still open
        final dayAfterInterim = await controller.getActiveBusinessDay();
        expect(dayAfterInterim?.id, equals(activeDayBefore.id));
        expect(dayAfterInterim?.isOpen, isTrue);

        // Close shift (even with a discrepancy flag)
        final closedShift = await controller.closeShift(shiftId: shift.id, staffId: cashierId, countedCash: 3500.0);
        expect(closedShift.isClosed, isTrue);
        expect(closedShift.isFlagged, isTrue);

        // Generate Closing X-Report
        final closingXReport = await controller.generateXReport(shift.id);
        expect(closingXReport.isInterim, isFalse);
        expect(closingXReport.discrepancy, equals(-500.0));

        // Business Day is STILL open!
        final dayAfterClose = await controller.getActiveBusinessDay();
        expect(dayAfterClose?.id, equals(activeDayBefore.id));
        expect(dayAfterClose?.isOpen, isTrue);

        // Printable string contains thermal layout
        final printable = closingXReport.toPrintableString();
        expect(printable, contains('RESTURANT POS'));
        expect(printable, contains('SHIFT CLOSING X-REPORT'));
        expect(printable, contains('Discrepancy:'));
      });
    });
  });
}
