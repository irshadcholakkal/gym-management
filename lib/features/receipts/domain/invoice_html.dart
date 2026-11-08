import 'dart:convert';
import '../../members/member_identity.dart';
import '../../payments/domain/money.dart';

abstract final class InvoiceHtml {
  static const defaultDesign = '''<!doctype html>
<html><head><meta charset="utf-8"><style>
@page { size: A4; margin: 16mm; }
* { box-sizing: border-box; }
body { font: 14px Arial,sans-serif; color:#222; padding:24px; margin:0; }
header { display:flex; justify-content:space-between; gap:24px; border-bottom:2px solid #222; padding-bottom:20px; }
h1 { margin:0 0 8px; font-size:26px; } h2 { margin:0 0 8px; font-size:18px; }
p { line-height:1.6; } .muted { color:#666; font-size:12px; }
table { width:100%; border-collapse:collapse; margin:24px 0; }
td,th { padding:12px; border-bottom:1px solid #ddd; text-align:left; }
th { background:#f5f5f5; } td:last-child,th:last-child { text-align:right; }
.totals { margin-left:auto; max-width:380px; } .balance { font-weight:bold; background:#f5f5f5; }
footer { margin-top:32px; font-size:12px; color:#666; }
</style></head><body>
<header><div><h1>{{gym_name}}</h1><p>{{gym_address}}<br>{{gym_phone}}</p></div>
<div><h2>{{invoice_status}}</h2><p>{{invoice_number}}<br>Issued: {{issued_at}}<br>Due: {{due_date}}</p></div></header>
<p><strong>Bill to: {{member_name}}</strong><br>Member ID: {{member_number}}<br>{{member_email}}<br>{{member_phone}}</p>
<p>{{package_name}}<br>{{start_date}} to {{end_date}}</p>
<table><thead><tr><th>Description</th><th>Amount before tax</th></tr></thead><tbody>{{items}}</tbody></table>
<table class="totals"><tbody>
<tr><td>Subtotal</td><td>{{subtotal}}</td></tr><tr><td>Discount</td><td>{{discount}}</td></tr>
<tr><td>Tax</td><td>{{tax}}</td></tr><tr><td>Invoice total</td><td>{{total}}</td></tr>
<tr><td>Payments received</td><td>{{paid}}</td></tr><tr><td>Credit applied</td><td>{{credit}}</td></tr>
<tr class="balance"><td>Balance due</td><td>{{balance}}</td></tr></tbody></table>
<p>Status: {{status}}</p><footer>This invoice is not a payment receipt. Reference: {{invoice_id}}</footer>
</body></html>''';
  static const placeholders = [
    'gym_name',
    'gym_address',
    'gym_phone',
    'invoice_status',
    'invoice_number',
    'invoice_id',
    'issued_at',
    'due_date',
    'member_name',
    'member_number',
    'member_email',
    'member_phone',
    'package_name',
    'start_date',
    'end_date',
    'items',
    'subtotal',
    'discount',
    'tax',
    'total',
    'paid',
    'credit',
    'balance',
    'currency',
    'status'
  ];
  static String? validate(String html) {
    if (html.trim().isEmpty) return 'Enter an invoice design.';
    if (html.length > 100000) {
      return 'Keep the design below 100,000 characters.';
    }
    for (final match in RegExp(r'\{\{\s*(\w+)\s*\}\}').allMatches(html)) {
      if (!placeholders.contains(match[1])) {
        return 'Unknown placeholder: ${match[1]}';
      }
    }
    for (final key in [
      'invoice_number',
      'member_name',
      'items',
      'total',
      'paid',
      'balance'
    ]) {
      if (!RegExp(r'\{\{\s*' + key + r'\s*\}\}').hasMatch(html)) {
        return 'Include {{$key}} in the design.';
      }
    }
    return null;
  }

  static String number(Object? value) =>
      value == null ? '' : 'INV-${value.toString().padLeft(4, '0')}';
  static String render(String template, Map<String, dynamic> invoice) {
    if (invoice['invoice_number'] == null ||
        invoice['snapshot'] is! Map ||
        invoice['items'] is! List) {
      throw ArgumentError('A stored server invoice is required');
    }
    final data = Map<String, dynamic>.from(invoice['snapshot'] as Map);
    final currency = data['currency'] as String? ?? 'AED';
    String money(String key) => Money.format(data[key] as int? ?? 0, currency);
    String escape(Object? value) =>
        const HtmlEscape().convert(value?.toString() ?? '');
    String date(Object? value) =>
        DateTime.tryParse(value?.toString() ?? '')
            ?.toIso8601String()
            .substring(0, 10) ??
        '';
    final end = DateTime.tryParse(data['end_exclusive']?.toString() ?? '')
        ?.subtract(const Duration(days: 1));
    final lines = invoice['items'] as List;
    final rows = lines.isEmpty
        ? '<tr><td>${escape(data['package_name'] ?? 'Invoice')}</td><td>${escape(Money.format((data['total_minor'] as int? ?? 0) - (data['tax_minor'] as int? ?? 0), currency))}</td></tr>'
        : lines
            .map((item) =>
                '<tr><td>${escape(item['description'])}</td><td>${escape(Money.format(item['amount_minor'] as int, currency))}</td></tr>')
            .join();
    final values = <String, Object?>{
      ...data,
      'invoice_number': number(invoice['invoice_number']),
      'invoice_id': invoice['id'],
      'invoice_status': invoice['status'] == 'voided'
          ? 'VOIDED INVOICE'
          : invoice['status'] == 'sample'
              ? 'SAMPLE INVOICE'
              : 'INVOICE',
      'issued_at': date(invoice['created_at']),
      'due_date': date(invoice['due_date']),
      'member_number': memberId(data['member_number']),
      'member_name': RegExp(r'\{\{\s*member_number\s*\}\}').hasMatch(template)
          ? data['member_name']
          : memberNameWithId(data),
      'start_date': date(data['start_date']),
      'end_date': date(end),
      'subtotal': money('subtotal_minor'),
      'discount': money('discount_minor'),
      'tax': money('tax_minor'),
      'total': money('total_minor'),
      'paid': money('paid_minor'),
      'credit': money('credit_minor'),
      'balance': invoice['status'] == 'voided'
          ? Money.format(0, currency)
          : money('balance_minor'),
      'status': invoice['status']?.toString().replaceAll('_', ' '),
      'currency': currency,
    };
    return template.replaceAllMapped(RegExp(r'\{\{\s*(\w+)\s*\}\}'),
        (match) => match[1] == 'items' ? rows : escape(values[match[1]]));
  }

  static Map<String, dynamic> sample(String gymName) => {
        'id': 'SAMPLE',
        'invoice_number': 1,
        'created_at': '2026-11-01',
        'due_date': '2026-11-01',
        'status': 'sample',
        'items': [
          {'description': 'Monthly membership', 'amount_minor': 30000}
        ],
        'snapshot': {
          'gym_name': gymName,
          'gym_address': 'Dubai, UAE',
          'gym_phone': '+971501234567',
          'member_name': 'Sample Member',
          'member_number': 7,
          'member_email': 'member@example.com',
          'member_phone': '+971501234568',
          'package_name': 'Monthly membership',
          'start_date': '2026-11-01',
          'end_exclusive': '2026-12-01',
          'subtotal_minor': 30000,
          'discount_minor': 0,
          'tax_minor': 1500,
          'total_minor': 31500,
          'paid_minor': 10000,
          'credit_minor': 0,
          'balance_minor': 21500,
          'currency': 'AED'
        },
      };
}
