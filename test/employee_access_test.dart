import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/theme.dart';
import 'package:gym_saas/features/auth/data/auth_repository.dart';
import 'package:gym_saas/features/auth/domain/access.dart';
import 'package:gym_saas/features/auth/presentation/login_page.dart';

class LoginCapture implements AuthRepository {
  String? identifier, password;
  @override
  Future<void> signIn(String email, String password) async {
    identifier = email;
    this.password = password;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Custom options restrict a role without expanding it', () {
    const restricted = GymAccess(
        gymId: 'g',
        userId: 'u',
        name: 'A',
        gymName: 'G',
        role: GymRole.manager,
        options: {'operations': false, 'administration': true});
    expect(restricted.finances, false);
    expect(restricted.editMembers, false);
    expect(restricted.canDiscount, false);
    expect(restricted.administer, false);
    expect(restricted.allows('/subscriptions'), false);
    const readOnly = GymAccess(
        gymId: 'g',
        userId: 'u',
        name: 'A',
        gymName: 'G',
        role: GymRole.receptionist,
        options: {'edit_members': false, 'discounts': true});
    expect(readOnly.finances, true);
    expect(readOnly.editMembers, false);
    expect(readOnly.canDiscount, false);
  });
  testWidgets('Employees can submit a username or employee ID with a password',
      (tester) async {
    final repository = LoginCapture();
    await tester.pumpWidget(MaterialApp(
        theme: GymTheme.light, home: LoginPage(repository: repository)));
    for (final identifier in ['trainer.one', 'EMP-42']) {
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Email, employee ID or username'),
          identifier);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'employee-password');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(repository.identifier, identifier);
      expect(repository.password, 'employee-password');
      expect(find.text('Enter a valid email address'), findsNothing);
    }
  });
}
