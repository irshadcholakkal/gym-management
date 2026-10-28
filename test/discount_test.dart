import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/payments/domain/discount_totals.dart';
import 'package:gym_saas/features/payments/domain/membership_quote.dart';
import 'package:gym_saas/core/operation_error.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'Discount quote uses exact minor units and computes tax after discount',
    () {
      const quote = MembershipQuote(
        priceMinor: 30000,
        enrollmentFeeMinor: 1000,
        discountMinor: 5000,
        taxBasisPoints: 500,
      );
      expect(quote.subtotalMinor, 31000);
      expect(quote.taxMinor, 1300);
      expect(quote.totalMinor, 27300);
    },
  );
  test('Monthly discount totals follow Dubai boundaries and exclude voided/other currencies', () {
    final invoices = [
      {
        'discount_minor': 5000,
        'discount_granted_at': '2026-09-30T21:00:00Z',
        'status': 'paid',
        'currency': 'AED',
      },
      {
        'discount_minor': 2500,
        'discount_granted_at': '2026-10-31T19:59:59Z',
        'status': 'unpaid',
        'currency': 'AED',
      },
      {
        'discount_minor': 9000,
        'discount_granted_at': '2026-10-31T20:00:00Z',
        'status': 'paid',
        'currency': 'AED',
      },
      {
        'discount_minor': 1000,
        'discount_granted_at': '2026-10-15T00:00:00Z',
        'status': 'voided',
        'currency': 'AED',
      },
      {
        'discount_minor': 1000,
        'discount_granted_at': '2026-10-15T00:00:00Z',
        'status': 'paid',
        'currency': 'USD',
      },
    ];
    expect(DiscountTotals.forMonth(invoices, DateTime.utc(2026, 10, 28)), 7500);
  });
  test('Membership overlap shows a specific correction instead of generic confirmation error', () {
    const error = PostgrestException(message: 'conflicting key', code: '23P01');
    expect(operationErrorMessage(error), contains('Renew membership'));
    expect(definitiveOperationError(error), isTrue);
    expect(definitiveOperationError(StateError('network')), isFalse);
  });
}
