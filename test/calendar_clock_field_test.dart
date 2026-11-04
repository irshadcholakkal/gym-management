import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/calendar_clock_field.dart';
import 'package:gym_saas/core/theme.dart';

void main() {
  testWidgets('Calendar selection saves an ISO date; cancel preserves it',
      (tester) async {
    final controller = TextEditingController(text: '2026-11-04');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: GymTheme.light,
        home: Scaffold(
            body: CalendarClockField(
                controller: controller, label: 'Start date'))));
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
    await tester.tap(find.byTooltip('Open calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('15'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(controller.text, '2026-11-15');
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(controller.text, '2026-11-15');
  });

  testWidgets('Clock uses a dial and saves 24-hour time', (tester) async {
    final controller = TextEditingController(text: '20:30');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: GymTheme.dark,
        home: Scaffold(
            body: CalendarClockField(
                controller: controller, label: 'Time', time: true))));
    await tester.tap(find.byTooltip('Open clock'));
    await tester.pumpAndSettle();
    final dialog =
        tester.widget<TimePickerDialog>(find.byType(TimePickerDialog));
    expect(dialog.initialEntryMode, TimePickerEntryMode.dialOnly);
    expect(dialog.initialTime, const TimeOfDay(hour: 20, minute: 30));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(controller.text, '20:30');
  });

  testWidgets('Disabled selection cannot open the calendar', (tester) async {
    final controller = TextEditingController(text: '2026-11-04');
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CalendarClockField(
                controller: controller, label: 'Date', enabled: false))));
    expect(
        tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    expect(tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        isFalse);
  });
}
