import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/app.dart';

void main() {
  testWidgets(
    'Missing configuration gives actionable setup without fake data',
    (tester) async {
      await tester.pumpWidget(const GymProApp());
      await tester.pumpAndSettle();
      expect(find.text('Welcome to GymPro UAE'), findsOneWidget);
      expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Setup remains usable at a narrow mobile width', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const GymProApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
