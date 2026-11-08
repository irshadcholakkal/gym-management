import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';
import 'period_report.dart';

Future<Uint8List> encodeReport(
    (ReportRow, String, Uint8List?, Uint8List?) request) async {
  final report = PeriodReport(request.$1);
  return switch (request.$2) {
    'pdf' =>
      ReportExports.pdf(report, latinFont: request.$3, arabicFont: request.$4),
    'xlsx' => ReportExports.xlsx(report),
    'csv' => ReportExports.csv(report),
    _ => throw ArgumentError('Unsupported report format'),
  };
}

abstract final class ReportExports {
  static String display(Object value) =>
      value is double ? value.toStringAsFixed(2) : value.toString();

  static Future<Uint8List> pdf(PeriodReport report,
      {Uint8List? latinFont, Uint8List? arabicFont}) async {
    final font =
        latinFont == null ? null : pw.Font.ttf(ByteData.sublistView(latinFont));
    final fallback = arabicFont == null
        ? <pw.Font>[]
        : [pw.Font.ttf(ByteData.sublistView(arabicFont))];
    final document =
        pw.Document(title: '${report.gym} - ${report.label} report');
    for (final table in report.tables) {
      document.addPage(pw.MultiPage(
        theme: font == null
            ? null
            : pw.ThemeData.withFont(
                base: font,
                bold: pw.Font.helveticaBold(),
                italic: font,
                boldItalic: font,
                fontFallback: [font, ...fallback]),
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(28),
        maxPages: 10000,
        header: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(report.gym,
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text(
                  '${report.label} | ${report.timezone} | Generated ${report.generatedAt}',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.SizedBox(height: 12),
            ]),
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                    'Current balances and statuses at generation. Currency totals are separate.',
                    style: const pw.TextStyle(fontSize: 7)),
                pw.Text('Page ${context.pageNumber} / ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 7)),
              ]),
        ),
        build: (_) => [
          pw.Text(table.name,
              style:
                  pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          if (table.rows.isEmpty)
            pw.Text('No records for this period.',
                style: const pw.TextStyle(fontSize: 10))
          else
            pw.TableHelper.fromTextArray(
              headers: table.columns.map((c) => c.label).toList(),
              data: table.rows
                  .map((row) => table.columns
                      .map((c) => display(table.value(row, c)))
                      .toList())
                  .toList(),
              cellStyle:
                  pw.TextStyle(fontSize: table.columns.length > 10 ? 7 : 9),
              headerStyle: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColor.fromInt(0xff245b47)),
              oddRowDecoration:
                  const pw.BoxDecoration(color: PdfColor.fromInt(0xfff2f6f4)),
              cellPadding: const pw.EdgeInsets.all(5),
              columnWidths: {
                for (var i = 0; i < table.columns.length; i++)
                  i: pw.FlexColumnWidth(
                      table.name == 'Overview' && i == 1 ? 3 : 1)
              },
              border: null,
            ),
        ],
      ));
    }
    return document.save();
  }

  /// A standards-based XLSX workbook: numeric money cells and literal text,
  /// with one sheet for every report section. No formula evaluation of names.
  static Uint8List xlsx(PeriodReport report) {
    final archive = Archive();
    void add(String path, String text) =>
        archive.addFile(ArchiveFile.string(path, text));
    final tables = report.tables;
    const main = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
    const rels = 'http://schemas.openxmlformats.org/package/2006/relationships';
    const office =
        'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
    add(
        '[Content_Types].xml',
        '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
            '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
            '<Default Extension="xml" ContentType="application/xml"/>'
            '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
            '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
            '${[
          for (var i = 0; i < tables.length; i++)
            '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        ].join()}'
            '</Types>');
    add('_rels/.rels',
        '<Relationships xmlns="$rels"><Relationship Id="rId1" Type="$office/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    add(
        'xl/workbook.xml',
        '<workbook xmlns="$main" xmlns:r="$office"><sheets>'
            '${[
          for (var i = 0; i < tables.length; i++)
            '<sheet name="${tables[i].name}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'
        ].join()}'
            '</sheets></workbook>');
    add(
        'xl/_rels/workbook.xml.rels',
        '<Relationships xmlns="$rels">'
            '${[
          for (var i = 0; i < tables.length; i++)
            '<Relationship Id="rId${i + 1}" Type="$office/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'
        ].join()}'
            '<Relationship Id="rId${tables.length + 1}" Type="$office/styles" Target="styles.xml"/></Relationships>');
    add('xl/styles.xml', '''<styleSheet xmlns="$main">
      <fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Calibri"/></font></fonts>
      <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF245B47"/><bgColor indexed="64"/></patternFill></fill></fills>
      <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
      <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
      <cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"><alignment vertical="top" wrapText="1"/></xf><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"><alignment wrapText="1"/></xf><xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs>
      <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
    </styleSheet>''');
    for (var i = 0; i < tables.length; i++) {
      final table = tables[i];
      final builder = XmlBuilder();
      builder.processing('xml', 'version="1.0" encoding="UTF-8"');
      builder.element('worksheet', attributes: {'xmlns': main}, nest: () {
        builder.element('sheetViews',
            nest: () => builder.element('sheetView',
                attributes: {'workbookViewId': '0'},
                nest: () => builder.element('pane', attributes: {
                      'ySplit': '1',
                      'topLeftCell': 'A2',
                      'activePane': 'bottomLeft',
                      'state': 'frozen'
                    })));
        builder.element('cols', nest: () {
          for (var c = 0; c < table.columns.length; c++) {
            builder.element('col', attributes: {
              'min': '${c + 1}',
              'max': '${c + 1}',
              'width': table.name == 'Overview' && c == 1 ? '95' : '22',
              'customWidth': '1'
            });
          }
        });
        builder.element('sheetData', nest: () {
          void row(int number, List<Object> cells, {bool header = false}) {
            builder.element('row', attributes: {'r': '$number'}, nest: () {
              for (var c = 0; c < cells.length; c++) {
                final value = cells[c];
                builder.element('c', attributes: {
                  'r': '${_column(c)}$number',
                  's': header
                      ? '1'
                      : value is double
                          ? '2'
                          : '0',
                  't': value is num ? 'n' : 'inlineStr'
                }, nest: () {
                  if (value is num) {
                    builder.element('v', nest: '$value');
                  } else {
                    final cleaned = value.toString().replaceAll(
                        RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
                    builder.element('is',
                        nest: () => builder.element('t',
                            attributes: {'xml:space': 'preserve'},
                            nest: cleaned.substring(
                                0, cleaned.length.clamp(0, 32767))));
                  }
                });
              }
            });
          }

          row(1, table.columns.map((c) => c.label).toList(), header: true);
          for (var r = 0; r < table.rows.length; r++) {
            row(
                r + 2,
                table.columns
                    .map((c) => table.value(table.rows[r], c))
                    .toList());
          }
        });
        builder.element('autoFilter', attributes: {
          'ref':
              'A1:${_column(table.columns.length - 1)}${table.rows.length + 1}'
        });
      });
      add('xl/worksheets/sheet${i + 1}.xml',
          builder.buildDocument().toXmlString());
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  static String _column(int index) {
    var value = index + 1, result = '';
    while (value > 0) {
      result = String.fromCharCode(65 + (value - 1) % 26) + result;
      value = (value - 1) ~/ 26;
    }
    return result;
  }

  /// CSV is a single sectioned document; XLSX provides individual worksheets.
  static Uint8List csv(PeriodReport report) {
    String cell(Object value) {
      var text = display(value);
      if (value is String && RegExp(r'^[\s]*[=+@\-]').hasMatch(text)) {
        text = "'$text";
      }
      return '"${text.replaceAll('"', '""')}"';
    }

    final lines = <String>[];
    for (final table in report.tables) {
      lines.add(cell(table.name));
      lines.add(table.columns.map((c) => cell(c.label)).join(','));
      lines.addAll(table.rows.map((row) =>
          table.columns.map((c) => cell(table.value(row, c))).join(',')));
      lines.add('');
    }
    return Uint8List.fromList(utf8.encode('\uFEFF${lines.join('\r\n')}'));
  }
}
