abstract final class Money {
  static int parse(String value) {
    final text = value.trim();
    if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(text)) {
      throw const FormatException(
        'Enter a positive amount with at most two decimal places',
      );
    }
    final parts = text.split('.');
    return int.parse(parts[0]) * 100 +
        int.parse(parts.length == 1 ? '00' : parts[1].padRight(2, '0'));
  }

  static String format(int minor, [String currency = 'AED']) =>
      '$currency ${minor < 0 ? '-' : ''}${minor.abs() ~/ 100}.${(minor.abs() % 100).toString().padLeft(2, '0')}';
  static int balance({
    required int charges,
    required int received,
    int adjustments = 0,
  }) => charges + adjustments - received;
  static int refundableCredit({
    required int unusedValue,
    required int received,
  }) => unusedValue.clamp(0, received < 0 ? 0 : received);
}
