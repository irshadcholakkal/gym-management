import 'package:supabase_flutter/supabase_flutter.dart';

class InvoiceDocumentRepository {
  InvoiceDocumentRepository(this.client, this.gymId);
  final SupabaseClient client;
  final String gymId;
  Future<Map<String, dynamic>> load(String invoiceId) async =>
      Map<String, dynamic>.from(await client.rpc('get_invoice_document',
          params: {'p_gym': gymId, 'p_invoice': invoiceId}) as Map);
}
