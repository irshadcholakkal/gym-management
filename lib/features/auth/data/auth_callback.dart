/// Separates Supabase credentials from Flutter's hash route in email links.
class AuthCallback {
  AuthCallback._(this.uri, this.parameters);

  factory AuthCallback.parse(Uri source) {
    final parameters = Map<String, String>.from(source.queryParameters);
    final fragment = source.fragment.replaceAll(
      RegExp('%23', caseSensitive: false),
      '#',
    );
    final start = RegExp(
      r'(^|[#?&])(access_token|refresh_token|code|error|error_code|error_description)=',
    ).firstMatch(fragment);
    if (start != null) {
      final offset = start.start + (start.group(1)!.isEmpty ? 0 : 1);
      parameters.addAll(Uri.splitQueryString(
        fragment.substring(offset).replaceAll('#', '&'),
      ));
    }
    // getSessionFromUrl expects credentials in a query or a plain fragment,
    // never /recovery#access_token=... or /recovery?access_token=....
    return AuthCallback._(
      source.replace(
          path: '/',
          query: '',
          fragment: Uri(queryParameters: parameters).query),
      parameters,
    );
  }

  final Uri uri;
  final Map<String, String> parameters;
  bool get isCallback => [
        'access_token',
        'code',
        'error',
        'error_code',
        'error_description'
      ].any(parameters.containsKey);
}
