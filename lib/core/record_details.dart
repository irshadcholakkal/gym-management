import 'status_badge.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import '../features/subscriptions/membership_actions.dart';
import '../features/auth/domain/access.dart';
import 'dart:convert';

import 'package:flutter/material.dart';
import '../features/members/member_photos.dart';
import '../features/members/member_identity.dart';
import '../features/receipts/domain/invoice_html.dart';
import '../features/payments/domain/money.dart';
import '../features/subscriptions/domain/membership_status.dart';
import 'database/database.dart';
import 'record_labels.dart';
import 'sync/workspace_repository.dart';

/// One responsive detail surface for members, packages and operational records.
class RecordDetailsPanel extends StatelessWidget {
  const RecordDetailsPanel(
      {super.key,
      required this.record,
      required this.repository,
      this.photos,
      this.onOperation,
      this.actions = const []});
  final void Function(String action, CachedRecord record)? onOperation;
  final CachedRecord record;
  final WorkspaceRepository repository;
  final MemberPhotos? photos;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phone = MediaQuery.sizeOf(context).width < 600;
    final content = SafeArea(
        child: Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 12, 12),
          child: Row(children: [
            Expanded(
                child: Text('${_kindName(record.kind)} details',
                    style: Theme.of(context).textTheme.titleMedium)),
            IconButton(
                tooltip: 'Close details',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(CupertinoIcons.xmark)),
          ])),
      const Divider(height: 1),
      Expanded(
          child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: RecordDetails(
                  record: record,
                  repository: repository,
                  photos: photos,
                  onOperation: onOperation))),
      if (actions.isNotEmpty) ...[
        const Divider(height: 1),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(children: [
              Expanded(
                  child: Text('Quick actions',
                      style: Theme.of(context).textTheme.bodySmall)),
              Flexible(
                  flex: 3,
                  child: Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      alignment: WrapAlignment.end,
                      children: [
                        for (final action in actions)
                          if (action is IconButton && action.tooltip != null)
                            TextButton.icon(
                                onPressed: action.onPressed,
                                icon: action.icon,
                                label: Text(action.tooltip!))
                          else
                            action
                      ])),
            ])),
      ],
    ]));
    if (phone) {
      return Dialog.fullscreen(backgroundColor: scheme.surface, child: content);
    }
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(32),
      child: SizedBox(
          width: 820,
          height: MediaQuery.sizeOf(context).height * .9,
          child: content),
    );
  }
}

String _kindName(String kind) => switch (kind) {
      'members' => 'Member',
      'membership_packages' => 'Package',
      'subscriptions' => 'Membership',
      'invoices' => 'Invoice',
      'payments' => 'Payment',
      'receipts' => 'Receipt',
      'employees' => 'Team member',
      _ => displayLabel(kind),
    };

IconData _kindIcon(String kind) => switch (kind) {
      'members' || 'employees' => CupertinoIcons.person,
      'membership_packages' => CupertinoIcons.cube_box,
      'subscriptions' => CupertinoIcons.calendar,
      'payments' || 'invoices' => CupertinoIcons.creditcard,
      _ => CupertinoIcons.doc_text,
    };

class RecordDetails extends StatelessWidget {
  const RecordDetails(
      {super.key,
      required this.record,
      required this.repository,
      this.photos,
      this.onOperation});
  final void Function(String action, CachedRecord record)? onOperation;
  final MemberPhotos? photos;
  final CachedRecord record;
  final WorkspaceRepository repository;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<CachedRecord>>(
        stream: repository.records,
        builder: (context, snapshot) {
          final records = snapshot.data ?? <CachedRecord>[];
          final current = records
                  .where((r) => r.id == record.id && r.kind == record.kind)
                  .firstOrNull ??
              record;
          final m = jsonDecode(current.payload) as Map<String, dynamic>;
          final labels = RecordLabels(records);
          final scheme = Theme.of(context).colorScheme;
          final status = current.kind == 'subscriptions'
              ? MembershipStatus(m).status
              : m['status']?.toString();
          final title = labels.title(current.kind, m);
          final currency = m['currency'] as String? ?? 'AED';
          final member = current.kind == 'members';
          final package = current.kind == 'membership_packages';
          String value(String key) {
            final raw = m[key];
            if (key == 'member_number') {
              return memberId(raw).isEmpty
                  ? 'Assigned after sync'
                  : memberId(raw);
            }
            if (key == 'invoice_number') return InvoiceHtml.number(raw);
            if (raw == null || raw.toString().trim().isEmpty) return '';
            if ([
              'joining_date',
              'start_date',
              'due_date',
              'created_at',
              'read_at'
            ].contains(key)) {
              return displayDate(raw);
            }
            if (['access_role', 'method', 'duration_unit'].contains(key)) {
              return displayLabel(raw.toString());
            }
            return raw.toString();
          }

          List<_DetailValue> fields(
                  List<(String, String, IconData)> definitions) =>
              [
                for (final (key, label, icon) in definitions)
                  if (value(key).isNotEmpty)
                    _DetailValue(label, value(key), icon),
              ];
          final contact = fields([
            ('phone', 'Phone number', CupertinoIcons.phone),
            ('email', 'Email address', CupertinoIcons.mail),
            ('address', 'Address', CupertinoIcons.location),
            ('occupation', 'Occupation', CupertinoIcons.briefcase),
          ]);
          final information = fields([
            if (member) ('member_number', 'Member ID', CupertinoIcons.number),
            ('employee_number', 'Employee number', CupertinoIcons.number),
            ('username', 'Username', Icons.alternate_email_rounded),
            ('access_role', 'Access role', Icons.admin_panel_settings_outlined),
            ('joining_date', 'Member since', CupertinoIcons.calendar),
            ('start_date', 'Membership starts', CupertinoIcons.calendar),
            ('due_date', 'Payment due', CupertinoIcons.calendar),
            ('created_at', 'Created on', CupertinoIcons.calendar),
            ('receipt_number', 'Receipt number', CupertinoIcons.doc_text),
            ('invoice_number', 'Invoice number', CupertinoIcons.doc_text),
            ('reference', 'Reference', Icons.tag_outlined),
            ('method', 'Payment method', CupertinoIcons.creditcard),
            ('read_at', 'Read on', CupertinoIcons.envelope_open),
          ]);
          final finalDay =
              DateTime.tryParse(m['end_exclusive']?.toString() ?? '');
          if (finalDay != null) {
            information.add(_DetailValue(
                'Final valid membership day',
                displayDate(finalDay.subtract(const Duration(days: 1))),
                CupertinoIcons.calendar));
          }
          final packageDetails = <_DetailValue>[
            if (m['duration_value'] != null)
              _DetailValue(
                  'Membership duration',
                  '${m['duration_value']} ${displayLabel(m['duration_unit']?.toString() ?? 'days').toLowerCase()}',
                  CupertinoIcons.calendar),
            if (m['allowed_pause_days'] != null)
              _DetailValue('Pause allowance', '${m['allowed_pause_days']} days',
                  CupertinoIcons.pause_circle),
          ];
          final money = <_DetailValue>[
            for (final entry in {
              'price_minor': 'Package price',
              'amount_minor': 'Payment amount',
              'subtotal_minor': 'Subtotal before discount',
              'discount_minor': 'Special discount',
              'total_minor': 'Invoice total',
              'paid_minor': 'Amount collected',
              'credit_minor': 'Applied credit',
            }.entries)
              if (m[entry.key] is int)
                _DetailValue(
                    entry.value,
                    Money.format(m[entry.key] as int, currency),
                    CupertinoIcons.money_dollar_circle),
            if (current.kind == 'invoices' && m['total_minor'] is int)
              _DetailValue(
                  'Balance due',
                  Money.format(
                      m['status'] == 'voided'
                          ? 0
                          : (m['total_minor'] as int) -
                              (m['paid_minor'] as int? ?? 0) -
                              (m['credit_minor'] as int? ?? 0),
                      currency),
                  CupertinoIcons.creditcard),
          ];
          final memberPayments = records
              .where((r) =>
                  r.kind == 'payments' &&
                  (jsonDecode(r.payload) as Map)['member_id'] == current.id)
              .map((r) => r.id)
              .toSet();
          final related = records.where((r) {
            if (!['subscriptions', 'payments', 'invoices', 'receipts']
                .contains(r.kind)) {
              return false;
            }
            if (!repository.access.finances && r.kind != 'subscriptions') {
              return false;
            }
            final data = jsonDecode(r.payload) as Map;
            if (data['deleted_at'] != null ||
                data['deleted_with_membership'] != null) {
              return false;
            }
            return data['member_id'] == current.id ||
                (r.kind == 'receipts' &&
                    memberPayments.contains(data['payment_id'])) ||
                (r.kind == 'receipts' &&
                    m['member_number'] != null &&
                    (data['snapshot'] as Map?)?['member_number']?.toString() ==
                        m['member_number'].toString());
          }).toList()
            ..sort((a, b) => ((jsonDecode(b.payload) as Map)['created_at'] ??
                    (jsonDecode(b.payload) as Map)['start_date'] ??
                    '')
                .toString()
                .compareTo(((jsonDecode(a.payload) as Map)['created_at'] ??
                        (jsonDecode(a.payload) as Map)['start_date'] ??
                        '')
                    .toString()));
          return SingleChildScrollView(
            padding: EdgeInsets.all(
                MediaQuery.sizeOf(context).width < 600 ? 16 : 24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (snapshot.hasError)
                    const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text(
                            'Live updates are unavailable. Showing the last available details.')),
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                          width: 64,
                                          height: 64,
                                          decoration: BoxDecoration(
                                              color: scheme.secondaryContainer,
                                              borderRadius:
                                                  BorderRadius.circular(22)),
                                          child: Icon(_kindIcon(current.kind),
                                              size: 30, color: scheme.primary)),
                                      const SizedBox(width: 16),
                                      Expanded(
                                          child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                            Text(_kindName(current.kind),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall),
                                            const SizedBox(height: 4),
                                            SelectableText(title,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .headlineSmall),
                                          ])),
                                    ]),
                                const SizedBox(height: 18),
                                Wrap(spacing: 8, runSpacing: 8, children: [
                                  if (status != null) StatusBadge(status),
                                  StatusBadge(current.syncState,
                                      label: current.syncState == 'synced'
                                          ? 'Up to date'
                                          : null),
                                  if (package &&
                                      repository.access.finances &&
                                      m['price_minor'] is int)
                                    Chip(
                                        label: Text(Money.format(
                                            m['price_minor'] as int,
                                            currency))),
                                ]),
                                if (current.kind == 'subscriptions' &&
                                    MembershipStatus(m)
                                        .countdown
                                        .isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Text(MembershipStatus(m).countdown,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                ],
                              ]))),
                  if (member)
                    _MemberActivity(
                        member: current,
                        records: related,
                        repository: repository,
                        labels: labels,
                        onOperation: onOperation),
                  if (!member &&
                      repository.access.finances &&
                      onOperation != null)
                    _RecordOperations(
                        record: current,
                        onOperation: onOperation!,
                        access: repository.access,
                        hasPaymentHistory: records.any((r) {
                          if (r.kind != 'invoices') return false;
                          final invoice = jsonDecode(r.payload) as Map;
                          return invoice['subscription_id'] == current.id &&
                              ((invoice['paid_minor'] as int? ?? 0) > 0 ||
                                  (invoice['credit_minor'] as int? ?? 0) > 0);
                        })),
                  if (member && photos != null)
                    _DetailSection(
                        title: 'Profile photo',
                        subtitle: 'A familiar face for your front desk.',
                        child: MemberPhotoEditor(
                            photos: photos!, member: current)),
                  if (current.kind == 'subscriptions' &&
                      m['deleted_at'] == null &&
                      repository.access.finances)
                    _DetailSection(
                        title: 'Invoices & payments',
                        subtitle:
                            'Membership dates and payment status are separate. Record a payment only after receiving it.',
                        child: Column(children: [
                          for (final invoice in records.where((r) =>
                              r.kind == 'invoices' &&
                              (jsonDecode(r.payload)
                                      as Map)['subscription_id'] ==
                                  current.id))
                            Builder(builder: (context) {
                              final data = jsonDecode(invoice.payload) as Map;
                              final due = (data['total_minor'] as int? ?? 0) -
                                  (data['paid_minor'] as int? ?? 0) -
                                  (data['credit_minor'] as int? ?? 0);
                              return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(CupertinoIcons.doc_text),
                                  onTap: onOperation == null
                                      ? null
                                      : () => onOperation!('invoice', invoice),
                                  title: Text(data['status'] == 'voided'
                                      ? 'Invoice voided'
                                      : 'Balance due: ${Money.format(due, data['currency'] as String? ?? 'AED')}'),
                                  subtitle: Text(
                                      'Due ${displayDate(data['due_date'])}'),
                                  trailing: due > 0 &&
                                          data['status'] != 'voided' &&
                                          onOperation != null
                                      ? OutlinedButton.icon(
                                          onPressed: () =>
                                              onOperation!('pay', invoice),
                                          icon: const Icon(
                                              CupertinoIcons.creditcard,
                                              size: 18),
                                          label: const Text('Record payment'))
                                      : StatusBadge(
                                          data['status']?.toString() ??
                                              'unpaid'));
                            }),
                        ])),
                  if (contact.isNotEmpty)
                    _DetailSection(
                        title: 'Contact & personal details',
                        subtitle: 'The essentials, in one place.',
                        child: _DetailGrid(values: contact)),
                  if (packageDetails.isNotEmpty)
                    _DetailSection(
                        title: 'What this membership includes',
                        child: _DetailGrid(values: packageDetails)),
                  if (m['member_id'] != null || m['snapshot'] is Map)
                    _DetailSection(
                        title: 'Member & package',
                        child: _DetailGrid(values: [
                          _DetailValue('Member', labels.member(m),
                              CupertinoIcons.person),
                          _DetailValue('Package', labels.package(m),
                              CupertinoIcons.cube_box),
                        ])),
                  if (information.isNotEmpty)
                    _DetailSection(
                        title: member
                            ? 'Member information'
                            : 'Record information',
                        child: _DetailGrid(values: information)),
                  if (repository.access.finances && money.isNotEmpty)
                    _DetailSection(
                        title: 'Price & payment details',
                        subtitle: 'All amounts in $currency.',
                        child: _DetailGrid(values: money)),
                  for (final (key, heading) in [
                    ('description', 'About this package'),
                    ('notes', 'Notes'),
                    ('discount_reason', 'Discount reason'),
                    ('body', 'Message')
                  ])
                    if (value(key).isNotEmpty)
                      _DetailSection(
                          title: heading,
                          child: SelectableText(value(key),
                              style: Theme.of(context).textTheme.bodyLarge)),
                ]),
          );
        },
      );
}

class _MemberActivity extends StatefulWidget {
  const _MemberActivity(
      {required this.member,
      required this.records,
      required this.repository,
      required this.labels,
      this.onOperation});
  final CachedRecord member;
  final List<CachedRecord> records;
  final WorkspaceRepository repository;
  final RecordLabels labels;
  final void Function(String, CachedRecord)? onOperation;

  @override
  State<_MemberActivity> createState() => _MemberActivityState();
}

class _MemberActivityState extends State<_MemberActivity> {
  String selected = 'subscriptions';
  @override
  Widget build(BuildContext context) {
    final finance = widget.repository.access.finances;
    final sections = <String, String>{
      'subscriptions': 'Memberships',
      if (finance) ...{
        'payments': 'Payments',
        'invoices': 'Invoices',
        'receipts': 'Receipts'
      },
    };
    final active = sections.containsKey(selected) ? selected : 'subscriptions';
    final records = widget.records.where((r) => r.kind == active).toList();
    final unpaid = widget.records.where((r) {
      if (r.kind != 'invoices' || r.syncState != 'synced') return false;
      final data = jsonDecode(r.payload) as Map;
      return !['void', 'voided'].contains(data['status']) &&
          (data['total_minor'] as int? ?? 0) -
                  (data['paid_minor'] as int? ?? 0) -
                  (data['credit_minor'] as int? ?? 0) >
              0;
    }).toList();
    return _DetailSection(
        title: 'Member activity',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final section in sections.entries)
                ChoiceChip(
                  label: Text(
                      '${section.value} (${widget.records.where((r) => r.kind == section.key).length})'),
                  selected: active == section.key,
                  onSelected: (_) => setState(() => selected = section.key),
                ),
            ]),
            if (finance && widget.onOperation != null) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: widget.member.syncState == 'synced'
                      ? () => widget.onOperation!('subscribe', widget.member)
                      : null,
                  icon: const Icon(CupertinoIcons.add),
                  label: const Text('New membership'),
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      widget.onOperation!('whatsapp', widget.member),
                  icon: const Icon(CupertinoIcons.chat_bubble_text),
                  label: const Text('WhatsApp message'),
                ),
                OutlinedButton.icon(
                  onPressed: unpaid.isEmpty
                      ? null
                      : () => widget.onOperation!('pay_all', widget.member),
                  icon: const Icon(CupertinoIcons.checkmark_alt_circle),
                  label: const Text('Pay all invoices'),
                ),
                OutlinedButton.icon(
                  onPressed: unpaid.isEmpty
                      ? null
                      : () {
                          if (unpaid.length == 1) {
                            widget.onOperation!('pay', unpaid.single);
                          } else {
                            setState(() => selected = 'invoices');
                          }
                        },
                  icon: const Icon(CupertinoIcons.creditcard),
                  label: const Text('Pay invoice'),
                ),
              ]),
            ],
            const SizedBox(height: 12),
            if (records.isEmpty)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text('No ${sections[active]!.toLowerCase()} yet.')),
            for (final item in records)
              Builder(builder: (context) {
                final data = jsonDecode(item.payload) as Map<String, dynamic>;
                final amount = data['amount_minor'] ??
                    data['total_minor'] ??
                    (data['snapshot'] as Map?)?['amount_minor'];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_kindIcon(item.kind)),
                  title: Text(item.kind == 'subscriptions'
                      ? widget.labels.package(data)
                      : item.kind == 'receipts'
                          ? 'Receipt #${data['receipt_number'] ?? ''}'
                          : _kindName(item.kind)),
                  subtitle: Text([
                    displayDate(data['start_date'] ??
                        data['created_at'] ??
                        data['due_date']),
                    if (finance && amount is int)
                      Money.format(
                          amount, data['currency'] as String? ?? 'AED'),
                  ].where((s) => s.isNotEmpty).join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (data['status'] != null)
                      StatusBadge(item.kind == 'subscriptions'
                          ? MembershipStatus(data).status
                          : data['status'].toString()),
                    const Icon(CupertinoIcons.chevron_right),
                  ]),
                  onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => RecordDetailsPanel(
                          record: item,
                          repository: widget.repository,
                          onOperation: widget.onOperation)),
                );
              }),
          ],
        ));
  }
}

class _RecordOperations extends StatelessWidget {
  const _RecordOperations(
      {required this.record,
      required this.onOperation,
      required this.access,
      this.hasPaymentHistory = false});
  final GymAccess access;
  final bool hasPaymentHistory;
  final CachedRecord record;
  final void Function(String, CachedRecord) onOperation;
  @override
  Widget build(BuildContext context) {
    if (record.kind == 'subscriptions') {
      return Padding(
          padding: const EdgeInsets.only(top: 16),
          child: MembershipActions(
              record: record,
              access: access,
              onAction: onOperation,
              hasPaymentHistory: hasPaymentHistory));
    }
    final data = jsonDecode(record.payload) as Map<String, dynamic>;
    final balance = (data['total_minor'] as int? ?? 0) -
        (data['paid_minor'] as int? ?? 0) -
        (data['credit_minor'] as int? ?? 0);
    final actions = <(String, String, IconData)>[
      if (record.kind == 'invoices')
        ('invoice', 'View / print invoice', CupertinoIcons.doc_text),
      if (record.kind == 'invoices' &&
          balance > 0 &&
          !['void', 'voided'].contains(data['status']))
        ('pay', 'Record payment', CupertinoIcons.creditcard),
      if (record.kind == 'receipts')
        ('receipt', 'Open receipt & print', CupertinoIcons.printer),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (action, label, icon) in actions)
            OutlinedButton.icon(
                onPressed: record.syncState == 'synced'
                    ? () => onOperation(action, record)
                    : null,
                icon: Icon(icon),
                label: Text(label)),
        ]));
  }
}

class _DetailValue {
  const _DetailValue(this.label, this.value, this.icon);
  final String label, value;
  final IconData icon;
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.values});
  final List<_DetailValue> values;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, box) => Wrap(spacing: 24, runSpacing: 24, children: [
            for (final item in values)
              SizedBox(
                  width: box.maxWidth >= 500
                      ? (box.maxWidth - 24) / 2
                      : box.maxWidth,
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.icon,
                            size: 21,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(item.label,
                                  style: Theme.of(context).textTheme.bodySmall),
                              const SizedBox(height: 4),
                              SelectableText(item.value,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                            ])),
                      ])),
          ]));
}

class _DetailSection extends StatelessWidget {
  const _DetailSection(
      {required this.title, required this.child, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!,
                          style: Theme.of(context).textTheme.bodySmall)
                    ],
                    const SizedBox(height: 22),
                    child,
                  ]))));
}
