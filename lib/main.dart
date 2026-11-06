import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app.dart';
import 'core/config.dart';
import 'features/auth/data/auth_repository.dart';
import 'features/auth/data/auth_callback.dart';
import 'features/auth/data/auth_callback_location.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SupabaseAuthRepository? repository;
  String? loginMessage;
  if (AppConfig.configured) {
    final callback = AuthCallback.parse(Uri.base);
    final handleCallback = kIsWeb && callback.isCallback;
    await Supabase.initialize(
      url: AppConfig.url,
      publishableKey: AppConfig.key,
      authOptions:
          FlutterAuthClientOptions(detectSessionInUri: !handleCallback),
    );
    final client = Supabase.instance.client;
    var passwordRecovery = false;
    if (handleCallback) {
      try {
        final response = await client.auth.getSessionFromUrl(callback.uri);
        passwordRecovery = response.redirectType == 'recovery';
      } catch (_) {
        loginMessage =
            'This invitation or password reset link has expired or could not be verified. Request a new password reset link below.';
      } finally {
        clearAuthCallbackLocation();
      }
    }
    repository =
        SupabaseAuthRepository(client, passwordRecovery: passwordRecovery);
    // Restore a preserved session before the UI reads the sign-in state, so
    // lost auth storage no longer ends in an automatic logout.
    if (loginMessage != null) {
      await repository.signOut();
    } else {
      await repository.restoreBackupSession();
    }
  }
  runApp(GymProApp(
    client: AppConfig.configured ? Supabase.instance.client : null,
    repository: repository,
    loginMessage: loginMessage,
  ));
}
