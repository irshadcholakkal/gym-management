abstract final class AppConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const key = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  static const redirect = String.fromEnvironment('AUTH_REDIRECT_URL');
  static bool get configured => url.startsWith('https://') && key.isNotEmpty;
}
