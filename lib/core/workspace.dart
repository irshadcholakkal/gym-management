import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
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
import 'database/database.dart';
import 'sync/sync_engine.dart';
import 'sync/durable_operations.dart';
import 'sync/workspace_repository.dart';
import 'theme.dart';

const destinations = <(String, String, IconData)>[
  ('/', 'Overview', Icons.space_dashboard_outlined),
  ('/members', 'Members', Icons.people_outline_rounded),
  ('/packages', 'Packages', Icons.inventory_2_outlined),
  ('/subscriptions', 'Memberships', Icons.event_repeat_rounded),
  ('/payments', 'Payments', Icons.account_balance_wallet_outlined),
  ('/receipts', 'Receipts', Icons.receipt_long_outlined),
  ('/employees', 'Team', Icons.badge_outlined),
  ('/notifications', 'Notifications', Icons.notifications_none_rounded),
  ('/sync', 'Sync center', Icons.cloud_sync_outlined),
  ('/settings', 'Settings', Icons.tune_rounded),
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
    final available = destinations
        .where((d) => widget.access.allows(d.$1))
        .toList();
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final title =
        destinations.where((d) => d.$1 == widget.path).firstOrNull?.$2 ??
        'Overview';
    final navigation = Container(
      width: collapsed ? 88 : 244,
      color: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
              child: Row(
                children: [
                  const Icon(
                    Icons.fitness_center_rounded,
                    color: GymTheme.sage,
                    size: 28,
                  ),
                  if (!collapsed) ...[
                    const SizedBox(width: 12),
                    const Expanded(
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
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, 14),
                child: Text(
                  'WORKSPACE',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2,
                    color: Color(0xFF708079),
                  ),
                ),
              ),
            Expanded(
              child: ListView(
                children: [
                  for (final d in available)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 3,
                      ),
                      child: ListTile(
                        selected: widget.path == d.$1,
                        selectedTileColor: const Color(0xFFE7F2EB),
                        selectedColor: GymTheme.sage,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        leading: Icon(d.$3),
                        title: collapsed
                            ? null
                            : Text(
                                d.$2,
                                style: const TextStyle(
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
            if (!collapsed)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EFFA),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.spa_outlined, color: Color(0xFF60599A)),
                    SizedBox(height: 8),
                    Text(
                      'A little stronger, every day.',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'More time for your community.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: collapsed ? null : const Text('Sign out'),
              onTap: () async {
                try {
                  await widget.session.signOut();
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Unable to sign out. Try again.'),
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    return RepositoryProvider.value(
      value: repository,
      child: RepositoryProvider<OperationsRepository>(
        create: (_) => DurableOperations(
          SupabaseOperationsRepository(widget.client, widget.access.gymId),
          repository,
        ),
        child: BlocProvider.value(
          value: sync,
          child: Scaffold(
            drawer: wide ? null : Drawer(child: navigation),
            body: Row(
              children: [
                if (wide) navigation,
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
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
                                  icon: const Icon(Icons.menu_open),
                                )
                              else
                                Builder(
                                  builder: (c) => IconButton(
                                    tooltip: 'Open navigation',
                                    onPressed: () =>
                                        Scaffold.of(c).openDrawer(),
                                    icon: const Icon(Icons.menu),
                                  ),
                                ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  widget.access.gymName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Notifications',
                                onPressed: () => context.go('/notifications'),
                                icon: const Icon(Icons.notifications_none),
                              ),
                              const SizedBox(width: 12),
                              CircleAvatar(
                                backgroundColor: const Color(0xFFE8E5F7),
                                child: Text(
                                  widget.access.name
                                      .substring(0, 1)
                                      .toUpperCase(),
                                ),
                              ),
                              if (wide)
                                Padding(
                                  padding: const EdgeInsets.only(left: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.access.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        widget.access.role.name,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF657570),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      BlocBuilder<SyncEngine, SyncStatus>(
                        builder: (context, status) =>
                            StreamBuilder<List<SyncOperation>>(
                              stream: repository.watchOutbox(),
                              builder: (context, snapshot) {
                                final pending = snapshot.data?.length ?? 0;
                                return Container(
                                  width: double.infinity,
                                  color: status.error == null
                                      ? const Color(0xFFEFF7F2)
                                      : const Color(0xFFFFF1E8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        status.error != null
                                            ? Icons.cloud_off_outlined
                                            : Icons.cloud_done_outlined,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          status.error ??
                                              (status.running
                                                  ? 'Synchronizing workspace…'
                                                  : pending > 0
                                                  ? '$pending changes on this device awaiting confirmation'
                                                  : 'Workspace synchronized'),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: status.running
                                            ? null
                                            : sync.sync,
                                        child: const Text('Sync now'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.all(wide ? 32 : 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title == 'Overview'
                                    ? 'Your gym, at a glance'
                                    : title,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                title == 'Overview'
                                    ? 'A clear view of your community and daily operations.'
                                    : 'Manage your ${title.toLowerCase()} in one place.',
                                style: const TextStyle(
                                  color: Color(0xFF657570),
                                ),
                              ),
                              const SizedBox(height: 24),
                              Expanded(child: widget.child),
                            ],
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
                    destinations: const [
                      NavigationDestination(
                        icon: Icon(Icons.space_dashboard_outlined),
                        label: 'Overview',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.people_outline),
                        label: 'Members',
                      ),
                      NavigationDestination(
                        icon: Icon(Icons.event_repeat),
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

class WorkspaceContent extends StatelessWidget {
  const WorkspaceContent({super.key, required this.path});
  final String path;
  @override
  Widget build(BuildContext context) {
    if (path == '/') return const Dashboard();
    if (path == '/sync') return const SyncCenter();
    if (path == '/settings') return const SettingsPanel();
    final kind = {
      '/members': 'members',
      '/packages': 'membership_packages',
      '/subscriptions': 'subscriptions',
      '/payments': 'invoices',
      '/receipts': 'receipts',
      '/employees': 'employees',
      '/notifications': 'notifications',
    }[path]!;
    return RecordDirectory(kind: kind);
  }
}

class Dashboard extends StatelessWidget {
  const Dashboard({super.key});
  @override
  Widget build(BuildContext context) {
    final repo = context.read<WorkspaceRepository>();
    return StreamBuilder<List<CachedRecord>>(
      stream: (repo.db.select(
        repo.db.cachedRecords,
      )..where((r) => r.scope.equals(repo.scope))).watch(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text(
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
        final today = DateTime.now().toUtc().add(const Duration(hours: 4));
        final date = DateTime.utc(today.year, today.month, today.day);
        final reversed = all
            .where((r) => r.kind == 'payment_reversals')
            .map((r) => (jsonDecode(r.payload) as Map)['payment_id'])
            .toSet();
        final payments = all
            .where((r) => r.kind == 'payments' && !reversed.contains(r.id))
            .map((r) => jsonDecode(r.payload) as Map)
            .toList();
        int collected(bool month) => payments
            .where((p) {
              final d = DateTime.parse(p['created_at'] as String)
                  .toUtc()
                  .add(const Duration(hours: 4));
              return d.year == today.year &&
                  d.month == today.month &&
                  (month || d.day == today.day);
            })
            .fold<int>(0, (sum, p) => sum + (p['amount_minor'] as int));
        final expiring = subscriptions
            .where(
              (s) =>
                  s['status'] == 'active' &&
                  DateTime.parse(s['end_exclusive'] as String)
                          .subtract(const Duration(days: 1))
                          .difference(date)
                          .inDays >=
                      0 &&
                  DateTime.parse(s['end_exclusive'] as String)
                          .subtract(const Duration(days: 1))
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
            Icons.people_outline,
            const Color(0xFFE3F1E9),
          ),
          (
            'Active memberships',
            '${subscriptions.where((r) => r['status'] == 'active').length}',
            Icons.verified_outlined,
            const Color(0xFFECE9FA),
          ),
          (
            'Paused memberships',
            '${subscriptions.where((r) => r['status'] == 'paused').length}',
            Icons.pause_circle_outline,
            const Color(0xFFFFEDE5),
          ),
          if (repo.access.finances)
            (
              'Outstanding balance',
              Money.format(balance),
              Icons.account_balance_wallet_outlined,
              const Color(0xFFE5F2FA),
            ),
          (
            'Expired memberships',
            '${subscriptions.where((s) => s['status'] == 'expired').length}',
            Icons.event_busy,
            const Color(0xFFFFEDE5),
          ),
          (
            'Expiring within 7 days',
            '$expiring',
            Icons.event_available,
            const Color(0xFFECE9FA),
          ),
          if (repo.access.finances) ...[
            (
              'Collected today',
              Money.format(collected(false)),
              Icons.payments_outlined,
              const Color(0xFFE3F1E9),
            ),
            (
              'Collected this month',
              Money.format(collected(true)),
              Icons.trending_up,
              const Color(0xFFE5F2FA),
            ),
            (
              'Overdue balance',
              Money.format(overdue),
              Icons.schedule,
              const Color(0xFFFFEDE5),
            ),
          ],
        ];
        return ListView(
          children: [
            if (repo.access.finances) ...[
              CollectionChart(payments: payments, today: today),
              const SizedBox(height: 24),
            ],
            LayoutBuilder(
              builder: (context, box) => Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final m in metrics)
                    SizedBox(
                      width: box.maxWidth < 600
                          ? box.maxWidth
                          : (box.maxWidth -
                                    16 * (box.maxWidth > 1200 ? 3 : 1)) /
                                (box.maxWidth > 1200 ? 4 : 2),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: m.$4,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(m.$3, color: GymTheme.ink),
                              ),
                              const SizedBox(height: 20),
                              Text(
                                m.$2,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                m.$1,
                                style: const TextStyle(
                                  color: Color(0xFF657570),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
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
                          child: const Text('View all'),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    if (members.isEmpty)
                      const EmptyPanel(
                        icon: Icons.people_outline,
                        title: 'Your community starts here',
                        message: 'Add your first member to see registrations and membership activity.',
                      )
                    else
                      ...members.reversed.take(5).map((r) {
                        final m = jsonDecode(r.payload) as Map;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                            backgroundColor: Color(0xFFE3F1E9),
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
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Make room for what matters',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Keep your members, memberships, and collections connected.',
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (repo.access.editMembers)
                          FilledButton.icon(
                            onPressed: () =>
                                showRecordEditor(context, 'members'),
                            icon: const Icon(Icons.person_add_alt),
                            label: const Text('Register member'),
                          ),
                        if (repo.access.administer)
                          OutlinedButton.icon(
                            onPressed: () => context.go('/packages'),
                            icon: const Icon(Icons.inventory_2_outlined),
                            label: const Text('Manage packages'),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => context.go('/sync'),
                          icon: const Icon(Icons.cloud_sync_outlined),
                          label: const Text('Review sync activity'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Unsynchronized changes are stored on this device. Clearing browser storage removes them. Sync resumes while the application is open.',
              style: TextStyle(fontSize: 12, color: Color(0xFF657570)),
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
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: GymTheme.sage),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF657570)),
          ),
        ],
      ),
    ),
  );
}

class RecordDirectory extends StatefulWidget {
  const RecordDirectory({super.key, required this.kind});
  final String kind;
  @override
  State<RecordDirectory> createState() => _RecordDirectoryState();
}

class _RecordDirectoryState extends State<RecordDirectory> {
  String query = '', filter = 'all';
  int page = 0;
  @override
  void didUpdateWidget(RecordDirectory oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      query = '';
      filter = 'all';
      page = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<WorkspaceRepository>(), kind = widget.kind;
    final editable =
        kind == 'members' && repo.access.editMembers ||
        kind == 'membership_packages' && repo.access.administer;
    return Column(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: MediaQuery.sizeOf(context).width < 600 ? 240 : 320,
              child: TextField(
                key: ValueKey(kind),
                onChanged: (v) => setState(() {
                  query = v.toLowerCase();
                  page = 0;
                }),
                decoration: const InputDecoration(
                  hintText: 'Search records…',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ),
            DropdownButton<String>(
              value: filter,
              items: [
                for (final status in ['all', 'active', 'archived', 'pending'])
                  DropdownMenuItem(
                    value: status,
                    child: Text(status == 'all' ? 'All statuses' : status),
                  ),
              ],
              onChanged: (v) => setState(() {
                filter = v!;
                page = 0;
              }),
            ),
            if (editable)
              FilledButton.icon(
                onPressed: () => showRecordEditor(context, kind),
                icon: const Icon(Icons.add),
                label: Text(
                  kind == 'members' ? 'Add member' : 'Create package',
                ),
              ),
            if (kind == 'subscriptions' && repo.access.finances)
              FilledButton.icon(
                onPressed: () => showServerOperation(context, 'subscribe'),
                icon: const Icon(Icons.add),
                label: const Text('Create / renew membership'),
              ),
            if (kind == 'employees' && repo.access.administer)
              FilledButton.icon(
                onPressed: () => showServerOperation(context, 'invite'),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Invite employee'),
              ),
            if (kind == 'notifications')
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final subscription = await subscribePush(
                      const String.fromEnvironment('VAPID_PUBLIC_KEY'),
                    );
                    if (!context.mounted) return;
                    await context.read<OperationsRepository>().registerPush(
                      jsonDecode(subscription) as Map<String, dynamic>,
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Browser push enabled for this workspace.',
                          ),
                        ),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Push is unavailable, unconfigured, or permission was denied. In-app reminders remain available.',
                          ),
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.notifications_active_outlined),
                label: const Text('Enable browser push'),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Expanded(
          child: StreamBuilder<List<CachedRecord>>(
            stream: repo.watch(kind),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text(
                  'Unable to open local storage. Check browser storage permissions.',
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final records =
                  snapshot.data!
                      .where(
                        (r) =>
                            r.payload.toLowerCase().contains(query) &&
                            (filter == 'all' ||
                                filter == 'pending' &&
                                    r.syncState != 'synced' ||
                                (jsonDecode(r.payload) as Map)['status'] ==
                                    filter),
                      )
                      .toList()
                    ..sort((a, b) => a.payload.compareTo(b.payload));
              if (records.isEmpty) {
                return Card(
                  child: EmptyPanel(
                    icon: Icons.folder_open_outlined,
                    title: 'No records yet',
                    message: editable
                        ? 'Create your first record. Changes appear immediately, even before sync.'
                        : 'Authorized records will appear here after synchronization.',
                  ),
                );
              }
              final start = (page * 15).clamp(0, records.length);
              return Card(
                child: Column(
                  children: [
                    Expanded(
                      child: ListView.separated(
                        itemCount: records.skip(start).take(15).length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = records[start + i],
                              m = jsonDecode(r.payload) as Map<String, dynamic>;
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFFECE9FA),
                              child: Icon(
                                kind == 'members'
                                    ? Icons.person_outline
                                    : Icons.inventory_2_outlined,
                              ),
                            ),
                            title: Text(
                              (m['full_name'] ??
                                      m['name'] ??
                                      m['title'] ??
                                      m['receipt_number'] ??
                                      m['id'])
                                  .toString(),
                            ),
                            subtitle: Text(
                              (m['phone'] ??
                                      m['description'] ??
                                      m['status'] ??
                                      '')
                                  .toString(),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (m['price_minor'] != null)
                                  Text(
                                    Money.format(
                                      m['price_minor'] as int,
                                      m['currency'] as String? ?? 'AED',
                                    ),
                                  ),
                                const SizedBox(width: 8),
                                Chip(
                                  label: Text(
                                    r.syncState == 'synced'
                                        ? (m['status'] ?? 'active').toString()
                                        : r.syncState,
                                  ),
                                ),
                                if (editable)
                                  IconButton(
                                    tooltip: 'Edit record',
                                    onPressed: () => showRecordEditor(
                                      context,
                                      kind,
                                      record: r,
                                    ),
                                    icon: const Icon(Icons.edit_outlined),
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
                                    icon: const Icon(Icons.more_horiz),
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
                                    icon: const Icon(Icons.add_card),
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
                                    icon: const Icon(Icons.swap_horiz),
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
                                    icon: const Icon(Icons.person_off_outlined),
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
                                                const SnackBar(
                                                  content: Text(
                                                    'Unable to verify receipt. Reconnect and try again.',
                                                  ),
                                                ),
                                              );
                                        }
                                      }
                                    },
                                    icon: const Icon(
                                      Icons.picture_as_pdf_outlined,
                                    ),
                                  ),
                                if (kind == 'receipts' &&
                                    repo.access.administer &&
                                    m['status'] == 'issued')
                                  IconButton(
                                    tooltip: 'Reverse payment',
                                    onPressed: () => showAdjustment(context, r),
                                    icon: const Icon(Icons.undo),
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
                                          await context
                                              .read<SyncEngine>()
                                              .sync();
                                        }
                                      } catch (_) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                    'Unable to mark notification read. Retry when connected.',
                                                  ),
                                                ),
                                              );
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.done),
                                  ),
                              ],
                            ),
                            onTap: () => showDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Record details'),
                                content: RecordDetails(
                                  record: r,
                                  repository: repo,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('Close'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${records.length} records · Page ${page + 1}'),
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed: page == 0
                              ? null
                              : () => setState(() => page--),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: start + 15 >= records.length
                              ? null
                              : () => setState(() => page++),
                          icon: const Icon(Icons.chevron_right),
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
      ? ['full_name', 'phone', 'email', 'address', 'notes']
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
                      padding: const EdgeInsets.only(bottom: 14),
                      child: TextFormField(
                        controller: controllers[f],
                        decoration: InputDecoration(
                          labelText:
                              f.replaceAll('_', ' ') +
                              (f == 'price' ? ' (AED)' : ''),
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
                      decoration: const InputDecoration(
                        labelText: 'Duration unit',
                      ),
                      items: [
                        for (final u in ['days', 'weeks', 'months', 'years'])
                          DropdownMenuItem(value: u, child: Text(u)),
                      ],
                      onChanged: (v) => unit = v!,
                    ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      for (final s in ['active', 'inactive', 'archived'])
                        DropdownMenuItem(value: s, child: Text(s)),
                    ],
                    onChanged: (v) => status = v!,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
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
            child: const Text('Cancel'),
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
                        values['email'] = (values['email'] as String)
                            .toLowerCase();
                        values['phone'] = (values['phone'] as String)
                            .replaceAll(RegExp(r'[\s()-]'), '');
                        values['joining_date'] =
                            data['joining_date'] ??
                            DateTime.now()
                                .toUtc()
                                .add(const Duration(hours: 4))
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
            child: Text(busy ? 'Saving…' : 'Save on this device'),
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
          return const Card(
            child: EmptyPanel(
              icon: Icons.cloud_done_outlined,
              title: 'All caught up',
              message: 'There are no unconfirmed changes on this device.',
            ),
          );
        }
        return ListView(
          children: [
            const Text(
              'Conflicts retain your local change. Review the server version before discarding it. Financial changes always require server authorization.',
            ),
            const SizedBox(height: 16),
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
                                  const SnackBar(
                                    content: Text(
                                      'Cannot confirm this operation while disconnected.',
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Check confirmation'),
                        )
                      : op.state == 'conflict' || op.state == 'approval'
                      ? TextButton(
                          onPressed: () async {
                            final discard = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Discard local change?'),
                                content: SingleChildScrollView(
                                  child: SelectableText(
                                    'Local change:\n${op.payload}\n\nThe server record will be fetched again. This discards only the uncommitted local operation.',
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Keep local change'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text(
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
                              )..where((c) => c.scope.equals(repo.scope))).go();
                            });
                            if (context.mounted) {
                              await context.read<SyncEngine>().sync();
                            }
                          },
                          child: const Text('Resolve'),
                        )
                      : TextButton(
                          onPressed: () => repo.retry(op.id),
                          child: const Text('Retry'),
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
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  access.gymName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                const ListTile(
                  leading: Icon(Icons.payments_outlined),
                  title: Text('Default currency'),
                  subtitle: Text('AED · stored as integer fils'),
                ),
                const ListTile(
                  leading: Icon(Icons.schedule),
                  title: Text('Default timezone'),
                  subtitle: Text(
                    'Asia/Dubai · membership boundaries use calendar dates',
                  ),
                ),
                const ListTile(
                  leading: Icon(Icons.security),
                  title: Text('Offline security'),
                  subtitle: Text(
                    'A live server authorization is required to unlock a workspace. Cached data is isolated by gym and user.',
                  ),
                ),
                SelectableText('Gym ID: ${access.gymId}'),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
