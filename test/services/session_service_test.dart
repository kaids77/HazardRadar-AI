import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/auth_service.dart';
import 'package:hazardradarai/services/profile_repository.dart';
import 'package:hazardradarai/services/session_service.dart';

class FakeAuthService implements AuthService {
  FakeAuthService(this.uid);

  final String uid;
  int calls = 0;

  @override
  Future<String> ensureSignedIn() async {
    calls++;
    return uid;
  }
}

class FakeProfileRepository implements ProfileRepository {
  final List<String> requestedUids = [];

  @override
  Future<UserProfile> getOrCreateProfile(String uid) async {
    requestedUids.add(uid);
    return UserProfile(
      uid: uid,
      role: UserProfile.roleCitizen,
      tier: UserProfile.tierCommuterObserver,
      accountStatus: UserProfile.accountActive,
    );
  }
}

void main() {
  test('start signs in first, then loads the profile for that uid', () async {
    final auth = FakeAuthService('uid-123');
    final profiles = FakeProfileRepository();
    final session = SessionService(auth: auth, profiles: profiles);

    final profile = await session.start();

    expect(auth.calls, 1);
    expect(profiles.requestedUids, ['uid-123']);
    expect(profile.uid, 'uid-123');
    expect(profile.tier, 1);
    expect(profile.role, 'CITIZEN');
  });
}
