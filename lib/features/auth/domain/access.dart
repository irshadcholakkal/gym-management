enum GymRole { owner, admin, manager, trainer, receptionist, staff }

class GymAccess {
  const GymAccess({
    required this.gymId,
    required this.userId,
    required this.name,
    required this.gymName,
    required this.role,
    this.options = const {},
  });
  final String gymId, userId, name, gymName;
  final GymRole role;
  final Map<String, bool> options;
  bool enabled(String key) => role == GymRole.owner || options[key] != false;
  String get permissionKey => [
        'edit_members',
        'operations',
        'discounts',
        'administration'
      ].map((key) => enabled(key) ? '1' : '0').join();
  bool get administer =>
      (role == GymRole.owner || role == GymRole.admin) &&
      enabled('administration');
  bool get finances =>
      (role == GymRole.owner ||
          role == GymRole.admin ||
          role == GymRole.manager ||
          role == GymRole.receptionist) &&
      enabled('operations');
  bool get editMembers => finances && enabled('edit_members');
  bool get canDiscount =>
      finances &&
      (role == GymRole.owner ||
          role == GymRole.admin ||
          role == GymRole.manager) &&
      enabled('discounts');
  bool allows(String path) {
    if (path.startsWith('/employees') || path.startsWith('/settings')) {
      return administer;
    }
    if (path.startsWith('/payments') ||
        path.startsWith('/receipts') ||
        path.startsWith('/subscriptions') &&
            role != GymRole.trainer &&
            role != GymRole.staff) {
      return finances;
    }
    if (path.startsWith('/packages')) {
      return finances;
    }
    return true;
  }

  /// Persisted as the last server-verified access so a network failure on a
  /// later launch can restore the workspace instead of locking the user out.
  Map<String, dynamic> toJson() => {
        'gym_id': gymId,
        'user_id': userId,
        'name': name,
        'gym_name': gymName,
        'role': role.name,
        'options': options,
      };

  static GymAccess? fromJson(Object? json) {
    if (json is! Map) return null;
    final gymId = json['gym_id'], userId = json['user_id'];
    if (gymId is! String || userId is! String) return null;
    try {
      return GymAccess(
        gymId: gymId,
        userId: userId,
        name: json['name'] as String? ?? 'Team member',
        gymName: json['gym_name'] as String? ?? 'Gym',
        role: GymRole.values.byName(json['role'] as String),
        options: Map<String, bool>.from(json['options'] as Map? ?? {}),
      );
    } catch (_) {
      return null;
    }
  }
}
