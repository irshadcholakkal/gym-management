import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../features/auth/domain/access.dart';
import '../database/database.dart';

class WorkspaceRepository {
  WorkspaceRepository(this.db, this.access);
  final GymDatabase db;
  final GymAccess access;
  String get scope => '${access.gymId}:${access.userId}:${access.role.name}';
  Stream<List<CachedRecord>> watch(String kind) => (db.select(
    db.cachedRecords,
  )..where((r) => r.scope.equals(scope) & r.kind.equals(kind))).watch();
  Stream<List<SyncOperation>> watchOutbox() => (db.select(
    db.syncOperations,
  )..where((r) => r.scope.equals(scope))).watch();
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
    final data = {...fields, 'id': recordId, 'gym_id': access.gymId};
    await db.transaction(() async {
      final existing =
          await (db.select(db.syncOperations)..where(
                (o) => o.scope.equals(scope) & o.recordId.equals(recordId),
              ))
              .get();
      if (existing.isNotEmpty) {
        throw StateError('Sync or resolve this record before editing again.');
      }
      await db
          .into(db.cachedRecords)
          .insertOnConflictUpdate(
            CachedRecordsCompanion.insert(
              scope: scope,
              kind: kind,
              id: recordId,
              payload: jsonEncode(data),
              version: Value(version),
              syncState: const Value('pending'),
            ),
          );
      await db
          .into(db.syncOperations)
          .insert(
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

  Future<void> retry(String id) =>
      (db.update(db.syncOperations)..where(
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
