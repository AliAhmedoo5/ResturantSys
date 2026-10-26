import 'package:archive/archive.dart';

import 'analytics_models.dart';

/// Serializes the displayed immutable snapshot without querying operational data.
class AnalyticsExportService {
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
    ['report_version', 'manager-analytics-v1'],
    ['report_kind', 'Exploratory current-record snapshot; not a sealed Z-report'],
    ['family', family], ['currency', 'PKR; monetary numbers are integer paisa (100 paisa = PKR 1)'],
    ['generated_utc', s.generatedAt.toUtc().toIso8601String()],
    ['generated_local', '${s.generatedAt.toUtc().add(const Duration(hours: 5)).toIso8601String().replaceAll('Z', '')}+05:00'],
    ['timezone', 'Asia/Karachi'], ['generated_by_staff_id', s.generatedByStaffId],
    ['business_date_start', _date(s.query.startDate)],
    ['business_date_end_exclusive', _date(s.query.endDateExclusive)],
    ['business_day_ids', s.businessDayIds.join(';')], ['live', s.query.live.toString()],
    ['cashier_id', s.query.cashierId], ['shift_id', s.query.shiftId],
    ['dining_type', s.query.diningType], ['payment_method', s.query.paymentMethod],
    ['time_basis', 'Orders/shifts/trips use Business Day IDs; timestamp events use selected actual Business Day intervals. Current stock is current.'],
    ['filter_scope', 'Order filters apply to order-derived datasets only; each section discloses its scope.'],
    for (final note in s.notes) ['snapshot_note', note],
  ];

  List<List<Object?>> _sectionRows(AnalyticsSection s) => [
    ['section', s.title],
    for (final note in s.notes) ['section_note', note],
    ['Metric ID', 'Metric', 'Value', 'Unit', 'Quality', 'Formula / explanation', 'Sample count', 'Population count', 'Change percent'],
    for (final m in s.metrics) [m.id, m.label, m.value, m.unit.name, m.quality.name, m.explanation, m.sampleCount, m.populationCount, m.changePercent],
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

