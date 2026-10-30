import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/database/pos_database.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/shifts/shift_and_cash_controller.dart';
import 'package:resturant_sys/core/analytics/historical_corrections.dart';
import 'package:resturant_sys/core/analytics/analytics_export_service.dart';

void main(){
  setUpAll(sqfliteFfiInit);
  test('late COD bridge preserves original receipts and rejects foreign-period physical effects',()async{
    final store=PosDatabase(factory:databaseFactoryFfi,customPath:inMemoryDatabasePath);
    final db=await store.initialize();addTearDown(store.close);
    final auth=AuthService(database:db);final manager=(await auth.authenticateAndLogin('1234'))!;
    final cashier=(await db.query('staff',where:"role='CASHIER'")).first;
    final shifts=ShiftAndCashController(database:db);
    final day=await shifts.openBusinessDay(openedByStaffId:manager.id,openedAt:DateTime(2026,10,20,10));
    final shift=await shifts.openShift(staffId:cashier['id'] as int,openingFloat:0);
    // Imported original historical evidence; commands below exercise the approved correction seam.
    final order=await db.insert('orders',{'business_day_id':day.id,'shift_id':shift.id,'cashier_id':cashier['id'],
      'token_number':1,'dining_type':'DELIVERY','subtotal':2500,'grand_total':2500,
      'payment_status':'COLLECTION_DUE','created_at':'2026-10-20T12:00:00Z'});
    await shifts.closeShift(shiftId:shift.id,staffId:cashier['id'] as int,countedCash:0);
    await shifts.closeBusinessDay(closedByStaffId:manager.id,closedAt:DateTime(2026,10,20,22));
    final service=HistoricalCorrections(database:db,auth:auth,clock:()=>DateTime.utc(2026,10,23,12));
    await expectLater(service.append(managerPin:'1234',businessDayId:day.id,shiftId:shift.id,orderId:order,
      type:HistoricalCorrectionType.collection,deltaPaisa:250000,evidenceKey:'future-pouch',reason:'Verified courier pouch',
      reconciled:true,eventTime:DateTime.utc(2026,10,21,12)),throwsStateError);
    await service.append(managerPin:'1234',businessDayId:day.id,shiftId:shift.id,orderId:order,
      type:HistoricalCorrectionType.collection,deltaPaisa:250000,evidenceKey:'pouch-1042',reason:'Verified courier pouch',
      reconciled:true,eventTime:DateTime.utc(2026,10,20,12));
    final snapshot=await service.load(day.id);
    expect(snapshot.originalCashReceiptsPaisa,0);
    expect(snapshot.adjustedCashReceiptsPaisa,250000);
    expect(snapshot.originalCollectionDuePaisa,250000);
    expect(snapshot.adjustedCollectionDuePaisa,0);
    await expectLater(service.append(managerPin:'1234',businessDayId:day.id,orderId:order,
      type:HistoricalCorrectionType.collection,deltaPaisa:1,evidenceKey:'overcollection',reason:'Verified courier pouch',
      reconciled:true,eventTime:DateTime.utc(2026,10,20,12)),throwsStateError);
    final exporter=AnalyticsExportService();
    expect(exporter.workbook(snapshot.toAnalyticsSnapshot()),isNotEmpty);
    expect(await exporter.pdf(snapshot.toAnalyticsSnapshot(),AnalyticsFamily.cash),isNotEmpty);
    expect(snapshot.csv(),contains('Original sealed evidence'));
    auth.session.login(Staff.fromMap(cashier));
    await expectLater(service.load(day.id),throwsStateError);
    await expectLater(service.closedDays(),throwsStateError);
  });
}
