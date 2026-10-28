import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../features/subscriptions/data/operations_repository.dart';
import 'database/database.dart';
import 'sync/sync_engine.dart';
import 'sync/workspace_repository.dart';
import 'operation_error.dart';

Future<void> showAdjustment(
  BuildContext context,
  CachedRecord record, {
  bool packageChange = false,
  bool deactivate = false,
}) async {
  final operations = context.read<OperationsRepository>(),
      repo = context.read<WorkspaceRepository>(),
      sync = context.read<SyncEngine>();
  final form = GlobalKey<FormState>(), reason = TextEditingController();
  final operation = const Uuid().v4();
  String? package, error;
  var policy = 'next_renewal', busy = false, attempted = false;
  final packages =
      await (repo.db.select(repo.db.cachedRecords)..where(
            (r) =>
                r.scope.equals(repo.scope) &
                r.kind.equals('membership_packages') &
                r.syncState.equals('synced'),
          ))
          .get();
  if (!context.mounted) {
    reason.dispose();
    return;
  }
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(
          packageChange
              ? 'Change membership package'
              : deactivate
              ? 'Deactivate employee'
              : 'Reverse payment',
        ),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    packageChange
                        ? 'Immediate changes use daily-rate proration over the remaining paid term. The server retains every invoice and adjustment.'
                        : deactivate
                        ? 'This removes gym access. The employee account and audit history are retained.'
                        : 'This restores the invoice balance and voids the official receipt. The original payment remains in the audit history.',
                  ),
                  const SizedBox(height: 16),
                  if (packageChange) ...[
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'New package',
                      ),
                      items: [
                        for (final p in packages.where(
                          (p) =>
                              (jsonDecode(p.payload) as Map)['status'] ==
                              'active',
                        ))
                          DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              (jsonDecode(p.payload) as Map)['name'] as String,
                            ),
                          ),
                      ],
                      onChanged: attempted ? null : (v) => package = v,
                      validator: (v) => v == null ? 'Select a package' : null,
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: policy,
                      decoration: const InputDecoration(
                        labelText: 'Change policy',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'next_renewal',
                          child: Text('At next renewal'),
                        ),
                        DropdownMenuItem(
                          value: 'immediate',
                          child: Text('Immediately with proration'),
                        ),
                      ],
                      onChanged: attempted ? null : (v) => policy = v!,
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: reason,
                    enabled: !attempted,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Enter a reason' : null,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton(
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
                      if (packageChange) {
                        await operations.changePackage(
                          record.id,
                          record.version,
                          package!,
                          policy,
                          reason.text.trim(),
                          operation,
                        );
                      } else if (deactivate) {
                        await operations.deactivate(
                          (jsonDecode(record.payload) as Map)['user_id']
                              as String,
                        );
                      } else {
                        await operations.reversePayment(
                          (jsonDecode(record.payload) as Map)['payment_id']
                              as String,
                          reason.text.trim(),
                          operation,
                        );
                      }
                      await sync.sync();
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } catch (failure) {
                      if (!dialogContext.mounted) return;
                      update(() {
                        busy = false;
                        if (definitiveOperationError(failure) ||
                            failure is StateError) {
                          attempted = false;
                        }
                        error = operationErrorMessage(failure);
                      });
                    }
                  },
            child: Text(
              busy
                  ? 'Saving…'
                  : attempted
                  ? 'Retry request'
                  : packageChange
                  ? 'Change package'
                  : deactivate
                  ? 'Deactivate employee'
                  : 'Reverse payment',
            ),
          ),
        ],
      ),
    ),
  );
  await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  reason.dispose();
}
