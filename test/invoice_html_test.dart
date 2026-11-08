import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/receipts/domain/invoice_html.dart';

void main() {
  test(
      'Invoice rendering uses stored figures, stable number and escaped line items',
      () {
    final invoice = InvoiceHtml.sample('My Gym');
    (invoice['snapshot'] as Map)['member_name'] =
        '<img src=x onerror=alert(1)>';
    (invoice['items'] as List)
        .add({'description': '<script>bad</script>', 'amount_minor': -1000});
    final html = InvoiceHtml.render(InvoiceHtml.defaultDesign, invoice);
    expect(html, contains('INV-0001'));
    expect(html, contains('0007'));
    expect(html, contains('AED 315.00'));
    expect(html, contains('AED 100.00'));
    expect(html, contains('AED 215.00'));
    expect(html, contains('&lt;img'));
    expect(html, contains('&lt;script&gt;'));
    expect(html, isNot(contains('<script>bad')));
    expect(html, contains('2026-11-30'));
    invoice['status'] = 'voided';
    expect(InvoiceHtml.render(InvoiceHtml.defaultDesign, invoice),
        contains('VOIDED INVOICE'));
    expect(InvoiceHtml.render('{{balance}}', invoice), 'AED 0.00');
  });
  test('Invoice designs require identity, line items and financial totals', () {
    expect(InvoiceHtml.validate(InvoiceHtml.defaultDesign), isNull);
    expect(
        InvoiceHtml.validate(
            InvoiceHtml.defaultDesign.replaceAll('{{total}}', '')),
        contains('{{total}}'));
    expect(InvoiceHtml.validate('${InvoiceHtml.defaultDesign}{{unknown}}'),
        contains('Unknown placeholder'));
    expect(() => InvoiceHtml.render(InvoiceHtml.defaultDesign, {'id': 'local'}),
        throwsArgumentError);
  });
}
