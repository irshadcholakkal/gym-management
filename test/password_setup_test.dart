import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/auth/data/auth_repository.dart';
import 'package:gym_saas/features/auth/presentation/login_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SetupAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
      'Password setup explains the steps and rejects mismatched confirmation',
      (tester) async {
    final client = await tester.runAsync(
      () async => SupabaseClient('https://example.supabase.co', 'test-key'),
    );
    await tester.pumpWidget(MaterialApp(
      home: LoginPage(repository: SetupAuth(), recoveryClient: client),
    ));
    expect(find.text('Choose a new password'), findsOneWidget);
    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm password'), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'a-long-password');
    await tester.enterText(fields.at(1), 'different-password');
    await tester.ensureVisible(find.text('Save password'));
    await tester.tap(find.text('Save password'));
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);
    await tester.runAsync(() => client!.dispose());
  });

  testWidgets('Expired invitation offers a new reset link', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LoginPage(
        repository: SetupAuth(),
        initialReset: true,
        initialMessage: 'This invitation has expired. Request a new link.',
      ),
    ));
    expect(find.text('Reset your password'), findsOneWidget);
    expect(find.text('Send reset link'), findsOneWidget);
    expect(find.text('This invitation has expired. Request a new link.'),
        findsOneWidget);
  });
}
