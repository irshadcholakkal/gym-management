import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app.dart';
import 'core/config.dart';
import 'features/auth/data/auth_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SupabaseAuthRepository? repository;
  if (AppConfig.configured) {
    await Supabase.initialize(
      url: AppConfig.url,
      publishableKey: AppConfig.key,
    );
    final client = Supabase.instance.client;
    repository = SupabaseAuthRepository(client);
    // Restore a preserved session before the UI reads the sign-in state, so
    // lost auth storage no longer ends in an automatic logout.
    await repository.restoreBackupSession();
  }
  runApp(GymProApp(
    client: AppConfig.configured ? Supabase.instance.client : null,
    repository: repository,
  ));
}
