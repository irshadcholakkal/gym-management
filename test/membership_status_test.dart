import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/subscriptions/domain/membership_status.dart';

void main() {
  final now = DateTime.utc(2026, 10, 29, 12);
  MembershipStatus state(String status, String end) => MembershipStatus(
        {'status': status, 'end_exclusive': end},
        now: now,
      );
  test('exclusive expiry boundary and last usable day', () {
    expect(state('active', '2026-10-29').status, 'expired');
    expect(state('active', '2026-10-30').countdown, 'Last day today');
    expect(state('active', '2026-11-05').status, 'expiring_soon');
    expect(state('active', '2026-11-06').status, 'active');
  });
  test('paused membership does not become expired from stored end date', () {
    expect(state('paused', '2026-10-01').status, 'paused');
    expect(
        state('paused', '2026-10-01').countdown, contains('Countdown paused'));
    expect(state('cancelled', '2026-10-01').status, 'cancelled');
  });
  test('expiry follows Dubai midnight', () {
    final status = MembershipStatus(
        {'status': 'active', 'end_exclusive': '2026-10-30'},
        now: DateTime.utc(2026, 10, 29, 20));
    expect(status.status, 'expired');
  });
  test('normalizes UAE local and international WhatsApp numbers', () {
    expect(whatsappPhone('050 123 4567'), '971501234567');
    expect(whatsappPhone('+91 98765 43210'), '919876543210');
    expect(whatsappPhone('00971-50-123-4567'), '971501234567');
    expect(whatsappPhone(''), isNull);
    expect(whatsappPhone('123abc45678'), isNull);
  });
}
