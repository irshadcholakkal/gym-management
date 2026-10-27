import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../database/database.dart';
import 'workspace_repository.dart';
import 'connectivity_native.dart'
    if (dart.library.js_interop) 'connectivity_web.dart';

class SyncStatus {
  const SyncStatus({this.running = false, this.error, this.lastSync});
  final bool running;
  final String? error;
  final DateTime? lastSync;
}

class SyncEngine extends Cubit<SyncStatus> {
  SyncEngine(this.repository, this.client, {this.onAccessDenied})
    : super(const SyncStatus()) {
    _stopConnectivity = onConnectivityRestored(() => unawaited(sync()));
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => sync());
    _outbox = repository.watchOutbox().listen((_) => sync());
    _channel =
        client.channel(
            'gym:${repository.access.gymId}',
            opts: const RealtimeChannelConfig(private: true),
          )
          ..onBroadcast(event: 'changed', callback: (_) => sync())
          ..subscribe();
    unawaited(sync());
  }
  final WorkspaceRepository repository;
  final SupabaseClient client;
  final Future<void> Function()? onAccessDenied;
  Timer? _timer;
  late final void Function() _stopConnectivity;
  StreamSubscription<List<SyncOperation>>? _outbox;
  RealtimeChannel? _channel;
  bool _running = false, _stopping = false;
  Future<void> sync() async {
    if (_running || _stopping) return;
    _running = true;
    emit(SyncStatus(running: true, lastSync: state.lastSync));
    final db = repository.db, scope = repository.scope;
    try {
      final ops =
          await (db.select(db.syncOperations)..where(
                (o) =>
                    o.scope.equals(scope) &
                    o.state.equals('pending') &
                    o.nextAttempt.isSmallerOrEqualValue(DateTime.now().toUtc()),
              ))
              .get();
      for (final op in ops) {
        if (_stopping) break;
        try {
          final result = Map<String, dynamic>.from(
            await client.rpc(
              'apply_sync_operation',
              params: {
                'p_gym': repository.access.gymId,
                'p_operation': op.id,
                'p_kind': op.kind,
                'p_id': op.recordId,
                'p_expected': op.expectedVersion,
                'p_data': jsonDecode(op.payload),
              },
            ) as Map,
          );
          await db.transaction(() async {
            await db
                .into(db.cachedRecords)
                .insertOnConflictUpdate(
                  CachedRecordsCompanion.insert(
                    scope: scope,
                    kind: op.kind,
                    id: op.recordId,
                    payload: jsonEncode(result),
                    version: Value(result['version'] as int),
                    syncState: const Value('synced'),
                  ),
                );
            await (db.delete(
              db.syncOperations,
            )..where((o) => o.id.equals(op.id))).go();
          });
        } on PostgrestException catch (e) {
          final conflict = e.code == '40001';
          final denied = e.code == '42501';
          if (denied) {
            unawaited(onAccessDenied?.call());
          }
          await _fail(
            op,
            conflict
                ? 'conflict'
                : denied
                ? 'approval'
                : op.attempts >= 7
                ? 'failed'
                : 'pending',
            e.message,
          );
        } catch (_) {
          await _fail(
            op,
            op.attempts >= 7 ? 'failed' : 'pending',
            'Server unreachable. Your change remains on this device.',
          );
        }
      }
      var checkpoint = await (db.select(
        db.syncCheckpoints,
      )..where((c) => c.scope.equals(scope))).getSingleOrNull();
      while (!_stopping) {
        final result = Map<String, dynamic>.from(
          await client.rpc(
            'pull_changes',
            params: {
              'p_gym': repository.access.gymId,
              'p_cursor': checkpoint?.cursor ?? 0,
            },
          ) as Map,
        );
        final changes = (result['changes'] as List)
            .cast<Map<String, dynamic>>();
        await db.transaction(() async {
          for (final change in changes) {
            if (change['deleted'] == true) {
              await (db.delete(db.cachedRecords)..where(
                    (r) =>
                        r.scope.equals(scope) &
                        r.kind.equals(change['kind'] as String) &
                        r.id.equals(change['record_id'] as String),
                  ))
                  .go();
              continue;
            }
            final pending =
                await (db.select(db.syncOperations)..where(
                      (o) =>
                          o.scope.equals(scope) &
                          o.recordId.equals(change['record_id'] as String),
                    ))
                    .get();
            if (pending.isNotEmpty) continue;
            await db
                .into(db.cachedRecords)
                .insertOnConflictUpdate(
                  CachedRecordsCompanion.insert(
                    scope: scope,
                    kind: change['kind'] as String,
                    id: change['record_id'] as String,
                    payload: jsonEncode(change['payload']),
                    syncState: const Value('synced'),
                    version: Value(
                      (change['payload'] as Map)['version'] as int,
                    ),
                  ),
                );
          }
          await db
              .into(db.syncCheckpoints)
              .insertOnConflictUpdate(
                SyncCheckpointsCompanion.insert(
                  scope: scope,
                  cursor: Value(result['cursor'] as int),
                ),
              );
        });
        checkpoint = SyncCheckpoint(
          scope: scope,
          cursor: result['cursor'] as int,
        );
        if (result['has_more'] != true) break;
      }
      if (!_stopping) emit(SyncStatus(lastSync: DateTime.now().toUtc()));
    } on PostgrestException catch (e) {
      if (e.code == '42501') {
        unawaited(onAccessDenied?.call());
      }
      if (!_stopping) {
        emit(
          SyncStatus(
            error: 'Server authorization or synchronization failed. Revalidating access when required.',
            lastSync: state.lastSync,
          ),
        );
      }
    } catch (_) {
      if (!_stopping) {
        emit(
          SyncStatus(
            error: 'Unable to sync. Cached records are available; retry when connected.',
            lastSync: state.lastSync,
          ),
        );
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _fail(SyncOperation op, String status, String message) async {
    await repository.db.transaction(() async {
      await (repository.db.update(
        repository.db.syncOperations,
      )..where((o) => o.id.equals(op.id))).write(
        SyncOperationsCompanion(
          attempts: Value(op.attempts + 1),
          state: Value(status),
          error: Value(message),
          nextAttempt: Value(
            DateTime.now().toUtc().add(
              Duration(seconds: min(900, 2 << op.attempts)),
            ),
          ),
        ),
      );
      await (repository.db.update(repository.db.cachedRecords)..where(
            (r) =>
                r.scope.equals(repository.scope) &
                r.id.equals(op.recordId) &
                r.kind.equals(op.kind),
          ))
          .write(CachedRecordsCompanion(syncState: Value(status)));
    });
  }

  @override
  Future<void> close() async {
    _stopping = true;
    _stopConnectivity();
    _timer?.cancel();
    await _outbox?.cancel();
    if (_channel != null) await client.removeChannel(_channel!);
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return super.close();
  }
}
