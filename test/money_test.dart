import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/payments/domain/money.dart';

void main() {
  test('Money parses exactly without binary floating point', () {
    expect(Money.parse('0.29'), 29);
    expect(Money.parse('150.5'), 15050);
    expect(Money.parse('1400'), 140000);
    expect(() => Money.parse('1.001'), throwsFormatException);
    expect(() => Money.parse('-1'), throwsFormatException);
  });
  test('Upgrade adds a charge while preserving partial payment', () {
    expect(
      Money.balance(charges: 30000, received: 10000, adjustments: 15000),
      35000,
    );
    expect(Money.refundableCredit(unusedValue: 30000, received: 10000), 10000);
  });
  test('Formatting handles minor units and credits', () {
    expect(Money.format(15050), 'AED 150.50');
    expect(Money.format(-100), 'AED -1.00');
  });
}
