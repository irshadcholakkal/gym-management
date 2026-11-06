import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import '../domain/access.dart';

enum SessionStatus { loading, signedOut, signedIn, recovery, needsGym, denied }

class SessionState {
  const SessionState(this.status, {this.access, this.message});
  final SessionStatus status;
  final GymAccess? access;
  final String? message;
}

class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this.repository)
      : super(const SessionState(SessionStatus.loading)) {
    _subscription = repository.changes.listen((event) {
      if (event.event == AuthChangeEvent.passwordRecovery) {
        _passwordRecovery = true;
        ++_generation;
        emit(const SessionState(SessionStatus.recovery));
      } else {
        if (event.event == AuthChangeEvent.signedOut ||
            (event.event == AuthChangeEvent.signedIn &&
                state.access != null &&
                event.session?.user.id != state.access!.userId)) {
          ++_generation;
          _restoring = null;
          _passwordRecovery = false;
        }
        unawaited(restore());
      }
    }, onError: (Object error, StackTrace stack) {
      // Offline token refresh errors must not escape into the UI.
    });
    _accessTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (state.status == SessionStatus.signedIn) unawaited(restore());
    });
    unawaited(restore());
  }
  final AuthRepository repository;
  StreamSubscription<AuthState>? _subscription;
  int _generation = 0;
  Timer? _accessTimer;
  Future<void>? _restoring;
  bool _passwordRecovery = false;

  Future<void> restore() {
    if (isClosed) return Future<void>.value();
    final pending = _restoring;
    if (pending != null) return pending;
    late final Future<void> check;
    check = _restore().whenComplete(() {
      if (identical(_restoring, check)) _restoring = null;
    });
    return _restoring = check;
  }

  Future<void> _restore() async {
    if (isClosed) return;
    final generation = ++_generation;
    if (!repository.signedIn && repository is SupabaseAuthRepository) {
      await (repository as SupabaseAuthRepository).restoreBackupSession();
      if (isClosed || generation != _generation) return;
    }
    if (!repository.signedIn) {
      emit(const SessionState(SessionStatus.signedOut));
      return;
    }
    if (_passwordRecovery || repository.requiresPasswordSetup) {
      emit(const SessionState(SessionStatus.recovery));
      return;
    }
    try {
      final access =
          await repository.access().timeout(const Duration(seconds: 15));
      if (!isClosed && generation == _generation) {
        final previous = state.access;
        if (state.status != SessionStatus.signedIn ||
            previous == null ||
            previous.gymId != access.gymId ||
            previous.userId != access.userId ||
            previous.role != access.role ||
            previous.permissionKey != access.permissionKey ||
            previous.name != access.name ||
            previous.gymName != access.gymName) {
          emit(SessionState(SessionStatus.signedIn, access: access));
        }
        // Persist the last server-verified access so a later launch with no
        // network can still open the workspace instead of failing closed.
        unawaited(repository.cacheAccess(access));
      }
    } on NoGymAccessException {
      if (!isClosed && generation == _generation) {
        emit(const SessionState(SessionStatus.needsGym));
      }
    } on PostgrestException catch (error) {
      if (!isClosed && generation == _generation) {
        final message = ['PGRST205', '42P01', 'PGRST202', '42703', 'PGRST204']
                .contains(error.code)
            ? 'The gym database is not configured yet. Contact the app administrator to apply the database migrations.'
            : 'The server could not authorize gym access. Please retry or contact your administrator.';
        emit(SessionState(SessionStatus.denied, message: message));
      }
    } on AuthException catch (error) {
      if (!isClosed && generation == _generation) {
        emit(SessionState(SessionStatus.denied, message: error.message));
      }
    } catch (_) {
      if (!isClosed && generation == _generation) {
        // A failed background network check must not destroy an already
        // authorized, local-first workspace. Explicit access denials above
        // still take effect immediately; a fresh launch fails open with the
        // last verified access instead of locking the user out.
        if (state.status == SessionStatus.signedIn && repository.signedIn) {
          return;
        }
        if (repository.signedIn) {
          final cached = await repository.cachedAccess();
          if (!isClosed &&
              generation == _generation &&
              repository.signedIn &&
              cached != null) {
            emit(SessionState(SessionStatus.signedIn, access: cached));
            return;
          }
        }
        emit(
          const SessionState(
            SessionStatus.denied,
            message:
                'Unable to verify gym access. Check your connection or contact your administrator.',
          ),
        );
      }
    }
  }

  Future<void> signOut() async {
    final generation = ++_generation;
    await repository.signOut();
    if (!isClosed && generation == _generation) {
      emit(const SessionState(SessionStatus.signedOut));
    }
  }

  @override
  Future<void> close() async {
    ++_generation;
    _accessTimer?.cancel();
    await _subscription?.cancel();
    return super.close();
  }
}
