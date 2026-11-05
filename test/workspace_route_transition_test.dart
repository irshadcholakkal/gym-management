import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/sync/workspace_repository.dart';
import 'package:gym_saas/core/workspace.dart';
import 'package:gym_saas/features/auth/domain/access.dart';
import 'package:gym_saas/features/members/member_photos.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets(
      'Shell navigation leaves member pages repeatedly and preserves route filters',
      (tester) async {
    final db = GymDatabase.forTesting(NativeDatabase.memory());
    final client = (await tester.runAsync(() async => SupabaseClient(
        'https://example.test', 'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false))))!;
    final repo = WorkspaceRepository(
        db,
        const GymAccess(
            gymId: 'gym',
            userId: 'user',
            name: 'Owner',
            gymName: 'Gym',
            role: GymRole.owner));
    addTearDown(db.close);
    addTearDown(() => tester.runAsync(client.dispose));
    await repo.applyRemoteChanges([
      for (var i = 0; i < 30; i++)
        {
          'kind': 'members',
          'record_id': '$i',
          'payload': {
            'full_name': 'Member $i',
            'phone': '+971501234567',
            'status': i == 29 ? 'archived' : 'active',
            'version': 1
          }
        }
    ], 30);
    final router = GoRouter(routes: [
      ShellRoute(
          builder: (context, state, child) => Scaffold(
                  body: Column(children: [
                Row(children: [
                  TextButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Overview')),
                  TextButton(
                      onPressed: () => context.go('/members'),
                      child: const Text('Members')),
                  TextButton(
                      onPressed: () => context.go('/members?filter=archived'),
                      child: const Text('Archived members')),
                ]),
                Expanded(child: child)
              ])),
          routes: [
            for (final path in ['/', '/members'])
              GoRoute(
                  path: path,
                  pageBuilder: (_, state) => NoTransitionPage<void>(
                      key: state.pageKey,
                      child: WorkspaceContent(
                          path: path,
                          queryParameters: state.uri.queryParameters)))
          ])
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MultiRepositoryProvider(providers: [
      RepositoryProvider.value(value: repo),
      RepositoryProvider.value(value: MemberPhotos(client, repo)),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Members'));
      await tester.pumpAndSettle();
      expect(find.text('30 records - Page 1'), findsOneWidget);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('Registered members'), findsOneWidget);
    }
    await tester.tap(find.text('Archived members'));
    await tester.pumpAndSettle();
    expect(find.text('1 records - Page 1'), findsOneWidget);
    expect(find.text('Member 29'), findsOneWidget);
    await tester.tap(find.text('Overview'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
