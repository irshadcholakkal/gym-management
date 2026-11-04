import 'dart:convert';

import 'package:flutter/material.dart';
import '../features/members/member_photos.dart';
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
      this.actions = const []});
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
                icon: const Icon(Icons.close_rounded)),
          ])),
      const Divider(height: 1),
      Expanded(
          child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: RecordDetails(
                  record: record, repository: repository, photos: photos))),
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
                      children: actions)),
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
      'members' || 'employees' => Icons.person_outline_rounded,
      'membership_packages' => Icons.inventory_2_outlined,
      'subscriptions' => Icons.calendar_month_outlined,
      'payments' || 'invoices' => Icons.account_balance_wallet_outlined,
      _ => Icons.receipt_long_outlined,
    };

class RecordDetails extends StatelessWidget {
  const RecordDetails(
      {super.key, required this.record, required this.repository, this.photos});
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
            ('phone', 'Phone number', Icons.phone_outlined),
            ('email', 'Email address', Icons.mail_outline_rounded),
            ('address', 'Address', Icons.location_on_outlined),
            ('occupation', 'Occupation', Icons.work_outline_rounded),
          ]);
          final information = fields([
            ('member_number', 'Member number', Icons.badge_outlined),
            ('employee_number', 'Employee number', Icons.badge_outlined),
            ('username', 'Username', Icons.alternate_email_rounded),
            ('access_role', 'Access role', Icons.admin_panel_settings_outlined),
            ('joining_date', 'Member since', Icons.calendar_today_outlined),
            ('start_date', 'Membership starts', Icons.event_available_outlined),
            ('due_date', 'Payment due', Icons.event_outlined),
            ('created_at', 'Created on', Icons.calendar_today_outlined),
            ('receipt_number', 'Receipt number', Icons.receipt_long_outlined),
            ('reference', 'Reference', Icons.tag_outlined),
            ('method', 'Payment method', Icons.credit_card_outlined),
            ('read_at', 'Read on', Icons.mark_email_read_outlined),
          ]);
          final finalDay =
              DateTime.tryParse(m['end_exclusive']?.toString() ?? '');
          if (finalDay != null) {
            information.add(_DetailValue(
                'Final valid membership day',
                displayDate(finalDay.subtract(const Duration(days: 1))),
                Icons.event_available_outlined));
          }
          final packageDetails = <_DetailValue>[
            if (m['duration_value'] != null)
              _DetailValue(
                  'Membership duration',
                  '${m['duration_value']} ${displayLabel(m['duration_unit']?.toString() ?? 'days').toLowerCase()}',
                  Icons.date_range_outlined),
            if (m['allowed_pause_days'] != null)
              _DetailValue('Pause allowance', '${m['allowed_pause_days']} days',
                  Icons.pause_circle_outline_rounded),
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
                    Icons.payments_outlined),
            if (current.kind == 'invoices' && m['total_minor'] is int)
              _DetailValue(
                  'Balance due',
                  Money.format(
                      (m['total_minor'] as int) -
                          (m['paid_minor'] as int? ?? 0) -
                          (m['credit_minor'] as int? ?? 0),
                      currency),
                  Icons.account_balance_wallet_outlined),
          ];
          final related = records.where((r) {
            if (!['subscriptions', 'payments', 'invoices', 'receipts']
                .contains(r.kind)) {
              return false;
            }
            if (!repository.access.finances && r.kind != 'subscriptions') {
              return false;
            }
            final data = jsonDecode(r.payload) as Map;
            return data['member_id'] == current.id ||
                (r.kind == 'receipts' &&
                    m['member_number'] != null &&
                    (data['snapshot'] as Map?)?['member_number'] ==
                        m['member_number']);
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
                                  if (status != null)
                                    Chip(
                                        avatar: Icon(Icons.circle,
                                            size: 8, color: scheme.primary),
                                        label: Text(displayLabel(status))),
                                  Chip(
                                      avatar: Icon(
                                          current.syncState == 'synced'
                                              ? Icons.cloud_done_outlined
                                              : Icons.cloud_upload_outlined,
                                          size: 16),
                                      label: Text(current.syncState == 'synced'
                                          ? 'Up to date'
                                          : displayLabel(current.syncState))),
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
                  if (member && photos != null)
                    _DetailSection(
                        title: 'Profile photo',
                        subtitle: 'A familiar face for your front desk.',
                        child: MemberPhotoEditor(
                            photos: photos!, member: current)),
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
                              Icons.person_outline_rounded),
                          _DetailValue('Package', labels.package(m),
                              Icons.inventory_2_outlined),
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
                  if (member)
                    _DetailSection(
                        title: 'Membership & payment history',
                        subtitle:
                            '${related.length} linked ${related.length == 1 ? 'record' : 'records'}',
                        child: Column(children: [
                          if (related.isEmpty)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                child: Column(children: [
                                  Icon(Icons.history_rounded,
                                      size: 32, color: scheme.onSurfaceVariant),
                                  const SizedBox(height: 12),
                                  const Text(
                                      'No membership or payment activity yet.',
                                      textAlign: TextAlign.center),
                                ])),
                          for (var i = 0; i < related.length; i++) ...[
                            if (i > 0) const Divider(height: 24),
                            Builder(builder: (context) {
                              final item = related[i];
                              final data = jsonDecode(item.payload)
                                  as Map<String, dynamic>;
                              return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                            color: scheme.secondaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(14)),
                                        child: Icon(_kindIcon(item.kind),
                                            color: scheme.primary, size: 20)),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(
                                              item.kind == 'subscriptions'
                                                  ? labels.package(data)
                                                  : _kindName(item.kind),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium),
                                          Text(
                                              [
                                                displayDate(
                                                    data['start_date'] ??
                                                        data['created_at']),
                                                if (data['status'] != null)
                                                  displayLabel(
                                                      data['status'].toString())
                                              ]
                                                  .where((s) => s.isNotEmpty)
                                                  .join(' · '),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall),
                                          if (repository.access.finances &&
                                              data['total_minor'] is int)
                                            Text(
                                                Money.format(
                                                    data['total_minor'] as int,
                                                    data['currency']
                                                            as String? ??
                                                        'AED'),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium),
                                        ])),
                                  ]);
                            }),
                          ],
                        ])),
                ]),
          );
        },
      );
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
