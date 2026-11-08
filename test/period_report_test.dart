import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/reports/domain/period_report.dart';
import 'package:gym_saas/features/reports/domain/report_exports.dart';
import 'package:xml/xml.dart';

PeriodReport reportFixture({bool yearly = false}) => PeriodReport({
      'gym_name': 'Report Gym',
      'timezone': 'Asia/Dubai',
      'currency': 'AED',
      'generated_at': '2026-11-08 14:30',
      'start_date': '2026-01-01',
      'end_exclusive': yearly ? '2027-01-01' : '2026-02-01',
      'invoices': [
        {
          'invoice_number': 1,
          'date': '2026-01-31',
          'due_date': '2026-02-01',
          'member_number': 7,
          'member_name': 'Amina',
          'currency': 'AED',
          'subtotal_minor': 10000,
          'discount_minor': 1000,
          'tax_minor': 450,
          'total_minor': 9450,
          'paid_minor': 5000,
          'credit_minor': 1000,
          'balance_minor': 3450,
          'status': 'partially_paid'
        },
        {
          'invoice_number': 2,
          'date': '2026-01-10',
          'currency': 'AED',
          'total_minor': 99999,
          'status': 'voided'
        },
        {
          'invoice_number': 3,
          'date': '2026-01-15',
          'currency': 'USD',
          'total_minor': 3000,
          'balance_minor': 3000,
          'status': 'unpaid'
        },
      ],
      'payments': [
        {
          'date': '2026-01-31',
          'receipt_number': 5,
          'member_number': 7,
          'member_name': 'Amina',
          'currency': 'AED',
          'amount_minor': 5000,
          'method': 'cash',
          'reference': 'Paid',
          'reversed': true
        },
        if (yearly)
          {
            'date': '2026-02-10',
            'currency': 'USD',
            'amount_minor': 2000,
            'method': 'cash'
          },
      ],
      'reversals': [
        {
          'date': '2026-01-15',
          'member_name': 'Older member',
          'currency': 'AED',
          'amount_minor': 2000,
          'kind': 'refund',
          'reason': 'December payment'
        },
        if (yearly)
          {
            'date': '2026-02-15',
            'currency': 'AED',
            'amount_minor': 5000,
            'kind': 'reversal'
          },
      ],
      'receipts': [
        {
          'date': '2026-01-31',
          'receipt_number': 5,
          'member_name': 'Amina',
          'currency': 'AED',
          'amount_minor': 5000,
          'status': 'voided'
        }
      ],
      'members': [
        {
          'member_name': '=HYPERLINK("https://example.test")',
          'member_number': 7,
          'date': '2026-01-01',
          'phone': '+971501234567',
          'email': 'a@example.test',
          'status': 'active'
        }
      ],
      'memberships': [
        {
          'member_name': 'Amina',
          'member_number': 7,
          'package_name': 'Monthly',
          'date': '2026-01-01',
          'valid_through': '2026-01-31',
          'status': 'expired'
        }
      ],
      'invoice_credits': [],
      'member_credits': [],
    });

void main() {
  test('Empty yearly periods keep twelve months and export zero totals', () {
    final report = PeriodReport({
      'gym_name': 'Empty gym',
      'timezone': 'Asia/Dubai',
      'currency': 'AED',
      'generated_at': '2026-11-08 14:30',
      'start_date': '2024-01-01',
      'end_exclusive': '2025-01-01',
    });
    expect(report.totals.single['net'], 0);
    expect(report.monthlyBreakdown.length, 12);
    expect(report.tables.first.rows.first['value'], 'Empty gym');
    expect(ReportExports.xlsx(report).take(2), [80, 75]);
  });
  test(
      'Totals keep currencies separate and count reversals in their own period',
      () {
    final report = reportFixture();
    final aed = report.totals.firstWhere((r) => r['currency'] == 'AED');
    expect(aed['billed'], 94.5);
    expect(aed['discount'], 10);
    expect(aed['tax'], 4.5);
    expect(aed['balance'], 34.5);
    expect(aed['collections'], 50);
    expect(aed['reversals'], 20);
    expect(aed['net'], 30);
    expect(
        report.totals.firstWhere((r) => r['currency'] == 'USD')['billed'], 30);
    final annual = reportFixture(yearly: true);
    expect(
        annual.monthlyBreakdown
            .where((r) => r['month'] == '2026-02' && r['currency'] == 'AED')
            .single['net'],
        -50);
    expect(annual.totals.firstWhere((r) => r['currency'] == 'AED')['net'], -20);
    expect(annual.label, '2026');
    expect(report.label, 'January 2026');
  });

  test(
      'XLSX contains every section, numeric amounts and safe literal member text',
      () {
    final report = reportFixture();
    final archive = ZipDecoder().decodeBytes(ReportExports.xlsx(report));
    XmlDocument part(String name) =>
        XmlDocument.parse(utf8.decode(archive.findFile(name)!.content));
    final workbook = part('xl/workbook.xml');
    expect(workbook.findAllElements('sheet').length, report.tables.length);
    for (var i = 0; i < report.tables.length; i++) {
      final sheet = part('xl/worksheets/sheet${i + 1}.xml');
      expect(sheet.findAllElements('row').length,
          report.tables[i].rows.length + 1);
      expect(sheet.findAllElements('f'), isEmpty);
    }
    final invoices = part('xl/worksheets/sheet4.xml');
    final total = invoices
        .findAllElements('c')
        .firstWhere((c) => c.getAttribute('r') == 'J2');
    expect(total.getAttribute('t'), 'n');
    expect(total.findElements('v').single.innerText, '94.5');
    final members = part('xl/worksheets/sheet8.xml');
    expect(members.findAllElements('t').map((t) => t.innerText),
        contains('=HYPERLINK("https://example.test")'));
  });

  test('CSV has real line endings, UTF-8 BOM, escaping and formula protection',
      () {
    final bytes = ReportExports.csv(reportFixture());
    expect(bytes.take(3), [239, 187, 191]);
    final csv = utf8.decode(bytes);
    expect(csv, contains('\r\n'));
    expect(csv, contains('"\'=HYPERLINK(""https://example.test"")"'));
    expect(csv, contains('"\'+971501234567"'));
    expect(csv, contains('94.50'));
  });

  test('PDF and Excel export complete reports including long detail tables',
      () async {
    final report = reportFixture();
    report.data['members'] = [
      ...report.rows('members'),
      for (var i = 0; i < 125; i++)
        {
          'member_name': 'Member $i',
          'member_number': i + 8,
          'date': '2026-01-01',
          'status': 'active'
        }
    ];
    final pdf = await ReportExports.pdf(report,
        latinFont: File('assets/fonts/NotoSans-Regular.ttf').readAsBytesSync(),
        arabicFont:
            File('assets/fonts/NotoSansArabic-Regular.ttf').readAsBytesSync());
    expect(ascii.decode(pdf.take(5).toList()), '%PDF-');
    final dir = Directory('artifacts')..createSync(recursive: true);
    File('${dir.path}/period-report-preview.pdf').writeAsBytesSync(pdf);
    File('${dir.path}/period-report-preview.xlsx')
        .writeAsBytesSync(ReportExports.xlsx(report));
    File('${dir.path}/period-report-preview.json')
        .writeAsStringSync(jsonEncode(report.data));
  });
}
