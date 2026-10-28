abstract final class DiscountTotals {
  /// Counts discounts granted on invoices in the gym's calendar month, including
  /// future renewals invoiced now. Voided invoices are excluded.
  static int forMonth(
    Iterable<Map> invoices,
    DateTime gymDate, {
    String currency = 'AED',
    Duration offset = const Duration(hours: 4),
  }) {
    var total = 0;
    for (final invoice in invoices) {
      if (invoice['status'] == 'voided' ||
          (invoice['currency'] ?? 'AED') != currency) {
        continue;
      }
      final granted = DateTime.tryParse(
        (invoice['discount_granted_at'] ?? invoice['created_at'] ?? '')
            .toString(),
      );
      if (granted == null) continue;
      final local = granted.toUtc().add(offset);
      if (local.year == gymDate.year && local.month == gymDate.month) {
        total += invoice['discount_minor'] as int? ?? 0;
      }
    }
    return total;
  }
}
