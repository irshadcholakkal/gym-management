import 'package:flutter/cupertino.dart' show CupertinoIcons;
import '../features/notifications/push_notification_controls.dart';
import '../features/receipts/presentation/receipt_design_editor.dart';
import '../features/receipts/presentation/receipt_preview.dart';
import '../features/receipts/data/receipt_design_repository.dart';
import '../features/receipts/domain/receipt_html.dart';
import '../features/employees/employee_access.dart';
import '../features/install/install_app_card.dart';
import 'dart:async';
import 'dart:convert';

import '../features/notifications/notification_center.dart';
import '../features/subscriptions/domain/membership_status.dart';
import '../features/subscriptions/membership_whatsapp.dart';

import '../features/members/member_photos.dart';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/domain/access.dart';
import '../features/auth/presentation/session_cubit.dart';
import '../features/payments/domain/money.dart';
import '../features/dashboard/presentation/collection_chart.dart';
import '../features/subscriptions/data/operations_repository.dart';
import '../features/notifications/data/push_client.dart';
import '../features/receipts/domain/receipt_pdf.dart';

import 'package:printing/printing.dart';

import 'operation_dialogs.dart';
import 'admin_actions.dart';
import 'record_details.dart';
import 'record_labels.dart';
import 'directory_index.dart';
import 'directory_filters.dart';
import '../features/payments/domain/discount_totals.dart';
import 'database/database.dart';
import 'sync/sync_engine.dart';
import 'sync/durable_operations.dart';
import 'sync/workspace_repository.dart';
import 'theme.dart';

const destinations = <(String, String, IconData)>[
  ('/', 'Overview', CupertinoIcons.square_grid_2x2),
  ('/members', 'Members', CupertinoIcons.person_2),
  ('/packages', 'Packages', CupertinoIcons.cube_box),
  ('/subscriptions', 'Memberships', CupertinoIcons.calendar),
  ('/payments', 'Payments', CupertinoIcons.creditcard),
  ('/receipts', 'Receipts', CupertinoIcons.doc_text),
  ('/employees', 'Team', CupertinoIcons.person_crop_rectangle),
  ('/notifications', 'Notifications', CupertinoIcons.bell),
  ('/sync', 'Sync center', CupertinoIcons.cloud),
  ('/settings', 'Settings', CupertinoIcons.slider_horizontal_3),
];

class Workspace extends StatefulWidget {
  const Workspace({
    super.key,
    required this.access,
    required this.client,
    required this.session,
    required this.path,
    required this.child,
  });
  final GymAccess access;
  final SupabaseClient client;
  final SessionCubit session;
  final String path;
  final Widget child;
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> with WidgetsBindingObserver {
  late final GymDatabase db;
  late final WorkspaceRepository repository;
  late final SyncEngine sync;
  bool collapsed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    db = GymDatabase();
    repository = WorkspaceRepository(db, widget.access);
    sync = SyncEngine(
      repository,
      widget.client,
      onAccessDenied: widget.session.restore,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync.sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(sync.close().then((_) => db.close()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available =
        destinations.where((d) => widget.access.allows(d.$1)).toList();
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final title =
        destinations.where((d) => d.$1 == widget.path).firstOrNull?.$2 ??
            'Overview';
    final navigation = AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: collapsed ? 88 : 244,
      decoration: BoxDecoration(
          border: Border(
              right: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant))),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 22, vertical: 30),
              child: Row(
                children: [
                  Icon(
                    Icons.fitness_center_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    size: 28,
                  ),
                  if (!collapsed) ...[
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'GymPro',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!collapsed)
              Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 14),
                child: Text(
                  'WORKSPACE',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final d in available)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3,
                      ),
                      child: ListTile(
                        selected: widget.path == d.$1,
                        selectedTileColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        selectedColor:
                            Theme.of(context).colorScheme.onPrimaryContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        leading: Icon(d.$3),
                        title: collapsed
                            ? null
                            : Text(
                                d.$2,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                        onTap: () {
                          context.go(d.$1);
                          if (!wide) Navigator.of(context).pop();
                        },
                      ),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(Icons.logout),
              title: collapsed ? null : Text('Sign out'),
              onTap: () async {
                try {
                  await widget.session.signOut();
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Unable to sign out. Try again.'),
                      ),
                    );
                  }
                }
              },
            ),
            SizedBox(height: 12),
          ],
        ),
      ),
    );
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider.value(value: repository),
        RepositoryProvider<SupabaseClient>.value(value: widget.client),
        RepositoryProvider<MemberPhotos>(
          create: (_) => MemberPhotos(widget.client, repository),
        ),
      ],
      child: RepositoryProvider<OperationsRepository>(
        create: (_) => DurableOperations(
          SupabaseOperationsRepository(widget.client, widget.access.gymId),
          repository,
        ),
        child: BlocProvider.value(
          value: sync,
          child: Scaffold(
            drawer: wide
                ? null
                : Drawer(
                    child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: navigation)),
            body: Row(
              children: [
                if (wide)
                  Material(
                      color: Theme.of(context).colorScheme.surface,
                      child: navigation),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        color: Theme.of(context).colorScheme.surface,
                        padding: EdgeInsets.symmetric(
                          horizontal: wide ? 20 : 8,
                          vertical: wide ? 14 : 4,
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: Row(
                            children: [
                              if (wide)
                                IconButton(
                                  tooltip: 'Toggle sidebar',
                                  onPressed: () =>
                                      setState(() => collapsed = !collapsed),
                                  icon: Icon(Icons.menu_open),
                                )
                              else
                                Builder(
                                  builder: (c) => IconButton(
                                    tooltip: 'Open navigation',
                                    onPressed: () =>
                                        Scaffold.of(c).openDrawer(),
                                    icon: Icon(Icons.menu),
                                  ),
                                ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  wide ? widget.access.gymName : title,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const ThemeSwitcher(),
                              WorkspaceSyncAction(
                                  repository: repository, sync: sync),
                              NotificationBell(),
                              SizedBox(width: wide ? 12 : 4),
                              CircleAvatar(
                                radius: wide ? 20 : 16,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .secondaryContainer,
                                child: Text(
                                  widget.access.name
                                      .substring(0, 1)
                                      .toUpperCase(),
                                ),
                              ),
                              if (wide)
                                Padding(
                                  padding: EdgeInsets.only(left: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.access.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        widget.access.role.name,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: wide
                            ? Padding(
                                padding: EdgeInsets.all(wide ? 32 : 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title == 'Overview'
                                          ? 'Welcome to your workspace'
                                          : title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineLarge,
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      title == 'Overview'
                                          ? 'Your people, your progress, all in one place.'
                                          : 'Manage your ${title.toLowerCase()} in one place.',
                                      style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                    SizedBox(height: 24),
                                    Expanded(
                                        child: PageEntrance(
                                            key: ValueKey(widget.path),
                                            child: widget.child)),
                                  ],
                                ),
                              )
                            : SafeArea(
                                top: false,
                                bottom: false,
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
                                  child: PageEntrance(
                                      key: ValueKey(widget.path),
                                      child: widget.child),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: widget.path == '/members'
                        ? 1
                        : widget.path == '/subscriptions'
                            ? 2
                            : 0,
                    onDestinationSelected: (i) =>
                        context.go(['/', '/members', '/subscriptions'][i]),
                    destinations: [
                      NavigationDestination(
                        icon: Icon(CupertinoIcons.square_grid_2x2),
                        label: 'Overview',
                      ),
                      NavigationDestination(
                        icon: Icon(CupertinoIcons.person_2),
                        label: 'Members',
                      ),
                      NavigationDestination(
                        icon: Icon(CupertinoIcons.calendar),
                        label: 'Memberships',
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Keeps synchronization available without taking a row from the content viewport.
class WorkspaceSyncAction extends StatelessWidget {
  const WorkspaceSyncAction(
      {super.key, required this.repository, required this.sync});
  final WorkspaceRepository repository;
  final SyncEngine sync;

  @override
  Widget build(BuildContext context) => BlocBuilder<SyncEngine, SyncStatus>(
        bloc: sync,
        builder: (context, status) => StreamBuilder<List<SyncOperation>>(
          stream: repository.watchOutbox(),
          builder: (context, snapshot) {
            final pending = snapshot.data?.length ?? 0;
            final message = status.error ??
                (status.running
                    ? 'Synchronizing workspace?'
                    : pending > 0
                        ? '$pending changes awaiting confirmation'
                        : 'Workspace synchronized');
            return PopupMenuButton<String>(
              tooltip: 'Sync workspace',
              onSelected: (value) {
                if (value == 'sync') unawaited(sync.sync());
                if (value == 'center') context.go('/sync');
              },
              icon: Badge(
                isLabelVisible: pending > 0 || status.error != null,
                label: Text(status.error != null ? '!' : '$pending'),
                child: status.running
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(
                        status.error != null
                            ? Icons.cloud_off_outlined
                            : Icons.cloud_done_outlined,
                        color: status.error != null
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary),
              ),
              itemBuilder: (_) => [
                PopupMenuItem<String>(enabled: false, child: Text(message)),
                PopupMenuItem<String>(
                    value: 'sync',
                    enabled: !status.running,
                    child: Text('Sync now')),
                PopupMenuItem<String>(
                    value: 'center', child: Text('Open sync center')),
              ],
            );
          },
        ),
      );
}

class WorkspaceContent extends StatelessWidget {
  const WorkspaceContent({
    super.key,
    required this.path,
    this.queryParameters = const {},
  });
  final String path;
  final Map<String, String> queryParameters;
  @override
  Widget build(BuildContext context) {
    if (path == '/') return const Dashboard();
    if (path == '/sync') return const SyncCenter();
    if (path == '/settings') return const SettingsPanel();
    if (path == '/notifications') {
      return NotificationCenter(queryParameters: queryParameters);
    }
    final kind = {
      '/members': 'members',
      '/packages': 'membership_packages',
      '/subscriptions': 'subscriptions',
      '/payments': 'invoices',
      '/receipts': 'receipts',
      '/employees': 'employees',
      '/notifications': 'notifications',
    }[path]!;
    return RecordDirectory(
      kind: kind,
      photos: context.read<MemberPhotos>(),
      // Read the route builder's state rather than looking up a departing
      // page's removed registry entry during a ShellRoute transition.
      initialFilter: queryParameters['filter'] ?? 'all',
    );
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  static String destination(String label) => switch (label) {
        'Registered members' => '/members',
        'Active memberships' => '/subscriptions?filter=active',
        'Paused memberships' => '/subscriptions?filter=paused',
        'Expired memberships' => '/subscriptions?filter=expired',
        'Expiring within 7 days' => '/subscriptions?filter=expiring_soon',
        _ => '/payments',
      };
  @override
  Widget build(BuildContext context) {
    final repo = context.read<WorkspaceRepository>();
    final compact = MediaQuery.sizeOf(context).width < 600;
    return StreamBuilder<List<CachedRecord>>(
      stream: repo.watchKinds(const [
        'members',
        'subscriptions',
        'invoices',
        'payments',
        'payment_reversals'
      ]),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text(
            'Local storage is unavailable. Enable browser storage and reload.',
          );
        }
        final all = snapshot.data ?? [];
        final members = all.where((r) => r.kind == 'members').toList();
        final subscriptions = all
            .where((r) => r.kind == 'subscriptions')
            .map((r) => jsonDecode(r.payload) as Map)
            .toList();
        final invoices = all
            .where((r) => r.kind == 'invoices')
            .map((r) => jsonDecode(r.payload) as Map)
            .toList();
        final balance = invoices.fold<int>(
          0,
          (sum, r) =>
              sum +
              ((r['total_minor'] as int? ?? 0) -
                  (r['paid_minor'] as int? ?? 0) -
                  (r['credit_minor'] as int? ?? 0)),
        );
        final today = DateTime.now().toUtc().add(Duration(hours: 4));
        final date = DateTime.utc(today.year, today.month, today.day);
        final reversed = all
            .where((r) => r.kind == 'payment_reversals')
            .map((r) => (jsonDecode(r.payload) as Map)['payment_id'])
            .toSet();
        final payments = all
            .where((r) => r.kind == 'payments' && !reversed.contains(r.id))
            .map((r) => jsonDecode(r.payload) as Map)
            .toList();
        int collected(bool month) => payments.where((p) {
              final d = DateTime.parse(p['created_at'] as String)
                  .toUtc()
                  .add(Duration(hours: 4));
              return d.year == today.year &&
                  d.month == today.month &&
                  (month || d.day == today.day);
            }).fold<int>(0, (sum, p) => sum + (p['amount_minor'] as int));
        final expiring = subscriptions
            .where(
              (s) =>
                  s['status'] == 'active' &&
                  DateTime.parse(s['end_exclusive'] as String)
                          .subtract(Duration(days: 1))
                          .difference(date)
                          .inDays >=
                      0 &&
                  DateTime.parse(s['end_exclusive'] as String)
                          .subtract(Duration(days: 1))
                          .difference(date)
                          .inDays <=
                      7,
            )
            .length;
        final overdue = invoices
            .where(
              (i) =>
                  i['status'] != 'voided' &&
                  DateTime.parse(i['due_date'] as String).isBefore(date),
            )
            .fold<int>(
              0,
              (sum, i) =>
                  sum +
                  (i['total_minor'] as int) -
                  (i['paid_minor'] as int) -
                  (i['credit_minor'] as int? ?? 0),
            );
        final metrics = <(String, String, IconData, Color)>[
          (
            'Registered members',
            '${members.length}',
            CupertinoIcons.person_2,
            Theme.of(context).colorScheme.secondaryContainer,
          ),
          (
            'Active memberships',
            '${subscriptions.where((r) => MembershipStatus(r).matchesFilter('active')).length}',
            Icons.verified_outlined,
            Theme.of(context).colorScheme.secondaryContainer,
          ),
          (
            'Paused memberships',
            '${subscriptions.where((r) => r['status'] == 'paused').length}',
            Icons.pause_circle_outline,
            Theme.of(context).colorScheme.secondaryContainer,
          ),
          if (repo.access.finances)
            (
              'Outstanding balance',
              Money.format(balance),
              CupertinoIcons.creditcard,
              Theme.of(context).colorScheme.secondaryContainer,
            ),
          (
            'Expired memberships',
            '${subscriptions.where((s) => MembershipStatus(s).matchesFilter('expired')).length}',
            Icons.event_busy,
            Theme.of(context).colorScheme.secondaryContainer,
          ),
          (
            'Expiring within 7 days',
            '$expiring',
            Icons.event_available,
            Theme.of(context).colorScheme.secondaryContainer,
          ),
          if (repo.access.finances) ...[
            (
              'Discounts given this month',
              Money.format(DiscountTotals.forMonth(invoices, today)),
              Icons.local_offer_outlined,
              Theme.of(context).colorScheme.secondaryContainer,
            ),
            (
              'Collected today',
              Money.format(collected(false)),
              Icons.payments_outlined,
              Theme.of(context).colorScheme.secondaryContainer,
            ),
            (
              'Collected this month',
              Money.format(collected(true)),
              Icons.trending_up,
              Theme.of(context).colorScheme.secondaryContainer,
            ),
            (
              'Overdue balance',
              Money.format(overdue),
              Icons.schedule,
              Theme.of(context).colorScheme.secondaryContainer,
            ),
          ],
        ];
        return ListView(
          children: [
            LayoutBuilder(
              builder: (context, box) => Wrap(
                spacing: compact ? 12 : 16,
                runSpacing: compact ? 12 : 16,
                children: [
                  for (final m in metrics)
                    SizedBox(
                      width: box.maxWidth < 600
                          ? (box.maxWidth - 12) / 2
                          : (box.maxWidth -
                                  16 * (box.maxWidth > 1200 ? 3 : 1)) /
                              (box.maxWidth > 1200 ? 4 : 2),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        color: m == metrics.first
                            ? Theme.of(context).colorScheme.secondaryContainer
                            : Theme.of(context).colorScheme.surface,
                        child: InkWell(
                            onTap: () => context.go(destination(m.$1)),
                            child: Padding(
                              padding: EdgeInsets.all(compact ? 12 : 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Expanded(
                                        child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Container(
                                              padding: EdgeInsets.all(
                                                  compact ? 8 : 12),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .secondaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                              ),
                                              child: Icon(m.$3,
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .primary,
                                                  size: compact ? 18 : 24),
                                            ))),
                                    Icon(Icons.arrow_outward_rounded,
                                        size: 18,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)
                                  ]),
                                  SizedBox(height: compact ? 12 : 20),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(m.$2,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall),
                                  ),
                                  SizedBox(height: 6),
                                  SizedBox(
                                      height: 38,
                                      child: Text(
                                        m.$1,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      )),
                                ],
                              ),
                            )),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 24),
            if (repo.access.finances) ...[
              CollectionChart(payments: payments, today: today),
              SizedBox(height: 24),
            ],
            Card(
              child: Padding(
                padding: EdgeInsets.all(compact ? 16 : 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Recent registrations',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => context.go('/members'),
                          child: Text('View all'),
                        ),
                      ],
                    ),
                    Divider(height: 32),
                    if (members.isEmpty)
                      const EmptyPanel(
                        icon: CupertinoIcons.person_2,
                        title: 'Your community starts here',
                        message:
                            'Add your first member to see registrations and membership activity.',
                      )
                    else
                      ...members.reversed.take(5).map((r) {
                        final m = jsonDecode(r.payload) as Map;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
                            child: Icon(Icons.person_outline),
                          ),
                          title: Text(m['full_name'] as String),
                          subtitle: Text(m['phone'] as String),
                          trailing: Chip(
                            label: Text(
                              r.syncState == 'synced'
                                  ? m['status'] as String? ?? 'active'
                                  : r.syncState,
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your next move',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Keep your members, memberships, and collections connected.',
                    ),
                    SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (repo.access.editMembers)
                          FilledButton.icon(
                            onPressed: () =>
                                showRecordEditor(context, 'members'),
                            icon: Icon(Icons.person_add_alt),
                            label: Text('Add member'),
                          ),
                        if (repo.access.administer)
                          OutlinedButton.icon(
                            onPressed: () => context.go('/packages'),
                            icon: Icon(CupertinoIcons.cube_box),
                            label: Text('Manage packages'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/sync'),
                          icon: Icon(CupertinoIcons.cloud),
                          label: Text('Review sync activity'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Unsynchronized changes are stored on this device. Clearing browser storage removes them. Sync resumes while the application is open.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(vertical: 40, horizontal: 16),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(icon,
                    size: 36, color: Theme.of(context).colorScheme.primary),
              ),
              SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
}

class RecordDirectory extends StatefulWidget {
  const RecordDirectory(
      {super.key, required this.kind, this.photos, this.initialFilter = 'all'});
  final MemberPhotos? photos;
  final String kind;
  final String initialFilter;
  @override
  State<RecordDirectory> createState() => _RecordDirectoryState();
}

class _RecordDirectoryState extends State<RecordDirectory> {
  String query = '', filter = 'all';
  int page = 0;
  Timer? _statusTimer, _searchTimer;
  Stream<DirectoryIndex>? _directoryStream;
  String? _directoryKey;
  Stream<DirectoryIndex> _watchDirectory(
      WorkspaceRepository repo, String kind, List<String> kinds) {
    final key = '${repo.scope}:${kinds.join(',')}';
    if (_directoryKey != key) {
      _directoryKey = key;
      _directoryStream = repo.watchKinds(kinds).asyncMap(DirectoryIndex.create);
    }
    return _directoryStream!;
  }

  @override
  void initState() {
    super.initState();
    filter = widget.initialFilter;
    _statusTimer = Timer.periodic(Duration(minutes: 1), (_) {
      if (mounted && widget.kind == 'subscriptions') setState(() {});
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _searchTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(RecordDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind ||
        oldWidget.initialFilter != widget.initialFilter) {
      _searchTimer?.cancel();
      query = '';
      filter = widget.initialFilter;
      page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<WorkspaceRepository>(), kind = widget.kind;
    final focusedRecord = GoRouter.maybeOf(context)
        ?.routeInformationProvider
        .value
        .uri
        .queryParameters['record'];
    final editable = kind == 'members' && repo.access.editMembers ||
        kind == 'membership_packages' && repo.access.administer;
    return Focus(
      skipTraversal: true,
      child: Column(
        children: [
          if (focusedRecord != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => context.go(GoRouter.of(context)
                    .routeInformationProvider
                    .value
                    .uri
                    .path),
                icon: Icon(Icons.arrow_back),
                label: Text('Show all records'),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey(kind),
                  autofocus: false,
                  onChanged: (value) {
                    _searchTimer?.cancel();
                    _searchTimer = Timer(Duration(milliseconds: 180), () {
                      if (!mounted) return;
                      setState(() {
                        query = value.toLowerCase();
                        page = 0;
                      });
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search records…',
                    prefixIcon: Icon(CupertinoIcons.search),
                  ),
                ),
              ),
              SizedBox(width: 4),
              PopupMenuButton<String>(
                tooltip: filter == 'all'
                    ? 'Filter records'
                    : 'Filter: ${displayLabel(filter)}',
                icon: Badge(
                    isLabelVisible: filter != 'all',
                    smallSize: 6,
                    child: Icon(Icons.filter_list_rounded,
                        color: filter == 'all'
                            ? null
                            : Theme.of(context).colorScheme.primary)),
                initialValue: filter,
                itemBuilder: (_) => [
                  for (final option in directoryFilters(kind))
                    CheckedPopupMenuItem<String>(
                      value: option.value,
                      checked: filter == option.value,
                      child: SizedBox(
                        width: 260,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(option.label),
                              Text(option.description,
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
                onSelected: (value) => setState(() {
                  filter = value;
                  page = 0;
                }),
              ),
              if (editable)
                IconButton.filled(
                  tooltip: kind == 'members' ? 'Add member' : 'Create package',
                  onPressed: () => showRecordEditor(context, kind),
                  icon: Icon(CupertinoIcons.add),
                ),
              if (kind == 'subscriptions' && repo.access.finances)
                IconButton.filled(
                  tooltip: 'Create membership',
                  onPressed: () => showServerOperation(context, 'subscribe'),
                  icon: Icon(CupertinoIcons.add),
                ),
              if (kind == 'employees' && repo.access.administer)
                IconButton.filled(
                  tooltip: 'Invite employee',
                  onPressed: () => showServerOperation(context, 'invite'),
                  icon: Icon(Icons.person_add_alt),
                ),
              if (kind == 'notifications')
                IconButton(
                  tooltip: 'Enable browser push',
                  onPressed: () async {
                    try {
                      final subscription = await subscribePush(
                        String.fromEnvironment('VAPID_PUBLIC_KEY'),
                      );
                      if (!context.mounted) return;
                      await context.read<OperationsRepository>().registerPush(
                            jsonDecode(subscription) as Map<String, dynamic>,
                          );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Browser push enabled for this workspace.',
                            ),
                          ),
                        );
                      }
                    } catch (_) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Push is unavailable, unconfigured, or permission was denied. In-app reminders remain available.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                  icon: Icon(Icons.notifications_active_outlined),
                ),
            ],
          ),
          SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<DirectoryIndex>(
              stream: _watchDirectory(repo, kind, [
                kind,
                if (['subscriptions', 'invoices', 'payments', 'receipts']
                    .contains(kind)) ...[
                  'members',
                  'membership_packages',
                  'subscriptions'
                ]
              ]),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(
                    'Unable to open local storage. Check browser storage permissions.',
                  );
                }
                if (!snapshot.hasData) {
                  return Center(child: CircularProgressIndicator());
                }
                final index = snapshot.data!;
                final labels = index.labels;
                final records = index.records
                    .where((r) =>
                        r.kind == kind &&
                        (focusedRecord != null
                            ? r.id == focusedRecord
                            : (query.isEmpty ||
                                    index.search['${r.kind}:${r.id}']!
                                        .contains(query)) &&
                                matchesDirectoryFilter(kind,
                                    labels.lookup(kind, r.id), r.syncState,
                                    filter)))
                    .toList();
                if (records.isEmpty) {
                  return Card(
                    child: EmptyPanel(
                      icon: Icons.folder_open_outlined,
                      title: filter != 'all' || query.isNotEmpty
                          ? 'No matching records' : 'No records yet',
                      message: filter != 'all' || query.isNotEmpty
                          ? 'Try another filter or search to find records.'
                          : editable
                          ? 'Create your first record. Changes appear immediately, even before sync.'
                          : 'Authorized records will appear here after synchronization.',
                    ),
                  );
                }
                final start = focusedRecord != null
                    ? 0
                    : (page * 15).clamp(0, records.length);
                return Card(
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          itemCount: records.skip(start).take(15).length,
                          separatorBuilder: (context, index) =>
                              Divider(height: 1),
                          itemBuilder: (context, i) {
                            final r = records[start + i],
                                m = labels.lookup(kind, r.id);
                            final membership = kind == 'subscriptions'
                                ? MembershipStatus(m)
                                : null;
                            final compact =
                                MediaQuery.sizeOf(context).width < 760;
                            final actions = <Widget>[
                              if (kind == 'employees' &&
                                  repo.access.administer &&
                                  m['access_role'] != 'owner')
                                IconButton(
                                    tooltip: 'Manage access',
                                    onPressed: () =>
                                        showEmployeeAccess(context, r),
                                    icon: Icon(
                                        Icons.admin_panel_settings_outlined)),
                              if (m['price_minor'] != null)
                                Text(
                                  Money.format(
                                    m['price_minor'] as int,
                                    m['currency'] as String? ?? 'AED',
                                  ),
                                ),
                              SizedBox(width: 8),
                              Chip(
                                backgroundColor: switch (membership?.status) {
                                  'expired' || 'cancelled' => Theme.of(context)
                                      .colorScheme
                                      .errorContainer,
                                  'paused' ||
                                  'expiring_soon' =>
                                    Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer,
                                  'active' => Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer,
                                  _ => null,
                                },
                                label: Text(
                                  displayLabel(
                                    membership?.status ??
                                        (m['status'] ?? 'active').toString(),
                                  ),
                                ),
                              ),
                              if (r.syncState != 'synced')
                                Chip(label: Text(displayLabel(r.syncState))),
                              if (membership != null && repo.access.finances)
                                IconButton(
                                  tooltip: 'WhatsApp message',
                                  icon: Icon(Icons.chat_outlined),
                                  onPressed: () => showMembershipWhatsApp(
                                    context,
                                    subscription: m,
                                    member: labels.lookup(
                                      'members',
                                      m['member_id'],
                                    ),
                                    package: labels.package(m),
                                    gym: repo.access.gymName,
                                  ),
                                ),
                              if (editable)
                                IconButton(
                                  tooltip: 'Edit record',
                                  onPressed: () => showRecordEditor(
                                      context, kind,
                                      record: r),
                                  icon: Icon(Icons.edit_outlined),
                                ),
                              if (kind == 'subscriptions' &&
                                  repo.access.finances)
                                IconButton(
                                  tooltip: m['status'] == 'paused'
                                      ? 'Resume before renewal'
                                      : 'Renew membership',
                                  onPressed: m['status'] == 'paused'
                                      ? null
                                      : () => showServerOperation(
                                            context,
                                            'subscribe',
                                            record: r,
                                          ),
                                  icon: Icon(Icons.autorenew),
                                ),
                              if (kind == 'subscriptions' &&
                                  repo.access.finances)
                                IconButton(
                                  tooltip: 'Manage membership',
                                  onPressed: () => showServerOperation(
                                    context,
                                    'transition',
                                    record: r,
                                  ),
                                  icon: Icon(CupertinoIcons.ellipsis),
                                ),
                              if (kind == 'invoices' &&
                                  repo.access.finances &&
                                  m['status'] != 'paid')
                                IconButton(
                                  tooltip: 'Record payment',
                                  onPressed: () => showServerOperation(
                                    context,
                                    'pay',
                                    record: r,
                                  ),
                                  icon: Icon(Icons.add_card),
                                ),
                              if (kind == 'subscriptions' &&
                                  repo.access.finances)
                                IconButton(
                                  tooltip: 'Change package',
                                  onPressed: () => showAdjustment(
                                    context,
                                    r,
                                    packageChange: true,
                                  ),
                                  icon: Icon(Icons.swap_horiz),
                                ),
                              if (kind == 'employees' &&
                                  repo.access.administer &&
                                  m['status'] == 'active')
                                IconButton(
                                  tooltip: 'Deactivate employee',
                                  onPressed: () => showAdjustment(
                                    context,
                                    r,
                                    deactivate: true,
                                  ),
                                  icon: Icon(Icons.person_off_outlined),
                                ),
                              if (kind == 'receipts')
                                IconButton(
                                  tooltip: 'Preview official receipt',
                                  onPressed: () async {
                                    try {
                                      final receipt = await context
                                          .read<OperationsRepository>()
                                          .receipt(r.id);
                                      if (!context.mounted) return;
                                      if (kIsWeb) {
                                        final design =
                                            await ReceiptDesignRepository(
                                                    context
                                                        .read<SupabaseClient>(),
                                                    repo.access.gymId)
                                                .load();
                                        await previewReceiptHtml(
                                            ReceiptHtml.render(
                                                design.html, receipt),
                                            'Receipt #${receipt['receipt_number']}');
                                        return;
                                      }
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => Scaffold(
                                            appBar: AppBar(
                                              title: Text(
                                                'Receipt #${receipt['receipt_number']}',
                                              ),
                                            ),
                                            body: PdfPreview(
                                              build: (_) =>
                                                  ReceiptPdf.build(receipt),
                                            ),
                                          ),
                                        ),
                                      );
                                    } catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Unable to verify receipt. Reconnect and try again.',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  icon: Icon(Icons.picture_as_pdf_outlined),
                                ),
                              if (kind == 'receipts' &&
                                  repo.access.administer &&
                                  m['status'] == 'issued')
                                IconButton(
                                  tooltip: 'Reverse payment',
                                  onPressed: () => showAdjustment(context, r),
                                  icon: Icon(Icons.undo),
                                ),
                              if (kind == 'notifications' &&
                                  m['read_at'] == null)
                                IconButton(
                                  tooltip: 'Mark read',
                                  onPressed: () async {
                                    try {
                                      await context
                                          .read<OperationsRepository>()
                                          .readNotification(r.id);
                                      if (context.mounted) {
                                        await context.read<SyncEngine>().sync();
                                      }
                                    } catch (_) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Unable to mark notification read. Retry when connected.',
                                            ),
                                          ),
                                        );
                                      }
                                    }
                                  },
                                  icon: Icon(Icons.done),
                                ),
                            ];
                            final tile = ListTile(
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: compact ? 12 : 20,
                                  vertical: compact ? 2 : 8),
                              leading:
                                  kind == 'members' && widget.photos != null
                                      ? MemberPhoto(
                                          photos: widget.photos!,
                                          path: m['profile_image'] as String?,
                                          size: compact ? 34 : 44,
                                        )
                                      : CircleAvatar(
                                          radius: compact ? 16 : 20,
                                          backgroundColor: Theme.of(context)
                                              .colorScheme
                                              .secondaryContainer,
                                          child: Icon(
                                            kind == 'members'
                                                ? Icons.person_outline
                                                : CupertinoIcons.cube_box,
                                          ),
                                        ),
                              title: Text(labels.title(kind, m)),
                              subtitle: Text(
                                [
                                  labels.subtitle(kind, m),
                                  if (kind == 'employees' &&
                                      m['employee_number'] != null)
                                    'EMP-${m['employee_number']} ? ${m['access_role'] ?? 'staff'}',
                                  if (kind == 'employees' &&
                                      m['username'] != null)
                                    'Username: ${m['username']}',
                                  if (membership != null &&
                                      membership.countdown.isNotEmpty)
                                    membership.countdown,
                                ].join('\n'),
                              ),
                              trailing: compact
                                  ? RecordActionsMenu(actions: actions)
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: actions,
                                    ),
                              onTap: () => showDialog<void>(
                                context: context,
                                builder: (_) => RecordDetailsPanel(
                                  photos: widget.photos,
                                  record: r,
                                  repository: repo,
                                  actions:
                                      actions.whereType<IconButton>().toList(),
                                ),
                              ),
                            );
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                tile,
                                if (compact &&
                                    actions.any((action) =>
                                        action is! IconButton &&
                                        action is! SizedBox))
                                  Padding(
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      0,
                                      16,
                                      12,
                                    ),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        for (final action in actions)
                                          if (action is! IconButton &&
                                              action is! SizedBox)
                                            action,
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      Divider(height: 1),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Expanded(
                              child: Text(
                                  '${records.length} records - Page ${page + 1}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.right,
                                  style:
                                      Theme.of(context).textTheme.bodySmall)),
                          IconButton(
                            tooltip: 'Previous page',
                            onPressed:
                                page == 0 ? null : () => setState(() => page--),
                            icon: Icon(CupertinoIcons.chevron_left),
                          ),
                          IconButton(
                            tooltip: 'Next page',
                            onPressed: start + 15 >= records.length
                                ? null
                                : () => setState(() => page++),
                            icon: Icon(CupertinoIcons.chevron_right),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showRecordEditor(
  BuildContext context,
  String kind, {
  CachedRecord? record,
}) async {
  final repo = context.read<WorkspaceRepository>();
  final data = record == null
      ? <String, dynamic>{}
      : jsonDecode(record.payload) as Map<String, dynamic>;
  final member = kind == 'members', form = GlobalKey<FormState>();
  final fields = member
      ? ['full_name', 'phone', 'email', 'occupation', 'address', 'notes']
      : [
          'name',
          'description',
          'duration_value',
          'price',
          'allowed_pause_days',
        ];
  final controllers = {
    for (final f in fields)
      f: TextEditingController(
        text: f == 'price'
            ? ((data['price_minor'] as int? ?? 0) / 100).toStringAsFixed(2)
            : (data[f] ??
                    (f == 'duration_value'
                        ? '1'
                        : f == 'allowed_pause_days'
                            ? '0'
                            : ''))
                .toString(),
      ),
  };
  var status = data['status'] as String? ?? 'active',
      unit = data['duration_unit'] as String? ?? 'months';
  var busy = false;
  String? error;
  final route = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        actionsOverflowButtonSpacing: 8,
        title: Text(
          '${record == null ? 'Create' : 'Edit'} ${member ? 'member' : 'package'}',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final f in fields)
                    Padding(
                      padding: EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: controllers[f],
                        decoration: InputDecoration(
                          prefixIcon: Icon(switch (f) {
                            'full_name' => Icons.person_outline_rounded,
                            'phone' => Icons.phone_outlined,
                            'email' => Icons.mail_outline_rounded,
                            'occupation' => Icons.work_outline_rounded,
                            'address' => Icons.location_on_outlined,
                            'price' => Icons.payments_outlined,
                            'duration_value' => Icons.date_range_outlined,
                            'allowed_pause_days' => Icons.pause_circle_outline,
                            'notes' || 'description' => Icons.notes_outlined,
                            _ => Icons.inventory_2_outlined,
                          }),
                          labelText: {
                                'full_name': 'Full name',
                                'phone': 'Phone number',
                                'email': 'Email address',
                                'name': 'Package name',
                                'duration_value': 'Duration',
                                'price': 'Price (AED)',
                                'allowed_pause_days': 'Allowed pause days',
                              }[f] ??
                              displayLabel(f),
                        ),
                        maxLines: f == 'notes' || f == 'description' ? 3 : 1,
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if ([
                                'full_name',
                                'name',
                                'phone',
                                'duration_value',
                                'price',
                                'allowed_pause_days',
                              ].contains(f) &&
                              s.isEmpty) {
                            return 'This field is required';
                          }
                          if (f == 'phone' &&
                              !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(
                                s.replaceAll(RegExp(r'[\s()-]'), ''),
                              )) {
                            return 'Use international format, e.g. +971501234567';
                          }
                          if (f == 'email' &&
                              s.isNotEmpty &&
                              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(s)) {
                            return 'Enter a valid email';
                          }
                          if (f == 'price') {
                            try {
                              Money.parse(s);
                            } catch (_) {
                              return 'Use an amount with up to two decimal places';
                            }
                          }
                          if (f == 'duration_value' &&
                              (int.tryParse(s) ?? 0) < 1) {
                            return 'Enter a positive whole number';
                          }
                          if (f == 'allowed_pause_days' &&
                              (int.tryParse(s) ?? -1) < 0) {
                            return 'Enter zero or a positive whole number';
                          }
                          return null;
                        },
                      ),
                    ),
                  if (!member)
                    DropdownButtonFormField<String>(
                      initialValue: unit,
                      decoration: InputDecoration(
                          labelText: 'Duration unit',
                          prefixIcon: const Icon(Icons.date_range_outlined)),
                      items: [
                        for (final u in ['days', 'weeks', 'months', 'years'])
                          DropdownMenuItem(
                            value: u,
                            child: Text(displayLabel(u)),
                          ),
                      ],
                      onChanged: (v) => unit = v!,
                    ),
                  SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: InputDecoration(
                        labelText: 'Status',
                        prefixIcon: const Icon(Icons.verified_outlined)),
                    items: [
                      for (final s in ['active', 'inactive', 'archived'])
                        DropdownMenuItem(
                          value: s,
                          child: Text(displayLabel(s)),
                        ),
                    ],
                    onChanged: (v) => status = v!,
                  ),
                  if (error != null)
                    Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
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
            child: Text('Cancel'),
          ),
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
                      final values = <String, dynamic>{
                        for (final e in controllers.entries)
                          e.key: e.value.text.trim(),
                        'status': status,
                      };
                      if (member) {
                        values['email'] =
                            (values['email'] as String).toLowerCase();
                        values['phone'] = (values['phone'] as String)
                            .replaceAll(RegExp(r'[\s()-]'), '');
                        values['joining_date'] = data['joining_date'] ??
                            DateTime.now()
                                .toUtc()
                                .add(Duration(hours: 4))
                                .toIso8601String()
                                .substring(0, 10);
                      } else {
                        values['price_minor'] = Money.parse(
                          values.remove('price') as String,
                        );
                        values['currency'] = 'AED';
                        values['duration_unit'] = unit;
                        values['duration_value'] = int.parse(
                          values['duration_value'] as String,
                        );
                        values['allowed_pause_days'] = int.parse(
                          values['allowed_pause_days'] as String,
                        );
                      }
                      await repo.save(
                        kind,
                        values,
                        id: record?.id,
                        version: record?.version ?? 0,
                      );
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } catch (e) {
                      update(() {
                        error = e.toString();
                        busy = false;
                      });
                    }
                  },
            child: Text(
              busy
                  ? 'Saving…'
                  : member
                      ? 'Save member'
                      : 'Save package',
            ),
          ),
        ],
      ),
    ),
  );
  await Navigator.of(context, rootNavigator: true).push(route);
  await route.completed;
  for (final c in controllers.values) {
    c.dispose();
  }
}

class RecordActionsMenu extends StatelessWidget {
  const RecordActionsMenu({super.key, required this.actions});
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final buttons = actions.whereType<IconButton>().toList();
    if (buttons.isEmpty) return SizedBox.shrink();
    return PopupMenuButton<int>(
      tooltip: 'Record actions',
      icon: Icon(CupertinoIcons.ellipsis, size: 20),
      onSelected: (index) => buttons[index].onPressed?.call(),
      itemBuilder: (_) => [
        for (var i = 0; i < buttons.length; i++)
          PopupMenuItem(
              value: i,
              enabled: buttons[i].onPressed != null,
              child: Row(children: [
                buttons[i].icon,
                SizedBox(width: 12),
                Flexible(child: Text(buttons[i].tooltip ?? 'Open'))
              ]))
      ],
    );
  }
}

class SyncCenter extends StatelessWidget {
  const SyncCenter({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = context.read<WorkspaceRepository>();
    return StreamBuilder<List<SyncOperation>>(
      stream: repo.watchOutbox(),
      builder: (context, snapshot) {
        final ops = snapshot.data ?? [];
        if (ops.isEmpty) {
          return Card(
            child: EmptyPanel(
              icon: Icons.cloud_done_outlined,
              title: 'All caught up',
              message: 'There are no unconfirmed changes on this device.',
            ),
          );
        }
        return ListView(
          children: [
            Text(
              'Conflicts retain your local change. Review the server version before discarding it. Financial changes always require server authorization.',
            ),
            SizedBox(height: 16),
            for (final op in ops)
              Card(
                child: ListTile(
                  title: Text('${op.kind} · ${op.state}'),
                  subtitle: Text(op.error ?? 'Awaiting server confirmation'),
                  trailing: op.state == 'confirmation'
                      ? TextButton(
                          onPressed: () async {
                            try {
                              final confirmed = await context
                                  .read<OperationsRepository>()
                                  .isConfirmed(op.id);
                              if (confirmed) {
                                await (repo.db.delete(repo.db.syncOperations)
                                      ..where(
                                        (o) =>
                                            o.scope.equals(repo.scope) &
                                            o.id.equals(op.id),
                                      ))
                                    .go();
                                await (repo.db.delete(
                                  repo.db.syncCheckpoints,
                                )..where((c) => c.scope.equals(repo.scope)))
                                    .go();
                                if (context.mounted) {
                                  await context.read<SyncEngine>().sync();
                                }
                              } else if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Awaiting confirmation. Reopen the original form and retry these same details: ${op.payload}',
                                    ),
                                  ),
                                );
                              }
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Cannot confirm this operation while disconnected.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          child: Text('Check confirmation'),
                        )
                      : op.state == 'conflict' || op.state == 'approval'
                          ? TextButton(
                              onPressed: () async {
                                final discard = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    titlePadding: const EdgeInsets.fromLTRB(
                                        24, 24, 24, 16),
                                    contentPadding: const EdgeInsets.fromLTRB(
                                        24, 0, 24, 20),
                                    actionsPadding: const EdgeInsets.fromLTRB(
                                        24, 0, 24, 20),
                                    actionsOverflowButtonSpacing: 8,
                                    title: Text('Discard local change?'),
                                    content: SingleChildScrollView(
                                      child: SelectableText(
                                        'Local change:\n${op.payload}\n\nThe server record will be fetched again. This discards only the uncommitted local operation.',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text('Keep local change'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(
                                          'Discard and fetch server',
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (discard != true) return;
                                await repo.db.transaction(() async {
                                  await (repo.db.delete(repo.db.syncOperations)
                                        ..where(
                                          (o) =>
                                              o.id.equals(op.id) &
                                              o.scope.equals(repo.scope),
                                        ))
                                      .go();
                                  await (repo.db.delete(repo.db.cachedRecords)
                                        ..where(
                                          (r) =>
                                              r.scope.equals(repo.scope) &
                                              r.id.equals(op.recordId) &
                                              r.kind.equals(op.kind),
                                        ))
                                      .go();
                                  await (repo.db.delete(
                                    repo.db.syncCheckpoints,
                                  )..where((c) => c.scope.equals(repo.scope)))
                                      .go();
                                });
                                if (context.mounted) {
                                  await context.read<SyncEngine>().sync();
                                }
                              },
                              child: Text('Resolve'),
                            )
                          : TextButton(
                              onPressed: () => repo.retry(op.id),
                              child: Text('Retry'),
                            ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class SettingsPanel extends StatelessWidget {
  const SettingsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final access = context.read<WorkspaceRepository>().access;
    return ListView(
      children: [
        ReceiptDesignCard(),
        SizedBox(height: 16),
        PushNotificationSettingsCard(),
        SizedBox(height: 16),
        InstallAppCard(),
        SizedBox(height: 20),
        Card(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  access.gymName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                SizedBox(height: 20),
                ListTile(
                  leading: Icon(Icons.payments_outlined),
                  title: Text('Default currency'),
                  subtitle: Text('AED · stored as integer fils'),
                ),
                ListTile(
                  leading: Icon(Icons.schedule),
                  title: Text('Default timezone'),
                  subtitle: Text(
                    'Asia/Dubai · membership boundaries use calendar dates',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.security),
                  title: Text('Offline security'),
                  subtitle: Text(
                    'A live server authorization is required to unlock a workspace. Cached data is isolated by gym and user.',
                  ),
                ),
                Text('Workspace: ${access.gymName}'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
