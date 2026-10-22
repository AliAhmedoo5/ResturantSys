import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'excel_reporting_engine.dart';

/// A sealed report snapshot survives process loss and filesystem outages.
class ReportExportService {
  ReportExportService({required this.database, String? directory})
      : directory = directory ?? (database.path == inMemoryDatabasePath
          ? ExcelReportingEngine.resolveDefaultReportsDir()
          : p.join(p.dirname(database.path), 'reports'));
  final Database database;
  final String directory;

  static Future<void> capture(DatabaseExecutor db, int dayId, int managerId) async {
    final day = (await db.query('business_days', where: 'id=?', whereArgs: [dayId])).single;
    final opened = day['opened_at'] as String;
    final closed = day['closed_at'] as String;
    final generated = DateTime.now();
    final name = await db.query('system_settings', where: "key='restaurant_name'");
    final totals = (await db.rawQuery("""SELECT COUNT(*) AS orders,
      COALESCE(SUM(CAST(ROUND(subtotal*100) AS INTEGER)),0) AS gross,
      COALESCE(SUM(CAST(ROUND(discount_amount*100) AS INTEGER)),0) AS discount,
      COALESCE(SUM(CAST(ROUND(tax_amount*100) AS INTEGER)),0) AS tax,
      COALESCE(SUM(CAST(ROUND(grand_total*100) AS INTEGER)),0) AS net,
      COALESCE(SUM(cash_rounding_paisa),0) AS rounding
      FROM orders WHERE business_day_id=? AND payment_status NOT IN ('VOIDED','CANCELLED','REFUNDED')""", [dayId])).single;
    final tenders = await db.rawQuery("""SELECT op.payment_method,
      SUM(COALESCE(op.amount_tendered_paisa,CAST(ROUND(op.amount_tendered*100) AS INTEGER))
      -COALESCE(op.change_returned_paisa,CAST(ROUND(op.change_returned*100) AS INTEGER))) AS paisa
      FROM order_payments op JOIN orders o ON o.id=op.order_id
      WHERE o.business_day_id=? AND o.payment_status IN ('SETTLED','REFUND_PENDING','CANCELLED','REFUNDED')
      GROUP BY op.payment_method ORDER BY op.payment_method""", [dayId]);
    final due = (await db.rawQuery("SELECT COALESCE(SUM(CAST(ROUND(grand_total*100) AS INTEGER)),0) AS paisa FROM orders WHERE business_day_id=? AND payment_status='COLLECTION_DUE'", [dayId])).single['paisa'];
    final sales = await db.rawQuery("""SELECT o.token_number,oi.name,oi.quantity,
      CAST(ROUND(oi.total_price*100) AS INTEGER) AS paisa,o.payment_status
      FROM orders o JOIN order_items oi ON oi.order_id=o.id WHERE o.business_day_id=? ORDER BY o.token_number,oi.id""", [dayId]);
    final inventory = await db.rawQuery("""SELECT i.name,i.storage_unit,i.current_stock,
      COALESCE((SELECT SUM(m.quantity_delta) FROM inventory_movements m WHERE m.ingredient_id=i.id AND m.business_day_id=?),0) AS delta
      FROM raw_ingredients i ORDER BY i.name""", [dayId]);
    final wastage = await db.rawQuery("""SELECT w.created_at,i.name,w.quantity,w.reason,CAST(ROUND(w.cost_loss*100) AS INTEGER) AS loss
      FROM kitchen_wastage w JOIN raw_ingredients i ON i.id=w.raw_ingredient_id
      WHERE datetime(w.created_at)>=datetime(?) AND datetime(w.created_at)<=datetime(?) ORDER BY w.id""", [opened,closed]);
    final shifts = await db.rawQuery("""SELECT s.*,st.name FROM shifts s JOIN staff st ON st.id=s.staff_id
      WHERE s.business_day_id=? ORDER BY s.id""", [dayId]);
    final vendors = await db.rawQuery("""SELECT v.name,t.type,CAST(ROUND(t.amount*100) AS INTEGER) AS paisa,t.created_at
      FROM vendor_transactions t JOIN vendor_khata v ON v.id=t.vendor_id
      WHERE datetime(t.created_at)>=datetime(?) AND datetime(t.created_at)<=datetime(?) ORDER BY t.id""", [opened,closed]);
    int paisa(Object? value) => (((value as num?)?.toDouble() ?? 0)*100).round();
    Map<String,dynamic> section(String title,List<String> headers,List<List<dynamic>> rows) => {'title':title,'headers':headers,'rows':rows};
    final sections = [
      section('Z-Report / Executive Summary', ['Measure','Value (money in integer paisa)'], [
        ['Restaurant',name.isEmpty ? 'Restaurant' : name.first['value']],
        ['Business Day',dayId],['Business date',opened.substring(0,10)],['Opened',opened],['Closed / snapshot cutoff',closed],
        ['Generated',generated.toIso8601String()],['Timezone',generated.timeZoneName],['UTC offset minutes',generated.timeZoneOffset.inMinutes],['Report revision',1],
        ['Orders',totals['orders']],['Gross sales',totals['gross']],['Discounts',totals['discount']],['Tax carve-out',totals['tax']],['Net sales incl. Collection Due',totals['net']],['Cash rounding',totals['rounding']],['Collection Due',due],
        ...tenders.map((r)=>['Tender ${r['payment_method']} (collected)',r['paisa']]),
        ['Count missing shifts',shifts.where((s)=>s['counted_cash']==null).length],
      ]),
      section('Sales by Item / Order Status',['Token','Item','Quantity','Amount (paisa)','Payment status'],sales.map((r)=>[r['token_number'],r['name'],r['quantity'],r['paisa'],r['payment_status']]).toList()),
      section('Inventory Movement',['Ingredient','Unit','Opening stock','Net movement','Closing stock'],inventory.map((r)=>[r['name'],r['storage_unit'],(r['current_stock'] as num)-(r['delta'] as num),r['delta'],r['current_stock']]).toList()),
      section('Kitchen Wastage',['Recorded','Ingredient','Quantity','Reason','Loss (paisa)'],wastage.map((r)=>[r['created_at'],r['name'],r['quantity'],r['reason'],r['loss']]).toList()),
      section('Shift Handover Audit',['Shift','Cashier','Float (paisa)','Expected (paisa)','Counted (paisa)','Variance (paisa)','Audit'],shifts.map((r)=>[r['id'],r['name'],paisa(r['opening_float']),paisa(r['expected_cash']),r['counted_cash']==null?'NOT COUNTED':paisa(r['counted_cash']),r['discrepancy']==null?'UNKNOWN':paisa(r['discrepancy']),r['discrepancy_status']]).toList()),
      section('Vendor Khata Movements',['Vendor','Type','Amount (paisa)','Recorded'],vendors.map((r)=>[r['name'],r['type'],r['paisa'],r['created_at']]).toList()),
    ];
    final policies = await db.query('system_settings',where:"key='report_delivery_settings'");
    final delivery = policies.isEmpty ? null : jsonDecode(policies.single['value'] as String);
    final snapshot = jsonEncode({'delivery':delivery,'business_day_id':dayId,'business_date':opened.substring(0,10),'revision':1,'cutoff':closed,'sections':sections});
    await db.insert('report_runs', {'business_day_id':dayId,'snapshot_json':snapshot,
      'content_hash':sha256.convert(utf8.encode(snapshot)).toString(),'created_by':managerId,
      'created_at':generated.toUtc().toIso8601String()});
  }

  Future<List<Map<String,dynamic>>> history() => database.query('report_runs',orderBy:'id DESC');

  /// Returns successfully persisted immutable artifact references.
  Future<void> exportPending() async {
    final runs = await database.query('report_runs',where:"status != 'READY'",orderBy:'id');
    for (final run in runs) {
      try {
        final snapshot = jsonDecode(run['snapshot_json'] as String) as Map<String,dynamic>;
        final sections = (snapshot['sections'] as List).map((s)=>Map<String,dynamic>.from(s as Map)).toList();
        final base = 'business_day_${snapshot['business_day_id']}_${snapshot['business_date']}_v1_${(run['content_hash'] as String).substring(0,12)}';
        final folder = Directory(directory);
        await folder.create(recursive:true);
        final document = pw.Document(title:'Business Day ${snapshot['business_date']} Z-Report',author:'Restaurant POS');
        for (final section in sections) {
          document.addPage(pw.MultiPage(pageFormat:PdfPageFormat.a4.landscape,
            margin:const pw.EdgeInsets.all(28),
            header:(context)=>pw.Text('Business Day ${snapshot['business_date']} | Revision 1 | ${section['title']}',style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold)),
            footer:(context)=>pw.Text('Snapshot ${run['content_hash']} | Page ${context.pageNumber}',style:const pw.TextStyle(fontSize:7)),
            build:(context)=>[pw.SizedBox(height:12),pw.TableHelper.fromTextArray(
              headers:List<String>.from(section['headers'] as List),
              data:(section['rows'] as List).map((row)=>(row as List).map((cell)=>'$cell').toList()).toList(),
              headerDecoration:const pw.BoxDecoration(color:PdfColors.grey200),
              cellStyle:const pw.TextStyle(fontSize:8),headerStyle:pw.TextStyle(fontSize:9,fontWeight:pw.FontWeight.bold),
            )]));
        }
        final outputs = {'pdf':await document.save(),'xlsx':ExcelReportingEngine(database:database).generateSnapshotWorkbook(sections)};
        final artifacts = <Map<String,dynamic>>[];
        for (final output in outputs.entries) {
          final file = File(p.join(directory,'$base.${output.key}'));
          if (await file.exists()) {
            if (sha256.convert(await file.readAsBytes()).toString()!=sha256.convert(output.value).toString()) {
              // PDF creation metadata can vary between recoveries. Existing committed
              // files are preserved; their actual digest is recorded below.
              if (output.key!='pdf') throw StateError('Existing workbook differs from immutable snapshot');
            }
          } else {
            final temporary = File('${file.path}.tmp');
            await temporary.writeAsBytes(output.value,flush:true);
            await temporary.rename(file.path);
          }
          final bytes = await file.readAsBytes();
          artifacts.add({'kind':output.key,'path':file.path,'sha256':sha256.convert(bytes).toString(),'size_bytes':bytes.length});
        }
        await database.update('report_runs',{'status':'READY','artifacts_json':jsonEncode(artifacts),'error_message':null},where:'id=?',whereArgs:[run['id']]);
      } catch (_) {
        await database.update('report_runs',{'status':'PENDING','error_message':'Local report export failed; check storage and retry.'},where:'id=?',whereArgs:[run['id']]);
      }
    }
  }
}
