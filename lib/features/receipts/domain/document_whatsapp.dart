import '../../payments/domain/money.dart';
import 'invoice_html.dart';

String documentWhatsAppMessage(Map<String, dynamic> document,
    {required bool invoice}) {
  final data = document['snapshot'] as Map;
  final currency = data['currency'] as String? ?? 'AED';
  String money(String key) => Money.format(data[key] as int? ?? 0, currency);
  final voided = ['void', 'voided', 'reversed'].contains(document['status']);
  return [
    'Hi ${data['member_name'] ?? 'Member'},',
    '${data['gym_name'] ?? 'Gym'} — ${voided ? 'VOIDED ' : ''}${invoice ? 'Invoice ${InvoiceHtml.number(document['invoice_number'])}' : 'Receipt #${document['receipt_number']}'}',
    if (data['package_name'] != null) '${data['package_name']}',
    if (invoice && document['due_date'] != null)
      'Due date: ${document['due_date']}',
    if (!invoice && data['payment_date'] != null)
      'Payment date: ${data['payment_date']}',
    'Total: ${money('total_minor')}',
    'Payment received: ${money('paid_minor')}',
    if (invoice && (data['credit_minor'] as int? ?? 0) != 0)
      'Credit applied: ${money('credit_minor')}',
    'Balance: ${voided ? Money.format(0, currency) : money('balance_minor')}',
    if (!invoice && data['method'] != null) 'Method: ${data['method']}',
    if (voided) 'This document is voided.',
    if (invoice) 'This invoice is not a payment receipt.',
    'Thank you!',
  ].join('\n');
}
