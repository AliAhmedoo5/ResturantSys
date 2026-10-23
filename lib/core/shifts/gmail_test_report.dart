import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'excel_reporting_engine.dart';

/// Synthetic attachments exercise the same PDF/XLSX email path without reading
/// sales, opening a Business Day, or creating financial records.
Future<List<Map<String, dynamic>>> createGmailTestAttachments(
  Database database, Directory directory,
) async {
  final document = pw.Document();
  document.addPage(pw.Page(build: (_) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('Restaurant POS - Gmail setup test', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 16),
      pw.Text('This is a synthetic attachment. It contains no restaurant financial data.'),
      pw.SizedBox(height: 8),
      pw.Text('Receiving this PDF and the Excel sample confirms the attachment delivery path.'),
    ],
  )));
  final sections = List<Map<String, dynamic>>.generate(6, (index) => {
    'title': 'Gmail setup sample ${index + 1} - not a financial report',
    'headers': <String>['Check', 'Value'],
    'rows': <List<String>>[['Purpose', 'Synthetic email setup test'], ['Business data', 'None']],
  });
  final outputs = <String, List<int>>{
    'pdf': await document.save(),
    'xlsx': ExcelReportingEngine(database: database).generateSnapshotWorkbook(sections),
  };
  final artifacts = <Map<String, dynamic>>[];
  for (final output in outputs.entries) {
    final file = File('${directory.path}/gmail-setup-sample.${output.key}');
    await file.writeAsBytes(output.value, flush: true);
    artifacts.add({'kind': output.key, 'path': file.path,
      'sha256': sha256.convert(output.value).toString(), 'size_bytes': output.value.length});
  }
  return artifacts;
}
