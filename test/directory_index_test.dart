import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/directory_index.dart';

void main() {
  test(
      'Large member directories yield to input and retain searchable sorted records',
      () async {
    final rows = List.generate(
        3000,
        (i) => CachedRecord(
            scope: 'scope',
            kind: 'members',
            id: '$i',
            payload: jsonEncode({
              'full_name': 'Member ${3000 - i}',
              'phone': '+971501234567',
              'status': 'active'
            }),
            version: 1,
            syncState: 'synced'));
    var ticks = 0;
    final heartbeat =
        Timer.periodic(const Duration(milliseconds: 1), (_) => ticks++);
    final index = await DirectoryIndex.create(rows);
    heartbeat.cancel();
    expect(ticks, greaterThan(10));
    expect(index.records.length, 3000);
    final names = index.records
        .map((r) => index.labels.lookup(r.kind, r.id)['full_name'] as String)
        .toList();
    expect(names, orderedEquals([...names]..sort()));
    expect(index.search['members:2999'], contains('member 1'));
    expect(index.search['members:0'], contains('+971501234567'));
  });
}
