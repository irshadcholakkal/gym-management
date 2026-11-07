import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/members/member_identity.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/directory_index.dart';
import 'package:gym_saas/core/record_labels.dart';
import 'package:gym_saas/features/receipts/domain/receipt_html.dart';

void main() {
  test('Member IDs keep stable numbers and add leading zeros', () {
    expect(memberId(1), '0001');
    expect(memberId('42'), '0042');
    expect(memberId(9999), '9999');
    expect(memberId(10000), '10000');
    expect(memberId(null), '');
  });
  test('Member IDs appear in related labels, search and receipt templates',
      () async {
    CachedRecord record(String kind, String id, Map data) => CachedRecord(
        scope: 'gym',
        kind: kind,
        id: id,
        payload: jsonEncode(data),
        version: 1,
        syncState: 'synced');
    final member = record(
        'members', 'member', {'full_name': 'Amina', 'member_number': 42});
    final subscription = record('subscriptions', 'subscription', {
      'member_id': 'member',
      'package_snapshot': {'name': 'Monthly'}
    });
    final labels = RecordLabels([member, subscription]);
    expect(
        labels.title('members', jsonDecode(member.payload)), 'Amina · ID 0042');
    expect(
        labels.member({'subscription_id': 'subscription'}), 'Amina · ID 0042');
    expect(
        labels.member({
          'snapshot': {'member_name': 'Amina', 'member_number': 42}
        }),
        'Amina · ID 0042');
    final index = await DirectoryIndex.create([member, subscription]);
    expect(index.search['members:member'], contains('0042'));
    expect(index.search['subscriptions:subscription'], contains('0042'));
    final receipt = {
      'receipt_number': 1,
      'snapshot': {
        'member_name': 'Amina',
        'member_number': 42,
        'currency': 'AED'
      }
    };
    expect(ReceiptHtml.render('{{member_name}} / {{member_number}}', receipt),
        'Amina / 0042');
    expect(ReceiptHtml.render('{{member_name}}', receipt), 'Amina · ID 0042');
  });
}
