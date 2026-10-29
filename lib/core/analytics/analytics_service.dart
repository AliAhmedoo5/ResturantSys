import 'dart:convert';
import 'dart:math' as math;
import 'package:sqflite_common/sqlite_api.dart';
import '../auth/auth_service.dart';
import '../auth/staff_role.dart';
import '../orders/paisa_engine.dart';
import '../inventory/stock_count_valuation.dart';
import 'analytics_models.dart';

part 'analytics_reports.dart';
part 'customer_report_details.dart';
typedef _Record = Map<String, Object?>;

/// Consistent, authorized reads. Computation runs after releasing SQLite.
class AnalyticsService {
  AnalyticsService({required this.database, required this.authService});
  final Database database;
  final AuthService authService;

  /// Contact information is loaded separately from masked analytics/exports.
  Future<List<CustomerReportProfile>> loadCustomerDetails(AnalyticsQuery query) =>
      _CustomerInformationReader(this).load(query);

  Future<AnalyticsSnapshot> load(AnalyticsQuery query) async {
    final actor = authService.session.currentStaff;
    if (actor == null || !actor.isActive || !actor.canAccessSupervisorPortal) {
      throw StateError('An active Manager session is required.');
    }
    final evidence = await database.transaction((txn) async {
      final staff = await txn.query('staff', columns: ['id', 'role', 'is_active', 'login_enabled'], where: 'id=?', whereArgs: [actor.id]);
      if (staff.isEmpty || staff.single['is_active'] != 1 || staff.single['login_enabled'] != 1 || !StaffRole.fromCode(staff.single['role'] as String).isManager) {
        throw StateError('Manager access is no longer enabled.');
      }
      return _read(txn, query, actor.id);
    });
    if (!identical(authService.session.currentStaff, actor)) throw StateError('Session changed while loading analytics.');
    return _ReportBuilder(evidence).build();
  }

  Future<_Evidence> _read(Transaction txn, AnalyticsQuery query, int actor) async {
    final e = _Evidence(query, actor, DateTime.now().toUtc());
    final dayScope = _dayScope(query);
    final dayArgs = _dayArgs(query);
    final orderScope = _orderScope(query);
    final orderArgs = [...dayArgs, ..._orderArgs(query)];
    final tables = (await txn.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r['name']).toSet();
    Future<void> read(String key, String table, String sql, [List<Object?> args = const []]) async {
      if (!tables.contains(table)) { e.absent.add(table); e.rows[key] = []; return; }
      e.rows[key] = await txn.rawQuery(sql, args);
    }
    await read('days', 'business_days', 'SELECT b.id,b.opened_at,b.closed_at,b.status FROM business_days b WHERE $dayScope ORDER BY b.opened_at', dayArgs);
    const fields = 'o.id,o.business_day_id,o.shift_id,o.cashier_id,o.token_number,o.dining_type,o.subtotal,o.discount_amount,o.discount_id,o.tax_amount,o.grand_total,o.payment_status,o.token_status,o.cash_rounding_paisa,o.delivery_area_id,o.delivery_area_name_snapshot,o.delivery_fee_paisa,o.customer_phone,o.created_at';
    final orderFrom = 'FROM orders o JOIN business_days b ON b.id=o.business_day_id WHERE $dayScope AND $orderScope';
    await read('orders', 'orders', 'SELECT $fields $orderFrom ORDER BY o.id', orderArgs);
    final joinedOrder = 'JOIN orders o ON o.id=x.order_id JOIN business_days b ON b.id=o.business_day_id WHERE $dayScope AND $orderScope';
    await read('payments', 'order_payments', 'SELECT x.* FROM order_payments x $joinedOrder', orderArgs);
    // Independent receiving evidence must survive an originating order outside scope.
    await read('payment_events', 'payment_events', 'SELECT x.*,o.business_day_id AS originating_business_day_id,o.shift_id AS originating_shift_id,s.staff_id AS shift_owner_id FROM payment_events x LEFT JOIN orders o ON o.id=x.order_id LEFT JOIN shifts s ON s.id=x.shift_id');
    await read('items', 'order_items', 'SELECT x.id,x.order_id,x.menu_item_id,x.deal_id,x.name,x.quantity,x.unit_price,x.total_price,x.modifiers_json,x.deal_choices_json,x.bom_json FROM order_items x $joinedOrder', orderArgs);
    await read('revisions', 'order_revisions', 'SELECT x.id,x.order_id,x.revision_no,x.action,x.reason,x.cashier_id,x.created_at_utc,x.money_delta_paisa FROM order_revisions x $joinedOrder', orderArgs);
    await read('cost_coverage', 'order_cost_coverage', 'SELECT x.* FROM order_cost_coverage x $joinedOrder', orderArgs);
    await read('cost_events', 'order_cost_events', 'SELECT x.* FROM order_cost_events x $joinedOrder', orderArgs);
    // A physical drawer uses all orders in its shifts; order filters never alter it.
    await read('shifts', 'shifts', 'SELECT s.* FROM shifts s JOIN business_days b ON b.id=s.business_day_id WHERE $dayScope', dayArgs);
    await read('cash_payments', 'order_payments', "SELECT p.*,o.shift_id FROM order_payments p JOIN orders o ON o.id=p.order_id JOIN business_days b ON b.id=o.business_day_id WHERE $dayScope AND o.payment_status IN ('SETTLED','REFUND_PENDING','CANCELLED','REFUNDED')", dayArgs);
    await read('movements', 'cash_movements', 'SELECT m.id,m.shift_id,m.staff_id,m.type,m.amount,m.category,m.created_at FROM cash_movements m JOIN shifts s ON s.id=m.shift_id JOIN business_days b ON b.id=s.business_day_id WHERE $dayScope', dayArgs);
    await read('trips', 'rider_trips', 'SELECT t.* FROM rider_trips t JOIN business_days b ON b.id=t.business_day_id WHERE $dayScope', dayArgs);
    await read('attempts', 'rider_trip_orders', 'SELECT x.id,x.order_id,x.trip_id,x.status,x.delivered_at,x.returned_at,t.dispatched_at,t.rider_staff_id FROM rider_trip_orders x JOIN rider_trips t ON t.id=x.trip_id $joinedOrder', orderArgs);
    await read('ingredients', 'raw_ingredients', 'SELECT id,name,storage_unit,current_stock,low_stock_threshold,cost_per_recipe_unit FROM raw_ingredients');
    await read('inventory', 'inventory_movements', 'SELECT m.* FROM inventory_movements m JOIN business_days b ON b.id=m.business_day_id WHERE $dayScope', dayArgs);
    final cutoff = e.get('days').map((d) => _karachi(d['closed_at']) ?? _karachi(e.now.toIso8601String())!).fold<DateTime?>(null, (latest, time) => latest == null || time.isAfter(latest) ? time : latest);
    if (cutoff != null) {
      await read('balances', 'inventory_movements', 'SELECT id,ingredient_id,balance_after,recorded_at FROM (SELECT m.*,ROW_NUMBER() OVER(PARTITION BY ingredient_id ORDER BY ${_localSql('m.recorded_at')} DESC,id DESC) AS evidence_rank FROM inventory_movements m WHERE ${_localSql('m.recorded_at')}<=?) WHERE evidence_rank=1', [_sqlTime(cutoff)]);
    }
    final interval = _intervalScope(query, 'x.created_at');
    final intervalArgs = [...dayArgs, _sqlTime(_karachi(e.now.toIso8601String())!.add(const Duration(seconds: 1)))];
    await read('purchases', 'mandi_procurements', 'SELECT x.id,x.raw_ingredient_id,x.traditional_unit,x.quantity,x.converted_quantity,x.total_cost,x.cost_per_recipe_unit,x.created_at FROM mandi_procurements x WHERE $interval', intervalArgs);
    await read('physical_counts', 'stock_count_lines', 'SELECT x.*,c.status,c.reason,c.created_by,c.approved_by,c.posted_by,c.posted_at AS created_at FROM stock_count_lines x JOIN stock_counts c ON c.id=x.count_id WHERE ${_intervalScope(query, 'c.posted_at')} AND c.status=\'POSTED\'', intervalArgs);
    e.rows['physical_counts'] = e.get('physical_counts').map((row) => <String, Object?>{...row, 'recorded_estimated_cost_paisa': row['estimated_cost_paisa'], 'estimated_cost_paisa': StockCountValuation.paisa(row)}).toList();
    await read('waste', 'kitchen_wastage', 'SELECT x.id,x.staff_id,x.raw_ingredient_id,x.quantity,x.cost_loss,x.reason,x.created_at FROM kitchen_wastage x WHERE $interval', intervalArgs);
    await read('vendor_events', 'vendor_transactions', 'SELECT x.id,x.vendor_id,x.shift_id,x.staff_id,x.type,x.amount,x.raw_ingredient_id,x.quantity,x.created_at FROM vendor_transactions x WHERE $interval', intervalArgs);
    await read('expense_entries', 'expense_entries', 'SELECT x.* FROM expense_entries x JOIN business_days b ON b.id=x.business_day_id WHERE $dayScope', dayArgs);
    await read('payroll_entries', 'payroll_entries', 'SELECT x.* FROM payroll_entries x WHERE $interval', intervalArgs);
    await read('payroll_balances', 'payroll_entries', 'SELECT employee_id AS id,SUM(payable_delta_paisa) payable_paisa,SUM(advance_delta_paisa) advance_paisa FROM payroll_entries GROUP BY employee_id');
    if (tables.contains('supplier_payment_allocations')) {
      await read('invoice_balances', 'vendor_transactions', "SELECT t.id,t.vendor_id,t.due_date,COALESCE(t.amount_paisa,CAST(ROUND(t.amount*100) AS INTEGER))-COALESCE(SUM(a.amount_paisa),0) due_paisa FROM vendor_transactions t LEFT JOIN supplier_payment_allocations a ON a.invoice_id=t.id WHERE t.type='PURCHASE_CREDIT' GROUP BY t.id");
    } else {
      e.absent.add('supplier_payment_allocations');
    }
    await read('vendors', 'vendor_khata', 'SELECT id,name,opening_balance,current_balance,created_at FROM vendor_khata');
    await read('staff', 'staff', 'SELECT s.id,s.name,s.department_id,s.job_role_id,s.role,s.is_active,s.login_enabled,d.name AS department,j.name AS job_role FROM staff s LEFT JOIN departments d ON d.id=s.department_id LEFT JOIN job_roles j ON j.id=s.job_role_id');
    await read('catalog', 'menu_items', 'SELECT id,name,category_id,is_active FROM menu_items');
    await read('deals', 'deals', 'SELECT id,name,is_active FROM deals');
    await read('reports', 'report_runs', 'SELECT r.id,r.business_day_id,r.content_hash,r.created_by,r.created_at,r.status FROM report_runs r JOIN business_days b ON b.id=r.business_day_id WHERE $dayScope', dayArgs);
    await read('outbox', 'report_outbox', 'SELECT r.id,r.business_day_id,r.channel,r.status,r.retry_count,r.created_at FROM report_outbox r JOIN business_days b ON b.id=r.business_day_id WHERE $dayScope', dayArgs);
    await read('delivery_audit', 'report_delivery_audit', 'SELECT x.id,x.staff_id,x.action,x.created_at FROM report_delivery_audit x WHERE $interval', intervalArgs);
    await read('token_audit', 'checkout_token_audit', 'SELECT x.id,x.order_id,x.token_number,x.action,x.payment_status,x.revision,x.recorded_at FROM checkout_token_audit x $joinedOrder', orderArgs);
    await read('rounding', 'rounding_variance_ledger', 'SELECT x.id,x.order_id,x.shift_id,x.cash_rounding_paisa,x.created_at FROM rounding_variance_ledger x $joinedOrder', orderArgs);
    await read('stock_alerts', 'checkout_stock_alerts', 'SELECT x.order_id,x.ingredient_id,x.stock_at_checkout,x.created_at FROM checkout_stock_alerts x $joinedOrder', orderArgs);
    await read('all_due', 'orders', "SELECT id,grand_total FROM orders WHERE payment_status='COLLECTION_DUE'");
    await read('all_trips', 'rider_trips', "SELECT id,cash_expected_paisa FROM rider_trips WHERE status IN ('DISPATCHED','RETURNED')");
    if (!query.live) {
      final duration = _date(query.endDateExclusive).difference(_date(query.startDate));
      final prior = query.copyWith(startDate: query.startDate.subtract(duration), endDateExclusive: query.startDate);
      await read('previous_orders', 'orders', 'SELECT o.id,o.grand_total,o.payment_status FROM orders o JOIN business_days b ON b.id=o.business_day_id WHERE ${_dayScope(prior)} AND ${_orderScope(prior)}', [..._dayArgs(prior), ..._orderArgs(prior)]);
      final priorIntervalArgs = [..._dayArgs(prior), _sqlTime(_karachi(e.now.toIso8601String())!)];
      await read('previous_purchases', 'mandi_procurements', 'SELECT x.id,x.total_cost FROM mandi_procurements x WHERE ${_intervalScope(prior, 'x.created_at')}', priorIntervalArgs);
      await read('previous_waste', 'kitchen_wastage', 'SELECT x.id,x.cost_loss FROM kitchen_wastage x WHERE ${_intervalScope(prior, 'x.created_at')}', priorIntervalArgs);
    }
    return e;
  }

  static String _dayScope(AnalyticsQuery q) => q.live ? "b.status='OPEN'" : '(${_localSql('b.opened_at', dateOnly: true)}>=? AND ${_localSql('b.opened_at', dateOnly: true)}<?)';
  static List<Object?> _dayArgs(AnalyticsQuery q) => q.live ? [] : [_sqlDate(q.startDate), _sqlDate(q.endDateExclusive)];
  static String _orderScope(AnalyticsQuery q) => [if (q.cashierId != null) 'o.cashier_id=?', if (q.shiftId != null) 'o.shift_id=?', if (q.diningType != null) 'o.dining_type=?', if (q.paymentMethod != null) 'o.id IN(SELECT fp.order_id FROM order_payments fp WHERE fp.payment_method=?)', '1=1'].join(' AND ');
  static List<Object?> _orderArgs(AnalyticsQuery q) => [if (q.cashierId != null) q.cashierId, if (q.shiftId != null) q.shiftId, if (q.diningType != null) q.diningType, if (q.paymentMethod != null) q.paymentMethod];
  static String _intervalScope(AnalyticsQuery q, String timestamp) => 'EXISTS(SELECT 1 FROM business_days b WHERE ${_dayScope(q)} AND ${_localSql(timestamp)}>=${_localSql('b.opened_at')} AND ${_localSql(timestamp)}<COALESCE(${_localSql('b.closed_at')},?))';
}

class _Evidence {
  _Evidence(this.query, this.actor, this.now);
  final AnalyticsQuery query;
  final int actor;
  final DateTime now;
  final Map<String, List<_Record>> rows = {};
  final Set<String> absent = {};
  List<_Record> get(String name) => rows[name] ?? const [];
}

int _money(_Record row, String key) => (row['${key}_paisa'] as num?)?.toInt() ?? PaisaEngine.rupeesToPaisa((row[key] as num?) ?? 0);
int _sum(Iterable<_Record> rows, String key) => rows.fold(0, (sum, row) => sum + _money(row, key));
int _integers(Iterable<_Record> rows, String key) => rows.fold(0, (sum, row) => sum + ((row[key] as num?)?.toInt() ?? 0));
bool _valid(_Record o) => !['VOIDED', 'CANCELLED', 'REFUNDED'].contains(o['payment_status']);
bool _collected(_Record o) => ['SETTLED', 'REFUND_PENDING', 'CANCELLED', 'REFUNDED'].contains(o['payment_status']);
DateTime _date(DateTime t) => DateTime.utc(t.year, t.month, t.day);
String _sqlDate(DateTime t) => '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
String _sqlTime(DateTime t) => '${_sqlDate(t)} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
String _localSql(String column, {bool dateOnly = false}) {
  final function = dateOnly ? 'date' : 'datetime';
  return "CASE WHEN $column LIKE '%Z' OR substr($column,-6,1) IN ('+','-') THEN $function($column,'+5 hours') ELSE $function($column) END";
}
DateTime? _karachi(Object? raw) {
  if (raw is! String) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return parsed.isUtc || RegExp(r'[+-]\d\d:\d\d$').hasMatch(raw) ? parsed.toUtc().add(const Duration(hours: 5)) : DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour, parsed.minute, parsed.second);
}
