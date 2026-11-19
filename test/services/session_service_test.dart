import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/account_linker.dart';
import 'package:hazardradarai/services/auth_service.dart';
import 'package:hazardradarai/services/profile_repository.dart';
import 'package:hazardradarai/services/session_service.dart';
import 'package:hazardradarai/services/staff_auth.dart';

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

  final List<String> earnedLevelUids = [];

  @override
  Future<UserProfile> applyEarnedLevel(String uid) async {
    earnedLevelUids.add(uid);
    return UserProfile(uid: uid, role: 'CITIZEN', tier: 2, accountStatus: 'ACTIVE', ctp: 50);
  }

  @override
  Future<void> setFocusBadge(String uid, String badge) async {}

  final Map<String, String> displayNames = {};

  @override
  Future<void> setDisplayName(String uid, String name) async => displayNames[uid] = name;
}

/// A repository whose stored profile has earned a level.
class EarnedLevelRepository extends FakeProfileRepository {
  @override
  Future<UserProfile> getOrCreateProfile(String uid) async {
    requestedUids.add(uid);
    return UserProfile(uid: uid, role: 'CITIZEN', tier: 1, accountStatus: 'ACTIVE', ctp: 50);
  }
}

class FakeLinker implements AccountLinker {
  FakeLinker(this.result, {this.displayName});

  final Future<String?> Function() result;

  @override
  final String? displayName;

  @override
  Future<String?> linkGoogle() => result();
}

void main() {
  staffTests();
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

  test('start applies a level earned with points', () async {
    final profiles = EarnedLevelRepository();
    final session = SessionService(auth: FakeAuthService('uid-1'), profiles: profiles);

    final profile = await session.start();

    expect(profile.tier, 2);
    expect(profiles.earnedLevelUids, ['uid-1']);
  });

  test('start does not try a level-up when none is due', () async {
    final profiles = FakeProfileRepository();
    await SessionService(auth: FakeAuthService('uid-1'), profiles: profiles).start();
    expect(profiles.earnedLevelUids, isEmpty);
  });

  group('upgradeWithGoogle', () {
    test('stores the Google display name on the profile', () async {
      final profiles = FakeProfileRepository();
      final session = SessionService(
        auth: FakeAuthService('guest'),
        profiles: profiles,
        linker: FakeLinker(() async => 'guest', displayName: 'Maria Santos'),
      );

      await session.upgradeWithGoogle();

      expect(profiles.displayNames, {'guest': 'Maria Santos'});
    });

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

class FakeStaffAuth implements StaffAuth {
  FakeStaffAuth({this.fail = false});

  final bool fail;
  bool signedIn = false;
  bool signedOut = false;

  @override
  bool get isEmailSession => signedIn;

  @override
  Future<String> signIn({required String email, required String password}) async {
    if (fail) throw const StaffSignInFailed('Wrong email or password.');
    signedIn = true;
    return 'staff-uid';
  }

  @override
  Future<void> signOut() async {
    signedIn = false;
    signedOut = true;
  }
}

void staffTests() {
  test('staff sign-in signs in, then loads the profile', () async {
    final staff = FakeStaffAuth();
    final session = SessionService(auth: FakeAuthService('staff-uid'), profiles: FakeProfileRepository(), staffAuth: staff);

    final profile = await session.signInStaff(email: 'a@city.gov.ph', password: 'pw');

    expect(staff.signedIn, isTrue);
    expect(profile.uid, 'staff-uid');
  });

  test('a failed staff sign-in reports the message; without staff auth it fails clearly', () async {
    final failing = SessionService(
      auth: FakeAuthService('x'),
      profiles: FakeProfileRepository(),
      staffAuth: FakeStaffAuth(fail: true),
    );
    expect(failing.signInStaff(email: 'a', password: 'b'), throwsA(isA<StaffSignInFailed>()));

    final none = SessionService(auth: FakeAuthService('x'), profiles: FakeProfileRepository());
    expect(none.signInStaff(email: 'a', password: 'b'), throwsA(isA<StaffSignInFailed>()));
  });

  test('staff sign-out starts a new session', () async {
    final staff = FakeStaffAuth()..signedIn = true;
    final session = SessionService(auth: FakeAuthService('guest'), profiles: FakeProfileRepository(), staffAuth: staff);

    final profile = await session.signOutStaff();

    expect(staff.signedOut, isTrue);
    expect(profile.uid, 'guest');
  });
}
