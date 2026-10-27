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
        role: GymRole.owner,
      ),
    );
  });
  tearDown(() => db.close());
  test(
    'Optimistic member and outbox persist together and emit immediately',
    () async {
      final id = await repo.save('members', {
        'full_name': 'Amina',
        'phone': '+971501234567',
        'status': 'active',
        'joining_date': '2026-01-01',
      });
      final records = await repo.watch('members').first;
      final ops = await repo.watchOutbox().first;
      expect(records.single.id, id);
      expect(records.single.syncState, 'pending');
      expect(ops.single.recordId, id);
      expect(ops.single.expectedVersion, 0);
      await expectLater(
        repo.save('members', {
          'full_name': 'Changed',
          'phone': '+971501234567',
          'status': 'active',
          'joining_date': '2026-01-01',
        }, id: id),
        throwsStateError,
      );
      expect((await repo.watchOutbox().first).length, 1);
    },
  );
  test('Different gym/user/role scopes cannot read cached records', () async {
    await repo.save('members', {
      'full_name': 'Private',
      'phone': '+971501234567',
      'joining_date': '2026-01-01',
      'status': 'active',
    });
    final other = WorkspaceRepository(
      db,
      const GymAccess(
        gymId: 'other',
        userId: 'other',
        name: 'Other',
        gymName: 'Gym',
        role: GymRole.owner,
      ),
    );
    expect(await other.watch('members').first, isEmpty);
    final trainer = WorkspaceRepository(
      db,
      const GymAccess(
        gymId: 'gym',
        userId: 'user',
        name: 'User',
        gymName: 'Gym',
        role: GymRole.trainer,
      ),
    );
    expect(await trainer.watch('members').first, isEmpty);
    await expectLater(
      trainer.save('members', {'full_name': 'Denied'}),
      throwsStateError,
    );
  });
}
