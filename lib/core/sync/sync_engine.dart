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
  SyncEngine(this.repository, this.client,
      {this.onAccessDenied, bool autoStart = true})
      : super(const SyncStatus()) {
    if (!autoStart) return;
    _authSubscription = client.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.tokenRefreshed ||
          event.event == AuthChangeEvent.signedIn) {
        _scheduleSync();
      }
    }, onError: (Object error, StackTrace stack) {});
    _stopConnectivity = onConnectivityRestored(() => unawaited(sync()));
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => sync());
    _outbox = repository.watchOutbox().listen((operations) {
      if (operations.any((op) =>
          op.state == 'pending' &&
          !op.nextAttempt.isAfter(DateTime.now().toUtc()))) {
        unawaited(sync());
      }
    }, onError: (Object error, StackTrace stack) {
      if (!_stopping && !isClosed) {
        emit(SyncStatus(
            error:
                'Local storage is unavailable. Check browser storage permissions.',
            lastSync: state.lastSync));
      }
    });
    _channel = client.channel(
      'gym:${repository.access.gymId}',
      opts: const RealtimeChannelConfig(private: true),
    )
      ..onBroadcast(
          event: 'changed',
          // Coalesce bursts so a burst of remote edits cannot pin the UI
          // thread with back-to-back pull cycles.
          callback: (_) => _scheduleSync())
      ..subscribe();
    unawaited(sync());
  }
  final WorkspaceRepository repository;
  final SupabaseClient client;
  final Future<void> Function()? onAccessDenied;
  Timer? _timer, _broadcastTimer;
  void Function() _stopConnectivity = () {};
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<List<SyncOperation>>? _outbox;
  RealtimeChannel? _channel;
  bool _running = false, _stopping = false;
  bool _requested = false;
  Future<void>? _activeSync;
  bool _recoveredLegacyFailures = false;
  void _scheduleSync() {
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer(const Duration(milliseconds: 600), () {
      if (!_stopping) unawaited(sync());
    });
  }

  Future<void> sync() {
    if (_stopping || isClosed) return Future<void>.value();
    _requested = true;
    return _activeSync ??= _drain().whenComplete(() => _activeSync = null);
  }

  Future<void> _drain() async {
    while (_requested && !_stopping) {
      _requested = false;
      await _syncOnce();
    }
  }

  Future<dynamic> _rpc(String name, Map<String, dynamic> params) async {
    Future<dynamic> send() =>
        client.rpc(name, params: params).timeout(const Duration(seconds: 20));
    try {
      return await send();
    } on PostgrestException catch (error) {
      if (!['PGRST301', 'PGRST303'].contains(error.code) ||
          client.auth.currentSession == null) {
        rethrow;
      }
      // Renew an expired JWT once, preserving the operation's idempotency key.
      await client.auth.refreshSession().timeout(const Duration(seconds: 15));
      if (_stopping) throw StateError('Sync stopped');
      return send();
    }
  }

  Future<void> _syncOnce() async {
    _running = true;
    emit(SyncStatus(running: true, lastSync: state.lastSync));
    final db = repository.db, scope = repository.scope;
    try {
      if (!_recoveredLegacyFailures) {
        // Older versions permanently failed edits after repeated offline tries.
        // Recover only that known network failure; leave validation errors alone.
        await db.transaction(() async {
          final stranded = await (db.select(db.syncOperations)
                ..where((o) =>
                    o.scope.equals(scope) &
                    o.state.equals('failed') &
                    o.error.equals(
                        'Server unreachable. Your change remains on this device.')))
              .get();
          for (final op in stranded) {
            await (db.update(db.syncOperations)
                  ..where((o) => o.id.equals(op.id)))
                .write(SyncOperationsCompanion(
                    state: const Value('pending'),
                    attempts: const Value(0),
                    nextAttempt: Value(DateTime.now().toUtc())));
            await (db.update(db.cachedRecords)
                  ..where((r) =>
                      r.scope.equals(scope) &
                      r.kind.equals(op.kind) &
                      r.id.equals(op.recordId)))
                .write(
                    const CachedRecordsCompanion(syncState: Value('pending')));
          }
        });
        _recoveredLegacyFailures = true;
      }
      final ops = await (db.select(db.syncOperations)
            ..where(
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
            await _rpc(
              'apply_sync_operation',
              {
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
            await db.into(db.cachedRecords).insertOnConflictUpdate(
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
            )..where((o) => o.id.equals(op.id)))
                .go();
          });
        } on PostgrestException catch (e) {
          if (e.code == null ||
              ['PGRST301', 'PGRST303', '502', '503', '504'].contains(e.code)) {
            await _fail(op, 'pending',
                'Connection interrupted. Will retry automatically.');
            rethrow;
          }
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
            'pending',
            'Server unreachable. Your change remains on this device.',
          );
          // Do not wait twenty seconds for every queued edit while offline.
          rethrow;
        }
      }
      var checkpoint = await (db.select(
        db.syncCheckpoints,
      )..where((c) => c.scope.equals(scope)))
          .getSingleOrNull();
      while (!_stopping) {
        // Yield between pages so a long initial pull keeps the UI responsive.
        await Future<void>.delayed(Duration.zero);
        if (_stopping) break;
        final result = Map<String, dynamic>.from(
          await _rpc(
            'pull_changes',
            {
              'p_gym': repository.access.gymId,
              'p_cursor': checkpoint?.cursor ?? 0,
            },
          ) as Map,
        );
        final changes =
            (result['changes'] as List).cast<Map<String, dynamic>>();
        final nextCursor = result['cursor'] as int;
        if (result['has_more'] == true &&
            nextCursor <= (checkpoint?.cursor ?? 0)) {
          throw StateError('The sync cursor did not advance.');
        }
        await repository.applyRemoteChanges(changes, nextCursor);
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
            error:
                'Server authorization or synchronization failed. Revalidating access when required.',
            lastSync: state.lastSync,
          ),
        );
      }
    } catch (_) {
      if (!_stopping) {
        emit(
          SyncStatus(
            error:
                'Unable to sync. Cached records are available; retry when connected.',
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
      )..where((o) => o.id.equals(op.id)))
          .write(
        SyncOperationsCompanion(
          attempts: Value(op.attempts + 1),
          state: Value(status),
          error: Value(message),
          nextAttempt: Value(
            DateTime.now().toUtc().add(
                  Duration(seconds: min(900, 2 << min(op.attempts, 9))),
                ),
          ),
        ),
      );
      await (repository.db.update(repository.db.cachedRecords)
            ..where(
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
    _broadcastTimer?.cancel();
    await _authSubscription?.cancel();
    await _outbox?.cancel();
    if (_channel != null) await client.removeChannel(_channel!);
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return super.close();
  }
}
