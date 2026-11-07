import 'package:flutter/material.dart';
import 'record_labels.dart';

/// Shared semantic colors, independent of the app's red brand color.
Color statusColor(String status, {bool dark = false}) {
  final shade = switch (status.toLowerCase()) {
    'active' ||
    'paid' ||
    'issued' ||
    'synced' ||
    'completed' ||
    'success' =>
      Colors.green,
    'paused' ||
    'expiring_soon' ||
    'partially_paid' ||
    'pending_sync' ||
    'queued' =>
      Colors.orange,
    'expired' ||
    'overdue' ||
    'unpaid' ||
    'cancelled' ||
    'deleted' ||
    'inactive' ||
    'void' ||
    'voided' ||
    'failed' ||
    'error' ||
    'conflict' =>
      Colors.red,
    'scheduled_renewal' ||
    'scheduled' ||
    'pending' ||
    'pending_activation' ||
    'draft' ||
    'syncing' =>
      Colors.blue,
    _ => Colors.blueGrey,
  };
  return shade[dark ? 200 : 800]!;
}

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.label});
  final String status;
  final String? label;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = statusColor(status, dark: dark);
    return Chip(
      avatar: Icon(Icons.circle, size: 8, color: color),
      label: Text(label ?? displayLabel(status)),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w600),
      backgroundColor: color.withValues(alpha: dark ? .16 : .09),
      side: BorderSide(color: color.withValues(alpha: .28)),
    );
  }
}
