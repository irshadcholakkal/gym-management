import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/auth/data/auth_repository.dart';
import 'package:gym_saas/features/auth/presentation/gym_setup_page.dart';
import 'package:gym_saas/features/auth/presentation/session_cubit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GymSetupRepository implements AuthRepository {
  String? createdName;
  @override
  Future<void> createGym(String name) async {
    createdName = name;
  }

  @override
  bool get signedIn => true;
  @override
  bool get requiresPasswordSetup => false;
  @override
  Stream<AuthState> get changes => const Stream.empty();
  @override
  Future<Never> access() async => throw const NoGymAccessException();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('Account without tenant membership is routed to gym setup', () async {
    final session = SessionCubit(GymSetupRepository());
    expect((await session.stream.first).status, SessionStatus.needsGym);
    await session.close();
  });
  testWidgets('Gym setup validates and explicitly creates named workspace', (
    tester,
  ) async {
    final repo = GymSetupRepository();
    var restored = false;
    await tester.pumpWidget(
      MaterialApp(
        home: GymSetupPage(
          repository: repo,
          onComplete: () async {
            restored = true;
          },
          onSignOut: () async {},
        ),
      ),
    );
    await tester.tap(find.text('Create gym workspace'));
    await tester.pumpAndSettle();
    expect(find.text('Enter your gym name'), findsOneWidget);
    expect(repo.createdName, isNull);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Gym name'),
      '  My Gym  ',
    );
    await tester.tap(find.text('Create gym workspace'));
    await tester.pumpAndSettle();
    expect(repo.createdName, 'My Gym');
    expect(restored, isTrue);
  });
}
