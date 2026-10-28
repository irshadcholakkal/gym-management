import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/record_labels.dart';

void main() {
  test('Membership and invoice labels resolve member and package names without UUID fallback', () {
    CachedRecord record(String kind, String id, Map data) => CachedRecord(
      scope: 'scope',
      kind: kind,
      id: id,
      payload: jsonEncode(data),
      version: 1,
      syncState: 'synced',
    );
    final subscription = {
      'member_id': 'member-uuid',
      'package_id': 'package-uuid',
      'package_snapshot': {'name': 'Monthly plan'},
    };
    final labels = RecordLabels([
      record('members', 'member-uuid', {'full_name': 'Amina Ali'}),
      record('subscriptions', 'subscription-uuid', subscription),
    ]);
    expect(
      labels.title('subscriptions', subscription),
      'Amina Ali · Monthly plan',
    );
    expect(
      labels.title('invoices', {
        'member_id': 'member-uuid',
        'subscription_id': 'subscription-uuid',
      }),
      'Invoice · Amina Ali',
    );
    expect(
      labels.package({'subscription_id': 'subscription-uuid'}),
      'Monthly plan',
    );
    expect(
      labels.title('invoices', {'id': 'unknown-uuid'}),
      isNot(contains('unknown-uuid')),
    );
  });
}
