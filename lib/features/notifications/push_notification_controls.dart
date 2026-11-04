import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/sync/workspace_repository.dart';
import '../subscriptions/data/operations_repository.dart';
import 'data/device_push_controller.dart';

class PushNotificationControls extends StatefulWidget {
  const PushNotificationControls(
      {super.key, this.controller, this.showTest = false});
  final DevicePushController? controller;
  final bool showTest;
  @override
  State<PushNotificationControls> createState() =>
      _PushNotificationControlsState();
}

class _PushNotificationControlsState extends State<PushNotificationControls>
    with WidgetsBindingObserver {
  DevicePushController? controller;
  PushAvailability availability = PushAvailability.unknown;
  bool loading = true, busy = false;
  String? message;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (controller != null) return;
    controller = widget.controller ??
        (kIsWeb
            ? WebDevicePushController(
                context.read<SupabaseClient>(),
                context.read<WorkspaceRepository>().access,
                context.read<OperationsRepository>())
            : UnsupportedDevicePushController());
    refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) refresh();
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> refresh() async {
    final current = ++generation;
    try {
      final status = await controller!.status();
      if (mounted && generation == current) {
        setState(() {
          availability = status;
          loading = false;
        });
      }
    } catch (_) {
      if (mounted && generation == current) {
        setState(() {
          availability = PushAvailability.unknown;
          loading = false;
        });
      }
    }
  }

  Future<void> run(bool test, {bool display = false}) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (display) {
        await controller!.testDisplay();
      } else if (test) {
        await controller!.test();
      } else {
        await controller!.enable();
      }
      if (mounted) {
        setState(() => message = display
            ? 'Device display requested. If nothing appears, check browser and system notification settings, including Do Not Disturb.'
            : test
                ? 'The push provider accepted the test. Check this device notifications.'
                : 'Push notifications enabled on this device.');
      }
    } on FunctionException catch (error) {
      if (mounted) {
        setState(() => message = error.status == 404
            ? 'The push test service is not available yet. Ask the app administrator to deploy it.'
            : error.status == 400
                ? 'The server rejected this device subscription. Reconnect push; if it persists, the server push-provider configuration needs updating.'
            : error.status == 410
                ? 'This subscription expired. Enable push notifications again.'
                : error.status == 503
                    ? 'Push delivery is not configured on the server yet.'
                    : error.status == 422
                        ? 'The push provider rejected the server credentials. The administrator must verify the VAPID key pair, then reconnect push on this device.'
                        : error.status == 401
                            ? 'Your session has expired. Sign in again, then retry the test.'
                            : error.status == 502
                                ? 'The push provider could not accept the test. Try again shortly.'
                                : error.status == 409
                                    ? 'Enable push notifications on this device first.'
                                    : 'Could not send the test push. Check your connection and try again.');
      }
    } catch (error) {
      if (mounted) {
        setState(() => message = display
            ? 'Device display could not be requested. Allow notifications for this app, reload it, and try again.'
            : error is StateError
                ? error.message
                : test
                    ? 'Could not send the test push. Check your connection and try again.'
                    : 'Push could not be enabled. ${error.toString()}');
      }
    } finally {
      await refresh();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = availability == PushAvailability.enabled;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (enabled)
                  const Chip(
                      avatar: Icon(Icons.check_circle,
                          color: Color(0xFF008F68), size: 18),
                      label: Text('Push enabled'),
                      backgroundColor: Color(0xFFE9F6F1))
                else
                  OutlinedButton.icon(
                      onPressed: loading ||
                              busy ||
                              availability == PushAvailability.blocked ||
                              availability == PushAvailability.unavailable
                          ? null
                          : () => run(false),
                      icon: Icon(availability == PushAvailability.blocked
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_active_outlined),
                      label: Text(loading
                          ? 'Checking push...'
                          : busy
                              ? 'Enabling...'
                              : availability == PushAvailability.blocked
                                  ? 'Push blocked'
                                  : availability == PushAvailability.unavailable
                                      ? 'Push unavailable'
                                      : availability == PushAvailability.unknown
                                          ? 'Enable / reconnect push'
                                          : 'Enable push')),
                if (widget.showTest)
                  OutlinedButton.icon(
                      onPressed: enabled && !busy ? () => run(true) : null,
                      icon: const Icon(Icons.send_outlined),
                      label: Text(busy && enabled
                          ? 'Sending...'
                          : 'Test notification')),
                if (widget.showTest)
                  TextButton.icon(
                    onPressed: loading ||
                            busy ||
                            availability == PushAvailability.blocked ||
                            availability == PushAvailability.unavailable
                        ? null
                        : () => run(false, display: true),
                    icon: const Icon(Icons.notifications_outlined),
                    label: const Text('Test device display'),
                  ),
                IconButton(
                    tooltip: 'Refresh push status',
                    onPressed: busy ? null : refresh,
                    icon: const Icon(Icons.refresh, size: 18)),
              ]),
          if (widget.showTest && availability == PushAvailability.blocked)
            const Text(
                'Allow notifications in your browser site settings, then refresh the status.'),
          if (widget.showTest)
            const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                    'Test notification checks server delivery. Test device display checks this browser without sending a remote push.')),
          if (widget.showTest && availability == PushAvailability.unavailable)
            const Text(
                'Use a browser that supports web push. On iPhone or iPad, open the installed web app.'),
          if (message != null)
            Padding(
                padding: const EdgeInsets.only(top: 8), child: Text(message!)),
        ]);
  }
}

class PushNotificationSettingsCard extends StatelessWidget {
  const PushNotificationSettingsCard({super.key});
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Push notifications',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('Notification status for this device and gym.'),
            const SizedBox(height: 12),
            const PushNotificationControls(showTest: true),
          ])));
}
