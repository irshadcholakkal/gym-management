import 'package:drift/drift.dart';

import 'connection_native.dart'
    if (dart.library.js_interop) 'connection_web.dart';
part 'database.g.dart';

class CachedRecords extends Table {
  TextColumn get scope => text()();
  TextColumn get kind => text()();
  TextColumn get id => text()();
  TextColumn get payload => text()();
  IntColumn get version => integer().withDefault(const Constant(0))();
  TextColumn get syncState => text().withDefault(const Constant('synced'))();
  @override
  Set<Column> get primaryKey => {scope, kind, id};
}

class SyncOperations extends Table {
  TextColumn get id => text()();
  TextColumn get scope => text()();
  TextColumn get kind => text()();
  TextColumn get recordId => text()();
  TextColumn get payload => text()();
  IntColumn get expectedVersion => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  TextColumn get error => text().nullable()();
  DateTimeColumn get nextAttempt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class SyncCheckpoints extends Table {
  TextColumn get scope => text()();
  IntColumn get cursor => integer().withDefault(const Constant(0))();
  @override
  Set<Column> get primaryKey => {scope};
}

@DriftDatabase(tables: [CachedRecords, SyncOperations, SyncCheckpoints])
class GymDatabase extends _$GymDatabase {
  GymDatabase() : super(openConnection());
  GymDatabase.forTesting(super.executor);
  @override
  int get schemaVersion => 1;
}
