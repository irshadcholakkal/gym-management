import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/period_report.dart';

class ReportsRepository {
  ReportsRepository(this.client, this.gymId);
  final SupabaseClient client;
  final String gymId;

  Future<PeriodReport> generate(int year, int? month) async {
    final data = await client.rpc('get_period_report', params: {
      'p_gym': gymId,
      'p_year': year,
      'p_month': month,
    });
    return PeriodReport(Map<String, dynamic>.from(data as Map));
  }
}
