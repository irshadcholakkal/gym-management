import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/auth/data/auth_callback.dart';

void main() {
  test('Direct invitation and recovery links open password setup', () {
    for (final type in ['invite', 'recovery']) {
      for (final url in [
        'https://gym.example.com/?token_hash=test-hash&type=$type',
        'https://gym.example.com/#/recovery?token_hash=test-hash&type=$type',
      ]) {
        final callback = AuthCallback.parse(Uri.parse(url));
        expect(callback.isCallback, isTrue);
        expect(callback.passwordToken, 'test-hash');
        expect(callback.parameters['type'], type);
      }
    }
    expect(
        AuthCallback.parse(
                Uri.parse('https://gym.example.com/?token_hash=x&type=signup'))
            .passwordToken,
        isNull);
  });
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
