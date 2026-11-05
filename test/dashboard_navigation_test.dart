import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/sync/workspace_repository.dart';
import 'package:gym_saas/core/theme.dart';
import 'package:gym_saas/core/workspace.dart';
import 'package:gym_saas/features/auth/domain/access.dart';
import 'package:gym_saas/features/subscriptions/domain/membership_status.dart';

void main() {
  testWidgets(
      'Every dashboard metric opens its related section and status filter',
      (tester) async {
    final db = GymDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = WorkspaceRepository(
        db,
        const GymAccess(
            gymId: 'gym',
            userId: 'owner',
            name: 'Owner',
            gymName: 'Gym',
            role: GymRole.owner));
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Dashboard())),
      for (final path in ['/members', '/subscriptions', '/payments'])
        GoRoute(
            path: path,
            builder: (_, state) =>
                Scaffold(body: Text('Destination: ${state.uri}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(RepositoryProvider.value(
        value: repo,
        child:
            MaterialApp.router(theme: GymTheme.light, routerConfig: router)));
    await tester.pumpAndSettle();
    final destinations = {
      'Registered members': '/members',
      'Active memberships': '/subscriptions?filter=active',
      'Paused memberships': '/subscriptions?filter=paused',
      'Expired memberships': '/subscriptions?filter=expired',
      'Expiring within 7 days': '/subscriptions?filter=expiring_soon',
      'Outstanding balance': '/payments',
      'Discounts given this month': '/payments',
      'Collected today': '/payments',
      'Collected this month': '/payments',
      'Overdue balance': '/payments',
    };
    for (final entry in destinations.entries) {
      await tester.ensureVisible(find.text(entry.key));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry.key));
      await tester.pumpAndSettle();
      expect(find.text('Destination: ${entry.value}'), findsOneWidget);
      expect(tester.takeException(), isNull);
      router.go('/');
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  test(
      'Membership drill-downs include active renewals and the inclusive seven-day boundary',
      () {
    MembershipStatus membership(String status, String end) =>
        MembershipStatus({'status': status, 'end_exclusive': end},
            now: DateTime.utc(2026, 11, 5, 8));
    expect(membership('active', '2026-11-06').matchesFilter('active'), isTrue);
    expect(membership('active', '2026-11-13').matchesFilter('expiring_soon'),
        isTrue);
    expect(membership('active', '2026-11-14').matchesFilter('expiring_soon'),
        isFalse);
    expect(membership('active', '2026-11-05').matchesFilter('active'), isFalse);
    expect(membership('active', '2026-11-05').matchesFilter('expired'), isTrue);
    expect(membership('paused', '2026-11-06').matchesFilter('expiring_soon'),
        isFalse);
  });
}
