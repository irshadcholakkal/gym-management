import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/sync/workspace_repository.dart';
import 'package:gym_saas/core/theme.dart';
import 'package:gym_saas/core/workspace.dart';
import 'package:gym_saas/features/auth/domain/access.dart';

void main() {
  testWidgets('Minimal membership cards open their details on tap',
      (tester) async {
    final textFont = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await textFont.load();
    final iconFont = FontLoader('CupertinoIcons')
      ..addFont(rootBundle
          .load('packages/cupertino_icons/assets/CupertinoIcons.ttf'));
    await iconFont.load();
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
    await repo.applyRemoteChanges([
      {
        'kind': 'members',
        'record_id': 'member',
        'payload': {
          'full_name': 'Amina Hassan',
          'member_number': 7,
          'version': 1
        }
      },
      {
        'kind': 'subscriptions',
        'record_id': 'membership',
        'payload': {
          'member_id': 'member',
          'package_snapshot': {'name': 'Quarterly plan'},
          'start_date': '2026-11-01',
          'end_exclusive': '2027-02-01',
          'status': 'active',
          'version': 1
        }
      },
    ], 1);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final boundaryKey = GlobalKey();
    for (final width in [390.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpWidget(RepositoryProvider.value(
          value: repo,
          child: MaterialApp(
              theme: GymTheme.light,
              home: RepaintBoundary(
                  key: boundaryKey,
                  child: const Scaffold(
                      body: RecordDirectory(kind: 'subscriptions'))))));
      await tester.pumpAndSettle();
      expect(find.text('Amina Hassan'), findsOneWidget);
      expect(find.text('ID 0007'), findsOneWidget);
      expect(find.text('Quarterly plan'), findsNothing);
      expect(find.text('Open'), findsNothing);
      expect(find.text('Renew membership'), findsNothing);
      expect(tester.takeException(), isNull);
      if (width == 390) {
        final boundary = boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/design_review/memberships-minimal-390.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.tap(find.text('Amina Hassan'));
    await tester.pumpAndSettle();
    expect(find.text('Membership details'), findsOneWidget);
    expect(find.textContaining('Quarterly plan'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
