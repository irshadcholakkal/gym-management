import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/receipts/domain/receipt_pdf.dart';

void main() {
  test('Final receipt produces a real PDF with integer figures', () async {
    final bytes = await ReceiptPdf.build({
      'id': 'receipt-id',
      'receipt_number': 42,
      'created_at': '2026-01-01',
      'status': 'issued',
      'snapshot': {
        'gym_name': 'GymPro UAE',
        'gym_address': 'Dubai',
        'gym_phone': '+971501234567',
        'member_name': 'Amina',
        'member_number': 1,
        'package_name': 'Quarterly',
        'start_date': '2026-01-01',
        'end_exclusive': '2026-04-21',
        'total_minor': 30000,
        'tax_minor': 0,
        'paid_minor': 10000,
        'balance_minor': 20000,
        'currency': 'AED',
        'method': 'cash',
        'reference': 'Ref42',
        'payment_date': '2026-01-01',
        'issuer': 'Owner',
      },
    });
    expect(ascii.decode(bytes.take(5).toList()), '%PDF-');
    expect(bytes.length, greaterThan(1000));
  });
  test(
    'Provisional outbox operation cannot masquerade as official receipt',
    () async {
      await expectLater(
        ReceiptPdf.build({'id': 'local-payment', 'amount_minor': 10000}),
        throwsArgumentError,
      );
    },
  );
}
