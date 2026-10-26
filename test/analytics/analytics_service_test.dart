import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:resturant_sys/core/analytics/analytics_models.dart';
import 'package:resturant_sys/core/analytics/analytics_service.dart';
import 'package:resturant_sys/core/auth/auth_service.dart';
import 'package:resturant_sys/core/auth/staff.dart';
import 'package:resturant_sys/core/database/pos_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test('Manager sees COD value separately from cash after an explicit refund', () async {
    final store = PosDatabase(factory: databaseFactoryFfi, customPath: inMemoryDatabasePath);
    final db = await store.initialize();
    addTearDown(store.close);
    final staff = await db.query('staff');
    final manager = staff.firstWhere((r) => r['role'] != 'CASHIER');
    final cashier = staff.firstWhere((r) => r['role'] == 'CASHIER');
    final auth = AuthService(database: db);
    auth.session.login(Staff.fromMap(manager));
    final day = await db.insert('business_days', {'opened_at':'2026-10-25 18:00:00','status':'OPEN','opened_by_staff_id':manager['id']});
    final shift = await db.insert('shifts', {'business_day_id':day,'staff_id':cashier['id'],'opened_at':'2026-10-25 18:00:00','opening_float':100,'status':'OPEN'});
    Future<int> order(int token, double value, String status) => db.insert('orders', {'business_day_id':day,'shift_id':shift,'cashier_id':cashier['id'],'token_number':token,'dining_type':'TAKEAWAY','subtotal':value,'grand_total':value,'payment_status':status,'created_at':'2026-10-26 01:00:00'});
    final paid = await order(1, 400, 'SETTLED');
    await order(2, 250, 'COLLECTION_DUE');
    await db.insert('order_payments', {'order_id':paid,'payment_method':'CASH','amount_tendered':500,'change_returned':0,'amount_tendered_paisa':50000,'change_returned_paisa':0});
    await db.insert('order_payments', {'order_id':paid,'payment_method':'CASH','amount_tendered':-100,'change_returned':0,'amount_tendered_paisa':-10000,'change_returned_paisa':0});
    await db.insert('cash_movements', {'shift_id':shift,'staff_id':cashier['id'],'type':'PAY_OUT','amount':100,'category':'REFUND','notes':'Synthetic refund','created_at':'2026-10-26 01:00:00'});
    final snapshot = await AnalyticsService(database:db, authService:auth).load(AnalyticsQuery(startDate:DateTime(2026,10,25),endDateExclusive:DateTime(2026,10,26)));
    num? metric(AnalyticsFamily family, String id) => snapshot.section(family).metrics.firstWhere((m)=>m.id==id).value;
    expect(metric(AnalyticsFamily.sales,'recorded_value'),65000);
    expect(metric(AnalyticsFamily.sales,'collected_tender'),40000);
    expect(metric(AnalyticsFamily.delivery,'collection_due'),25000);
    expect(metric(AnalyticsFamily.cash,'expected_drawer'),50000);
    expect(metric(AnalyticsFamily.cash,'variance'),isNull);
    expect(snapshot.businessDayIds,[day]);
  });
}
