import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/auth/data/auth_repository.dart';
import 'package:gym_saas/features/auth/domain/access.dart';
import 'package:gym_saas/features/auth/presentation/session_cubit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const testAccess = GymAccess(
    gymId: 'gym',
    userId: 'user',
    name: 'Owner',
    gymName: 'Gym',
    role: GymRole.owner);

class NetworkAuth implements AuthRepository {
  final events = StreamController<AuthState>.broadcast();
  Object? failure;
  Completer<GymAccess>? pending;
  bool authenticated = true;
  GymAccess? cached;
  @override
  Stream<AuthState> get changes => events.stream;
  @override
  bool get signedIn => authenticated;
  @override
  bool get requiresPasswordSetup => false;
  @override
  Future<GymAccess> access() async {
    if (failure != null) throw failure!;
    return pending == null ? Future.value(testAccess) : pending!.future;
  }

  @override
  Future<GymAccess?> cachedAccess() async => cached;
  @override
  Future<void> cacheAccess(GymAccess access) async => cached = access;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
      'Background network failure retains the authorized workspace; access denial still locks it',
      () async {
    final auth = NetworkAuth();
    final session = SessionCubit(auth);
    await Future<void>.delayed(Duration.zero);
    expect(session.state.status, SessionStatus.signedIn);
    final authorized = session.state;
    auth.failure = TimeoutException('Offline');
    await session.restore();
    expect(identical(session.state, authorized), isTrue);
    auth.failure = const AuthException('Access revoked');
    await session.restore();
    expect(session.state.status, SessionStatus.denied);
    auth.failure = null;
    await session.restore();
    auth.failure =
        const PostgrestException(message: 'Permission denied', code: '42501');
    await session.restore();
    expect(session.state.status, SessionStatus.denied);
    await session.close();
    await auth.events.close();
  });
  test('Initial access fails closed when the network is unavailable', () async {
    final auth = NetworkAuth()..failure = TimeoutException('Offline');
    final session = SessionCubit(auth);
    await Future<void>.delayed(Duration.zero);
    expect(session.state.status, SessionStatus.denied);
    await session.close();
    await auth.events.close();
  });
  test(
      'Initial launch with no network opens the last verified access instead of logging out',
      () async {
    final auth = NetworkAuth()
      ..failure = TimeoutException('Offline')
      ..cached = testAccess;
    final session = SessionCubit(auth);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(session.state.status, SessionStatus.signedIn);
    expect(session.state.access, testAccess);
    // The retained workspace also re-verifies in the background once the
    // network returns, without any additional failure loop.
    auth.failure = null;
    await session.restore();
    expect(session.state.status, SessionStatus.signedIn);
    await session.close();
    await auth.events.close();
  });
  test('Closing during an access check ignores its late result', () async {
    final auth = NetworkAuth()..pending = Completer<GymAccess>();
    final session = SessionCubit(auth);
    await session.close();
    auth.pending!.complete(testAccess);
    await Future<void>.delayed(Duration.zero);
    await session.restore();
    expect(session.isClosed, isTrue);
    await auth.events.close();
  });
}
