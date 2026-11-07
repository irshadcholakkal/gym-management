import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/database.dart';
import '../../core/operation_error.dart';
import '../../core/record_labels.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/workspace_repository.dart';
import '../members/member_identity.dart';
import '../subscriptions/data/operations_repository.dart';
import 'domain/money.dart';

Future<void> showPayAllInvoices(
    BuildContext context, CachedRecord member) async {
  final repo = context.read<WorkspaceRepository>();
  if (!repo.access.finances) return;
  final sync = context.read<SyncEngine>();
  final receipt = await showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PayAllInvoicesDialog(
        member: member,
        operations: context.read<OperationsRepository>(),
        scope: repo.scope),
  );
  if (receipt == null) return;
  try {
    await sync.sync();
  } catch (_) {/* The payment is already confirmed. */}
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'All reviewed invoices paid. Receipt #${receipt['receipt_number']} is available in Receipts.')));
  }
}

class PayAllInvoicesDialog extends StatefulWidget {
  const PayAllInvoicesDialog(
      {super.key,
      required this.member,
      required this.operations,
      required this.scope});
  final CachedRecord member;
  final OperationsRepository operations;
  final String scope;
  @override
  State<PayAllInvoicesDialog> createState() => _PayAllInvoicesDialogState();
}

class _PayAllInvoicesDialogState extends State<PayAllInvoicesDialog> {
  final reference = TextEditingController();
  List<Map<String, dynamic>> invoices = [];
  String method = 'cash', operation = const Uuid().v4();
  String? error;
  bool loading = true, busy = false, attempted = false, mustRefresh = false;
  String get storageKey => 'gympro_pay_all:${widget.scope}:${widget.member.id}';
  Set<String> get currencies =>
      invoices.map((i) => i['currency'] as String).toSet();
  int get total =>
      invoices.fold(0, (sum, i) => sum + (i['balance_minor'] as int));
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getString(storageKey);
      final data = pending == null
          ? await widget.operations.memberInvoiceQuote(widget.member.id)
          : jsonDecode(pending) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        invoices = (data['invoices'] as List)
            .map((i) => Map<String, dynamic>.from(i as Map))
            .toList();
        if (pending != null) {
          attempted = true;
          operation = data['operation'] as String;
          method = data['method'] as String;
          reference.text = data['reference'] as String;
          error =
              'A previous payment needs confirmation. Retry to confirm the same payment safely.';
        }
        loading = false;
      });
    } catch (failure) {
      if (mounted) {
        setState(() {
          loading = false;
          error = operationErrorMessage(failure);
        });
      }
    }
  }

  Future<void> submit() async {
    if (busy || invoices.isEmpty || currencies.length != 1 || mustRefresh) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
      attempted = true;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      // Persist before submission, including the reviewed invoice amounts.
      if (!await prefs.setString(
          storageKey,
          jsonEncode({
            'invoices': invoices,
            'operation': operation,
            'method': method,
            'reference': reference.text.trim(),
          }))) {
        throw StateError('Unable to save this payment request. Try again.');
      }
      final result = await widget.operations.payAllInvoices(
          widget.member.id,
          invoices
              .map((i) => {
                    'id': i['id'],
                    'balance_minor': i['balance_minor'],
                    'currency': i['currency']
                  })
              .toList(),
          method,
          reference.text.trim(),
          operation);
      // Cleanup must never turn a confirmed payment into a retry error.
      try {
        await prefs.remove(storageKey);
      } catch (_) {}
      if (mounted) {
        Navigator.pop(
            context, Map<String, dynamic>.from(result['receipt'] as Map));
      }
    } catch (failure) {
      if (definitiveOperationError(failure)) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove(storageKey);
        } catch (_) {}
        mustRefresh = true;
      }
      if (mounted) {
        setState(() {
          busy = false;
          error = operationErrorMessage(failure);
        });
      }
    }
  }

  @override
  void dispose() {
    reference.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('Pay all outstanding invoices'),
        content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
                child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                    memberNameWithId(jsonDecode(widget.member.payload) as Map)),
                const SizedBox(height: 16),
                if (loading) const Center(child: CircularProgressIndicator()),
                if (!loading && invoices.isEmpty && error == null)
                  const Text('This member has no outstanding invoices.'),
                for (final invoice in invoices)
                  ListTile(
                      contentPadding: EdgeInsets.zero,
                      title:
                          Text(invoice['package_name'] as String? ?? 'Invoice'),
                      subtitle: Text('Due ${displayDate(invoice['due_date'])}'),
                      trailing: Text(Money.format(
                          invoice['balance_minor'] as int,
                          invoice['currency'] as String))),
                if (invoices.isNotEmpty) ...[
                  const Divider(),
                  if (currencies.length == 1)
                    Text('Total: ${Money.format(total, currencies.single)}',
                        style: Theme.of(context).textTheme.titleLarge)
                  else
                    const Text(
                        'These invoices use different currencies. Pay them separately.'),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                      initialValue: method,
                      decoration:
                          const InputDecoration(labelText: 'Payment method'),
                      items: [
                        for (final value in [
                          'cash',
                          'bank_transfer',
                          'credit_card',
                          'debit_card',
                          'cheque',
                          'online',
                          'other'
                        ])
                          DropdownMenuItem(
                              value: value, child: Text(displayLabel(value)))
                      ],
                      onChanged: attempted
                          ? null
                          : (value) => setState(() => method = value!)),
                  const SizedBox(height: 12),
                  TextField(
                      controller: reference,
                      enabled: !attempted,
                      decoration: const InputDecoration(
                          labelText: 'Payment reference (optional)')),
                  const SizedBox(height: 16),
                  Text(
                      'Record the full amount received for these ${invoices.length} invoices. One payment and one receipt will be created.'),
                ],
                if (error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(error!)),
              ],
            ))),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('Close')),
          FilledButton(
              onPressed: loading ||
                      busy ||
                      invoices.isEmpty ||
                      currencies.length != 1 ||
                      mustRefresh
                  ? null
                  : submit,
              child: Text(busy
                  ? 'Recording…'
                  : attempted
                      ? 'Retry payment'
                      : 'Confirm payment')),
        ],
      ));
}
