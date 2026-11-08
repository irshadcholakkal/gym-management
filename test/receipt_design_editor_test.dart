import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/core/theme.dart';
import 'package:gym_saas/features/receipts/data/receipt_design_repository.dart';
import 'package:gym_saas/features/receipts/domain/receipt_html.dart';
import 'package:gym_saas/features/receipts/domain/invoice_html.dart';
import 'package:gym_saas/features/receipts/presentation/receipt_design_editor.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UnusedClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class MemoryDesignRepository extends ReceiptDesignRepository {
  MemoryDesignRepository({bool invoice = false})
      : super(UnusedClient(), 'gym', isInvoice: invoice) {
    design = ReceiptDesign(defaultDesign, 0);
  }
  late ReceiptDesign design;
  @override
  Future<ReceiptDesign> load() async => design;
  @override
  Future<ReceiptDesign> save(String html, int version) async {
    design = ReceiptDesign(html, version + 1);
    return design;
  }
}

void main() {
  testWidgets('Invoice editor saves independently of the receipt design',
      (tester) async {
    final invoice = MemoryDesignRepository(invoice: true);
    final receipt = MemoryDesignRepository();
    await tester.pumpWidget(MaterialApp(
        home: ReceiptDesignEditor(repository: invoice, gymName: 'Gym')));
    await tester.pumpAndSettle();
    expect(find.text('Invoice HTML design'), findsOneWidget);
    final edited = InvoiceHtml.defaultDesign.replaceAll('#222', '#112233');
    await tester.enterText(find.byType(TextField), edited);
    await tester.tap(find.text('Save design'));
    await tester.pumpAndSettle();
    expect(invoice.design.html, edited);
    expect(receipt.design.html, ReceiptHtml.defaultDesign);
    expect(find.text('Invoice design saved for your gym.'), findsOneWidget);
  });
  testWidgets('Receipt editor saves HTML and reloads it at mobile width',
      (tester) async {
    final repository = MemoryDesignRepository();
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> open() async {
      await tester.pumpWidget(MaterialApp(
          theme: GymTheme.mobile,
          home: ReceiptDesignEditor(
              repository: repository, gymName: 'Test gym')));
      await tester.pumpAndSettle();
    }

    await open();
    final edited = ReceiptHtml.defaultDesign.replaceAll('#397de5', '#112233');
    await tester.enterText(find.byType(TextField), edited);
    await tester.tap(find.text('Save design'));
    await tester.pumpAndSettle();
    expect(repository.design.html, edited);
    expect(find.text('Receipt design saved for your gym.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await open();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        edited);
    await tester.tap(find.text('Receipt placeholders'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
