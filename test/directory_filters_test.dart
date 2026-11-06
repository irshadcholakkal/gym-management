import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/directory_filters.dart';

void main() {
  test('pending payment includes outstanding invoice statuses only', () {
    for (final status in ['unpaid', 'partially_paid', 'overdue']) {
      expect(matchesDirectoryFilter('invoices', {'status': status}, 'synced', 'pending'), isTrue);
    }
    for (final status in ['paid', 'voided']) {
      expect(matchesDirectoryFilter('invoices', {'status': status}, 'pending', 'pending'), isFalse);
    }
  });
  test('sync state does not override business status', () {
    expect(matchesDirectoryFilter('members', {'status': 'inactive'}, 'pending', 'active'), isFalse);
    expect(matchesDirectoryFilter('members', {'status': 'inactive'}, 'pending', 'pending_sync'), isTrue);
    expect(matchesDirectoryFilter('members', {'status': 'active'}, 'synced', 'pending_sync'), isFalse);
  });
  test('screens offer their supported statuses', () {
    expect(directoryFilters('invoices').map((f) => f.value), containsAll(['paid', 'pending', 'unpaid', 'partially_paid', 'overdue', 'voided']));
    expect(directoryFilters('receipts').map((f) => f.value), ['all', 'issued', 'voided']);
    for (final kind in ['members', 'membership_packages', 'employees']) {
      expect(directoryFilters(kind).map((f) => f.value), containsAll(['active', 'inactive', 'archived']));
    }
  });
}
