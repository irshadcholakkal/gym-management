import 'dart:convert';

import 'package:intl/intl.dart';

import '../features/payments/domain/money.dart';
import 'database/database.dart';

String displayLabel(String value) => value
    .replaceAll('_', ' ')
    .split(' ')
    .where((s) => s.isNotEmpty)
    .map((s) => '${s[0].toUpperCase()}${s.substring(1)}')
    .join(' ');
String displayDate(Object? value) {
  final date = DateTime.tryParse(value?.toString() ?? '');
  return date == null ? '' : DateFormat('dd MMM yyyy').format(date);
}

class RecordLabels {
  RecordLabels(Iterable<CachedRecord> records) {
    for (final record in records) {
      _records['${record.kind}:${record.id}'] =
          jsonDecode(record.payload) as Map<String, dynamic>;
    }
  }
  final _records = <String, Map<String, dynamic>>{};
  Map<String, dynamic> lookup(String kind, Object? id) =>
      _records['$kind:$id'] ?? {};
  String member(Map data) =>
      (data['snapshot'] is Map ? data['snapshot']['member_name'] : null)
          ?.toString() ??
      lookup('members', data['member_id'])['full_name']?.toString() ??
      'Member unavailable';
  String package(Map data) {
    final subscription = data['subscription_id'] == null
        ? data
        : lookup('subscriptions', data['subscription_id']);
    return (data['snapshot'] is Map ? data['snapshot']['package_name'] : null)
            ?.toString() ??
        (subscription['package_snapshot'] as Map?)?['name']?.toString() ??
        lookup(
          'membership_packages',
          subscription['package_id'],
        )['name']?.toString() ??
        'Membership';
  }

  String title(String kind, Map data) {
    switch (kind) {
      case 'subscriptions':
        return '${member(data)} · ${package(data)}';
      case 'invoices':
        return 'Invoice · ${member(data)}';
      case 'receipts':
        return 'Receipt #${data['receipt_number']} · ${member(data)}';
      case 'payments':
        return 'Payment · ${member(data)}';
      default:
        return (data['full_name'] ??
                data['name'] ??
                data['title'] ??
                displayLabel(kind))
            .toString();
    }
  }

  String subtitle(String kind, Map data) {
    if (kind == 'subscriptions') {
      final end = DateTime.tryParse(data['end_exclusive']?.toString() ?? '')
          ?.subtract(const Duration(days: 1));
      return '${displayDate(data['start_date'])} – ${displayDate(end)}';
    }
    if (kind == 'invoices') {
      final balance =
          (data['total_minor'] as int? ?? 0) -
          (data['paid_minor'] as int? ?? 0) -
          (data['credit_minor'] as int? ?? 0);
      return '${package(data)} · ${Money.format(balance, data['currency'] as String? ?? 'AED')} due · ${displayDate(data['due_date'])}';
    }
    if (kind == 'receipts') {
      return '${package(data)} · ${displayDate(data['created_at'])}';
    }
    if (kind == 'membership_packages') {
      return '${data['duration_value']} ${data['duration_unit']} · ${data['description'] ?? ''}';
    }
    return (data['phone'] ?? data['description'] ?? data['body'] ?? '')
        .toString();
  }
}
