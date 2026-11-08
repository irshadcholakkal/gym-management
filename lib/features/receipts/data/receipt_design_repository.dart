import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/receipt_html.dart';
import '../domain/invoice_html.dart';

class ReceiptDesign {
  const ReceiptDesign(this.html, this.version);
  final String html;
  final int version;
}

class ReceiptDesignRepository {
  ReceiptDesignRepository(this.client, this.gymId, {this.isInvoice = false});
  final bool isInvoice;
  String get documentName => isInvoice ? 'Invoice' : 'Receipt';
  String get defaultDesign =>
      isInvoice ? InvoiceHtml.defaultDesign : ReceiptHtml.defaultDesign;
  List<String> get placeholders =>
      isInvoice ? InvoiceHtml.placeholders : ReceiptHtml.placeholders;
  String? validate(String html) =>
      isInvoice ? InvoiceHtml.validate(html) : ReceiptHtml.validate(html);
  String preview(String html, String gymName) => isInvoice
      ? InvoiceHtml.render(html, InvoiceHtml.sample(gymName))
      : ReceiptHtml.render(html, ReceiptHtml.sample(gymName));
  final SupabaseClient client;
  final String gymId;
  Future<ReceiptDesign> load() async {
    try {
      final row = await client
          .from(isInvoice ? 'invoice_designs' : 'receipt_designs')
          .select('html,version')
          .eq('gym_id', gymId)
          .maybeSingle();
      return row == null
          ? ReceiptDesign(defaultDesign, 0)
          : ReceiptDesign(row['html'] as String, row['version'] as int);
    } on PostgrestException catch (error) {
      if (['42P01', 'PGRST205'].contains(error.code)) {
        return ReceiptDesign(defaultDesign, 0);
      }
      rethrow;
    }
  }

  Future<ReceiptDesign> save(String html, int version) async {
    final problem = validate(html);
    if (problem != null) throw ArgumentError(problem);
    final row = await client.rpc(
        isInvoice ? 'save_invoice_design' : 'save_receipt_design',
        params: {'p_gym': gymId, 'p_html': html, 'p_expected': version}) as Map;
    return ReceiptDesign(row['html'] as String, row['version'] as int);
  }
}
