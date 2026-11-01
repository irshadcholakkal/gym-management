import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/receipts/domain/receipt_html.dart';

void main() {
  test(
      'HTML receipt uses immutable financial snapshot and escapes member content',
      () {
    final receipt = ReceiptHtml.sample('<Gym>');
    (receipt['snapshot'] as Map)['member_name'] =
        '<img src=x onerror=alert(1)>';
    final html = ReceiptHtml.render(ReceiptHtml.defaultDesign, receipt);
    expect(html, contains('&lt;Gym&gt;'));
    expect(html, contains('&lt;img'));
    expect(html, contains('AED 300.00'));
    expect(html, contains('AED 200.00'));
    expect(html, contains('AED 100.00'));
    expect(html, contains('2026-11-30'));
    expect(html, contains('SAMPLE RECEIPT - NOT VALID FOR PAYMENT'));
    receipt['status'] = 'voided';
    expect(ReceiptHtml.render(ReceiptHtml.defaultDesign, receipt),
        contains('VOIDED PAYMENT RECEIPT'));
  });
  test('Template validates required totals and rejects unknown placeholders',
      () {
    expect(ReceiptHtml.validate(ReceiptHtml.defaultDesign), isNull);
    expect(
        ReceiptHtml.validate(
            ReceiptHtml.defaultDesign.replaceAll('{{paid}}', '')),
        contains('{{paid}}'));
    expect(ReceiptHtml.validate('${ReceiptHtml.defaultDesign}{{not_known}}'),
        contains('Unknown placeholder'));
    expect(
        () => ReceiptHtml.render(
            ReceiptHtml.defaultDesign, {'id': 'pending-payment'}),
        throwsArgumentError);
  });
}
