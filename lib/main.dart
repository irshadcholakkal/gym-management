import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app.dart';
import 'core/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.configured) {
    await Supabase.initialize(
      url: AppConfig.url,
      publishableKey: AppConfig.key,
    );
  }
  runApp(
    GymProApp(client: AppConfig.configured ? Supabase.instance.client : null),
  );
}
