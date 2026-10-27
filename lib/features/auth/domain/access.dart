enum GymRole { owner, admin, manager, trainer, receptionist, staff }

class GymAccess {
  const GymAccess({
    required this.gymId,
    required this.userId,
    required this.name,
    required this.gymName,
    required this.role,
  });
  final String gymId, userId, name, gymName;
  final GymRole role;
  bool get administer => role == GymRole.owner || role == GymRole.admin;
  bool get finances =>
      administer || role == GymRole.manager || role == GymRole.receptionist;
  bool get editMembers => finances;
  bool allows(String path) {
    if (path.startsWith('/employees') || path.startsWith('/settings')) {
      return administer;
    }
    if (path.startsWith('/payments') || path.startsWith('/receipts')) {
      return finances;
    }
    if (path.startsWith('/packages')) {
      return role != GymRole.trainer && role != GymRole.staff;
    }
    return true;
  }
}
