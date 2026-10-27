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
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this.client);
  final SupabaseClient client;
  @override
  Stream<AuthState> get changes => client.auth.onAuthStateChange;
  @override
  bool get signedIn => client.auth.currentSession != null;
  @override
  bool get requiresPasswordSetup =>
      client.auth.currentUser?.userMetadata?['requires_password_setup'] == true;
  @override
  Future<void> signIn(String email, String password) async {
    await client.auth.signInWithPassword(
      email: email.trim().toLowerCase(),
      password: password,
    );
  }

  @override
  Future<void> signOut() => client.auth.signOut();
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
        .select('gym_id, role, gyms(name)')
        .eq('user_id', user.id)
        .eq('active', true)
        .order('created_at')
        .limit(1);
    if (rows.isEmpty) {
      throw const AuthException(
        'Your account has no active gym access. Contact your administrator.',
      );
    }
    final row = rows.first;
    return GymAccess(
      gymId: row['gym_id'] as String,
      userId: user.id,
      name:
          user.userMetadata?['full_name'] as String? ??
          user.email ??
          'Team member',
      gymName: (row['gyms'] as Map)['name'] as String,
      role: GymRole.values.byName(row['role'] as String),
    );
  }
}
