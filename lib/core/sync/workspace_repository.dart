import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/domain/access.dart';
import '../database/database.dart';

class WorkspaceRepository {
  WorkspaceRepository(this.db, this.access);
  final GymDatabase db;
  final GymAccess access;
  String get scope => '${access.gymId}:${access.userId}:${access.role.name}'
      '${access.permissionKey == '1111' ? '' : ':${access.permissionKey}'}';
  // Stable query streams avoid resubscribing on every keystroke or sync update.
  late final Stream<List<CachedRecord>> records = (db.select(db.cachedRecords)
        ..where((r) => r.scope.equals(scope)))
      .watch()
      .distinct(_sameRecords);
  final _kindStreams = <String, Stream<List<CachedRecord>>>{};
  Stream<List<CachedRecord>> watch(String kind) => _kindStreams.putIfAbsent(
      kind,
      () => (db.select(db.cachedRecords)
            ..where((r) => r.scope.equals(scope) & r.kind.equals(kind)))
          .watch()
          .distinct(_sameRecords));
  final _groupStreams = <String, Stream<List<CachedRecord>>>{};
  Stream<List<CachedRecord>> watchKinds(Iterable<String> kinds) {
    final selected = kinds.toSet().toList()..sort();
    return _groupStreams.putIfAbsent(
        selected.join(','),
        () => (db.select(db.cachedRecords)
              ..where((r) => r.scope.equals(scope) & r.kind.isIn(selected)))
            .watch()
            .distinct(_sameRecords));
  }

  static bool _sameRecords(
      List<CachedRecord> before, List<CachedRecord> after) {
    if (before.length != after.length) return false;
    for (var i = 0; i < before.length; i++) {
      if (before[i] != after[i]) return false;
    }
    return true;
  }

  late final Stream<List<SyncOperation>> _outboxStream =
      (db.select(db.syncOperations)..where((r) => r.scope.equals(scope)))
          .watch();
  Stream<List<SyncOperation>> watchOutbox() => _outboxStream;

  /// Apply a pull page in one transaction and one batch, not a query per row.
  Future<void> applyRemoteChanges(
          List<Map<String, dynamic>> changes, int cursor) =>
      db.transaction(() async {
        final pending = await (db.select(db.syncOperations)
              ..where((o) => o.scope.equals(scope)))
            .get();
        final protectedIds = pending.map((o) => o.recordId).toSet();
        await db.batch((batch) {
          for (final change in changes) {
            final id = change['record_id'] as String;
            final kind = change['kind'] as String;
            // Keep pending local edits, including when a remote deletion arrives.
            if (protectedIds.contains(id)) continue;
            if (change['deleted'] == true) {
              batch.deleteWhere(
                  db.cachedRecords,
                  (r) =>
                      r.scope.equals(scope) &
                      r.kind.equals(kind) &
                      r.id.equals(id));
            } else {
              batch.insertAllOnConflictUpdate(db.cachedRecords, [
                CachedRecordsCompanion.insert(
                  scope: scope,
                  kind: kind,
                  id: id,
                  payload: jsonEncode(change['payload']),
                  syncState: const Value('synced'),
                  version: Value((change['payload'] as Map)['version'] as int),
                )
              ]);
            }
          }
          batch.insertAllOnConflictUpdate(db.syncCheckpoints, [
            SyncCheckpointsCompanion.insert(scope: scope, cursor: Value(cursor))
          ]);
        });
      });
  Future<String> save(
    String kind,
    Map<String, dynamic> fields, {
    String? id,
    int version = 0,
  }) async {
    if (kind == 'members' && !access.editMembers ||
        kind == 'membership_packages' && !access.administer) {
      throw StateError('Permission denied');
    }
    if (!{'members', 'membership_packages'}.contains(kind)) {
      throw ArgumentError('Unsupported local mutation');
    }
    if (!['active', 'inactive', 'archived'].contains(fields['status'])) {
      throw ArgumentError('A valid record status is required');
    }
    if (kind == 'members') {
      if ((fields['full_name'] as String? ?? '').trim().isEmpty ||
          !RegExp(r'^\+[1-9]\d{7,14}$')
              .hasMatch(fields['phone'] as String? ?? '') ||
          DateTime.tryParse(fields['joining_date'] as String? ?? '') == null) {
        throw ArgumentError(
          'Name, international phone and joining date are required',
        );
      }
    } else if ((fields['name'] as String? ?? '').trim().isEmpty ||
        (fields['duration_value'] as int? ?? 0) <= 0 ||
        ![
          'days',
          'weeks',
          'months',
          'years',
        ].contains(fields['duration_unit']) ||
        (fields['price_minor'] as int? ?? -1) < 0 ||
        (fields['allowed_pause_days'] as int? ?? -1) < 0) {
      throw ArgumentError(
        'Package name, duration, price and pause allowance are required',
      );
    }
    final recordId = id ?? const Uuid().v4();

    await db.transaction(() async {
      final cached = await (db.select(db.cachedRecords)
            ..where(
              (r) =>
                  r.scope.equals(scope) &
                  r.kind.equals(kind) &
                  r.id.equals(recordId),
            ))
          .getSingleOrNull();
      final data = {
        ...?(cached == null
            ? null
            : jsonDecode(cached.payload) as Map<String, dynamic>),
        ...fields,
        'id': recordId,
        'gym_id': access.gymId,
      };
      final existing = await (db.select(db.syncOperations)
            ..where(
              (o) => o.scope.equals(scope) & o.recordId.equals(recordId),
            ))
          .get();
      if (existing.isNotEmpty) {
        throw StateError('Sync or resolve this record before editing again.');
      }
      await db.into(db.cachedRecords).insertOnConflictUpdate(
            CachedRecordsCompanion.insert(
              scope: scope,
              kind: kind,
              id: recordId,
              payload: jsonEncode(data),
              version: Value(version),
              syncState: const Value('pending'),
            ),
          );
      await db.into(db.syncOperations).insert(
            SyncOperationsCompanion.insert(
              id: const Uuid().v4(),
              scope: scope,
              kind: kind,
              recordId: recordId,
              payload: jsonEncode(data),
              expectedVersion: version,
              nextAttempt: DateTime.now().toUtc(),
            ),
          );
    });
    return recordId;
  }

  Future<void> retry(String id) => (db.update(db.syncOperations)
            ..where(
              (o) =>
                  o.scope.equals(scope) &
                  o.id.equals(id) &
                  o.state.isNotIn(['conflict', 'approval', 'confirmation']) &
                  o.kind.isIn(['members', 'membership_packages']),
            ))
          .write(
        SyncOperationsCompanion(
          state: const Value('pending'),
          attempts: const Value(0),
          error: const Value(null),
          nextAttempt: Value(DateTime.now().toUtc()),
        ),
      );
}
