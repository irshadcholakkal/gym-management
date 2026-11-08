import 'package:intl/intl.dart';
import '../../members/member_identity.dart';
import '../../receipts/domain/invoice_html.dart';

typedef ReportRow = Map<String, dynamic>;

class ReportColumn {
  const ReportColumn(this.key, this.label, {this.money = false});
  final String key, label;
  final bool money;
}

class ReportTable {
  const ReportTable(this.name, this.columns, this.rows);
  final String name;
  final List<ReportColumn> columns;
  final List<ReportRow> rows;
  Object value(ReportRow row, ReportColumn column) {
    final raw = row[column.key];
    if (column.money) return PeriodReport.minor(raw) / 100;
    if (column.key == 'invoice_number') return InvoiceHtml.number(raw);
    if (column.key == 'member_number') return memberId(raw);
    return raw ?? '';
  }
}

class PeriodReport {
  PeriodReport(this.data);
  final ReportRow data;
  String get gym => data['gym_name'] as String;
  String get timezone => data['timezone'] as String;
  String get generatedAt => data['generated_at'] as String;
  DateTime get start => DateTime.parse(data['start_date'] as String);
  DateTime get end => DateTime.parse(data['end_exclusive'] as String);
  bool get yearly => end.difference(start).inDays > 31;
  String get label => DateFormat(yearly ? 'yyyy' : 'MMMM yyyy').format(start);
  String get filename =>
      'gym-report-${DateFormat(yearly ? 'yyyy' : 'yyyy-MM').format(start)}';
  static int minor(Object? value) => (value as num? ?? 0).toInt();
  List<ReportRow> rows(String key) => (data[key] as List? ?? [])
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();

  static const notes =
      'Dates use the gym timezone. Invoices use issue date; collections and reversals use their recorded dates. '
      'A reversal reduces collections in the period it was recorded, including reversals of older payments. '
      'Voided invoices are excluded from billing totals. Invoice amounts, balances, member details and statuses '
      'are current at generation, not historical closing balances. Memberships use start date; members use joining date. '
      'Credits are non-cash and are not included in collections. This report does not include expenses or profit. '
      'Only server-saved records are included; sync pending changes before generating.';

  List<ReportRow> get totals => _totals(null);

  List<ReportRow> _totals(String? month) {
    final groups = <String, ReportRow>{};
    ReportRow group(String currency) => groups.putIfAbsent(
        currency,
        () => {
              'currency': currency,
              'subtotal': 0,
              'discount': 0,
              'tax': 0,
              'billed': 0,
              'paid': 0,
              'credits': 0,
              'balance': 0,
              'collections': 0,
              'reversals': 0,
              'net': 0,
            });
    bool includes(ReportRow row) =>
        month == null || row['date'].toString().startsWith(month);
    for (final row in rows('invoices').where(includes)) {
      if (row['status'] == 'voided') continue;
      final target = group(row['currency'] as String);
      for (final pair in const {
        'subtotal': 'subtotal_minor',
        'discount': 'discount_minor',
        'tax': 'tax_minor',
        'billed': 'total_minor',
        'paid': 'paid_minor',
        'credits': 'credit_minor',
        'balance': 'balance_minor',
      }.entries) {
        target[pair.key] = minor(target[pair.key]) + minor(row[pair.value]);
      }
    }
    for (final kind in ['payments', 'reversals']) {
      for (final row in rows(kind).where(includes)) {
        final target = group(row['currency'] as String);
        final key = kind == 'payments' ? 'collections' : 'reversals';
        target[key] = minor(target[key]) + minor(row['amount_minor']);
      }
    }
    // Include currencies that have credit activity but no cash/billing activity.
    for (final kind in ['invoice_credits', 'member_credits']) {
      for (final row in rows(kind).where(includes)) {
        group(row['currency'] as String);
      }
    }
    if (groups.isEmpty) group(data['currency'] as String? ?? 'AED');
    for (final row in groups.values) {
      row['net'] = minor(row['collections']) - minor(row['reversals']);
      for (final key in [
        'subtotal',
        'discount',
        'tax',
        'billed',
        'paid',
        'credits',
        'balance',
        'collections',
        'reversals',
        'net'
      ]) {
        row[key] = minor(row[key]) / 100;
      }
      if (month != null) row['month'] = month;
    }
    return groups.values.toList()
      ..sort((a, b) => '${a['currency']}'.compareTo('${b['currency']}'));
  }

  List<ReportRow> get monthlyBreakdown => [
        for (var month = start.month;
            month <= (yearly ? 12 : start.month);
            month++)
          ..._totals('${start.year}-${month.toString().padLeft(2, '0')}'),
      ];

  static const totalColumns = [
    ReportColumn('currency', 'Currency'),
    ReportColumn('subtotal', 'Subtotal'),
    ReportColumn('discount', 'Discount'),
    ReportColumn('tax', 'Tax'),
    ReportColumn('billed', 'Billed'),
    ReportColumn('paid', 'Paid currently'),
    ReportColumn('credits', 'Credit currently'),
    ReportColumn('balance', 'Balance currently'),
    ReportColumn('collections', 'Gross collections'),
    ReportColumn('reversals', 'Reversals'),
    ReportColumn('net', 'Net collections'),
  ];

  List<ReportTable> get tables => [
        ReportTable('Overview', const [
          ReportColumn('metric', 'Metric'),
          ReportColumn('value', 'Value')
        ], [
          {'metric': 'Gym', 'value': gym},
          {'metric': 'Period', 'value': label},
          {'metric': 'Timezone', 'value': timezone},
          {'metric': 'Generated at', 'value': generatedAt},
          {'metric': 'Invoices issued', 'value': rows('invoices').length},
          {'metric': 'Payments received', 'value': rows('payments').length},
          {'metric': 'Reversals recorded', 'value': rows('reversals').length},
          {'metric': 'Receipts issued', 'value': rows('receipts').length},
          {'metric': 'New members', 'value': rows('members').length},
          {'metric': 'Membership starts', 'value': rows('memberships').length},
          {'metric': 'Report basis', 'value': notes},
        ]),
        ReportTable('Totals', totalColumns, totals),
        ReportTable(
            'Monthly breakdown',
            [const ReportColumn('month', 'Month'), ...totalColumns],
            monthlyBreakdown),
        ReportTable(
            'Invoices',
            const [
              ReportColumn('invoice_number', 'Invoice'),
              ReportColumn('date', 'Issued'),
              ReportColumn('due_date', 'Due'),
              ReportColumn('member_number', 'Member ID'),
              ReportColumn('member_name', 'Member'),
              ReportColumn('currency', 'Currency'),
              ReportColumn('subtotal_minor', 'Subtotal', money: true),
              ReportColumn('discount_minor', 'Discount', money: true),
              ReportColumn('tax_minor', 'Tax', money: true),
              ReportColumn('total_minor', 'Total', money: true),
              ReportColumn('paid_minor', 'Paid currently', money: true),
              ReportColumn('credit_minor', 'Credit currently', money: true),
              ReportColumn('balance_minor', 'Balance currently', money: true),
              ReportColumn('status', 'Current status'),
            ],
            rows('invoices')),
        ReportTable(
            'Payments',
            const [
              ReportColumn('date', 'Date'),
              ReportColumn('receipt_number', 'Receipt'),
              ReportColumn('member_number', 'Member ID'),
              ReportColumn('member_name', 'Member'),
              ReportColumn('currency', 'Currency'),
              ReportColumn('amount_minor', 'Amount', money: true),
              ReportColumn('method', 'Method'),
              ReportColumn('reference', 'Reference'),
              ReportColumn('reversed', 'Reversed currently'),
            ],
            rows('payments')),
        ReportTable(
            'Reversals',
            const [
              ReportColumn('date', 'Date'),
              ReportColumn('member_number', 'Member ID'),
              ReportColumn('member_name', 'Member'),
              ReportColumn('currency', 'Currency'),
              ReportColumn('amount_minor', 'Amount', money: true),
              ReportColumn('kind', 'Type'),
              ReportColumn('reason', 'Reason'),
              ReportColumn('payment_id', 'Payment reference'),
            ],
            rows('reversals')),
        ReportTable(
            'Receipts',
            const [
              ReportColumn('receipt_number', 'Receipt'),
              ReportColumn('date', 'Date'),
              ReportColumn('member_name', 'Member'),
              ReportColumn('currency', 'Currency'),
              ReportColumn('amount_minor', 'Amount', money: true),
              ReportColumn('status', 'Current status'),
            ],
            rows('receipts')),
        ReportTable(
            'New members',
            const [
              ReportColumn('member_number', 'Member ID'),
              ReportColumn('member_name', 'Member'),
              ReportColumn('date', 'Joined'),
              ReportColumn('phone', 'Phone'),
              ReportColumn('email', 'Email'),
              ReportColumn('status', 'Current status'),
            ],
            rows('members')),
        ReportTable(
            'Membership starts',
            const [
              ReportColumn('member_number', 'Member ID'),
              ReportColumn('member_name', 'Member'),
              ReportColumn('package_name', 'Package'),
              ReportColumn('date', 'Start date'),
              ReportColumn('valid_through', 'Valid through currently'),
              ReportColumn('status', 'Current status'),
            ],
            rows('memberships')),
        ReportTable(
            'Invoice credits',
            const [
              ReportColumn('date', 'Date'),
              ReportColumn('invoice_number', 'Invoice'),
              ReportColumn('member_name', 'Member'),
              ReportColumn('currency', 'Currency'),
              ReportColumn('amount_minor', 'Credit amount', money: true),
              ReportColumn('reason', 'Reason'),
            ],
            rows('invoice_credits')),
        ReportTable(
            'Member credit ledger',
            const [
              ReportColumn('date', 'Date'),
              ReportColumn('member_name', 'Member'),
              ReportColumn('currency', 'Currency'),
              ReportColumn('amount_minor', 'Credit change', money: true),
              ReportColumn('kind', 'Type'),
            ],
            rows('member_credits')),
      ];
}
