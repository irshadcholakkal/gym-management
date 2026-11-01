import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/auth/data/auth_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
      'Existing gym accounts authorize before and after access-options migration',
      () async {
    var migrated = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      final select = request.uri.queryParameters['select'] ?? '';
      if (!migrated && select.split(',').contains('access_options')) {
        request.response.statusCode = 400;
        request.response.write(jsonEncode({
          'code': '42703',
          'message': 'column gym_users.access_options does not exist'
        }));
      } else {
        expect(request.uri.queryParameters['user_id'], 'eq.user');
        expect(request.uri.queryParameters['active'], 'eq.true');
        request.response.write(jsonEncode([
          {
            'gym_id': 'gym',
            'role': 'admin',
            'gyms': {'name': 'Test gym'},
            if (migrated) 'access_options': {'operations': false},
          }
        ]));
      }
      await request.response.close();
    });
    final client =
        SupabaseClient('http://127.0.0.1:${server.port}', 'test-key');
    addTearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final jwt = '${encode({'alg': 'HS256'})}.${encode({
          'sub': 'user',
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600
        })}.test';
    await client.auth.setInitialSession(jsonEncode({
      'access_token': jwt,
      'refresh_token': 'test-refresh',
      'token_type': 'bearer',
      'user': {
        'id': 'user',
        'aud': 'authenticated',
        'app_metadata': {},
        'user_metadata': {'full_name': 'Admin'},
        'created_at': '2026-01-01T00:00:00Z'
      },
    }));
    final repository = SupabaseAuthRepository(client);
    final legacy = await repository.access();
    expect(legacy.gymId, 'gym');
    expect(legacy.administer, true);
    expect(legacy.finances, true);
    migrated = true;
    final current = await repository.access();
    expect(current.administer, true);
    expect(current.finances, false);
  });
}
