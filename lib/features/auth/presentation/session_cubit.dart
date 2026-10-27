import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/auth_repository.dart';
import '../domain/access.dart';

enum SessionStatus { loading, signedOut, signedIn, recovery, denied }

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
        ++_generation;
        emit(const SessionState(SessionStatus.recovery));
      } else {
        unawaited(restore());
      }
    });
    unawaited(restore());
  }
  final AuthRepository repository;
  StreamSubscription<AuthState>? _subscription;
  int _generation = 0;
  Future<void> restore() async {
    final generation = ++_generation;
    if (!repository.signedIn) {
      emit(const SessionState(SessionStatus.signedOut));
      return;
    }
    if (repository.requiresPasswordSetup) {
      emit(const SessionState(SessionStatus.recovery));
      return;
    }
    try {
      final access = await repository.access();
      if (!isClosed && generation == _generation) {
        emit(SessionState(SessionStatus.signedIn, access: access));
      }
    } catch (_) {
      if (!isClosed && generation == _generation) {
        emit(
          const SessionState(
            SessionStatus.denied,
            message: 'Unable to verify gym access. Check your connection or contact your administrator.',
          ),
        );
      }
    }
  }

  Future<void> signOut() async {
    ++_generation;
    await repository.signOut();
    emit(const SessionState(SessionStatus.signedOut));
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    return super.close();
  }
}
