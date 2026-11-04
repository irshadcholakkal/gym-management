import '../features/employees/employee_access.dart';
import '../features/auth/domain/access.dart';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../features/payments/domain/money.dart';
import '../features/payments/domain/membership_quote.dart';
import '../features/receipts/domain/receipt_pdf.dart';
import '../features/subscriptions/data/operations_repository.dart';
import 'database/database.dart';
import 'sync/sync_engine.dart';
import 'sync/workspace_repository.dart';
import 'operation_error.dart';
import 'record_labels.dart';

Future<void> showServerOperation(
  BuildContext context,
  String type, {
  CachedRecord? record,
}) async {
  final parentContext = context;
  final repo = context.read<WorkspaceRepository>(),
      operations = context.read<OperationsRepository>(),
      sync = context.read<SyncEngine>();
  final values = record == null
      ? <String, dynamic>{}
      : jsonDecode(record.payload) as Map<String, dynamic>;
  final renewal = type == 'subscribe' && record?.kind == 'subscriptions';
  final operation =
      Uuid().v4(); // Retained across uncertain retries in this dialog.
  final form = GlobalKey<FormState>();
  final date = TextEditingController(
    text: DateTime.now()
        .toUtc()
        .add(Duration(hours: 4))
        .toIso8601String()
        .substring(0, 10),
  );
  final amount = TextEditingController(),
      reason = TextEditingController(),
      email = TextEditingController(),
      name = TextEditingController(),
      phone = TextEditingController(),
      username = TextEditingController();
  final employeeOptions = <String, bool>{};
  final discount = TextEditingController(text: '0.00'),
      discountReason = TextEditingController();
  if (renewal) {
    final end = DateTime.tryParse(values['end_exclusive'] as String? ?? '');
    if (end != null && end.isAfter(DateTime.parse(date.text))) {
      date.text = end.toIso8601String().substring(0, 10);
    }
  }
  var method = 'cash',
      role = 'trainer',
      action = values['status'] == 'paused' ? 'resume' : 'pause';
  String? member = renewal ? values['member_id'] as String? : null,
      package = renewal ? values['package_id'] as String? : null,
      error;
  var busy = false, attempted = false;
  final members = await (repo.db.select(repo.db.cachedRecords)
        ..where(
          (r) =>
              r.scope.equals(repo.scope) &
              r.kind.equals('members') &
              r.syncState.equals('synced'),
        ))
      .get();
  final packages = await (repo.db.select(repo.db.cachedRecords)
        ..where(
          (r) =>
              r.scope.equals(repo.scope) &
              r.kind.equals('membership_packages') &
              r.syncState.equals('synced'),
        ))
      .get();
  if (!context.mounted) return;
  if (!packages.any(
    (p) =>
        p.id == package && (jsonDecode(p.payload) as Map)['status'] == 'active',
  )) {
    package = null;
  }
  Map selectedPackage() =>
      packages
          .where((p) => p.id == package)
          .map((p) => jsonDecode(p.payload) as Map)
          .firstOrNull ??
      {};
  int discountValue() {
    try {
      return Money.parse(discount.text.trim().isEmpty ? '0' : discount.text);
    } catch (_) {
      return 0;
    }
  }

  MembershipQuote quote() => MembershipQuote(
        priceMinor: selectedPackage()['price_minor'] as int? ?? 0,
        enrollmentFeeMinor:
            selectedPackage()['enrollment_fee_minor'] as int? ?? 0,
        taxBasisPoints: selectedPackage()['tax_basis_points'] as int? ?? 0,
        discountMinor: discountValue(),
      );
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(
          {
            'subscribe': renewal ? 'Renew membership' : 'Create membership',
            'pay': 'Record payment',
            'transition': 'Manage membership',
            'invite': 'Invite team member',
          }[type]!,
        ),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    type == 'subscribe'
                        ? 'Choose the membership package and review the amount due.'
                        : type == 'pay'
                            ? 'Enter the amount actually received from the member.'
                            : type == 'invite'
                                ? 'Send a secure invitation to join your gym.'
                                : 'Choose the membership action and effective date.',
                  ),
                  SizedBox(height: 16),
                  if (type == 'subscribe') ...[
                    DropdownButtonFormField<String>(
                      initialValue: member,
                      decoration: InputDecoration(labelText: 'Member'),
                      items: [
                        for (final r in members)
                          DropdownMenuItem(
                            value: r.id,
                            child: Text(
                              (jsonDecode(r.payload) as Map)['full_name']
                                  as String,
                            ),
                          ),
                      ],
                      onChanged: attempted || renewal
                          ? null
                          : (v) => update(() => member = v),
                      validator: (v) =>
                          v == null ? 'Select a synced member' : null,
                    ),
                    SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: package,
                      decoration: InputDecoration(labelText: 'Package'),
                      items: [
                        for (final r in packages.where(
                          (p) =>
                              (jsonDecode(p.payload) as Map)['status'] ==
                              'active',
                        ))
                          DropdownMenuItem(
                            value: r.id,
                            child: Text(
                              (jsonDecode(r.payload) as Map)['name'] as String,
                            ),
                          ),
                      ],
                      onChanged:
                          attempted ? null : (v) => update(() => package = v),
                      validator: (v) =>
                          v == null ? 'Select an active synced package' : null,
                    ),
                    SizedBox(height: 14),
                    if (repo.access.canDiscount) ...[
                      TextFormField(
                        controller: discount,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        enabled: !attempted,
                        keyboardType: TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              'Special discount (${selectedPackage()['currency'] ?? 'AED'})',
                          helperText:
                              'Optional. Applied to the package price before tax.',
                        ),
                        onChanged: (_) => update(() {}),
                        validator: (v) {
                          try {
                            final value = Money.parse(
                              v?.trim().isEmpty ?? true ? '0' : v!,
                            );
                            return value >
                                    (selectedPackage()['price_minor'] as int? ??
                                        0)
                                ? 'Discount cannot exceed the package price'
                                : null;
                          } catch (_) {
                            return 'Enter an amount with at most two decimal places';
                          }
                        },
                      ),
                      SizedBox(height: 14),
                      if (discountValue() > 0) ...[
                        TextFormField(
                          controller: discountReason,
                          enabled: !attempted,
                          maxLength: 500,
                          decoration: InputDecoration(
                            labelText: 'Discount reason',
                          ),
                          validator: (v) => (v?.trim().isEmpty ?? true)
                              ? 'Enter a reason for this discount'
                              : null,
                        ),
                        SizedBox(height: 14),
                      ],
                    ],
                    if (package != null &&
                        discountValue() <=
                            (selectedPackage()['price_minor'] as int? ?? 0))
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Package price: ${Money.format(quote().priceMinor, selectedPackage()['currency'] as String? ?? 'AED')}',
                            ),
                            if (quote().enrollmentFeeMinor > 0)
                              Text(
                                'Enrollment fee: ${Money.format(quote().enrollmentFeeMinor, selectedPackage()['currency'] as String? ?? 'AED')}',
                              ),
                            if (quote().discountMinor > 0)
                              Text(
                                'Special discount: ${Money.format(quote().discountMinor, selectedPackage()['currency'] as String? ?? 'AED')}',
                              ),
                            if (quote().taxMinor > 0)
                              Text(
                                'Tax: ${Money.format(quote().taxMinor, selectedPackage()['currency'] as String? ?? 'AED')}',
                              ),
                            SizedBox(height: 6),
                            Text(
                              'Total due: ${Money.format(quote().totalMinor, selectedPackage()['currency'] as String? ?? 'AED')}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    SizedBox(height: 14),
                  ],
                  if (type == 'subscribe' || type == 'transition')
                    TextFormField(
                      controller: date,
                      enabled: !attempted,
                      decoration: InputDecoration(
                        labelText: type == 'subscribe'
                            ? 'Membership start date'
                            : 'Effective date',
                        helperText: 'YYYY-MM-DD',
                      ),
                      validator: (v) {
                        final parsed = DateTime.tryParse(v ?? '');
                        return parsed == null ||
                                parsed.toIso8601String().substring(0, 10) != v
                            ? 'Enter a valid calendar date'
                            : null;
                      },
                    ),
                  if (type == 'transition') ...[
                    SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: action,
                      decoration: InputDecoration(labelText: 'Action'),
                      items: [
                        for (final a in [
                          'pause',
                          'resume',
                          if (repo.access.administer) ...['extend', 'cancel'],
                        ])
                          DropdownMenuItem(
                            value: a,
                            child: Text(displayLabel(a)),
                          ),
                      ],
                      onChanged:
                          attempted ? null : (v) => update(() => action = v!),
                    ),
                    SizedBox(height: 14),
                    TextFormField(
                      controller: reason,
                      enabled: !attempted,
                      decoration: InputDecoration(labelText: 'Reason'),
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'A reason is required'
                          : null,
                    ),
                    if (action == 'extend') ...[
                      SizedBox(height: 14),
                      TextFormField(
                        controller: amount,
                        enabled: !attempted,
                        decoration: InputDecoration(
                          labelText: 'Extension days',
                        ),
                        validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                            ? 'Enter positive whole days'
                            : null,
                      ),
                    ],
                  ],
                  if (type == 'pay') ...[
                    Text(
                      'Outstanding: ${Money.format((values['total_minor'] as int) - (values['paid_minor'] as int) - (values['credit_minor'] as int? ?? 0), values['currency'] as String)}',
                    ),
                    SizedBox(height: 14),
                    TextFormField(
                      controller: amount,
                      enabled: !attempted,
                      decoration: InputDecoration(
                        labelText: 'Amount received',
                      ),
                      validator: (v) {
                        try {
                          if (Money.parse(v ?? '') <= 0) {
                            return 'Amount must be positive';
                          }
                          return null;
                        } catch (_) {
                          return 'Enter an amount with at most two decimals';
                        }
                      },
                    ),
                    SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: method,
                      decoration: InputDecoration(
                        labelText: 'Payment method',
                      ),
                      items: [
                        for (final m in [
                          'cash',
                          'bank_transfer',
                          'credit_card',
                          'debit_card',
                          'cheque',
                          'online',
                          'other',
                        ])
                          DropdownMenuItem(
                            value: m,
                            child: Text(displayLabel(m)),
                          ),
                      ],
                      onChanged: attempted ? null : (v) => method = v!,
                    ),
                    SizedBox(height: 14),
                    TextFormField(
                      controller: reason,
                      enabled: !attempted,
                      decoration: InputDecoration(
                        labelText: 'Payment reference (optional)',
                      ),
                    ),
                  ],
                  if (type == 'invite') ...[
                    TextFormField(
                      controller: name,
                      decoration: InputDecoration(labelText: 'Full name'),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'Enter a name' : null,
                    ),
                    SizedBox(height: 14),
                    TextFormField(
                      controller: email,
                      decoration: InputDecoration(labelText: 'Email'),
                      validator: (v) => RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                              .hasMatch(v ?? '')
                          ? null
                          : 'Enter a valid email',
                    ),
                    SizedBox(height: 14),
                    TextFormField(
                      controller: phone,
                      decoration: InputDecoration(
                        labelText: 'Phone (+country code)',
                      ),
                    ),
                    SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: InputDecoration(labelText: 'Role'),
                      items: [
                        for (final r in [
                          'admin',
                          'manager',
                          'trainer',
                          'receptionist',
                          'staff',
                        ])
                          DropdownMenuItem(
                            value: r,
                            child: Text(displayLabel(r)),
                          ),
                      ],
                      onChanged: (v) => update(() {
                        role = v!;
                        employeeOptions.clear();
                      }),
                    ),
                  ],
                  if (type == 'invite') ...[
                    SizedBox(height: 12),
                    EmployeeRoleSummary(role: GymRole.values.byName(role)),
                    SizedBox(height: 14),
                    TextFormField(
                        controller: username,
                        autocorrect: false,
                        decoration:
                            InputDecoration(labelText: 'Username (optional)'),
                        validator: (value) {
                          final text = (value ?? '').trim().toLowerCase();
                          return text.isEmpty ||
                                  RegExp(r'^[a-z][a-z0-9_.-]{2,31}$')
                                          .hasMatch(text) &&
                                      !text.startsWith('emp-')
                              ? null
                              : 'Use 3-32 characters, starting with a letter; no emp- prefix';
                        }),
                    for (final option in employeeOptionLabels.entries)
                      Builder(builder: (context) {
                        final base = GymAccess(
                            gymId: '',
                            userId: '',
                            name: '',
                            gymName: '',
                            role: GymRole.values.byName(role));
                        final available = switch (option.key) {
                          'administration' => base.administer,
                          'discounts' => base.canDiscount &&
                              employeeOptions['operations'] != false,
                          'edit_members' => base.finances &&
                              employeeOptions['operations'] != false,
                          _ => base.finances,
                        };
                        return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(option.value),
                            value: available &&
                                employeeOptions[option.key] != false,
                            onChanged: busy || !available
                                ? null
                                : (value) => update(() =>
                                    employeeOptions[option.key] = value!));
                      }),
                    SizedBox(height: 8),
                    Text(
                        'The employee will receive an email to set their password. They can then sign in with their username, employee ID or email.'),
                  ],
                  if (error != null)
                    Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: Text(
                        error!,
                        style: TextStyle(color: Colors.red),
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
            child: Text('Close'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!form.currentState!.validate()) return;
                    update(() {
                      busy = true;
                      attempted = type != 'invite';
                      error = null;
                    });
                    try {
                      Map<String, dynamic>? receipt;
                      switch (type) {
                        case 'subscribe':
                          await operations.subscribe(
                            member!,
                            package!,
                            date.text,
                            operation,
                            discountMinor:
                                repo.access.canDiscount ? discountValue() : 0,
                            discountReason: repo.access.canDiscount
                                ? discountReason.text.trim()
                                : '',
                          );
                        case 'transition':
                          await operations.transition(
                            record!.id,
                            record.version,
                            action,
                            date.text,
                            reason.text.trim(),
                            operation,
                            days:
                                action == 'extend' ? int.parse(amount.text) : 0,
                          );
                        case 'pay':
                          final result = await operations.pay(
                            record!.id,
                            Money.parse(amount.text),
                            method,
                            reason.text.trim(),
                            operation,
                          );
                          receipt = Map<String, dynamic>.from(
                            result['receipt'] as Map,
                          );
                        case 'invite':
                          await operations.invite({
                            'full_name': name.text.trim(),
                            'email': email.text.trim().toLowerCase(),
                            'phone': phone.text.trim(),
                            'role': role,
                            'username': username.text.trim().toLowerCase(),
                            'access_options': jsonEncode(employeeOptions),
                          });
                      }
                      await sync.sync();
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                      if (receipt != null && parentContext.mounted) {
                        final finalized = receipt;
                        await Navigator.of(parentContext).push(
                          MaterialPageRoute<void>(
                            builder: (_) => Scaffold(
                              appBar: AppBar(
                                title: Text(
                                  'Receipt #${finalized['receipt_number']}',
                                ),
                              ),
                              body: PdfPreview(
                                build: (_) => ReceiptPdf.build(finalized),
                              ),
                            ),
                          ),
                        );
                      }
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
                  ? (type == 'invite' ? 'Sending…' : 'Saving…')
                  : attempted
                      ? 'Retry request'
                      : {
                          'subscribe': renewal
                              ? 'Renew membership'
                              : 'Create membership',
                          'pay': 'Record payment',
                          'invite': 'Send invitation',
                          'transition': '${displayLabel(action)} membership',
                        }[type]!,
            ),
          ),
        ],
      ),
    ),
  );
  await Navigator.of(parentContext, rootNavigator: true).push(route);
  await route.completed;
  for (final c in [
    date,
    amount,
    reason,
    email,
    name,
    phone,
    username,
    discount,
    discountReason,
  ]) {
    c.dispose();
  }
}
