import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/receipts/domain/document_whatsapp.dart';
import 'package:gym_saas/features/receipts/domain/invoice_html.dart';
import 'package:gym_saas/features/receipts/domain/receipt_html.dart';

void main() {
  test(
      'Invoice message includes server totals and distinguishes payment receipt',
      () {
    final document = InvoiceHtml.sample('My Gym');
    final message = documentWhatsAppMessage(document, invoice: true);
    expect(message, contains('Invoice INV-0001'));
    expect(message, contains('Total: AED 315.00'));
    expect(message, contains('Payment received: AED 100.00'));
    expect(message, contains('Balance: AED 215.00'));
    expect(message, contains('not a payment receipt'));
    document['status'] = 'voided';
    final voided = documentWhatsAppMessage(document, invoice: true);
    expect(voided, contains('VOIDED Invoice'));
    expect(voided, contains('Balance: AED 0.00'));
  });

  test('Receipt message includes payment details', () {
    final message =
        documentWhatsAppMessage(ReceiptHtml.sample('My Gym'), invoice: false);
    expect(message, contains('Receipt #PREVIEW'));
    expect(message, contains('Payment received: AED 200.00'));
    expect(message, contains('Payment date: 2026-11-01'));
    expect(message, contains('Method: Card'));
    expect(message, isNot(contains('Invoice INV-')));
  });
}
