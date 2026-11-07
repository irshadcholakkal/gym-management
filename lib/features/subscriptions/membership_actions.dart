import 'dart:convert';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import '../../core/database/database.dart';
import '../auth/domain/access.dart';
import 'domain/membership_status.dart';

/// Present only actions that make sense for the membership's current state.
class MembershipActions extends StatelessWidget {
  const MembershipActions(
      {super.key,
      required this.record,
      required this.access,
      required this.onAction,
      this.hasPaymentHistory = false});
  final CachedRecord record;
  final GymAccess access;
  final bool hasPaymentHistory;
  final void Function(String, CachedRecord) onAction;
  @override
  Widget build(BuildContext context) {
    final status = MembershipStatus(jsonDecode(record.payload) as Map).status;
    final enabled = record.syncState == 'synced';
    if (!access.finances) return const SizedBox.shrink();
    if (status == 'deleted') {
      return access.administer
          ? OutlinedButton.icon(
              onPressed: enabled ? () => onAction('restore', record) : null,
              icon: const Icon(CupertinoIcons.arrow_uturn_left),
              label: const Text('Restore membership'),
            )
          : const SizedBox.shrink();
    }
    final current = ['active', 'expiring_soon'].contains(status);
    final more = <(String, String, IconData)>[
      if (current)
        ('package', 'Change plan', CupertinoIcons.arrow_2_squarepath),
      if (access.administer && (current || status == 'expired'))
        ('extend', 'Add extra days', CupertinoIcons.calendar_badge_plus),
      if (access.administer && status != 'cancelled')
        ('cancel', 'Cancel membership', CupertinoIcons.xmark_circle),
      if (access.administer)
        ('delete', 'Delete accidental membership', CupertinoIcons.trash),
    ];
    Widget button(String action, String label, IconData icon) =>
        OutlinedButton.icon(
            onPressed: enabled ? () => onAction(action, record) : null,
            icon: Icon(icon, size: 18),
            label: Text(label));
    return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (current || status == 'expired')
            button('subscribe', 'Renew membership',
                CupertinoIcons.arrow_2_circlepath),
          if (current)
            button('pause', 'Pause membership', CupertinoIcons.pause_circle),
          if (status == 'paused')
            button('resume', 'Resume membership', CupertinoIcons.play_circle),
          button('invoices', 'View invoices', CupertinoIcons.doc_text),
          if (more.isNotEmpty)
            PopupMenuButton<String>(
                enabled: enabled,
                tooltip: 'More membership options',
                onSelected: (action) => onAction(action, record),
                itemBuilder: (_) => [
                      for (final (action, label, icon) in more)
                        PopupMenuItem(
                            value: action,
                            enabled: action != 'delete' || !hasPaymentHistory,
                            child: ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(icon, size: 20),
                                title: Text(label),
                                subtitle:
                                    action == 'delete' && hasPaymentHistory
                                        ? const Text(
                                            'Payment history must be retained')
                                        : null))
                    ],
                child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(CupertinoIcons.ellipsis_circle, size: 20),
                      SizedBox(width: 8),
                      Text('More options')
                    ]))),
        ]);
  }
}
