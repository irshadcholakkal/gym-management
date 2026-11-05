import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/sync/workspace_repository.dart';
import 'package:gym_saas/core/workspace.dart';
import 'package:gym_saas/features/auth/domain/access.dart';

void main() {
  testWidgets('Members remain searchable and pageable during data updates',
      (tester) async {
    final db = GymDatabase.forTesting(NativeDatabase.memory());
    final repo = WorkspaceRepository(
        db,
        const GymAccess(
            gymId: 'gym',
            userId: 'user',
            name: 'Owner',
            gymName: 'Gym',
            role: GymRole.owner));
    addTearDown(db.close);
    Map<String, dynamic> member(int i, String name) => {
          'kind': 'members',
          'record_id': '$i',
          'payload': {
            'full_name': name,
            'phone': '+971501234567',
            'status': 'active',
            'version': 1
          }
        };
    await repo.applyRemoteChanges([
      for (var i = 0; i < 40; i++)
        member(i, 'Member ${i.toString().padLeft(3, '0')}')
    ], 40);
    await tester.pumpWidget(RepositoryProvider.value(
        value: repo,
        child: const MaterialApp(
            home: Scaffold(body: RecordDirectory(kind: 'members')))));
    await tester.pumpAndSettle();
    expect(find.text('40 records - Page 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();
    expect(find.text('40 records - Page 2'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'member 039');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Member 039'), findsOneWidget);
    expect(find.text('1 records - Page 1'), findsOneWidget);
    await tester.runAsync(
        () => repo.applyRemoteChanges([member(39, 'Renamed member')], 41));
    await tester.pumpAndSettle();
    expect(find.text('Member 039'), findsNothing);
    await tester.enterText(find.byType(TextField), 'renamed');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Renamed member'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
