abstract final class AppConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const key = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  static const redirect = String.fromEnvironment('AUTH_REDIRECT_URL');
  static String? get registrationRedirect => redirect.isEmpty
      ? null
      : Uri.parse(redirect).replace(fragment: '', query: '').toString();
  static bool get configured => url.startsWith('https://') && key.isNotEmpty;
}
