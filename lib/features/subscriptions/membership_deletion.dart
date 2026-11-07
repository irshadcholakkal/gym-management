import 'dart:convert';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/database.dart';
import '../../core/operation_error.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/workspace_repository.dart';
import 'data/operations_repository.dart';

Future<void> showMembershipDeletion(BuildContext context, CachedRecord record,
    {bool restore = false}) async {
  final workspace = context.read<WorkspaceRepository>();
  if (!workspace.access.administer) return;
  final operations = context.read<OperationsRepository>(),
      sync = context.read<SyncEngine>();
  final reason = TextEditingController();
  final form = GlobalKey<FormState>();
  final operation = const Uuid().v4();
  bool busy = false, attempted = false;
  String? error;
  final data = jsonDecode(record.payload) as Map;
  final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => PopScope(
              canPop: !busy,
              child: AlertDialog(
                title: Text(restore
                    ? 'Restore membership'
                    : 'Delete accidental membership'),
                content: SizedBox(
                    width: 460,
                    child: SingleChildScrollView(
                        child: Form(
                            key: form,
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text((data['package_snapshot']
                                              as Map?)?['name']
                                          ?.toString() ??
                                      'Membership'),
                                  const SizedBox(height: 12),
                                  Text(restore
                                      ? 'Restore this membership and its original invoices. Restoration is blocked if its dates overlap another membership.'
                                      : 'Remove this accidental membership from normal views and void its unpaid invoices. You can restore it from the Deleted memberships filter. Entries with payment, credit, pause or plan-change history cannot be deleted.'),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                      controller: reason,
                                      enabled: !attempted,
                                      maxLines: 2,
                                      decoration: const InputDecoration(
                                          labelText: 'Reason',
                                          hintText:
                                              'For example: Created the wrong plan'),
                                      validator: (value) =>
                                          value?.trim().isNotEmpty == true
                                              ? null
                                              : 'Enter a reason'),
                                  if (error != null)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(error!)),
                                ])))),
                actions: [
                  TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.pop(dialogContext, false),
                      child: const Text('Keep membership')),
                  FilledButton.icon(
                      style: restore
                          ? null
                          : FilledButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.error),
                      onPressed: busy
                          ? null
                          : () async {
                              if (!form.currentState!.validate()) return;
                              update(() {
                                busy = true;
                                attempted = true;
                                error = null;
                              });
                              try {
                                await operations.setMembershipDeleted(
                                    record.id,
                                    record.version,
                                    !restore,
                                    reason.text.trim(),
                                    operation);
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext, true);
                                }
                              } catch (failure) {
                                if (dialogContext.mounted) {
                                  update(() {
                                    busy = false;
                                    error = operationErrorMessage(failure);
                                  });
                                }
                              }
                            },
                      icon: Icon(restore
                          ? CupertinoIcons.arrow_uturn_left
                          : CupertinoIcons.trash),
                      label: Text(busy
                          ? 'Saving…'
                          : attempted
                              ? 'Retry request'
                              : restore
                                  ? 'Restore membership'
                                  : 'Delete membership')),
                ],
              ))));
  final done = await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  reason.dispose();
  if (done != true) return;
  try {
    await sync.sync();
  } catch (_) {}
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(restore
            ? 'Membership restored.'
            : 'Membership deleted. Find it under Deleted memberships if you need to restore it.')));
  }
}
