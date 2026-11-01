import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/theme.dart';
import 'package:gym_saas/features/notifications/data/device_push_controller.dart';
import 'package:gym_saas/features/notifications/push_notification_controls.dart';

class FakePush implements DevicePushController {
  PushAvailability availability = PushAvailability.disabled;
  int tests = 0, enables = 0;
  @override
  Future<PushAvailability> status() async => availability;
  @override
  Future<void> enable() async {
    enables++;
    availability = PushAvailability.enabled;
  }

  @override
  Future<void> test() async {
    tests++;
  }
}

void main() {
  testWidgets(
      'Push settings show enabled state, support a test and refresh revoked permissions',
      (tester) async {
    final push = FakePush()..availability = PushAvailability.enabled;
    await tester.pumpWidget(MaterialApp(
        theme: GymTheme.mobile,
        home: Scaffold(
            body: PushNotificationControls(controller: push, showTest: true))));
    await tester.pumpAndSettle();
    expect(find.text('Push enabled'), findsOneWidget);
    expect(find.text('Enable push'), findsNothing);
    await tester.tap(find.text('Test notification'));
    await tester.pumpAndSettle();
    expect(push.tests, 1);
    expect(find.text('Test push sent. Check this device notifications.'),
        findsOneWidget);
    push.availability = PushAvailability.blocked;
    await tester.tap(find.byTooltip('Refresh push status'));
    await tester.pumpAndSettle();
    expect(find.text('Push blocked'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Test notification'));
    expect(button.onPressed, isNull);
  });
  testWidgets(
      'Enabling push changes the label only after registration succeeds',
      (tester) async {
    final push = FakePush();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: PushNotificationControls(controller: push))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enable push'));
    await tester.pumpAndSettle();
    expect(push.enables, 1);
    expect(find.text('Push enabled'), findsOneWidget);
  });
}
