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
}
