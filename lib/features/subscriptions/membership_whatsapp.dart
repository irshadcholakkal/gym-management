import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/record_labels.dart';
import 'domain/membership_status.dart';

Future<void> showMembershipWhatsApp(
  BuildContext context, {
  required Map subscription,
  required Map member,
  required String package,
  required String gym,
}) async {
  final status = MembershipStatus(subscription);
  final name = member['full_name']?.toString() ?? 'Member';
  final lastDay = status.end?.subtract(const Duration(days: 1));
  final expiry = lastDay == null ? 'the expiry date' : displayDate(lastDay);
  final templates = <String, String>{
    if (status.status == 'active' || status.status == 'expiring_soon')
      'Before expiry':
          'Hi $name, a reminder from $gym: your $package membership is valid through $expiry (${status.countdown.toLowerCase()}). Please contact us to renew. Thank you!',
    if (status.status == 'expired')
      'Expired':
          'Hi $name, your $package membership at $gym expired after $expiry. We would love to welcome you back! Please contact us to renew.',
    if (status.status == 'paused')
      'Paused':
          'Hi $name, your $package membership at $gym is paused. Please contact us when you are ready to resume. Your expiry will be recalculated on resume.',
    if (status.status == 'active' ||
        status.status == 'expiring_soon' ||
        status.status == 'scheduled_renewal')
      'Renewed':
          'Hi $name, thank you for renewing your $package membership at $gym! Your membership runs from ${displayDate(subscription['start_date'])} through $expiry. We look forward to seeing you!',
    'Status update':
        'Hi $name, your $package membership status at $gym is ${displayLabel(status.status).toLowerCase()}. Please contact us if you need assistance.',
  };
  var selected = templates.keys.first;
  final message = TextEditingController(text: templates[selected]);
  final phone = TextEditingController(text: member['phone']?.toString() ?? '');
  final form = GlobalKey<FormState>();
  String? error;
  final route = DialogRoute<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
            builder: (context, setState) => AlertDialog(
              title: const Text('WhatsApp member'),
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
                    icon: const Icon(Icons.open_in_new),
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
