import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database.dart';
import '../../core/record_labels.dart';
import '../../core/sync/sync_engine.dart';
import '../../core/sync/workspace_repository.dart';
import '../subscriptions/data/operations_repository.dart';
import 'push_notification_controls.dart';

bool currentNotification(Map data, String user) =>
    data['recipient_id'] == user && data['superseded_at'] == null;

Stream<List<CachedRecord>> notificationRecords(WorkspaceRepository repo) =>
    repo.watch('notifications');

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final openedAt = DateTime.now().toUtc();
  final announced = <String>{};
  @override
  Widget build(BuildContext context) {
    final repo = context.read<WorkspaceRepository>();
    return StreamBuilder<List<CachedRecord>>(
      stream: repo.watch('notifications'),
      builder: (context, snapshot) {
        // Decode every payload once per emission; the bell rebuilds often.
        final decoded = (snapshot.data ?? [])
            .where((r) => r.kind == 'notifications')
            .map((r) => (record: r, data: jsonDecode(r.payload) as Map))
            .toList();
        final fresh = decoded.where((entry) {
          final data = entry.data;
          final created = DateTime.tryParse(
            data['created_at']?.toString() ?? '',
          );
          return currentNotification(data, repo.access.userId) &&
              data['read_at'] == null &&
              created != null &&
              !created.isBefore(openedAt) &&
              announced.add(entry.record.id);
        }).toList();
        if (fresh.isNotEmpty) {
          final id = fresh.first.record.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  fresh.length == 1
                      ? 'New membership warning or reminder'
                      : '${fresh.length} new membership alerts',
                ),
                action: SnackBarAction(
                  label: 'View',
                  onPressed: () => context.go(
                    Uri(
                      path: '/notifications',
                      queryParameters: {'notification': id},
                    ).toString(),
                  ),
                ),
              ),
            );
          });
        }
        final count = decoded
            .where((entry) =>
                currentNotification(entry.data, repo.access.userId) &&
                entry.data['read_at'] == null)
            .length;
        return IconButton(
          tooltip: count == 0 ? 'Notifications' : '$count unread notifications',
          onPressed: () => context.go('/notifications'),
          icon: Badge(
            isLabelVisible: count > 0,
            label: Text(count > 99 ? '99+' : '$count'),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }
}

class NotificationCenter extends StatefulWidget {
  const NotificationCenter({super.key, this.queryParameters = const {}});
  final Map<String, String> queryParameters;
  @override
  State<NotificationCenter> createState() => _NotificationCenterState();
}

class _NotificationCenterState extends State<NotificationCenter> {
  String filter = 'all';
  final reading = <String>{};
  Future<void> markRead(CachedRecord record) async {
    if (!reading.add(record.id)) return;
    setState(() {});
    try {
      await context.read<OperationsRepository>().readNotification(record.id);
      if (mounted) await context.read<SyncEngine>().sync();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not mark notification read. Reconnect and try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => reading.remove(record.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<WorkspaceRepository>();
    final params = widget.queryParameters;
    final focused = params['notification'];
    final wrongGym =
        params['gym'] != null && params['gym'] != repo.access.gymId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (MediaQuery.sizeOf(context).width >= 600)
              const Text(
                'Notifications',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
            for (final value in ['all', 'unread', 'warnings', 'reminders'])
              ChoiceChip(
                label: Text(displayLabel(value)),
                selected: filter == value,
                onSelected: (_) => setState(() => filter = value),
              ),
            const PushNotificationControls(),
            IconButton(
              tooltip: 'Refresh notifications',
              onPressed: () => context.read<SyncEngine>().sync(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Membership warnings and reminders. Select a notification to review its membership.',
        ),
        if (wrongGym)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'This alert belongs to another gym. Sign in to that workspace to review it.',
            ),
          ),
        if (focused != null)
          TextButton(
            onPressed: () => context.go('/notifications'),
            child: const Text('Show all notifications'),
          ),
        const SizedBox(height: 16),
        Expanded(
          child: StreamBuilder<List<CachedRecord>>(
            stream: notificationRecords(repo),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(
                  child: Text(
                    'Unable to load notifications. Refresh to try again.',
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final labels = RecordLabels(snapshot.data!);
              // Lookups reuse the decoded payloads; decoding inside the sort
              // comparator froze the inbox as notifications accumulated.
              final decoded = snapshot.data!
                  .where((r) => r.kind == 'notifications')
                  .map((r) =>
                      (record: r, data: labels.lookup('notifications', r.id)))
                  .toList();
              final records = decoded.where((entry) {
                final r = entry.record, m = entry.data;
                if (wrongGym) return false;
                if (!currentNotification(m, repo.access.userId)) {
                  return false;
                }
                if (focused != null && r.id != focused) return false;
                final warning = [
                  'expired',
                  'expiry_0',
                  'payment_overdue',
                ].contains(m['type']);
                return filter == 'all' ||
                    filter == 'unread' && m['read_at'] == null ||
                    filter == 'warnings' && warning ||
                    filter == 'reminders' && !warning;
              }).toList()
                ..sort(
                  (a, b) => ((b.data['created_at'] ?? '').toString())
                      .compareTo((a.data['created_at'] ?? '').toString()),
                );
              if (records.isEmpty) {
                return Center(
                  child: Text(
                    focused != null
                        ? 'This notification is unavailable or no longer current. Try refreshing.'
                        : 'No ${filter == 'all' ? '' : '$filter '}notifications. You’re up to date.',
                  ),
                );
              }
              return ListView.separated(
                itemCount: records.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = records[index],
                      r = entry.record,
                      m = entry.data;
                  final unread = m['read_at'] == null;
                  final warning = [
                    'expired',
                    'expiry_0',
                    'payment_overdue',
                  ].contains(m['type']);
                  final subscription = labels.lookup(
                    'subscriptions',
                    m['subscription_id'],
                  );
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              warning
                                  ? Icons.warning_amber_rounded
                                  : Icons.event_available_outlined,
                              color: warning ? Colors.deepOrange : Colors.teal,
                            ),
                            title: Text(
                              m['title']?.toString() ?? 'Gym update',
                              style: TextStyle(
                                fontWeight: unread
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            subtitle: Text(
                              '${m['body'] ?? ''}\n${displayDate(m['created_at'])}',
                            ),
                            trailing: unread
                                ? const Chip(label: Text('Unread'))
                                : null,
                          ),
                          if (subscription.isNotEmpty)
                            Text(labels.title('subscriptions', subscription)),
                          Wrap(
                            spacing: 12,
                            children: [
                              if (m['subscription_id'] != null)
                                TextButton.icon(
                                  icon: const Icon(Icons.arrow_forward),
                                  label: const Text('View membership'),
                                  onPressed: () {
                                    if (unread) markRead(r);
                                    context.go(
                                      Uri(
                                        path: '/subscriptions',
                                        queryParameters: {
                                          'record':
                                              m['subscription_id'].toString(),
                                        },
                                      ).toString(),
                                    );
                                  },
                                ),
                              if (unread)
                                TextButton(
                                  onPressed: reading.contains(r.id)
                                      ? null
                                      : () => markRead(r),
                                  child: Text(
                                    reading.contains(r.id)
                                        ? 'Saving…'
                                        : 'Mark read',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
