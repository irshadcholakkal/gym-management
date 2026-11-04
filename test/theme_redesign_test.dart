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
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Appearance restores and persists the selected mode', () async {
    SharedPreferences.setMockInitialValues({'gympro.theme': 'dark'});
    final preference = ThemePreference();
    await preference.restore();
    expect(preference.mode, ThemeMode.dark);
    await preference.select(ThemeMode.light);
    final restored = ThemePreference();
    await restored.restore();
    expect(restored.mode, ThemeMode.light);
    preference.dispose();
    restored.dispose();
  });

  testWidgets('Theme switch offers device, light and dark appearance',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preference = ThemePreference();
    await tester.pumpWidget(ThemeScope(
        preference: preference,
        child: MaterialApp(
            theme: GymTheme.light,
            home: const Scaffold(body: ThemeSwitcher()))));
    await tester.tap(find.byTooltip('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Use device theme'), findsOneWidget);
    await tester.tap(find.byWidgetPredicate((w) =>
        w is CheckedPopupMenuItem<ThemeMode> && w.value == ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(preference.mode, ThemeMode.dark);
    await tester.pumpWidget(const SizedBox());
    preference.dispose();
  });

  testWidgets(
      'Dashboard and directory render in both themes at phone and desktop sizes',
      (tester) async {
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final db = GymDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = WorkspaceRepository(
        db,
        const GymAccess(
            gymId: 'design',
            userId: 'owner',
            name: 'Owner',
            gymName: 'GymPro',
            role: GymRole.owner));
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dark in [false, true]) {
      for (final width in [390.0, 1440.0]) {
        tester.view.physicalSize = Size(width, 1000);
        for (final directory in [false, true]) {
          final key = GlobalKey();
          await tester.pumpWidget(RepositoryProvider.value(
              value: repo,
              child: MaterialApp(
                  theme: width < 600
                      ? GymTheme.compact(dark ? GymTheme.dark : GymTheme.light)
                      : dark
                          ? GymTheme.dark
                          : GymTheme.light,
                  home: RepaintBoundary(
                      key: key,
                      child: Scaffold(
                          body: Padding(
                              padding: const EdgeInsets.all(24),
                              child: directory
                                  ? const RecordDirectory(kind: 'members')
                                  : const Dashboard()))))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'dark=$dark width=$width directory=$directory');
          if (!directory) {
            final boundary = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final file = File(
                  'build/design_review/${dark ? 'dark' : 'light'}-${width.toInt()}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
