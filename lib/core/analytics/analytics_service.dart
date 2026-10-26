import 'package:sqflite_common/sqlite_api.dart';
import '../auth/auth_service.dart';
import '../auth/staff_role.dart';
import '../orders/paisa_engine.dart';
import 'analytics_models.dart';

typedef _Record = Map<String, Object?>;

/// One consistent, read-only projection of committed local business facts.
class AnalyticsService {
  AnalyticsService({required this.database, required this.authService});
  final Database database;
  final AuthService authService;

  Future<AnalyticsSnapshot> load(AnalyticsQuery query) async {
    final actor = authService.session.currentStaff;
    if (actor == null || !actor.isActive || !actor.canAccessSupervisorPortal) {
      throw StateError('An active Manager session is required.');
    }
    final snapshot = await database.transaction((txn) async {
      final persisted = await txn.query('staff', columns: ['id','role','is_active','login_enabled'], where:'id=?', whereArgs:[actor.id]);
      if (persisted.isEmpty || persisted.single['is_active'] != 1 || persisted.single['login_enabled'] != 1 || !StaffRole.fromCode(persisted.single['role'] as String).isManager) {
        throw StateError('Manager access is no longer enabled.');
      }
      return _load(txn, query, actor.id);
    });
    if (!identical(authService.session.currentStaff, actor)) throw StateError('Session changed while loading analytics.');
    return snapshot;
  }

  Future<AnalyticsSnapshot> _load(Transaction txn, AnalyticsQuery query, int actor) async {
    final days = (await txn.query('business_days')).where((d) {
      final date = _karachi(d['opened_at']);
      return date != null && !_date(date).isBefore(_date(query.startDate)) && _date(date).isBefore(_date(query.endDateExclusive));
    }).toList();
    final dayIds = days.map((d)=>d['id'] as int).toList();
    final orders = (await txn.query('orders')).where((o)=>dayIds.contains(o['business_day_id'])).toList();
    final ids = orders.map((o)=>o['id']).toSet();
    final payments = (await txn.query('order_payments')).where((p)=>ids.contains(p['order_id'])).toList();
    final valid = orders.where(_valid).toList();
    final value = _sum(valid,'grand_total');
    final collected = payments.fold<int>(0,(sum,p)=>sum+_money(p,'amount_tendered')-_money(p,'change_returned'));
    final due = _sum(valid.where((o)=>o['payment_status']=='COLLECTION_DUE'),'grand_total');
    final shifts = (await txn.query('shifts')).where((s)=>dayIds.contains(s['business_day_id'])).toList();
    final shiftIds = shifts.map((s)=>s['id']).toSet();
    final moves = (await txn.query('cash_movements')).where((m)=>shiftIds.contains(m['shift_id'])).toList();
    final receipts = payments.where((p)=>p['payment_method']=='CASH' && _money(p,'amount_tendered')>0).fold<int>(0,(sum,p)=>sum+_money(p,'amount_tendered')-_money(p,'change_returned'));
    final expected = _sum(shifts,'opening_float')+receipts+_sum(moves.where((m)=>m['type']=='PAY_IN'),'amount')-_sum(moves.where((m)=>m['type']!='PAY_IN'),'amount');
    final counted = shifts.where((s)=>s['counted_cash']!=null).length;
    return AnalyticsSnapshot(query:query,generatedAt:DateTime.now().toUtc(),businessDayIds:dayIds,generatedByStaffId:actor,sections:[
      AnalyticsSection(family:AnalyticsFamily.sales,title:'Sales',metrics:[_metric('recorded_value','Recorded order value',value),_metric('collected_tender','Collected tender',collected)]),
      AnalyticsSection(family:AnalyticsFamily.delivery,title:'Delivery',metrics:[_metric('collection_due','Collection Due',due)]),
      AnalyticsSection(family:AnalyticsFamily.cash,title:'Cash and shifts',metrics:[_metric('expected_drawer','Expected drawer',expected),AnalyticsMetric(id:'variance',label:'Counted variance',value:counted==shifts.length ? _sum(shifts,'counted_cash')-expected : null,unit:AnalyticsUnit.paisa,explanation:'Counted minus expected; unavailable until every shift has a blind count.',quality:counted==shifts.length ? AnalyticsQuality.complete : AnalyticsQuality.missing,sampleCount:counted,populationCount:shifts.length)]),
    ]);
  }

  static AnalyticsMetric _metric(String id,String label,num value,{AnalyticsUnit unit=AnalyticsUnit.paisa,String explanation='Selected Business Day order cohort; legacy rupees normalized per row to integer paisa.'}) => AnalyticsMetric(id:id,label:label,value:value,unit:unit,explanation:explanation);
  static bool _valid(_Record o) => !['VOIDED','CANCELLED','REFUNDED'].contains(o['payment_status']);
  static int _money(_Record row,String key) => (row['${key}_paisa'] as num?)?.toInt() ?? PaisaEngine.rupeesToPaisa((row[key] as num?) ?? 0);
  static int _sum(Iterable<_Record> rows,String key) => rows.fold(0,(sum,row)=>sum+_money(row,key));
  static DateTime _date(DateTime t) => DateTime.utc(t.year,t.month,t.day);
  static DateTime? _karachi(Object? raw) {
    if (raw is! String) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return null;
    return parsed.isUtc || RegExp(r'[+-]\d\d:\d\d$').hasMatch(raw) ? parsed.toUtc().add(const Duration(hours:5)) : DateTime.utc(parsed.year,parsed.month,parsed.day,parsed.hour,parsed.minute,parsed.second);
  }
}
