import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/auth/data/auth_repository.dart';
import 'package:gym_saas/features/auth/domain/access.dart';
import 'package:gym_saas/features/auth/presentation/session_cubit.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
      'Invited accounts wait for employee access and then open the assigned gym',
      () async {
    var assigned = false;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      expect(request.uri.queryParameters['gym_id'], 'eq.employee-gym');
      request.response.write(jsonEncode(assigned
          ? [
              {
                'gym_id': 'employee-gym',
                'role': 'trainer',
                'gyms': {'name': 'Employer gym'},
                'access_options': <String, bool>{},
              }
            ]
          : []));
      await request.response.close();
    });
    final client =
        SupabaseClient('http://127.0.0.1:${server.port}', 'test-key');
    String encode(Object value) =>
        base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
    final jwt = '${encode({'alg': 'HS256'})}.${encode({
          'sub': 'employee',
          'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600
        })}.test';
    await client.auth.setInitialSession(jsonEncode({
      'access_token': jwt,
      'refresh_token': 'test-refresh',
      'token_type': 'bearer',
      'user': {
        'id': 'employee',
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z',
        'invited_at': '2026-01-01T00:00:00Z',
        'app_metadata': {'employee_gym_id': 'employee-gym'},
        'user_metadata': {}
      },
    }));
    final repository = SupabaseAuthRepository(client);
    final session = SessionCubit(repository);
    addTearDown(() async {
      await session.close();
      await repository.dispose();
      await client.dispose();
      await server.close(force: true);
    });
    await session.restore();
    expect(session.state.status, SessionStatus.denied);
    expect(session.state.message, contains('employee invitation'));
    assigned = true;
    await session.restore();
    expect(session.state.status, SessionStatus.signedIn);
    expect(session.state.access!.gymId, 'employee-gym');
    expect(session.state.access!.role, GymRole.trainer);
  });
}
