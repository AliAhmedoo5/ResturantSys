import 'dart:convert';
import 'package:sqflite_common/sqlite_api.dart';
import '../auth/auth_service.dart';
import '../auth/staff_role.dart';
import '../payments/payment_event.dart';
import 'analytics_models.dart';
import 'analytics_export_service.dart';
export 'analytics_models.dart' show AnalyticsFamily;

enum HistoricalCorrectionType { collection, drawerPayout, expense, refund, discrepancyExplanation }

class HistoricalCorrections {
  HistoricalCorrections({required this.database, required this.auth, DateTime Function()? clock}) : clock = clock ?? DateTime.now;
  final Database database;
  final AuthService auth;
  final DateTime Function() clock;

  Future<int> _authorize(DatabaseExecutor txn) async {
    final actor = auth.session.currentStaff;
    if (actor == null || actor.role != StaffRole.manager) throw StateError('An active Manager session is required.');
    final staff = await txn.query('staff', where: 'id=? AND is_active=1 AND login_enabled=1', whereArgs: [actor.id]);
    if (staff.isEmpty || !StaffRole.fromCode(staff.single['role'] as String).isManager) throw StateError('Manager access is no longer enabled.');
    return actor.id;
  }

  Future<int> _verify(String pin) async {
    await _authorize(database);
    final actor = auth.session.currentStaff!;
    final verified = await auth.authenticateSupervisorPin(pin);
    if (verified?.id != actor.id || !identical(actor, auth.session.currentStaff)) throw StateError('Verify the signed-in Manager PIN.');
    return actor.id;
  }

  Future<List<int>> closedDays() => database.transaction((txn) async {
    await _authorize(txn);
    return (await txn.query('business_days', columns: ['id'], where: "status='CLOSED'", orderBy: 'id DESC')).map((r) => r['id'] as int).toList();
  });

  Future<int> append({required String managerPin, required int businessDayId,
    int? shiftId, int? orderId, required HistoricalCorrectionType type,
    required int deltaPaisa, required String evidenceKey, required String reason,
    required bool reconciled, DateTime? eventTime, String paymentSource = 'DRAWER_CASH'}) async {
    final actor = await _verify(managerPin);
    if (!reconciled || reason.trim().length < 10 || evidenceKey.trim().isEmpty || deltaPaisa == 0 ||
        deltaPaisa.abs() > 9000000000000000 || eventTime == null ||
        eventTime.toUtc().isAfter(clock().toUtc()) ||
        !const ['DRAWER_CASH','BANK_DIGITAL','OWNER_FUNDS'].contains(paymentSource)) {
      throw StateError('Verified source evidence, actual Event Time, nonzero Integer Paisa and a reason of at least 10 characters are required.');
    }
    return database.transaction((txn) async {
      if (await _authorize(txn) != actor) throw StateError('Session changed.');
      final days = await txn.query('business_days', where: "id=? AND status='CLOSED'", whereArgs: [businessDayId]);
      if (days.isEmpty) throw StateError('Only closed Business Days accept historical corrections.');
      DateTime? instant(Object? value) => analyticsKarachiTime(value)?.subtract(const Duration(hours: 5));
      final opened = instant(days.single['opened_at']);
      final closed = instant(days.single['closed_at']);
      if (opened == null || closed == null || eventTime.toUtc().isBefore(opened) || eventTime.toUtc().isAfter(closed)) {
        throw StateError('Actual Event Time must belong to the affected closed Business Day.');
      }
      final duplicate = await txn.query('historical_corrections', where: 'source_reference=? AND reverses_correction_id IS NULL', whereArgs: [evidenceKey.trim()]);
      if (duplicate.isNotEmpty) throw StateError('This physical evidence has already been recorded. Use a new replacement reference after reversal.');
      if ((await txn.query('payment_events', where: 'event_key=?', whereArgs: [evidenceKey.trim()])).isNotEmpty) throw StateError('This physical effect already exists in the payment ledger.');
      if (shiftId != null) {
        final shifts = await txn.query('shifts', where: "id=? AND business_day_id=? AND status='CLOSED'", whereArgs: [shiftId,businessDayId]);
        if (shifts.isEmpty) throw StateError('Affected Shift must belong to the closed Business Day.');
      }
      String target = 'CASH_MOVEMENT', code = 'DISCREPANCY_EXPLANATION';
      String metric = 'variance';
      if (type == HistoricalCorrectionType.collection) {
        if (deltaPaisa <= 0 || orderId == null) throw StateError('Late collection requires a positive amount and original Order.');
        final orders = await txn.rawQuery("SELECT o.*, $outstandingCollectionPaisaSql AS due FROM orders o WHERE o.id=? AND o.business_day_id=? AND o.payment_status='COLLECTION_DUE'", [orderId,businessDayId]);
        if (orders.isEmpty || (shiftId != null && orders.single['shift_id'] != shiftId)) throw StateError('Original Collection Due Order does not match.');
        final prior = await txn.rawQuery("SELECT COALESCE(SUM(delta_amount_paisa),0) AS net FROM historical_corrections WHERE target_entity_type='ORDER_PAYMENT' AND target_entity_id=?", [orderId]);
        if (deltaPaisa + (prior.single['net'] as int) > (orders.single['due'] as int)) throw StateError('Collection exceeds the unreconciled original amount.');
        target = 'ORDER_PAYMENT'; code = 'LATE_PAYMENT_COLLECTION'; metric = 'collection';
      } else {
        if (deltaPaisa >= 0) throw StateError('Historical disbursements require a negative amount.');
        if (paymentSource == 'DRAWER_CASH' && shiftId == null) throw StateError('Drawer reconciliation requires the affected closed Shift.');
        if (type == HistoricalCorrectionType.drawerPayout) { target = 'VENDOR_TRANSACTION'; code = 'LATE_VENDOR_PAYMENT'; }
        if (type == HistoricalCorrectionType.expense) { target = 'EXPENSE_ENTRY'; code = 'LATE_EXPENSE'; }
        if (type == HistoricalCorrectionType.refund) { target = 'ORDER_PAYMENT'; code = 'LATE_REFUND'; }
        if (paymentSource != 'DRAWER_CASH') metric = 'external';
      }
      final staff = (await txn.query('staff', where: 'id=?', whereArgs: [actor])).single;
      return txn.insert('historical_corrections', {
        'correction_key': evidenceKey.trim(), 'affected_business_day_id':businessDayId,
        'affected_shift_id':shiftId, 'target_entity_type':target, 'target_entity_id':orderId,
        'correction_type':code, 'delta_amount_paisa':deltaPaisa, 'payment_source':paymentSource,
        'event_time':eventTime.toUtc().toIso8601String(), 'recorded_at':clock().toUtc().toIso8601String(),
        'recorded_by_staff_id':actor, 'manager_name_snapshot':staff['name'],
        'reason':reason.trim(), 'source_reference':evidenceKey.trim(), 'metric':metric,
      });
    });
  }

  Future<int> reverse(int id, {required String managerPin, required String reason}) async {
    final actor = await _verify(managerPin);
    if (reason.trim().length < 10) throw StateError('A reversal reason of at least 10 characters is required.');
    return database.transaction((txn) async {
      if (await _authorize(txn) != actor) throw StateError('Session changed.');
      final rows = await txn.query('historical_corrections', where:'id=?', whereArgs:[id]);
      if (rows.isEmpty || rows.single['reverses_correction_id'] != null ||
          (await txn.query('historical_corrections', where:'reverses_correction_id=?', whereArgs:[id])).isNotEmpty) throw StateError('Only an unreversed original correction can be reversed once.');
      final original = rows.single;
      final staff = (await txn.query('staff', where:'id=?', whereArgs:[actor])).single;
      return txn.insert('historical_corrections', {...original, 'id':null,
        'correction_key':'reverse:$id', 'correction_type':'CONTRA_REVERSAL',
        'delta_amount_paisa':-(original['delta_amount_paisa'] as int),
        'recorded_at':clock().toUtc().toIso8601String(), 'recorded_by_staff_id':actor,
        'manager_name_snapshot':staff['name'], 'reason':reason.trim(), 'reverses_correction_id':id});
    });
  }

  Future<HistoricalCorrectionSnapshot> load(int dayId, {DateTime? cutoff}) async {
    final limit = (cutoff ?? clock()).toUtc();
    return database.transaction((txn) async {
      final actor = await _authorize(txn);
      final reports = await txn.query('report_runs', where:'business_day_id=?', whereArgs:[dayId], orderBy:'id', limit:1);
      if (reports.isEmpty) throw StateError('Original sealed report unavailable; historical values remain unknown.');
      final entries = await txn.query('historical_corrections', where:'affected_business_day_id=? AND recorded_at<=?', whereArgs:[dayId,limit.toIso8601String()], orderBy:'recorded_at,id');
      return HistoricalCorrectionSnapshot(dayId, actor, limit, reports.single['snapshot_json'] as String,
        reports.single['content_hash'] as String, reports.single['created_at'] as String, entries);
    });
  }
}

class HistoricalCorrectionSnapshot {
  HistoricalCorrectionSnapshot(this.dayId,this.actorId,this.cutoff,this.originalSnapshotJson,this.originalHash,this.originalRecordedAt,List<Map<String,Object?>> entries)
    : entries = List.unmodifiable(entries.map((r)=>Map<String,Object?>.unmodifiable(r)));
  final int dayId,actorId;
  final DateTime cutoff;
  final String originalSnapshotJson,originalHash,originalRecordedAt;
  final List<Map<String,Object?>> entries;
  List<dynamic> get _sections => (jsonDecode(originalSnapshotJson) as Map<String,dynamic>)['sections'] as List<dynamic>;
  int get originalCollectionDuePaisa {
    final rows = (_sections.first as Map<String,dynamic>)['rows'] as List<dynamic>;
    return ((rows.cast<List<dynamic>>().where((r)=>r.first=='Collection Due').firstOrNull?[1] as num?) ?? 0).toInt();
  }
  int get originalCashReceiptsPaisa {
    final rows = (_sections.first as Map<String,dynamic>)['rows'] as List<dynamic>;
    return rows.cast<List<dynamic>>().where((r)=>r.first=='Tender CASH (collected)').fold<int>(0,(sum,r)=>sum+(r[1] as num).toInt());
  }
  int get adjustedCashReceiptsPaisa => originalCashReceiptsPaisa + entries.where((r)=>r['metric']=='collection' && r['payment_source']=='DRAWER_CASH').fold<int>(0,(sum,r)=>sum+(r['delta_amount_paisa'] as int));
  int? get originalVariancePaisa {
    final section = _sections.cast<Map<String,dynamic>>().where((s)=>s['title']=='Shift Handover Audit').firstOrNull;
    if (section == null) return null;
    final rows = section['rows'] as List<dynamic>;
    if (rows.any((r)=>(r as List<dynamic>)[6] is! num)) return null;
    return rows.fold<int>(0,(sum,r)=>sum+((r as List<dynamic>)[6] as num).toInt());
  }
  int _sum(String metric) => entries.where((r)=>r['metric']==metric).fold(0,(sum,r)=>sum+(r['delta_amount_paisa'] as int));
  int get adjustedCollectionDuePaisa => originalCollectionDuePaisa-_sum('collection');
  int? get adjustedVariancePaisa => originalVariancePaisa == null ? null : originalVariancePaisa!-_sum('variance');
  AnalyticsSnapshot toAnalyticsSnapshot({bool adjusted = true}) {
    const columns = [AnalyticsColumn(key:'sealed_evidence',label:'Original sealed evidence'),AnalyticsColumn(key:'basis',label:'Basis'), AnalyticsColumn(key:'measure',label:'Measure'),
      AnalyticsColumn(key:'amount',label:'Amount',unit:AnalyticsUnit.paisa), AnalyticsColumn(key:'event_time',label:'Actual Event Time'),
      AnalyticsColumn(key:'recorded_at',label:'Recorded at'), AnalyticsColumn(key:'manager_name_snapshot',label:'Manager'),
      AnalyticsColumn(key:'reason',label:'Reason'), AnalyticsColumn(key:'source_reference',label:'Evidence reference'),
      AnalyticsColumn(key:'target_entity_type',label:'Original evidence type'), AnalyticsColumn(key:'target_entity_id',label:'Original evidence ID'),
      AnalyticsColumn(key:'affected_shift_id',label:'Affected Shift'), AnalyticsColumn(key:'reverses_correction_id',label:'Reverses correction')];
    final rows = <AnalyticsRow>[];
    void value(String basis,String measure,int? amount) => rows.add(AnalyticsRow(id:'$basis:$measure',sourceType:'report_runs',cells:{'basis':basis,'measure':measure,'amount':amount}));
    var sealedRow = 0;
    for (final section in _sections.cast<Map<String,dynamic>>()) {
      final headers = (section['headers'] as List<dynamic>).join(' | ');
      for (final row in section['rows'] as List<dynamic>) {
        rows.add(AnalyticsRow(id:'sealed:${sealedRow++}',sourceType:'report_runs',cells:{'basis':'Original sealed','measure':section['title'],'sealed_evidence':'$headers :: ' + (row as List<dynamic>).join(' | ')}));
      }
    }
    value('Original sealed','Cash receipts',originalCashReceiptsPaisa);
    value('Original sealed','Collection Due',originalCollectionDuePaisa);
    value('Original sealed','Drawer variance',originalVariancePaisa);
    if (adjusted) {
      for (final entry in entries) {
        rows.add(AnalyticsRow(id:'correction:${entry['id']}',sourceType:'historical_corrections',sourceId:'${entry['id']}',cells:{...entry,'basis':'Adjustment bridge','measure':entry['correction_type'],'amount':entry['delta_amount_paisa']}));
      }
      value('Correction-adjusted','Cash receipts',adjustedCashReceiptsPaisa);
      value('Correction-adjusted','Collection Due',adjustedCollectionDuePaisa);
      value('Correction-adjusted','Drawer variance',adjustedVariancePaisa);
    }
    return AnalyticsSnapshot(query:AnalyticsQuery(startDate:DateTime(2000),endDateExclusive:DateTime(2200)),
      generatedAt:cutoff, generatedByStaffId:actorId, businessDayIds:[dayId], sections:[AnalyticsSection(family:AnalyticsFamily.cash,
        title:adjusted ? 'Original sealed and correction-adjusted bridge' : 'Original sealed report',columns:columns,rows:rows,
        notes:['Business Day #$dayId; correction cutoff ${cutoff.toIso8601String()} (recorded_at inclusive).',
          'Original sealed hash $originalHash; original recording timestamp $originalRecordedAt.',
          'Original X/Z reports, balances and recording timestamps remain unchanged. Amounts are Integer Paisa.',
          'External disbursements are evidence only; they do not change drawer variance. Unknown Event Times are never inferred.'])]);
  }
  String csv() => AnalyticsExportService().csv(toAnalyticsSnapshot(),AnalyticsFamily.cash);
}



