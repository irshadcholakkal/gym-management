import 'dart:convert';
import '../../payments/domain/money.dart';

abstract final class ReceiptHtml {
  static const defaultDesign = '''<!doctype html>
<html><head><meta charset="utf-8"><style>
@page { size: A4; margin: 16mm; }
* { box-sizing: border-box; }
body { font: 14px Arial, sans-serif; color: #08152f; margin: 0; padding: 24px; }
header { border-bottom: 3px solid #397de5; padding-bottom: 20px; }
h1 { font-size: 26px; margin: 0 0 8px; }
h2 { font-size: 18px; color: #397de5; }
p { line-height: 1.6; }
.muted { color: #738097; font-size: 12px; }
table { width: 100%; border-collapse: collapse; margin: 24px 0; }
td, th { padding: 12px; border-bottom: 1px solid #e5e8ee; text-align: left; }
th { background: #ebf2ff; }
td:last-child, th:last-child { text-align: right; }
.total { font-weight: bold; background: #f3f5f8; }
footer { margin-top: 32px; font-size: 12px; color: #738097; }
@media (max-width: 480px) { body { padding: 14px; } td, th { padding: 8px; } }
</style></head><body>
<header><h1>{{gym_name}}</h1><p>{{gym_address}}<br>{{gym_phone}}</p></header>
<h2>{{receipt_status}}</h2>
<p>Receipt #{{receipt_number}}<br>Issued: {{issued_at}}</p>
<p><strong>{{member_name}}</strong> &middot; Member #{{member_number}}<br>
{{package_name}}<br>{{start_date}} to {{end_date}}</p>
<table><thead><tr><th>Description</th><th>Amount</th></tr></thead><tbody>
<tr><td>Subtotal</td><td>{{subtotal}}</td></tr>
<tr><td>Discount</td><td>{{discount}}</td></tr>
<tr><td>Tax included</td><td>{{tax}}</td></tr>
<tr class="total"><td>Invoice total</td><td>{{total}}</td></tr>
<tr><td>Payment received</td><td>{{paid}}</td></tr>
<tr><td>Balance outstanding</td><td>{{balance}}</td></tr>
</tbody></table>
<p>Method: {{method}}<br>Reference: {{reference}}<br>Payment date: {{payment_date}}<br>
Authorized issuer: {{issuer}}</p>
<footer>Thank you for being part of our community.<br>Verification reference: {{receipt_id}}</footer>
</body></html>''';

  static const placeholders = [
    'gym_name',
    'gym_address',
    'gym_phone',
    'receipt_status',
    'receipt_number',
    'issued_at',
    'member_name',
    'member_number',
    'package_name',
    'start_date',
    'end_date',
    'subtotal',
    'discount',
    'discount_reason',
    'tax',
    'total',
    'paid',
    'balance',
    'currency',
    'method',
    'reference',
    'payment_date',
    'issuer',
    'receipt_id'
  ];
  static String? validate(String html) {
    if (html.trim().isEmpty) return 'Enter a receipt design.';
    if (html.length > 100000) {
      return 'Keep the design below 100,000 characters.';
    }
    for (final match in RegExp(r'\{\{\s*(\w+)\s*\}\}').allMatches(html)) {
      if (!placeholders.contains(match[1])) {
        return 'Unknown placeholder: ${match[1]}';
      }
    }
    for (final key in [
      'receipt_status',
      'receipt_number',
      'member_name',
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

  static String render(String template, Map<String, dynamic> receipt) {
    if (receipt['receipt_number'] == null || receipt['snapshot'] is! Map) {
      throw ArgumentError('A finalized server receipt is required');
    }
    final data = Map<String, dynamic>.from(receipt['snapshot'] as Map);
    final currency = data['currency'] as String? ?? 'AED';
    String money(String key) => Money.format(data[key] as int? ?? 0, currency);
    final end = DateTime.tryParse(data['end_exclusive']?.toString() ?? '')
        ?.subtract(const Duration(days: 1));
    final values = <String, Object?>{
      for (final key in placeholders) key: data[key],
      'receipt_id': receipt['id'],
      'receipt_number': receipt['receipt_number'],
      'issued_at': receipt['created_at'],
      'receipt_status': receipt['status'] == 'sample'
          ? 'SAMPLE RECEIPT - NOT VALID FOR PAYMENT'
          : receipt['status'] == 'voided'
              ? 'VOIDED PAYMENT RECEIPT'
              : 'PAYMENT RECEIPT',
      'end_date': end?.toIso8601String().substring(0, 10) ?? '-',
      'subtotal': Money.format(
          data['subtotal_minor'] as int? ??
              (data['total_minor'] as int? ?? 0) -
                  (data['tax_minor'] as int? ?? 0),
          currency),
      'discount': money('discount_minor'),
      'tax': money('tax_minor'),
      'total': money('total_minor'),
      'paid': money('paid_minor'),
      'balance': money('balance_minor'),
    };
    return template.replaceAllMapped(RegExp(r'\{\{\s*(\w+)\s*\}\}'),
        (m) => const HtmlEscape().convert(values[m[1]]?.toString() ?? ''));
  }

  static Map<String, dynamic> sample(String gymName) => {
        'id': 'SAMPLE',
        'receipt_number': 'PREVIEW',
        'created_at': '2026-11-01',
        'status': 'sample',
        'snapshot': {
          'gym_name': gymName,
          'gym_address': 'Dubai, UAE',
          'gym_phone': '+971 50 000 0000',
          'member_name': 'Sample Member',
          'member_number': 1,
          'package_name': 'Monthly membership',
          'start_date': '2026-11-01',
          'end_exclusive': '2026-12-01',
          'subtotal_minor': 30000,
          'discount_minor': 0,
          'tax_minor': 0,
          'total_minor': 30000,
          'paid_minor': 20000,
          'balance_minor': 10000,
          'currency': 'AED',
          'method': 'Card',
          'reference': 'SAMPLE',
          'payment_date': '2026-11-01',
          'issuer': 'Sample issuer'
        }
      };
}
