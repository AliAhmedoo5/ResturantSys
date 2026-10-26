import 'dart:math' as math;
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'z_report.dart';

/// Sends the report to the OS print dialog, including installed Windows printers.
class ZReportPrinter {
  const ZReportPrinter();

  Future<bool> printReport(ZReport report) => Printing.layoutPdf(
    name: 'Z-Report Business Day ${report.businessDayId}',
    usePrinterSettings: true,
    onLayout: (format) => buildDocument(report, format),
  );

  Future<Uint8List> buildDocument(ZReport report, PdfPageFormat format) async {
    final pdf = pw.Document(title: 'Z-Report Business Day ${report.businessDayId}');
    // Fit the 42-column slip on receipt paper as well as full-size office paper.
    final left = math.max(12.0, format.marginLeft);
    final right = math.max(12.0, format.marginRight);
    final fontSize = math.min(11.0, (format.width - left - right) / (42 * 0.6));
    pdf.addPage(pw.MultiPage(
      pageFormat: format,
      margin: pw.EdgeInsets.fromLTRB(left, math.max(12.0, format.marginTop),
          right, math.max(12.0, format.marginBottom)),
      build: (_) => report.toPrintableString().split('\n').map((line) => pw.Text(
        line.isEmpty ? ' ' : line,
        style: pw.TextStyle(font: pw.Font.courier(), fontSize: fontSize),
      )).toList(),
    ));
    return pdf.save();
  }
}
