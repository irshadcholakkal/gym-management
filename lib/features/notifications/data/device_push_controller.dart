import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/access.dart';
import '../../subscriptions/data/operations_repository.dart';
import 'push_client.dart';

enum PushAvailability { enabled, disabled, blocked, unavailable, unknown }

abstract interface class DevicePushController {
  Future<PushAvailability> status();
  Future<void> enable();
  Future<void> test();
}

class WebDevicePushController implements DevicePushController {
  WebDevicePushController(this.client, this.access, this.operations);
  final SupabaseClient client;
  final GymAccess access;
  final OperationsRepository operations;
  Future<Map> _device() async => jsonDecode(await pushDeviceStatus()) as Map;
  @override
  Future<PushAvailability> status() async {
    final device = await _device();
    if (device['permission'] == 'unsupported') {
      return PushAvailability.unavailable;
    }
    if (device['permission'] == 'denied') return PushAvailability.blocked;
    final subscription = device['subscription'];
    if (device['permission'] != 'granted' || subscription is! Map) {
      return PushAvailability.disabled;
    }
    final row = await client
        .from('push_subscriptions')
        .select('enabled')
        .eq('gym_id', access.gymId)
        .eq('user_id', access.userId)
        .eq('endpoint', subscription['endpoint'] as String)
        .maybeSingle();
    return row?['enabled'] == true
        ? PushAvailability.enabled
        : PushAvailability.disabled;
  }

  @override
  Future<void> enable() async {
    final subscription = jsonDecode(await subscribePush(
            const String.fromEnvironment('VAPID_PUBLIC_KEY')))
        as Map<String, dynamic>;
    await operations.registerPush(subscription);
  }

  @override
  Future<void> test() async {
    final device = await _device();
    final subscription = device['subscription'];
    if (device['permission'] != 'granted' || subscription is! Map) {
      throw StateError('Enable push notifications on this device first.');
    }
    await client.functions.invoke('test-push',
        body: {'gym_id': access.gymId, 'endpoint': subscription['endpoint']});
  }
}

class UnsupportedDevicePushController implements DevicePushController {
  @override
  Future<PushAvailability> status() async => PushAvailability.unavailable;
  @override
  Future<void> enable() async => throw UnsupportedError(
      'Open the installed web app to enable push notifications.');
  @override
  Future<void> test() async => throw UnsupportedError(
      'Open the installed web app to test push notifications.');
}
