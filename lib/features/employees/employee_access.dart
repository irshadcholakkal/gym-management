import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/database/database.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/workspace_repository.dart';
import '../auth/domain/access.dart';

const employeeOptionLabels = {
  'operations': 'View members, memberships, packages, payments and receipts',
  'edit_members': 'Add and edit members',
  'discounts': 'Apply membership discounts',
  'administration': 'Manage employees and workspace settings',
};

class EmployeeRoleSummary extends StatelessWidget {
  const EmployeeRoleSummary({super.key, required this.role});
  final GymRole role;
  @override
  Widget build(BuildContext context) {
    final access =
        GymAccess(gymId: '', userId: '', name: '', gymName: '', role: role);
    return Text(
        [
          'Overview and notifications',
          if (role == GymRole.trainer)
            'Assigned members and memberships (read only)',
          if (access.finances)
            'Members, memberships, packages, payments and receipts',
          if (access.canDiscount) 'Discounts',
          if (access.administer) 'Employee and workspace administration',
        ].join(' • '),
        style: Theme.of(context).textTheme.bodySmall);
  }
}

Future<void> showEmployeeAccess(
    BuildContext context, CachedRecord record) async {
  final repo = context.read<WorkspaceRepository>();
  if (!repo.access.administer) return;
  final client = context.read<SupabaseClient>();
  final sync = context.read<SyncEngine>();
  final data = jsonDecode(record.payload) as Map;
  final username =
      TextEditingController(text: data['username'] as String? ?? '');
  final form = GlobalKey<FormState>();
  var role = GymRole.values.byName(data['access_role'] as String? ?? 'staff');
  final options = Map<String, bool>.from(data['access_options'] as Map? ?? {});
  var busy = false;
  String? error;
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) {
        final base =
            GymAccess(gymId: '', userId: '', name: '', gymName: '', role: role);
        bool available(String option) => switch (option) {
              'administration' => base.administer,
              'discounts' => base.canDiscount && options['operations'] != false,
              'edit_members' => base.finances && options['operations'] != false,
              _ => base.finances,
            };
        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          actionsOverflowButtonSpacing: 8,
          title: const Text('Employee access'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Form(
                key: form,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(data['full_name'] as String? ?? 'Employee',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      SelectableText(
                          'Employee ID: EMP-${data['employee_number']}'),
                      const SizedBox(height: 16),
                      TextFormField(
                          controller: username,
                          enabled: !busy,
                          autocorrect: false,
                          decoration: const InputDecoration(
                              labelText: 'Username (optional)',
                              helperText:
                                  '3–32 characters; letters, numbers, dots, _ or -'),
                          validator: (value) {
                            final text = (value ?? '').trim().toLowerCase();
                            return text.isEmpty ||
                                    RegExp(r'^[a-z][a-z0-9_.-]{2,31}$')
                                            .hasMatch(text) &&
                                        !text.startsWith('emp-')
                                ? null
                                : 'Start with a letter; do not use the emp- prefix';
                          }),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<GymRole>(
                          initialValue: role,
                          decoration: const InputDecoration(
                              labelText: 'Role',
                              prefixIcon: Icon(Icons.badge_outlined)),
                          items: [
                            for (final value in GymRole.values
                                .where((value) => value != GymRole.owner))
                              DropdownMenuItem(
                                  value: value,
                                  child: Text(value.name[0].toUpperCase() +
                                      value.name.substring(1)))
                          ],
                          onChanged: busy
                              ? null
                              : (value) => update(() {
                                    role = value!;
                                    options.clear();
                                  })),
                      const SizedBox(height: 12),
                      EmployeeRoleSummary(role: role),
                      const SizedBox(height: 16),
                      const Text('Available options',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      for (final entry in employeeOptionLabels.entries)
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.value),
                            value: available(entry.key) &&
                                options[entry.key] != false,
                            onChanged: busy || !available(entry.key)
                                ? null
                                : (value) => update(() {
                                      options[entry.key] = value!;
                                    })),
                      const Text(
                          'Employees set their password using their email invitation. They can then sign in with their employee ID, username or email. Password resets use their email address.'),
                      if (error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                    ]),
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        update(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await client.rpc('set_employee_access', params: {
                            'p_gym': repo.access.gymId,
                            'p_user': data['user_id'],
                            'p_role': role.name,
                            'p_username': username.text.trim().toLowerCase(),
                            'p_options': options
                          });
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          await sync.sync();
                        } on PostgrestException catch (failure) {
                          if (context.mounted) {
                            update(() {
                              error = failure.code == '23505'
                                  ? 'That username is already in use. Choose another.'
                                  : 'Could not update access. Check your connection and administrator permissions.';
                              busy = false;
                            });
                          }
                        } catch (_) {
                          if (context.mounted) {
                            update(() {
                              error =
                                  'Could not update employee access. Try again.';
                              busy = false;
                            });
                          }
                        }
                      },
                child: Text(busy ? 'Saving…' : 'Save access')),
          ],
        );
      }),
    );
  } finally {
    username.dispose();
  }
}
