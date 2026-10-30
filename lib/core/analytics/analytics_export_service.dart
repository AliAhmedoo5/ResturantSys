import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:archive/archive.dart';

import 'analytics_models.dart';

enum AnalyticsExportFormat { csv, xlsx, pdf }

/// Serializes the displayed immutable snapshot without querying operational data.
class AnalyticsExportService {
  Future<List<int>> pdf(AnalyticsSnapshot snapshot, AnalyticsFamily family) async {
    final section = snapshot.section(family);
    final document = pw.Document(title: 'Manager analytics - ${section.title}', author: 'Staff ${snapshot.generatedByStaffId ?? "unknown"}');
    final lines = <String>[
      ..._metadata(snapshot, family.name).map((r) => '${r[0]}: ${r[1] ?? "Unknown"}'),
      ...section.notes.map((note) => 'Section note: $note'),
      for (final metric in section.metrics) ...[
        '${metric.label}: ${_pdfValue(metric.value, metric.unit)} [${metric.quality.name}]',
        'Formula / explanation: ${metric.explanation}',
        'Coverage: ${metric.sampleCount ?? "unknown"} / ${metric.populationCount ?? "unknown"}; change percent: ${metric.changePercent ?? "unavailable"}',
        'Absolute change: ${metric.changeAbsolute == null ? "unavailable" : _pdfValue(metric.changeAbsolute, metric.unit)}',
      ],
      'Source details (${section.rows.length} rows)',
      for (final row in section.rows) ...[
        '${row.sourceType} / ${row.sourceId ?? row.id} (row ${row.id})',
        for (final col in section.columns) '${col.label}: ${_pdfValue(row.cells[col.key], col.unit)}',
      ],
    ];
    // Small independent text blocks can flow across pages, even for long notes.
    final blocks = <String>[];
    for (final line in lines) {
      for (var i = 0; i < line.length; i += 160) {
        blocks.add(line.substring(i, (i + 160).clamp(0, line.length)));
      }
    }
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4, maxPages: 100000,
      header: (_) => pw.Text('Manager analytics / ${section.title}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      footer: (context) => pw.Text('Exploratory snapshot | Page ${context.pageNumber} of ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
      build: (_) => [for (final block in blocks) pw.Padding(padding: const pw.EdgeInsets.only(bottom: 4), child: pw.Text(block, style: const pw.TextStyle(fontSize: 9)))],
    ));
    return document.save();
  }

  String _pdfValue(Object? value, AnalyticsUnit? unit) {
    if (value == null) return 'Missing data';
    if (unit == AnalyticsUnit.paisa && value is num) return 'PKR ${(value / 100).toStringAsFixed(2)}';
    return '$value${unit == null ? "" : " ${unit.name}"}';
  }

  /// Writes only to a directory deliberately selected by the caller. No delivery.
  Future<File> saveToDirectory(AnalyticsSnapshot snapshot, AnalyticsFamily family,
      AnalyticsExportFormat format, String directory, {bool Function()? canWrite}) async {
    final bytes = switch (format) {
      AnalyticsExportFormat.csv => utf8.encode(csv(snapshot, family)),
      AnalyticsExportFormat.xlsx => workbook(snapshot),
      AnalyticsExportFormat.pdf => await pdf(snapshot, family),
    };
    if (canWrite != null && !canWrite()) throw StateError('Export authorization expired.');
    if (!await Directory(directory).exists()) throw FileSystemException('Selected export directory is unavailable.', directory);
    final base = 'manager-analytics-${family.name}-${DateTime.now().toUtc().microsecondsSinceEpoch}';
    var suffix = 0;
    var target = File(p.join(directory, '$base.${format.name}'));
    while (await target.exists()) {
      target = File(p.join(directory, '$base-${++suffix}.${format.name}'));
    }
    final partial = File('${target.path}.partial');
    try {
      if (canWrite != null && !canWrite()) throw StateError('Export authorization expired.');
      await partial.writeAsBytes(bytes, flush: true);
      if (canWrite != null && !canWrite()) throw StateError('Export authorization expired.');
      return await partial.rename(target.path);
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }

  List<int> workbook(AnalyticsSnapshot snapshot) {
    final sheets = <String, List<List<Object?>>>{
      'Metadata': _metadata(snapshot, 'all snapshot families'),
      for (final section in snapshot.sections) section.family.name: _sectionRows(section),
    };
    final zip = Archive();
    void add(String path, String xml) => zip.addFile(ArchiveFile.string(path, '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>$xml'));
    add('[Content_Types].xml', '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${List.generate(sheets.length, (i) => '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>').join()}</Types>');
    add('_rels/.rels', '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    add('xl/workbook.xml', '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${List.generate(sheets.length, (i) => '<sheet name="${_xml(sheets.keys.elementAt(i))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>').join()}</sheets></workbook>');
    add('xl/_rels/workbook.xml.rels', '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${List.generate(sheets.length, (i) => '<Relationship Id="rId${i + 1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i + 1}.xml"/>').join()}</Relationships>');
    for (var sheet = 0; sheet < sheets.length; sheet++) {
      final rows = sheets.values.elementAt(sheet);
      final xml = StringBuffer('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>');
      for (var r = 0; r < rows.length; r++) {
        xml.write('<row r="${r + 1}">');
        for (var c = 0; c < rows[r].length; c++) {
          final value = rows[r][c];
          final ref = '${_column(c)}${r + 1}';
          xml.write(value is num && value.isFinite
            ? '<c r="$ref"><v>$value</v></c>'
            : '<c r="$ref" t="inlineStr"><is><t xml:space="preserve">${_xml(_safeText(value))}</t></is></c>');
        }
        xml.write('</row>');
      }
      xml.write('</sheetData></worksheet>');
      add('xl/worksheets/sheet${sheet + 1}.xml', xml.toString());
    }
    return ZipEncoder().encode(zip)!;
  }

  String _xml(String value) => value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '').replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&apos;');
  String _column(int index) {
    var result = '';
    for (var n = index + 1; n > 0; n = (n - 1) ~/ 26) {
      result = String.fromCharCode(65 + (n - 1) % 26) + result;
    }
    return result;
  }

  String csv(AnalyticsSnapshot snapshot, AnalyticsFamily family) =>
      [..._metadata(snapshot, family.name), ..._sectionRows(snapshot.section(family))]
          .map((row) => row.map(_csvCell).join(',')).join('\r\n');

  List<List<Object?>> _metadata(AnalyticsSnapshot s, String family) => [
    ['report_version', s.reportVersion],
    ['source_schema_version', s.sourceSchemaVersion ?? 'Unavailable'],
    ['snapshot_cutoff_utc', s.generatedAt.toUtc().toIso8601String()],
    ['timestamp_policy', 'Asia/Karachi UTC+05:00; naive legacy values assumed Karachi; original UTC/offset values retained in source columns'],
    ['identity_policy', 'At-transaction names are retained evidence; current names are separately labeled; unavailable history is not backfilled'],
    ['report_kind', 'Exploratory current-record snapshot; not a sealed Z-report'],
    ['family', family], ['currency', 'PKR; money amounts use integer paisa (100 paisa = PKR 1); decimal unit rates retain labeled PKR/base-unit precision'],
    ['generated_utc', s.generatedAt.toUtc().toIso8601String()],
    ['generated_local', '${s.generatedAt.toUtc().add(const Duration(hours: 5)).toIso8601String().replaceAll('Z', '')}+05:00'],
    ['timezone', 'Asia/Karachi'], ['generated_by_staff_id', s.generatedByStaffId],
    ['business_date_start', _date(s.query.startDate)],
    ['business_date_end_exclusive', _date(s.query.endDateExclusive)],
    ['query_start_inclusive', '${s.query.startDate.toIso8601String().replaceAll('Z', '')}+05:00'],
    ['query_end_exclusive', '${s.query.endDateExclusive.toIso8601String().replaceAll('Z', '')}+05:00'],
    ['business_day_ids', s.businessDayIds.join(';')], ['live', s.query.live.toString()],
    ['cashier_id', s.query.cashierId], ['shift_id', s.query.shiftId],
    ['dining_type', s.query.diningType], ['payment_method', s.query.paymentMethod],
    ['funding_stream', s.query.fundingStream],
    for (final entry in s.query.domainFilters.entries)
      ['domain_filter_${entry.key.name}', entry.value,
        s.filterOptions.where((o) => o.dimension == entry.key && o.id == entry.value).firstOrNull?.label ?? 'Unknown / archived ID'],
    ['time_basis', s.query.timeBasis.name],
    ['grouping', s.query.grouping.name],
    ['hold_stale_threshold_minutes', s.query.holdStaleMinutes],
    ['bucket_definitions', 'Asia/Karachi; start inclusive, end exclusive; Business Day weekday = assigned opening date; calendar weekday = actual creation date; weeks start Monday; months = local calendar months.'],
    ['non_order_scope', 'Shifts/trips and non-order ledgers retain Business Day scope; current stock is current.'],
    ['filter_scope', 'Order cohorts, receiving/owning drawers and current Hold ownership have distinct scopes; each section discloses applicable filters. Current Holds use Cashier ownership only and ignore historical date/Shift/order predicates.'],
    for (final note in s.notes) ['snapshot_note', note],
  ];

  List<List<Object?>> _sectionRows(AnalyticsSection s) => [
    ['section', s.title],
    ['source_row_count', s.rows.length],
    ['metric_count', s.metrics.length],
    for (final note in s.notes) ['section_note', note],
    ['Metric ID', 'Metric', 'Value', 'Unit', 'Quality', 'Formula / explanation', 'Sample count', 'Population count', 'Change percent', 'Change absolute'],
    for (final m in s.metrics) [m.id, m.label, m.value, m.unit.name, m.quality.name, m.explanation, m.sampleCount, m.populationCount, m.changePercent, m.changeAbsolute],
    ['Row ID', 'Source type', 'Source ID', ...s.columns.map((c) => c.unit == null ? c.label : '${c.label} (${c.unit!.name})')],
    for (final row in s.rows) [row.id, row.sourceType, row.sourceId, ...s.columns.map((c) => row.cells[c.key])],
  ];

  String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _safeText(Object? value) {
    final text = value?.toString() ?? '';
    return RegExp(r'^(?:[\t\r\n]|\s*[=+\-@])').hasMatch(text) ? "'$text" : text;
  }
  String _csvCell(Object? value) {
    final text = value is num ? value.toString() : _safeText(value);
    return text.contains(RegExp('[,"\r\n]')) ? '"${text.replaceAll('"', '""')}"' : text;
  }
}
