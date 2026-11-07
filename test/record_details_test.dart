import 'package:drift/drift.dart' hide Column, isNull, isNotNull;
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/record_details.dart';
import 'package:gym_saas/core/sync/workspace_repository.dart';
import 'package:gym_saas/core/theme.dart';
import 'package:gym_saas/features/auth/domain/access.dart';

void main() {
  testWidgets(
      'Details adapt to mobile and desktop, update live, and protect finances',
      (tester) async {
    final font = FontLoader('Manrope')
      ..addFont(rootBundle.load('assets/fonts/Manrope.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final db = GymDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = WorkspaceRepository(
        db,
        const GymAccess(
            gymId: 'gym',
            userId: 'owner',
            name: 'Owner',
            gymName: 'GymPro',
            role: GymRole.owner));
    final fixtures = {
      'members': {
        'full_name': 'Amina Hassan',
        'member_number': '1024',
        'phone': '+971501234567',
        'email': 'amina.hassan@example.com',
        'address': 'Dubai, United Arab Emirates',
        'occupation': 'Designer',
        'joining_date': '2026-01-15',
        'status': 'active',
        'notes': 'Prefers evening sessions.'
      },
      'membership_packages': {
        'name': 'Unlimited membership',
        'description':
            'Room to move. Full access to the gym and all group sessions.',
        'duration_value': 3,
        'duration_unit': 'months',
        'allowed_pause_days': 14,
        'price_minor': 90000,
        'currency': 'AED',
        'status': 'active'
      },
      'subscriptions': {
        'member_id': 'members',
        'package_id': 'membership_packages',
        'start_date': '2026-11-01',
        'end_exclusive': '2027-02-01',
        'status': 'active'
      },
      'invoices': {
        'member_id': 'members',
        'total_minor': 90000,
        'paid_minor': 30000,
        'credit_minor': 10000,
        'currency': 'AED',
        'status': 'partially_paid',
        'due_date': '2026-11-15'
      },
    };
    for (final entry in fixtures.entries) {
      await db.into(db.cachedRecords).insert(CachedRecordsCompanion.insert(
          scope: repo.scope,
          kind: entry.key,
          id: entry.key,
          payload: jsonEncode(entry.value)));
    }
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final width in [390.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 1000);
      for (final dark in [false, true]) {
        for (final entry in fixtures.entries) {
          final record = CachedRecord(
              scope: repo.scope,
              kind: entry.key,
              id: entry.key,
              payload: jsonEncode(entry.value),
              version: 0,
              syncState: 'synced');
          final key = GlobalKey();
          await tester.pumpWidget(MaterialApp(
              themeAnimationDuration: Duration.zero,
              theme: dark ? GymTheme.dark : GymTheme.light,
              home: RepaintBoundary(
                  key: key,
                  child: Scaffold(
                      body: RecordDetailsPanel(
                          record: record, repository: repo)))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '${entry.key} width=$width dark=$dark');
          if (entry.key == 'members') {
            expect(find.text('Amina Hassan · ID 1024'), findsOneWidget);
            expect(find.text('+971501234567'), findsOneWidget);
          }
          if (!dark && ['members', 'membership_packages'].contains(entry.key)) {
            final boundary = key.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              final file = File(
                  'build/design_review/details-${entry.key}-${width.toInt()}.png');
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      }
    }
    tester.view.physicalSize = const Size(1280, 1000);
    final invoice = CachedRecord(
        scope: repo.scope,
        kind: 'invoices',
        id: 'invoices',
        payload: jsonEncode(fixtures['invoices']),
        version: 0,
        syncState: 'synced');
    await tester.pumpWidget(MaterialApp(
        themeAnimationDuration: Duration.zero,
        theme: GymTheme.light,
        home:
            Scaffold(body: RecordDetails(record: invoice, repository: repo))));
    await tester.pumpAndSettle();
    expect(find.text('Balance due'), findsOneWidget);
    expect(find.text('AED 500.00'), findsOneWidget);
    final member = CachedRecord(
        scope: repo.scope,
        kind: 'members',
        id: 'members',
        payload: jsonEncode(fixtures['members']),
        version: 0,
        syncState: 'synced');
    String? operation;
    CachedRecord? operationRecord;
    await tester.pumpWidget(MaterialApp(
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
            body: RecordDetails(
                record: member,
                repository: repo,
                onOperation: (action, record) {
                  operation = action;
                  operationRecord = record;
                }))));
    await tester.pumpAndSettle();
    expect(find.text('Memberships (1)'), findsOneWidget);
    expect(find.text('Payments (0)'), findsOneWidget);
    expect(find.text('Invoices (1)'), findsOneWidget);
    expect(find.text('Receipts (0)'), findsOneWidget);
    await tester.ensureVisible(find.text('New membership'));
    await tester.tap(find.text('New membership'));
    expect(operation, 'subscribe');
    expect(operationRecord!.id, member.id);
    await tester.tap(find.text('Pay all invoices'));
    expect(operation, 'pay_all');
    expect(operationRecord!.id, member.id);
    await tester.tap(find.text('Pay invoice'));
    expect(operation, 'pay');
    expect(operationRecord!.id, invoice.id);
    await tester.tap(find.text('Invoices (1)'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Invoice'));
    await tester.tap(find.text('Invoice'));
    await tester.pumpAndSettle();
    expect(find.text('Invoice details'), findsOneWidget);
    await tester.ensureVisible(find.text('Record payment'));
    await tester.tap(find.text('Record payment'));
    expect(operation, 'pay');
    expect(operationRecord!.id, invoice.id);
    await tester.tap(find.byTooltip('Close details'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => (db.update(db.cachedRecords)
          ..where((r) => r.scope.equals(repo.scope) & r.id.equals('members')))
        .write(CachedRecordsCompanion(
            payload: Value(jsonEncode(
                {...fixtures['members']!, 'full_name': 'Amina Updated'})))));
    await tester.pumpAndSettle();
    expect(find.text('Amina Updated · ID 1024'), findsOneWidget);
    final trainerRepo = WorkspaceRepository(
        db,
        const GymAccess(
            gymId: 'gym',
            userId: 'trainer',
            name: 'Trainer',
            gymName: 'GymPro',
            role: GymRole.trainer));
    await tester.pumpWidget(MaterialApp(
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
            body: RecordDetails(record: member, repository: trainerRepo))));
    await tester.pumpAndSettle();
    expect(find.text('Memberships (0)'), findsOneWidget);
    expect(find.textContaining('Invoices ('), findsNothing);
    expect(find.textContaining('Payments ('), findsNothing);
    expect(find.textContaining('Receipts ('), findsNothing);
    expect(find.text('New membership'), findsNothing);
    await tester.pumpWidget(MaterialApp(
        themeAnimationDuration: Duration.zero,
        home: Scaffold(
            body: RecordDetails(record: invoice, repository: trainerRepo))));
    await tester.pumpAndSettle();
    expect(find.text('Price & payment details'), findsNothing);
    expect(find.text('AED 500.00'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
