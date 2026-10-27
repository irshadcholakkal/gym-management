import 'dart:math';

import 'package:flutter/material.dart';

import '../../payments/domain/money.dart';

class CollectionChart extends StatelessWidget {
  const CollectionChart({
    super.key,
    required this.payments,
    required this.today,
  });
  final List<Map> payments;
  final DateTime today;
  @override
  Widget build(BuildContext context) {
    final months = [
      for (var i = 5; i >= 0; i--) DateTime.utc(today.year, today.month - i),
    ];
    final totals = months
        .map(
          (m) => payments
              .where((p) {
                final date = DateTime.parse(p['created_at'] as String)
                    .toUtc()
                    .add(const Duration(hours: 4));
                return date.year == m.year && date.month == m.month;
              })
              .fold<int>(0, (sum, p) => sum + (p['amount_minor'] as int)),
        )
        .toList();
    final maximum = max(1, totals.reduce(max));
    const names = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monthly collections',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text('Confirmed payments, excluding reversals'),
            const SizedBox(height: 24),
            SizedBox(
              height: 180,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < months.length; i++)
                    Expanded(
                      child: Tooltip(
                        message: Money.format(totals[i]),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Flexible(
                              child: FractionallySizedBox(
                                heightFactor: totals[i] / maximum,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  constraints: const BoxConstraints(
                                    minHeight: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: i == 5
                                        ? const Color(0xFF8FBFA6)
                                        : const Color(0xFFDDEDE4),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              names[months[i].month - 1],
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
