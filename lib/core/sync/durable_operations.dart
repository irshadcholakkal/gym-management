import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/subscriptions/data/operations_repository.dart';
import '../database/database.dart';
import 'workspace_repository.dart';

/// Server-only commands still persist their identity before the first request.
/// This prevents an uncertain collection from becoming a new payment on refresh.
class DurableOperations implements OperationsRepository {
  DurableOperations(this.inner, this.workspace);
  final OperationsRepository inner;
  final WorkspaceRepository workspace;
  Future<T> _command<T>(
    String action,
    String subject,
    String operation,
    Map<String, dynamic> request,
    Future<T> Function(String) send,
  ) async {
    final db = workspace.db,
        kind = 'server:$action',
        payload = jsonEncode(request);
    final id = await db.transaction(() async {
      final previous =
          await (db.select(db.syncOperations)..where(
                (o) =>
                    o.scope.equals(workspace.scope) &
                    o.kind.equals(kind) &
                    o.recordId.equals(subject),
              ))
              .getSingleOrNull();
      if (previous != null) {
        if (previous.payload != payload) {
          throw StateError(
            'An earlier request for this record is awaiting confirmation. Retry its original details first.',
          );
        }
        return previous.id;
      }
      await db
          .into(db.syncOperations)
          .insert(
            SyncOperationsCompanion.insert(
              id: operation,
              scope: workspace.scope,
              kind: kind,
              recordId: subject,
              payload: payload,
              expectedVersion: 0,
              state: const Value('confirmation'),
              nextAttempt: DateTime.now().toUtc(),
            ),
          );
      return operation;
    });
    late final T result;
    try {
      result = await send(id);
    } on PostgrestException catch (e) {
      if (['P0001', 'P0002', '42501', '40001'].contains(e.code) ||
          e.code?.startsWith('23') == true ||
          e.code?.startsWith('22') == true) {
        await (db.delete(db.syncOperations)
              ..where((o) => o.scope.equals(workspace.scope) & o.id.equals(id)))
            .go();
      }
      rethrow;
    }
    await (db.delete(
      db.syncOperations,
    )..where((o) => o.scope.equals(workspace.scope) & o.id.equals(id))).go();
    return result;
  }

  @override
  Future<void> subscribe(
    String member,
    String package,
    String start,
    String operation,
  ) => _command('subscribe', member, operation, {
    'member': member,
    'package': package,
    'start': start,
  }, (id) => inner.subscribe(member, package, start, id));
  @override
  Future<Map<String, dynamic>> pay(
    String invoice,
    int amount,
    String method,
    String reference,
    String operation,
  ) => _command('pay', invoice, operation, {
    'invoice': invoice,
    'amount': amount,
    'method': method,
    'reference': reference,
  }, (id) => inner.pay(invoice, amount, method, reference, id));
  @override
  Future<void> transition(
    String subscription,
    int version,
    String action,
    String date,
    String reason,
    String operation, {
    int days = 0,
  }) => _command(
    'transition',
    subscription,
    operation,
    {
      'subscription': subscription,
      'version': version,
      'action': action,
      'date': date,
      'reason': reason,
      'days': days,
    },
    (id) => inner.transition(
      subscription,
      version,
      action,
      date,
      reason,
      id,
      days: days,
    ),
  );
  @override
  Future<void> changePackage(
    String subscription,
    int version,
    String package,
    String policy,
    String reason,
    String operation,
  ) => _command(
    'change_package',
    subscription,
    operation,
    {
      'subscription': subscription,
      'version': version,
      'package': package,
      'policy': policy,
      'reason': reason,
    },
    (id) =>
        inner.changePackage(subscription, version, package, policy, reason, id),
  );
  @override
  Future<void> reversePayment(
    String payment,
    String reason,
    String operation,
  ) => _command('reverse', payment, operation, {
    'payment': payment,
    'reason': reason,
  }, (id) => inner.reversePayment(payment, reason, id));
  @override
  Future<void> invite(Map<String, String> fields) => inner.invite(fields);
  @override
  Future<void> deactivate(String user) => inner.deactivate(user);
  @override
  Future<void> readNotification(String id) => inner.readNotification(id);
  @override
  Future<Map<String, dynamic>> receipt(String id) => inner.receipt(id);
  @override
  Future<void> registerPush(Map<String, dynamic> subscription) =>
      inner.registerPush(subscription);
  @override
  Future<bool> isConfirmed(String operation) => inner.isConfirmed(operation);
}
