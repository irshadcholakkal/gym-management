import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/sync/workspace_repository.dart';
import 'package:gym_saas/core/theme.dart';
import 'package:gym_saas/core/workspace.dart';
import 'package:gym_saas/features/auth/data/auth_repository.dart';
import 'package:gym_saas/features/auth/domain/access.dart';
import 'package:gym_saas/features/auth/presentation/session_cubit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AccessRepository implements AuthRepository {
  Map<String, bool> options = {};
  final events = StreamController<AuthState>.broadcast();
  @override
  Stream<AuthState> get changes => events.stream;
  @override
  bool get signedIn => true;
  @override
  bool get requiresPasswordSetup => false;
  @override
  Future<GymAccess> access() async => GymAccess(
      gymId: 'gym',
      userId: 'user',
      name: 'Admin',
      gymName: 'Gym',
      role: GymRole.admin,
      options: Map.of(options));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
      'Unchanged access checks do not refresh the router; permission changes still emit',
      () async {
    final repository = AccessRepository();
    final session = SessionCubit(repository);
    await Future<void>.delayed(Duration.zero);
    final updates = <SessionState>[];
    final subscription = session.stream.listen(updates.add);
    await session.restore();
    await session.restore();
    await Future<void>.delayed(Duration.zero);
    expect(updates, isEmpty);
    repository.options = {'operations': false};
    await session.restore();
    await Future<void>.delayed(Duration.zero);
    expect(updates, hasLength(1));
    expect(updates.single.access!.finances, false);
    await subscription.cancel();
    await session.close();
    await repository.events.close();
  });

  testWidgets(
      'Compact directory fits narrow screens, keeps actions reachable and filters records',
      (tester) async {
    final db = GymDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    const access = GymAccess(
        gymId: 'gym',
        userId: 'user',
        name: 'Admin',
        gymName: 'Gym',
        role: GymRole.admin);
    final repo = WorkspaceRepository(db, access);
    for (final name in ['Amina Ali', 'Bilal Ahmed']) {
      await db.into(db.cachedRecords).insert(CachedRecordsCompanion.insert(
          scope: repo.scope,
          kind: 'members',
          id: name,
          payload: jsonEncode({
            'full_name': name,
            'phone': '+971501234567',
            'status': 'active'
          })));
    }
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final width in [320.0, 390.0]) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpWidget(RepositoryProvider.value(
          value: repo,
          child: MaterialApp(
              theme: GymTheme.mobile,
              home: const Scaffold(
                  body: Padding(
                      padding: EdgeInsets.all(12),
                      child: RecordDirectory(kind: 'members'))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('Record actions'), findsNWidgets(2));
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, false);
      final searchCenter = tester.getCenter(find.byType(TextField));
      expect(tester.getCenter(find.byTooltip('Filter records')).dy,
          closeTo(searchCenter.dy, 1));
      expect(tester.getCenter(find.byTooltip('Add member')).dy,
          closeTo(searchCenter.dy, 1));
      await tester.tap(find.byTooltip('Filter records'));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((widget) =>
          widget is CheckedPopupMenuItem<String> &&
          widget.value == 'archived'));
      await tester.pumpAndSettle();
      expect(find.text('No records yet'), findsOneWidget);
      await tester.tap(find.byTooltip('Filter: Archived'));
      await tester.pumpAndSettle();
      await tester.tap(find.byWidgetPredicate((widget) =>
          widget is CheckedPopupMenuItem<String> && widget.value == 'all'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Record actions').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit record'), findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Amina');
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(find.text('Amina Ali'), findsOneWidget);
      expect(find.text('Bilal Ahmed'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
}
