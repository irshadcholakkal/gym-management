import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/period_report.dart';

class ReportsRepository {
  ReportsRepository(this.client, this.gymId);
  final SupabaseClient client;
  final String gymId;

  Future<PeriodReport> generateRange(DateTime start, DateTime end) async {
    String date(DateTime value) =>
        '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    final data = await client.rpc('get_date_range_report', params: {
      'p_gym': gymId,
      'p_start': date(start),
      'p_end': date(end),
    });
    return PeriodReport(Map<String, dynamic>.from(data as Map));
  }

  Future<PeriodReport> generate(int year, int? month) async {
    final data = await client.rpc('get_period_report', params: {
      'p_gym': gymId,
      'p_year': year,
      'p_month': month,
    });
    return PeriodReport(Map<String, dynamic>.from(data as Map));
  }
}
