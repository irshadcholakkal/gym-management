import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

abstract interface class OperationsRepository {
  Future<void> subscribe(
    String member,
    String package,
    String start,
    String operation, {
    int discountMinor = 0,
    String discountReason = '',
  });
  Future<Map<String, dynamic>> pay(
    String invoice,
    int amount,
    String method,
    String reference,
    String operation,
  );
  Future<void> transition(
    String subscription,
    int version,
    String action,
    String date,
    String reason,
    String operation, {
    int days = 0,
  });
  Future<void> invite(Map<String, String> fields);
  Future<void> deactivate(String user);
  Future<void> readNotification(String id);
  Future<Map<String, dynamic>> receipt(String id);
  Future<void> registerPush(Map<String, dynamic> subscription);
  Future<bool> isConfirmed(String operation);
  Future<void> changePackage(
    String subscription,
    int version,
    String package,
    String policy,
    String reason,
    String operation,
  );
  Future<void> reversePayment(String payment, String reason, String operation);
}

class SupabaseOperationsRepository implements OperationsRepository {
  SupabaseOperationsRepository(this.client, this.gymId);
  final SupabaseClient client;
  final String gymId;
  @override
  Future<bool> isConfirmed(String operation) async => await client.rpc(
    'check_operation',
    params: {'p_gym': gymId, 'p_operation': operation},
  ) as bool;
  @override
  Future<void> changePackage(
    String subscription,
    int version,
    String package,
    String policy,
    String reason,
    String operation,
  ) async {
    await client.rpc(
      'change_package',
      params: {
        'p_gym': gymId,
        'p_subscription': subscription,
        'p_expected': version,
        'p_package': package,
        'p_policy': policy,
        'p_reason': reason,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> reversePayment(
    String payment,
    String reason,
    String operation,
  ) async {
    await client.rpc(
      'reverse_payment',
      params: {
        'p_gym': gymId,
        'p_payment': payment,
        'p_kind': 'reversal',
        'p_reason': reason,
        'p_operation': operation,
      },
    );
  }

  @override
  Future<void> registerPush(Map<String, dynamic> subscription) async {
    await client.rpc(
      'register_push',
      params: {
        'p_gym': gymId,
        'p_endpoint': subscription['endpoint'],
        'p_keys': subscription['keys'],
      },
    );
  }

  static String operationId() => const Uuid().v4();
  @override
  Future<void> subscribe(
    String member,
    String package,
    String start,
    String operation, {
    int discountMinor = 0,
    String discountReason = '',
  }) async {
    await client.rpc(
      'create_subscription_discounted',
      params: {
        'p_gym': gymId,
        'p_member': member,
        'p_package': package,
        'p_start': start,
        'p_operation': operation,
        'p_discount_minor': discountMinor,
        'p_discount_reason': discountReason.trim(),
      },
    );
  }

  @override
  Future<Map<String, dynamic>> pay(
    String invoice,
    int amount,
    String method,
    String reference,
    String operation,
  ) async => Map<String, dynamic>.from(
    await client.rpc(
      'post_payment',
      params: {
        'p_gym': gymId,
        'p_invoice': invoice,
        'p_amount': amount,
        'p_method': method,
        'p_reference': reference,
        'p_operation': operation,
      },
    ) as Map,
  );
  @override
  Future<void> transition(
    String subscription,
    int version,
    String action,
    String date,
    String reason,
    String operation, {
    int days = 0,
  }) async {
    await client.rpc(
      'transition_subscription',
      params: {
        'p_gym': gymId,
        'p_subscription': subscription,
        'p_expected': version,
        'p_action': action,
        'p_date': date,
        'p_reason': reason,
        'p_operation': operation,
        'p_days': days,
      },
    );
  }

  @override
  Future<void> invite(Map<String, String> fields) async {
    final response = await client.functions.invoke(
      'invite-employee',
      body: {'gym_id': gymId, ...fields},
    );
    if (response.status != 200) throw StateError('Employee invitation failed');
  }

  @override
  Future<void> deactivate(String user) async {
    await client.rpc(
      'deactivate_employee',
      params: {'p_gym': gymId, 'p_user': user},
    );
  }

  @override
  Future<void> readNotification(String id) async {
    await client.rpc(
      'set_notification_read',
      params: {'p_gym': gymId, 'p_notification': id},
    );
  }

  @override
  Future<Map<String, dynamic>> receipt(String id) async => await client
      .from('receipts')
      .select()
      .eq('gym_id', gymId)
      .eq('id', id)
      .single();
}
