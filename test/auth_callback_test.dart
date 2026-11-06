import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/auth/data/auth_callback.dart';

void main() {
  for (final fragment in [
    'access_token=test-access&refresh_token=test-refresh&type=invite',
    '/recovery#access_token=test-access&refresh_token=test-refresh&type=invite',
    '/recovery?access_token=test-access&refresh_token=test-refresh&type=invite',
  ]) {
    test('Invitation credentials survive callback fragment $fragment', () {
      final callback = AuthCallback.parse(
        Uri.parse('https://gym.example.com/#$fragment'),
      );
      expect(callback.isCallback, isTrue);
      expect(callback.parameters['access_token'], 'test-access');
      expect(callback.parameters['refresh_token'], 'test-refresh');
      expect(Uri.splitQueryString(callback.uri.fragment)['type'], 'invite');
      expect(callback.uri.fragment, isNot(contains('/recovery')));
    });
  }

  test('PKCE callbacks and expired links remain detectable', () {
    final callback = AuthCallback.parse(
      Uri.parse('https://gym.example.com/?code=test-code'),
    );
    expect(callback.isCallback, isTrue);
    expect(callback.parameters['code'], 'test-code');
    final expired = AuthCallback.parse(Uri.parse(
      'https://gym.example.com/#/recovery#error=access_denied&error_code=otp_expired',
    ));
    expect(expired.isCallback, isTrue);
    expect(expired.parameters['error_code'], 'otp_expired');
  });

  test('Ordinary app routes are not treated as authentication callbacks', () {
    expect(
        AuthCallback.parse(Uri.parse('https://gym.example.com/#/team'))
            .isCallback,
        isFalse);
  });
}
