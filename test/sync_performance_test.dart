import 'dart:async';
import 'dart:convert';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/sync/workspace_repository.dart';
import 'package:gym_saas/features/auth/domain/access.dart';

void main() {
  late GymDatabase db;
  late WorkspaceRepository repo;
  setUp(() {
    db = GymDatabase.forTesting(NativeDatabase.memory());
    repo = WorkspaceRepository(
        db,
        const GymAccess(
            gymId: 'gym',
            userId: 'user',
            name: 'Owner',
            gymName: 'Gym',
            role: GymRole.owner));
  });
  tearDown(() => db.close());
  Map<String, dynamic> change(String kind, String id, {bool deleted = false}) =>
      {
        'kind': kind,
        'record_id': id,
        'deleted': deleted,
        'payload': {'version': 1, 'full_name': id, 'status': 'active'},
      };
  test('A large pull page is atomic and ordered, and advances its checkpoint',
      () async {
    final changes = [
      for (var i = 0; i < 1000; i++) change('members', 'member-$i'),
      change('members', 'member-0', deleted: true),
      change('members', 'member-0')
    ];
    await repo.applyRemoteChanges(changes, 1002);
    expect(await repo.watch('members').first, hasLength(1000));
    expect((await db.select(db.syncCheckpoints).getSingle()).cursor, 1002);
    await repo.applyRemoteChanges(
        [change('members', 'member-0', deleted: true)], 1003);
    expect(await repo.watch('members').first, hasLength(999));
  });
  test(
      'Remote deletion preserves a pending local edit and its outbox operation',
      () async {
    final id = await repo.save('members', {
      'full_name': 'Unsynced member',
      'phone': '+971501234567',
      'joining_date': '2026-01-01',
      'status': 'active'
    });
    await repo.applyRemoteChanges([change('members', id, deleted: true)], 1);
    final record = (await repo.watch('members').first).single;
    expect(record.syncState, 'pending');
    expect((jsonDecode(record.payload) as Map)['full_name'], 'Unsynced member');
    expect(await repo.watchOutbox().first, hasLength(1));
  });
  test('Malformed pull pages do not commit partial data or advance the cursor',
      () async {
    await repo.applyRemoteChanges([change('members', 'existing')], 1);
    await expectLater(
        repo.applyRemoteChanges([
          change('members', 'new'),
          {'kind': 'members', 'record_id': 'invalid', 'payload': {}}
        ], 2),
        throwsA(isA<TypeError>()));
    expect((await db.select(db.syncCheckpoints).getSingle()).cursor, 1);
    expect((await repo.watch('members').first).map((r) => r.id), ['existing']);
  });
  test(
      'Unrelated updates do not rebuild unchanged lists and streams are reused',
      () async {
    expect(
        identical(repo.watchKinds(['members', 'subscriptions']),
            repo.watchKinds(['subscriptions', 'members'])),
        isTrue);
    final events = <List<CachedRecord>>[];
    final first = Completer<void>();
    final subscription = repo.watch('members').listen((rows) {
      events.add(rows);
      if (!first.isCompleted) first.complete();
    });
    await first.future;
    await repo.applyRemoteChanges([change('notifications', 'alert')], 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, hasLength(1));
    await repo.applyRemoteChanges([change('members', 'member')], 2);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, hasLength(2));
    await subscription.cancel();
  });
}
