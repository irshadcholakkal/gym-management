import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/sync/workspace_repository.dart';
import 'package:gym_saas/core/theme.dart';
import 'package:gym_saas/core/workspace.dart';
import 'package:gym_saas/features/auth/domain/access.dart';

void main() {
  testWidgets('Reactive dashboard charts and cards fit desktop and mobile', (
    tester,
  ) async {
    final db = GymDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = WorkspaceRepository(
      db,
      const GymAccess(
        gymId: 'gym',
        userId: 'owner',
        name: 'Owner',
        gymName: 'Test gym',
        role: GymRole.owner,
      ),
    );
    final now = DateTime.now().toUtc().toIso8601String();
    await db
        .into(db.cachedRecords)
        .insert(
          CachedRecordsCompanion.insert(
            scope: repo.scope,
            kind: 'payments',
            id: 'payment',
            payload: jsonEncode({
              'id': 'payment',
              'amount_minor': 10000,
              'created_at': now,
            }),
          ),
        );
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepositoryProvider.value(
        value: repo,
        child: MaterialApp(
          theme: GymTheme.light,
          home: const Scaffold(
            body: Padding(padding: EdgeInsets.all(24), child: Dashboard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Monthly collections'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'Member form validates then saves an optimistic record and outbox entry',
    (tester) async {
      final db = GymDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = WorkspaceRepository(
        db,
        const GymAccess(
          gymId: 'gym',
          userId: 'owner',
          name: 'Owner',
          gymName: 'Test gym',
          role: GymRole.owner,
        ),
      );
      await tester.pumpWidget(
        RepositoryProvider.value(
          value: repo,
          child: MaterialApp(
            theme: GymTheme.light,
            home: const Scaffold(body: RecordDirectory(kind: 'members')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add member'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save member'));
      await tester.pumpAndSettle();
      expect(find.text('This field is required'), findsWidgets);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Full name'),
        'Amina',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone number'),
        '+971501234567',
      );
      await tester.tap(find.text('Save member'));
      await tester.pumpAndSettle();
      final records = await tester.runAsync(
        () => db.select(db.cachedRecords).get(),
      );
      final operations = await tester.runAsync(
        () => db.select(db.syncOperations).get(),
      );
      expect(records!.single.syncState, 'pending');
      expect(operations!.length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
