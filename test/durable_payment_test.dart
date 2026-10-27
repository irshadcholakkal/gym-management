import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/sync/durable_operations.dart';
import 'package:gym_saas/core/sync/workspace_repository.dart';
import 'package:gym_saas/features/auth/domain/access.dart';
import 'package:gym_saas/features/subscriptions/data/operations_repository.dart';

class PaymentTransport implements OperationsRepository {
  final ids = <String>[];
  bool connected = false;
  @override
  Future<Map<String, dynamic>> pay(
    String invoice,
    int amount,
    String method,
    String reference,
    String operation,
  ) async {
    ids.add(operation);
    if (!connected) throw StateError('Connection lost after request');
    return {'confirmed': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'Interrupted payment keeps its operation ID across repository recreation',
    () async {
      final db = GymDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      final workspace = WorkspaceRepository(
        db,
        const GymAccess(
          gymId: 'gym',
          userId: 'user',
          name: 'Owner',
          gymName: 'Gym',
          role: GymRole.owner,
        ),
      );
      final transport = PaymentTransport();
      await expectLater(
        DurableOperations(
          transport,
          workspace,
        ).pay('invoice', 10000, 'cash', 'Ref', 'original-op'),
        throwsStateError,
      );
      expect(
        (await workspace.watchOutbox().first).single.state,
        'confirmation',
      );
      await workspace.retry('original-op');
      expect(
        (await workspace.watchOutbox().first).single.state,
        'confirmation',
      );
      await expectLater(
        DurableOperations(
          transport,
          workspace,
        ).pay('invoice', 20000, 'cash', 'Ref', 'different-op'),
        throwsStateError,
      );
      transport.connected = true;
      await DurableOperations(
        transport,
        workspace,
      ).pay('invoice', 10000, 'cash', 'Ref', 'new-dialog-op');
      expect(transport.ids, ['original-op', 'original-op']);
      expect(await workspace.watchOutbox().first, isEmpty);
    },
  );
}
