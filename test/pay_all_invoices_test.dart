import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gym_saas/core/database/database.dart';
import 'package:gym_saas/features/payments/pay_all_invoices.dart';
import 'package:gym_saas/features/subscriptions/data/operations_repository.dart';

class BulkPayments implements OperationsRepository {
  final operations = <String>[];
  bool fail = true;
  bool mixed = false;
  List<Map<String, dynamic>>? reviewed;
  @override
  Future<Map<String, dynamic>> memberInvoiceQuote(String member) async => {
        'invoices': [
          {
            'id': 'invoice-one',
            'balance_minor': 7000,
            'currency': 'AED',
            'due_date': '2026-11-01',
            'package_name': 'Monthly plan'
          },
          {
            'id': 'invoice-two',
            'balance_minor': 20000,
            'currency': mixed ? 'USD' : 'AED',
            'due_date': '2026-11-02',
            'package_name': 'Renewal'
          },
        ]
      };
  @override
  Future<Map<String, dynamic>> payAllInvoices(
      String member,
      List<Map<String, dynamic>> invoices,
      String method,
      String reference,
      String operation) async {
    expect(member, 'member');
    expect(method, 'cash');
    operations.add(operation);
    reviewed = invoices;
    if (fail) {
      fail = false;
      throw TimeoutException('Response lost');
    }
    return {
      'receipt': {'receipt_number': 42}
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  Future<void> mount(WidgetTester tester, BulkPayments operations) async {
    final member = CachedRecord(
        scope: 'scope',
        kind: 'members',
        id: 'member',
        payload: jsonEncode({'full_name': 'Amina', 'member_number': 7}),
        version: 1,
        syncState: 'synced');
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showDialog<void>(
                        context: context,
                        builder: (_) => PayAllInvoicesDialog(
                            member: member,
                            operations: operations,
                            scope: 'scope')),
                    child: const Text('Open payment'))))));
    await tester.tap(find.text('Open payment'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'Review totals and preserve payment identity after reopening an uncertain request',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final operations = BulkPayments();
    await mount(tester, operations);
    expect(find.text('Amina · ID 0007'), findsOneWidget);
    expect(find.text('Total: AED 270.00'), findsOneWidget);
    expect(operations.operations, isEmpty);
    await tester.ensureVisible(find.text('Confirm payment'));
    await tester.tap(find.text('Confirm payment'));
    await tester.pumpAndSettle();
    expect(operations.operations.length, 1);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open payment'));
    await tester.pumpAndSettle();
    expect(find.text('Retry payment'), findsOneWidget);
    await tester.tap(find.text('Retry payment'));
    await tester.pumpAndSettle();
    expect(operations.operations.length, 2);
    expect(operations.operations[0], operations.operations[1]);
    expect(operations.reviewed, [
      {'id': 'invoice-one', 'balance_minor': 7000, 'currency': 'AED'},
      {'id': 'invoice-two', 'balance_minor': 20000, 'currency': 'AED'}
    ]);
    expect(find.text('Pay all outstanding invoices'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('gympro_pay_all:scope:member'), isNull);
  });
  testWidgets('Different currencies require separate payments', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final operations = BulkPayments()..mixed = true;
    await mount(tester, operations);
    expect(
        find.text(
            'These invoices use different currencies. Pay them separately.'),
        findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(operations.operations, isEmpty);
  });
}
