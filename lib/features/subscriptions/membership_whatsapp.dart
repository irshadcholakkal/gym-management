import 'dart:convert';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import '../../core/database/database.dart';
import '../../core/sync/workspace_repository.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/record_labels.dart';
import '../members/member_identity.dart';
import 'domain/membership_status.dart';

Map<String, String> membershipWhatsAppTemplates(
    {required Map subscription,
    required Map member,
    required String package,
    required String gym,
    DateTime? now}) {
  final status = MembershipStatus(subscription, now: now);
  final name = member['full_name']?.toString() ?? 'Member';
  final id = memberId(member['member_number']);
  final identity = id.isEmpty ? '' : ' Member ID: $id.';
  final lastDay = status.end?.subtract(const Duration(days: 1));
  final expiry = lastDay == null ? null : displayDate(lastDay);
  final start = displayDate(subscription['start_date']);
  final (title, body) = switch (status.status) {
    'expiring_soon' => (
        'Renewal reminder',
        'your $package membership at $gym ${status.days == 1 ? 'ends today' : 'is ending soon'}${expiry == null ? '' : ' (valid through $expiry)'}. Please contact us to renew.'
      ),
    'expired' => (
        'Membership expired',
        'your $package membership at $gym has expired${expiry == null ? '' : ' (last valid day: $expiry)'}. Please contact us to renew. We look forward to welcoming you back!'
      ),
    'paused' => (
        'Membership paused',
        'your $package membership at $gym is paused. Contact us when you are ready to resume; your expiry date will be recalculated when it resumes.'
      ),
    'scheduled_renewal' => (
        'Upcoming membership',
        'your $package membership at $gym is scheduled${start.isEmpty ? '' : ' to start on $start'}${expiry == null ? '' : ' and is valid through $expiry'}. We look forward to seeing you!'
      ),
    'cancelled' => (
        'Membership cancelled',
        'your $package membership at $gym has been cancelled. Contact us if you have any questions.'
      ),
    'draft' || 'pending_activation' => (
        'Membership pending',
        'your $package membership at $gym is awaiting activation. Contact us for the next steps.'
      ),
    'active' => (
        'Active membership',
        'your $package membership at $gym is active${expiry == null ? '' : ' and valid through $expiry'}. We look forward to seeing you!'
      ),
    _ => (
        'Member update',
        'this is a message from $gym. Please contact us if you need help with your membership.'
      ),
  };
  return {
    title: 'Hi $name, $body$identity',
    if (['active', 'expiring_soon', 'scheduled_renewal']
        .contains(status.status))
      'Membership confirmation':
          'Hi $name, your $package membership at $gym is confirmed${start.isEmpty ? '' : ' from $start'}${expiry == null ? '' : ' through $expiry'}. Thank you!$identity',
    'General message':
        'Hi $name, this is $gym. Please contact us if you need any assistance.$identity'
  };
}

Future<void> showRecordWhatsApp(BuildContext context,
    WorkspaceRepository repository, CachedRecord target) async {
  if (!repository.access.finances) return;
  try {
    final records =
        await repository.watchKinds(['members', 'subscriptions']).first;
    final data = jsonDecode(target.payload) as Map;
    final memberKey = target.kind == 'members' ? target.id : data['member_id'];
    final person = records
        .where((r) => r.kind == 'members' && r.id == memberKey)
        .firstOrNull;
    if (person == null) throw StateError('Member unavailable');
    final member = jsonDecode(person.payload) as Map;
    Map subscription = data;
    if (target.kind == 'members') {
      final memberships = records
          .where((r) => r.kind == 'subscriptions')
          .map((r) => jsonDecode(r.payload) as Map)
          .where((s) => s['member_id'] == memberKey && s['deleted_at'] == null)
          .toList();
      int rank(Map s) => switch (MembershipStatus(s).status) {
            'active' || 'expiring_soon' => 0,
            'paused' => 1,
            'scheduled_renewal' => 2,
            'expired' => 3,
            _ => 4
          };
      memberships.sort((a, b) {
        final order = rank(a).compareTo(rank(b));
        return order != 0
            ? order
            : (b['end_exclusive'] ?? '')
                .toString()
                .compareTo((a['end_exclusive'] ?? '').toString());
      });
      subscription = memberships.firstOrNull ?? {'status': 'no_membership'};
    }
    if (!context.mounted) return;
    await showMembershipWhatsApp(context,
        subscription: subscription,
        member: member,
        package:
            (subscription['package_snapshot'] as Map?)?['name']?.toString() ??
                'gym',
        gym: repository.access.gymName);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Unable to prepare the member message. Sync and try again.')));
    }
  }
}

Future<void> showMembershipWhatsApp(
  BuildContext context, {
  required Map subscription,
  required Map member,
  required String package,
  required String gym,
}) async {
  final templates = membershipWhatsAppTemplates(
      subscription: subscription, member: member, package: package, gym: gym);
  var selected = templates.keys.first;
  final message = TextEditingController(text: templates[selected]);
  final whatsapp = member['whatsapp']?.toString().trim() ?? '';
  final phone = TextEditingController(
      text: whatsapp.isEmpty ? member['phone']?.toString() ?? '' : whatsapp);
  final form = GlobalKey<FormState>();
  String? error;
  final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              actionsOverflowButtonSpacing: 8,
              title: const Text('WhatsApp message'),
              content: SizedBox(
                  width: 480,
                  child: Form(
                      key: form,
                      child: SingleChildScrollView(
                          child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                              controller: phone,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                  labelText: 'WhatsApp number',
                                  helperText:
                                      'Include country code, e.g. +971501234567')),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                              initialValue: selected,
                              decoration: const InputDecoration(
                                  labelText: 'Message template'),
                              items: [
                                for (final key in templates.keys)
                                  DropdownMenuItem(value: key, child: Text(key))
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    selected = value;
                                    message.text = templates[value]!;
                                  });
                                }
                              }),
                          const SizedBox(height: 16),
                          TextFormField(
                              controller: message,
                              minLines: 4,
                              maxLines: 8,
                              decoration:
                                  const InputDecoration(labelText: 'Message'),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? 'Enter a message'
                                      : null),
                          const SizedBox(height: 12),
                          const Text(
                              'WhatsApp opens with this message ready. Tap Send in WhatsApp to deliver it.'),
                          if (error != null)
                            Text(error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                        ],
                      )))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                FilledButton.icon(
                    icon: const Icon(CupertinoIcons.chat_bubble_text),
                    label: const Text('Open WhatsApp'),
                    onPressed: () async {
                      if (!form.currentState!.validate()) return;
                      final number = whatsappPhone(phone.text);
                      if (number == null) {
                        setState(() => error =
                            'Enter a valid WhatsApp number with country code.');
                        return;
                      }
                      try {
                        final uri = Uri.https(
                            'wa.me', '/$number', {'text': message.text.trim()});
                        if (!await launchUrl(uri,
                            mode: LaunchMode.externalApplication)) {
                          throw StateError('Unable to launch');
                        }
                        if (context.mounted) Navigator.pop(context);
                      } catch (_) {
                        if (context.mounted) {
                          setState(() => error =
                              'Unable to open WhatsApp. Check your browser or WhatsApp installation and try again.');
                        }
                      }
                    }),
              ],
            ),
          ));
  await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  message.dispose();
  phone.dispose();
}
