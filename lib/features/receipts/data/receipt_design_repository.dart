import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/receipt_html.dart';

class ReceiptDesign {
  const ReceiptDesign(this.html, this.version);
  final String html;
  final int version;
}

class ReceiptDesignRepository {
  ReceiptDesignRepository(this.client, this.gymId);
  final SupabaseClient client;
  final String gymId;
  Future<ReceiptDesign> load() async {
    try {
      final row = await client
          .from('receipt_designs')
          .select('html,version')
          .eq('gym_id', gymId)
          .maybeSingle();
      return row == null
          ? const ReceiptDesign(ReceiptHtml.defaultDesign, 0)
          : ReceiptDesign(row['html'] as String, row['version'] as int);
    } on PostgrestException catch (error) {
      if (['42P01', 'PGRST205'].contains(error.code))
        return const ReceiptDesign(ReceiptHtml.defaultDesign, 0);
      rethrow;
    }
  }

  Future<ReceiptDesign> save(String html, int version) async {
    final problem = ReceiptHtml.validate(html);
    if (problem != null) throw ArgumentError(problem);
    final row = await client.rpc('save_receipt_design',
        params: {'p_gym': gymId, 'p_html': html, 'p_expected': version}) as Map;
    return ReceiptDesign(row['html'] as String, row['version'] as int);
  }
}
