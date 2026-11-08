import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/features/auth/domain/access.dart';
import 'package:gym_saas/features/subscriptions/membership_actions.dart';
import 'package:gym_saas/features/subscriptions/membership_whatsapp.dart';

void main() {
  test(
      'Messages match the current situation and include the four-digit member ID',
      () {
    final now = DateTime.utc(2026, 11, 8);
    Map<String, String> messages(String status, String end) =>
        membershipWhatsAppTemplates(subscription: {
          'status': status,
          'start_date': '2026-11-01',
          'end_exclusive': end
        }, member: {
          'full_name': 'Amina',
          'member_number': 7
        }, package: 'Monthly', gym: 'My Gym', now: now);
    final active = messages('active', '2026-12-01');
    expect(active.keys.first, 'Active membership');
    expect(active.values.first, contains('Member ID: 0007'));
    expect(messages('active', '2026-11-15').keys.first, 'Renewal reminder');
    expect(
        messages('active', '2026-11-09').values.first, contains('ends today'));
    expect(messages('active', '2026-11-08').keys.first, 'Membership expired');
    expect(
        messages('paused', '2026-11-01').values.first, contains('is paused'));
    expect(messages('scheduled_renewal', '2026-12-01').keys.first,
        'Upcoming membership');
    expect(
        messages('cancelled', '2026-12-01').keys.first, 'Membership cancelled');
    expect(messages('pending_activation', '2026-12-01').keys.first,
        'Membership pending');
    expect(messages('no_membership', '').keys.first, 'Member update');
  });
  testWidgets('WhatsApp action opens the selected membership message flow',
      (tester) async {
    String? selected;
    final record = CachedRecord(
        scope: 'scope',
        kind: 'subscriptions',
        id: 'membership',
        payload: '{"status":"active","end_exclusive":"2099-12-31"}',
        version: 1,
        syncState: 'synced');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: MembershipActions(
                record: record,
                access: const GymAccess(
                    gymId: 'gym',
                    userId: 'owner',
                    name: 'Owner',
                    gymName: 'Gym',
                    role: GymRole.owner),
                onAction: (action, target) {
                  selected = action;
                  expect(target.id, 'membership');
                }))));
    await tester.tap(find.text('WhatsApp message'));
    expect(selected, 'whatsapp');
  });
}
