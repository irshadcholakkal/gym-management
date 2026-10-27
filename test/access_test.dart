import 'package:flutter_test/flutter_test.dart';
import 'package:gym_saas/features/auth/domain/access.dart';

void main() {
  GymAccess access(GymRole role) => GymAccess(
    gymId: 'gym',
    userId: 'user',
    name: 'A',
    gymName: 'Gym',
    role: role,
  );
  test('Trainer cannot open finances or staff administration', () {
    expect(access(GymRole.trainer).allows('/payments'), false);
    expect(access(GymRole.trainer).allows('/employees'), false);
    expect(access(GymRole.trainer).editMembers, false);
  });
  test('Reception can collect but cannot administer staff', () {
    expect(access(GymRole.receptionist).allows('/payments'), true);
    expect(access(GymRole.receptionist).allows('/employees'), false);
  });
}
