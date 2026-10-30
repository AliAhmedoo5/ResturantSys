import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/analytics/historical_corrections.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('Manager appends reconciled payout and contra entry without changing sealed evidence', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final auth = AuthService(database: db);
    final manager = (await auth.authenticateAndLogin('1234'))!;
    final cashier = (await db.query('staff', where: "role='CASHIER'")).first['id'] as int;
    final shifts = ShiftAndCashController(database: db);
    final day = await shifts.openBusinessDay(openedByStaffId: manager.id, openedAt: DateTime(2026,10,1));
    final shift = await shifts.openShift(staffId: cashier, openingFloat: 100);
    await shifts.closeShift(shiftId: shift.id, staffId: cashier, countedCash: 65);
    await shifts.closeBusinessDay(closedByStaffId: manager.id, closedAt: DateTime(2026,10,20));
    final service = HistoricalCorrections(database: db, auth: auth);
    final before = await service.load(day.id);
    final id = await service.append(managerPin: '1234', businessDayId: day.id,
      shiftId: shift.id, type: HistoricalCorrectionType.drawerPayout,
      deltaPaisa: -3500, evidenceKey: 'supplier-slip-41', reason: 'Late verified supplier payout slip',
      reconciled: true, eventTime: DateTime.utc(2026,10,10,12));
    final adjusted = await service.load(day.id);
    expect(adjusted.originalVariancePaisa, -3500);
    expect(adjusted.adjustedVariancePaisa, 0);
    expect(adjusted.originalSnapshotJson, before.originalSnapshotJson);
    expect(adjusted.originalHash, before.originalHash);
    expect(adjusted.originalRecordedAt, before.originalRecordedAt);
    expect(adjusted.toAnalyticsSnapshot().sourceSchemaVersion, await db.getVersion());
    expect(adjusted.toAnalyticsSnapshot().reportVersion, 'historical-corrections-v1');
    expect(before.entries, isEmpty);
    expect(adjusted.entries.single['id'], id);
    final originalShift = await shifts.getShift(shift.id);
    expect(originalShift.expectedCash, 100);
    expect(originalShift.discrepancy, -35);
    expect((await shifts.generateXReport(shift.id)).cashMovements, isEmpty);
    await expectLater(service.append(managerPin: '1234', businessDayId: day.id,
      shiftId: shift.id, type: HistoricalCorrectionType.drawerPayout,
      deltaPaisa: -3500, evidenceKey: 'supplier-slip-41', reason: 'Duplicate slip', reconciled: true), throwsA(isA<StateError>()));
    await expectLater(service.append(managerPin: '1234', businessDayId: day.id, shiftId: shift.id,
      type: HistoricalCorrectionType.drawerPayout, deltaPaisa: -3500, evidenceKey: 'SUPPLIER-SLIP-41',
      reason: 'Same physical supplier slip', reconciled: true, eventTime: DateTime.utc(2026,10,10,12)), throwsStateError);
    await expectLater(service.append(managerPin: '1234', businessDayId: day.id, shiftId: shift.id,
      type: HistoricalCorrectionType.drawerPayout, deltaPaisa: -3500, evidenceKey: 'different-reference',
      sourceTable: 'cash_movements', sourceId: 987654, reason: 'Unknown original evidence', reconciled: true,
      eventTime: DateTime.utc(2026,10,10,12)), throwsStateError);
    await service.reverse(id, managerPin: '1234', reason: 'Wrong supplier slip');
    expect((await service.load(day.id)).adjustedVariancePaisa, -3500);
    expect(adjusted.adjustedVariancePaisa, 0);
    final oldCutoff = await service.load(day.id, cutoff: DateTime.parse(adjusted.entries.single['recorded_at'] as String));
    expect(oldCutoff.entries, hasLength(1));
    expect(oldCutoff.toAnalyticsSnapshot().section(AnalyticsFamily.cash).notes.join(), contains('cutoff'));
    expect(oldCutoff.csv(), contains('Original sealed'));
  });
}


