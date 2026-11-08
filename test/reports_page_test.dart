import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/core/sync/workspace_repository.dart';
import 'package:gym_saas/features/auth/domain/access.dart';
import 'package:gym_saas/features/reports/data/reports_repository.dart';
import 'package:gym_saas/features/reports/domain/period_report.dart';
import 'package:gym_saas/features/reports/presentation/reports_page.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'period_report_test.dart' show reportFixture;

class FakeReports extends ReportsRepository {
  FakeReports(super.client, super.gymId);
  final requests = <(int, int?)>[];
  @override
  Future<PeriodReport> generate(int year, int? month) async {
    requests.add((year, month));
    return reportFixture(yearly: month == null);
  }
}

void main() {
  testWidgets(
      'Monthly and yearly reports generate and expose all export formats on mobile',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = GymDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final client = (await tester.runAsync(() async => SupabaseClient(
        'https://example.test', 'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false))))!;
    addTearDown(() => tester.runAsync(client.dispose));
    final source = FakeReports(client, 'gym');
    final repo = WorkspaceRepository(
        db,
        const GymAccess(
            gymId: 'gym',
            userId: 'user',
            name: 'Owner',
            gymName: 'Gym',
            role: GymRole.owner));
    await tester.pumpWidget(RepositoryProvider.value(
        value: repo,
        child: MaterialApp(
            home: Scaffold(body: ReportsPage(repository: source)))));
    await tester.pumpAndSettle();
    expect(find.text('Download PDF'), findsNothing);
    await tester.enterText(find.byType(TextFormField), '2026');
    await tester.tap(find.text('Generate report'));
    await tester.pumpAndSettle();
    expect(source.requests.single.$1, 2026);
    expect(source.requests.single.$2, isNotNull);
    expect(find.text('Download PDF'), findsOneWidget);
    expect(find.text('Export Excel'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Yearly'));
    await tester.pumpAndSettle();
    expect(find.text('Download PDF'), findsNothing);
    await tester.tap(find.text('Generate report'));
    await tester.pumpAndSettle();
    expect(source.requests.last, (2026, null));
    expect(find.text('Report Gym · 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
