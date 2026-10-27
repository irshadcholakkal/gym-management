import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/theme.dart';
import 'package:gym_saas/features/auth/data/auth_repository.dart';
import 'package:gym_saas/features/auth/presentation/login_page.dart';
import 'package:gym_saas/features/auth/presentation/signup_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegistrationRepository implements AuthRepository {
  int calls = 0;
  String? name, email;
  bool fail = false, confirmation = true;
  @override
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
    String? redirect,
  }) async {
    calls++;
    if (fail) throw const AuthException('Unable to register this email');
    name = fullName;
    this.email = email;
    return confirmation;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> open(WidgetTester tester, RegistrationRepository repository) =>
      tester.pumpWidget(
        MaterialApp(
          theme: GymTheme.light,
          home: SignupPage(repository: repository, onSignIn: () {}),
        ),
      );
  Future<void> fill(WidgetTester tester) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Full name'),
      '  Amina Ali  ',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Work email'),
      'AMINA@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'Strong-password-123',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'Strong-password-123',
    );
  }

  testWidgets('Sign-in screen offers create account navigation', (
    tester,
  ) async {
    var navigated = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          repository: RegistrationRepository(),
          onCreateAccount: () => navigated = true,
        ),
      ),
    );
    await tester.tap(find.text('Create account'));
    expect(navigated, isTrue);
  });
  testWidgets('Registration validates required inputs and matching passwords', (
    tester,
  ) async {
    final repository = RegistrationRepository();
    await open(tester, repository);
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your full name'), findsOneWidget);
    expect(repository.calls, 0);
    await fill(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm password'),
      'different-password',
    );
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Passwords must match'), findsOneWidget);
    expect(repository.calls, 0);
  });
  testWidgets(
    'Registration normalizes input and shows email confirmation feedback',
    (tester) async {
      final repository = RegistrationRepository();
      await open(tester, repository);
      await fill(tester);
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(repository.calls, 1);
      expect(repository.name, 'Amina Ali');
      expect(repository.email, 'amina@example.com');
      expect(find.text('Check your email'), findsOneWidget);
      expect(find.textContaining('does not grant gym access'), findsOneWidget);
    },
  );
  testWidgets(
    'Server registration errors remain visible and retry is available',
    (tester) async {
      final repository = RegistrationRepository()..fail = true;
      await open(tester, repository);
      await fill(tester);
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Unable to register this email'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Create account'),
            )
            .onPressed,
        isNotNull,
      );
    },
  );
}
