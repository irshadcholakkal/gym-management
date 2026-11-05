import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/sync/sync_engine.dart';
import 'package:gym_saas/core/sync/workspace_repository.dart';
import 'package:gym_saas/features/auth/domain/access.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late GymDatabase db;
  late WorkspaceRepository repo;
  late SyncEngine sync;
  late Future<void> Function(HttpRequest) handle;
  Future<void> reply(HttpRequest request, Object body,
      {int status = 200}) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    handle = (r) => reply(r, {'changes': [], 'cursor': 0, 'has_more': false});
    server.listen((r) => unawaited(handle(r)));
    client = SupabaseClient('http://127.0.0.1:${server.port}', 'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    db = GymDatabase.forTesting(NativeDatabase.memory());
    repo = WorkspaceRepository(
        db,
        const GymAccess(
            gymId: 'gym',
            userId: 'user',
            name: 'Owner',
            gymName: 'Gym',
            role: GymRole.owner));
    sync = SyncEngine(repo, client, autoStart: false);
  });
  tearDown(() async {
    await sync.close();
    await db.close();
    await client.dispose();
    await server.close(force: true);
  });
  test('Expired JWT refreshes and retries sync without logging out', () async {
    String token(int expiry) {
      final encoded = [
        {'alg': 'HS256', 'typ': 'JWT'},
        {'sub': 'user', 'exp': expiry}
      ]
          .map((v) =>
              base64Url.encode(utf8.encode(jsonEncode(v))).replaceAll('=', ''))
          .join('.');
      return '$encoded.signature';
    }

    final expires = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600;
    Map<String, dynamic> session(String jwt) => {
          'access_token': jwt,
          'refresh_token': 'refresh-token',
          'token_type': 'bearer',
          'expires_in': 3600,
          'user': {
            'id': 'user',
            'aud': 'authenticated',
            'created_at': '2026-01-01T00:00:00Z',
            'app_metadata': {},
            'user_metadata': {}
          }
        };
    await client.auth.recoverSession(jsonEncode(session(token(expires))));
    var pulls = 0, refreshes = 0;
    handle = (r) async {
      await r.drain<void>();
      if (r.uri.path == '/auth/v1/token') {
        refreshes++;
        await reply(r, session(token(expires + 3600)));
      } else if (++pulls == 1) {
        await reply(r, {'code': 'PGRST303', 'message': 'JWT expired'},
            status: 401);
      } else {
        await reply(r, {'changes': [], 'cursor': 1, 'has_more': false});
      }
    };
    await sync.sync();
    expect(refreshes, 1);
    expect(pulls, 2);
    expect(client.auth.currentSession, isNotNull);
    expect(sync.state.error, isNull);
  });
  test('Concurrent sync callers wait for a queued follow-up pull', () async {
    final arrived = Completer<void>(), release = Completer<void>();
    var pulls = 0;
    handle = (r) async {
      await r.drain<void>();
      pulls++;
      if (pulls == 1) {
        arrived.complete();
        await release.future;
      }
      await reply(r, {'changes': [], 'cursor': pulls, 'has_more': false});
    };
    final first = sync.sync();
    await arrived.future;
    final second = sync.sync();
    var completed = false;
    unawaited(second.then((_) => completed = true));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    release.complete();
    await Future.wait([first, second]);
    expect(pulls, 2);
    expect(sync.state.running, isFalse);
  });
  test('Previously stranded offline edits recover without resetting local data',
      () async {
    await repo.save('members', {
      'full_name': 'Offline member',
      'phone': '+971501234567',
      'joining_date': '2026-01-01',
      'status': 'active'
    });
    await db.update(db.syncOperations).write(const SyncOperationsCompanion(
        state: Value('failed'),
        attempts: Value(8),
        error:
            Value('Server unreachable. Your change remains on this device.')));
    handle = (r) async {
      final body = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
      await reply(
          r,
          r.uri.path.endsWith('apply_sync_operation')
              ? {...body['p_data'] as Map, 'version': 1}
              : {'changes': [], 'cursor': 1, 'has_more': false});
    };
    await sync.sync();
    expect(await repo.watchOutbox().first, isEmpty);
    expect((await repo.watch('members').first).single.syncState, 'synced');
  });
  test(
      'Offline queue stops after one failure and remains retryable after eight attempts',
      () async {
    for (var i = 0; i < 3; i++) {
      await repo.save('members', {
        'full_name': 'Member $i',
        'phone': '+971501234567',
        'joining_date': '2026-01-01',
        'status': 'active'
      });
    }
    await db
        .update(db.syncOperations)
        .write(const SyncOperationsCompanion(attempts: Value(9)));
    var requests = 0;
    handle = (r) async {
      await r.drain<void>();
      requests++;
      await reply(r, {'message': 'Service unavailable', 'code': '503'},
          status: 503);
    };
    await sync.sync();
    expect(requests, 1);
    final queued = await repo.watchOutbox().first;
    expect(queued, hasLength(3));
    expect(queued.every((o) => o.state == 'pending'), isTrue);
    expect(sync.state.error, isNotNull);
    // Returning connectivity succeeds with the same operation IDs, no login.
    await db.update(db.syncOperations).write(SyncOperationsCompanion(
        nextAttempt:
            Value(DateTime.now().subtract(const Duration(seconds: 1)))));
    handle = (r) async {
      final body = jsonDecode(await utf8.decoder.bind(r).join()) as Map;
      if (r.uri.path.endsWith('apply_sync_operation')) {
        await reply(r, {...body['p_data'] as Map, 'version': 1});
      } else {
        await reply(r, {'changes': [], 'cursor': 1, 'has_more': false});
      }
    };
    await sync.sync();
    expect(await repo.watchOutbox().first, isEmpty);
    expect(sync.state.error, isNull);
  });
}
