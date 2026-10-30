import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/sync/workspace_repository.dart';
import 'package:gym_saas/features/auth/domain/access.dart';
import 'package:gym_saas/features/notifications/notification_center.dart';

void main() {
  testWidgets('inbox filters warnings and opens the linked membership', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = GymDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = WorkspaceRepository(
      db,
      const GymAccess(
        gymId: 'gym',
        userId: 'me',
        name: 'Me',
        gymName: 'Gym',
        role: GymRole.owner,
      ),
    );
    for (final item in [
      {
        'id': 'warning',
        'recipient_id': 'me',
        'type': 'expired',
        'title': 'Expired membership',
        'subscription_id': 'membership',
        'read_at': '2026-10-30',
      },
      {
        'id': 'reminder',
        'recipient_id': 'me',
        'type': 'expiry_7',
        'title': 'Renewal soon',
      },
      {'id': 'private', 'recipient_id': 'other', 'title': 'Other user alert'},
      {
        'id': 'old',
        'recipient_id': 'me',
        'title': 'Obsolete alert',
        'superseded_at': '2026-10-30',
      },
    ]) {
      await db
          .into(db.cachedRecords)
          .insert(
            CachedRecordsCompanion.insert(
              scope: repo.scope,
              kind: 'notifications',
              id: item['id']!,
              payload: jsonEncode(item),
            ),
          );
    }
    final router = GoRouter(
      initialLocation: '/notifications',
      routes: [
        GoRoute(
          path: '/notifications',
          builder: (context, state) => Scaffold(
            appBar: AppBar(actions: const [NotificationBell()]),
            body: const NotificationCenter(),
          ),
        ),
        GoRoute(
          path: '/subscriptions',
          builder: (context, state) => Scaffold(
            body: Text('Membership ${state.uri.queryParameters['record']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: repo,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Renewal soon'), findsOneWidget);
    expect(find.text('Other user alert'), findsNothing);
    expect(find.text('Obsolete alert'), findsNothing);
    expect(find.byTooltip('1 unread notifications'), findsOneWidget);
    await db
        .into(db.cachedRecords)
        .insert(
          CachedRecordsCompanion.insert(
            scope: repo.scope,
            kind: 'notifications',
            id: 'fresh',
            payload: jsonEncode({
              'recipient_id': 'me',
              'type': 'expiry_1',
              'title': 'Tomorrow reminder',
              'created_at': DateTime.now()
                  .toUtc()
                  .add(const Duration(seconds: 1))
                  .toIso8601String(),
            }),
          ),
        );
    await tester.pumpAndSettle();
    expect(find.text('New membership warning or reminder'), findsOneWidget);
    expect(find.byTooltip('2 unread notifications'), findsOneWidget);
    await tester.tap(find.text('Warnings'));
    await tester.pumpAndSettle();
    expect(find.text('Renewal soon'), findsNothing);
    expect(find.text('Expired membership'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('View membership'));
    await tester.pumpAndSettle();
    expect(find.text('Membership membership'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  test('inbox excludes other recipients and superseded alerts', () {
    expect(currentNotification({'recipient_id': 'me'}, 'me'), isTrue);
    expect(currentNotification({'recipient_id': 'other'}, 'me'), isFalse);
    expect(
      currentNotification({
        'recipient_id': 'me',
        'superseded_at': '2026-10-30',
      }, 'me'),
      isFalse,
    );
    expect(
      currentNotification({
        'recipient_id': 'me',
        'read_at': '2026-10-30',
      }, 'me'),
      isTrue,
    );
  });
}
