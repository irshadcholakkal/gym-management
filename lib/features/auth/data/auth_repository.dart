import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/access.dart';

abstract interface class AuthRepository {
  Stream<AuthState> get changes;
  bool get signedIn;
  bool get requiresPasswordSetup;
  Future<void> signIn(String email, String password);
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
    String? redirect,
  });
  Future<void> signOut();
  Future<void> resetPassword(String email, String? redirect);
  Future<GymAccess> access();
  Future<GymAccess?> cachedAccess();
  Future<void> cacheAccess(GymAccess access);
  Future<void> createGym(String name);
  Future<void> dispose();
}

class NoGymAccessException extends AuthException {
  const NoGymAccessException()
      : super(
          'Set up a new gym or ask your administrator for a workspace invitation.',
        );
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this.client, {this.passwordRecovery = false}) {
    // Mirror every live session into a separate backup key. A token refresh
    // rejected with a 4xx makes gotrue delete its own storage entry, which
    // used to log the user out permanently; the backup lets the next launch
    // restore the session while the refresh token is still valid.
    _backupSubscription = client.auth.onAuthStateChange.listen((event) {
      final session = event.session;
      if (session != null) {
        unawaited(_persistBackup(jsonEncode(session.toJson())));
      } else if (event.event == AuthChangeEvent.signedOut) {
        // Keep the backup on an unexpected sign-out (storage glitch, token
        // rotation race); only a deliberate sign-out clears it.
        if (_signingOut) unawaited(_persistBackup(null));
      }
    }, onError: (Object error, StackTrace stack) {
      // Retryable refresh failures must not become unhandled stream errors.
    });
    final session = client.auth.currentSession;
    if (session != null) {
      unawaited(_persistBackup(jsonEncode(session.toJson())));
    }
  }
  final SupabaseClient client;
  bool passwordRecovery;
  static const _sessionBackupKey = 'gympro_session_backup';
  static const _accessCacheKey = 'gympro_last_access';
  bool _signingOut = false;
  StreamSubscription<AuthState>? _backupSubscription;
  Future<void> _backupWrites = Future<void>.value();
  Future<bool>? _restoringBackup;

  Future<void> _persistBackup(String? value) =>
      _backupWrites = _backupWrites.then((_) => _writeBackup(value));

  Future<void> _writeBackup(String? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(_sessionBackupKey);
      } else {
        await prefs.setString(_sessionBackupKey, value);
      }
    } catch (_) {
      // Backup storage is best-effort; never block auth on it.
    }
  }

  /// Restores a preserved session after the auth storage lost it.
  /// Returns true when a session is available afterwards.
  Future<bool> restoreBackupSession() => _restoringBackup ??=
      _restoreBackupSession().whenComplete(() => _restoringBackup = null);

  Future<bool> _restoreBackupSession() async {
    try {
      if (_signingOut) return false;
      if (client.auth.currentSession != null) return true;
      await _backupWrites;
      final prefs = await SharedPreferences.getInstance();
      final backup = prefs.getString(_sessionBackupKey);
      if (backup == null) return false;
      final session =
          Session.fromJson(jsonDecode(backup) as Map<String, dynamic>);
      final refreshToken = session?.refreshToken;
      if (refreshToken == null || refreshToken.isEmpty) return false;
      await client.auth
          .recoverSession(backup)
          .timeout(const Duration(seconds: 15));
      return client.auth.currentSession != null;
    } catch (_) {
      // An expired or revoked backup token must never block sign-in.
      return false;
    }
  }

  @override
  Future<GymAccess?> cachedAccess() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final access = GymAccess.fromJson(prefs.getString(_accessCacheKey));
      return access?.userId == client.auth.currentUser?.id ? access : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cacheAccess(GymAccess access) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_accessCacheKey, jsonEncode(access.toJson()));
    } catch (_) {
      // Best effort; the next successful access check rewrites it.
    }
  }

  @override
  Future<void> dispose() async {
    await _backupSubscription?.cancel();
    _backupSubscription = null;
  }

  @override
  Future<void> createGym(String name) async {
    await client.rpc('create_own_gym', params: {'p_name': name.trim()});
  }

  @override
  Stream<AuthState> get changes => client.auth.onAuthStateChange;
  @override
  bool get signedIn => client.auth.currentSession != null;
  @override
  bool get requiresPasswordSetup =>
      passwordRecovery ||
      client.auth.currentUser?.userMetadata?['requires_password_setup'] == true;
  @override
  Future<void> signIn(String email, String password) async {
    final identifier = email.trim().toLowerCase();
    if (identifier.contains('@')) {
      await client.auth
          .signInWithPassword(email: identifier, password: password);
      return;
    }
    try {
      final response = await client.functions.invoke('employee-login',
          body: {'identifier': identifier, 'password': password});
      final token =
          response.data is Map ? response.data['refresh_token'] : null;
      if (response.status != 200 || token is! String) {
        throw const AuthException('Invalid employee ID, username or password.');
      }
      await client.auth.setSession(token);
    } on FunctionException catch (error) {
      throw AuthException(error.status == 429
          ? 'Too many sign-in attempts. Try again in 15 minutes.'
          : 'Invalid employee ID, username or password.');
    }
  }

  @override
  Future<void> signOut() async {
    // Mark intent first so the backup listener clears the preserved session.
    _signingOut = true;
    passwordRecovery = false;
    try {
      await client.auth.signOut();
      await _persistBackup(null);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_accessCacheKey);
    } finally {
      _signingOut = false;
    }
  }

  @override
  Future<bool> signUp({
    required String fullName,
    required String email,
    required String password,
    String? redirect,
  }) async {
    final response = await client.auth.signUp(
      email: email.trim().toLowerCase(),
      password: password,
      data: {'full_name': fullName.trim()},
      emailRedirectTo: redirect,
    );
    return response.session == null;
  }

  @override
  Future<void> resetPassword(String email, String? redirect) => client.auth
      .resetPasswordForEmail(email.trim().toLowerCase(), redirectTo: redirect);
  @override
  Future<GymAccess> access() async {
    final user = client.auth.currentUser!;
    final rows = await client
        .from('gym_users')
        // Select the available membership columns so pre-migration databases
        // can still authorize existing users. Missing options keep role defaults.
        .select('*, gyms(name)')
        .eq('user_id', user.id)
        .eq('active', true)
        .order('created_at')
        .limit(1);
    if (rows.isEmpty) {
      final memberships = await client
          .from('gym_users')
          .select('id')
          .eq('user_id', user.id)
          .limit(1);
      if (memberships.isNotEmpty) {
        throw const AuthException(
          'Your gym access is inactive. Contact your gym administrator.',
        );
      }
      throw const NoGymAccessException();
    }
    final row = rows.first;
    return GymAccess(
      gymId: row['gym_id'] as String,
      userId: user.id,
      name: user.userMetadata?['full_name'] as String? ??
          user.email ??
          'Team member',
      gymName: (row['gyms'] as Map)['name'] as String,
      role: GymRole.values.byName(row['role'] as String),
      options: Map<String, bool>.from(row['access_options'] as Map? ?? {}),
    );
  }
}
