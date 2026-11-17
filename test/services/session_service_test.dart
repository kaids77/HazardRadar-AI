import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/account_linker.dart';
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
  final List<String> upgradedUids = [];

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

  @override
  Future<UserProfile> upgradeToCivicScout(String uid) async {
    upgradedUids.add(uid);
    return UserProfile(
      uid: uid,
      role: UserProfile.roleCitizen,
      tier: UserProfile.tierCivicScout,
      accountStatus: UserProfile.accountActive,
    );
  }
}

class FakeLinker implements AccountLinker {
  FakeLinker(this.result);

  final Future<String?> Function() result;

  @override
  Future<String?> linkGoogle() => result();
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

  group('upgradeWithGoogle', () {
    test('loads and upgrades the profile of the linked uid', () async {
      final profiles = FakeProfileRepository();
      final session = SessionService(
        auth: FakeAuthService('guest'),
        profiles: profiles,
        // The Google account already had a profile, so the uid changed.
        linker: FakeLinker(() async => 'existing-google-uid'),
      );

      final profile = await session.upgradeWithGoogle();

      expect(profile?.tier, 2);
      expect(profiles.requestedUids, ['existing-google-uid']);
      expect(profiles.upgradedUids, ['existing-google-uid']);
    });

    test('returns null and changes nothing when the user cancels', () async {
      final profiles = FakeProfileRepository();
      final session = SessionService(
        auth: FakeAuthService('guest'),
        profiles: profiles,
        linker: FakeLinker(() async => null),
      );

      expect(await session.upgradeWithGoogle(), isNull);
      expect(profiles.upgradedUids, isEmpty);
    });

    test('passes link failures through and fails clearly without a linker', () async {
      final failing = SessionService(
        auth: FakeAuthService('guest'),
        profiles: FakeProfileRepository(),
        linker: FakeLinker(() async => throw const LinkFailed('No connection.')),
      );
      expect(failing.upgradeWithGoogle(), throwsA(isA<LinkFailed>()));

      final missing = SessionService(auth: FakeAuthService('guest'), profiles: FakeProfileRepository());
      expect(missing.upgradeWithGoogle(), throwsA(isA<LinkFailed>()));
    });
  });
}
