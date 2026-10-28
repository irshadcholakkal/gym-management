import 'dart:convert';

import 'package:flutter/material.dart';

import '../features/payments/domain/money.dart';
import 'database/database.dart';
import 'sync/workspace_repository.dart';
import 'record_labels.dart';

class RecordDetails extends StatelessWidget {
  const RecordDetails({
    super.key,
    required this.record,
    required this.repository,
  });
  final CachedRecord record;
  final WorkspaceRepository repository;
  @override
  Widget build(BuildContext context) {
    final m = jsonDecode(record.payload) as Map<String, dynamic>;
    final currency = m['currency'] as String? ?? 'AED';
    const labels = {
      'full_name': 'Full name',
      'name': 'Name',
      'phone': 'Phone',
      'email': 'Email',
      'address': 'Address',
      'notes': 'Notes',
      'joining_date': 'Joined',
      'description': 'Description',
      'discount_reason': 'Discount reason',
      'status': 'Status',
      'start_date': 'Membership starts',
      'due_date': 'Payment due',
      'duration_value': 'Duration',
      'duration_unit': 'Duration unit',
      'allowed_pause_days': 'Pause allowance (days)',
      'body': 'Message',
      'read_at': 'Read on',
      'created_at': 'Created',
      'receipt_number': 'Receipt number',
      'reference': 'Reference',
      'method': 'Payment method',
    };
    return SizedBox(
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (m['member_id'] != null || m['snapshot'] is Map)
              StreamBuilder<List<CachedRecord>>(
                stream: (repository.db.select(
                  repository.db.cachedRecords,
                )..where((r) => r.scope.equals(repository.scope))).watch(),
                builder: (context, snapshot) {
                  final labels = RecordLabels(snapshot.data ?? []);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          labels.member(m),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(labels.package(m)),
                      ],
                    ),
                  );
                },
              ),
            for (final e in labels.entries)
              if (m[e.key] != null && m[e.key].toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 150,
                        child: Text(
                          e.value,
                          style: const TextStyle(color: Color(0xFF657570)),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          ['status', 'method', 'duration_unit'].contains(e.key)
                              ? displayLabel(m[e.key].toString())
                              : m[e.key].toString(),
                        ),
                      ),
                    ],
                  ),
                ),
            if (m['end_exclusive'] != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Final valid membership day'),
                subtitle: Text(
                  DateTime.parse(m['end_exclusive'] as String)
                      .subtract(const Duration(days: 1))
                      .toIso8601String()
                      .substring(0, 10),
                ),
              ),
            for (final e in {
              'price_minor': 'Package price',
              'subtotal_minor': 'Subtotal before discount',
              'discount_minor': 'Special discount',
              'total_minor': 'Invoice total',
              'paid_minor': 'Amount collected',
              'credit_minor': 'Applied credit',
            }.entries)
              if (m[e.key] != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(e.value),
                  trailing: Text(Money.format(m[e.key] as int, currency)),
                ),
            if (record.kind == 'members')
              StreamBuilder<List<CachedRecord>>(
                stream: (repository.db.select(
                  repository.db.cachedRecords,
                )..where((r) => r.scope.equals(repository.scope))).watch(),
                builder: (context, snapshot) {
                  final related = (snapshot.data ?? []).where((r) {
                    final value = jsonDecode(r.payload) as Map;
                    return value['member_id'] == record.id ||
                        (r.kind == 'receipts' &&
                            (value['snapshot'] as Map?)?['member_number'] ==
                                m['member_number']);
                  }).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 32),
                      const Text(
                        'Membership & payment history',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (related.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'No synchronized history for this member.',
                          ),
                        ),
                      for (final r in related)
                        Builder(
                          builder: (context) {
                            final value = jsonDecode(r.payload) as Map;
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                r.kind == 'subscriptions'
                                    ? Icons.event_repeat
                                    : Icons.receipt_long_outlined,
                              ),
                              title: Text(
                                r.kind == 'subscriptions'
                                    ? '${(value['package_snapshot'] as Map?)?['name'] ?? 'Membership'}'
                                    : '${r.kind.replaceAll('_', ' ')} · ${value['status'] ?? ''}',
                              ),
                              subtitle: Text(
                                '${value['start_date'] ?? value['created_at'] ?? ''}',
                              ),
                              trailing: value['total_minor'] != null
                                  ? Text(
                                      Money.format(
                                        value['total_minor'] as int,
                                        value['currency'] as String? ?? 'AED',
                                      ),
                                    )
                                  : null,
                            );
                          },
                        ),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
