import '../models/user_profile.dart';
import 'account_linker.dart';
import 'auth_service.dart';
import 'level_policy.dart';
import 'profile_repository.dart';
import 'staff_auth.dart';

/// Brings the app to a ready state: signed in, with a profile loaded.
class SessionService {
  const SessionService({
    required this.auth,
    required this.profiles,
    this.linker,
    this.staffAuth,
  });

  final AuthService auth;
  final ProfileRepository profiles;

  /// Null in builds or tests without Google sign-in.
  final AccountLinker? linker;

  /// Null in builds or tests without staff email sign-in.
  final StaffAuth? staffAuth;

  /// Signs in a staff member with email and password, then loads their profile.
  /// Throws [StaffSignInFailed] with a user-facing message.
  Future<UserProfile> signInStaff({required String email, required String password}) async {
    final staffAuth = this.staffAuth;
    if (staffAuth == null) throw const StaffSignInFailed('Staff sign-in is not available in this build.');
    await staffAuth.signIn(email: email, password: password);
    return start();
  }

  /// Signs out of a staff account and starts a fresh guest session.
  Future<UserProfile> signOutStaff() async {
    await staffAuth?.signOut();
    return start();
  }

  /// Signs in, loads the profile, and applies any level earned with points.
  /// A failed level-up never blocks the session; it is retried next time.
  Future<UserProfile> start() async {
    final uid = await auth.ensureSignedIn();
    final profile = await profiles.getOrCreateProfile(uid);
    if (LevelPolicy.dueUpgrade(profile) == null) return profile;
    try {
      return await profiles.applyEarnedLevel(uid);
    } on Object {
      return profile;
    }
  }

  /// Links Google and returns the upgraded profile, or null if the user cancelled.
  /// Throws [LinkFailed] with a user-facing message on failure.
  Future<UserProfile?> upgradeWithGoogle() async {
    final linker = this.linker;
    if (linker == null) {
      throw const LinkFailed('Google sign-in is not available in this build.');
    }

    final uid = await linker.linkGoogle();
    if (uid == null) return null;

    // The uid changes when the Google account already had a profile, so load it first.
    await profiles.getOrCreateProfile(uid);
    return profiles.upgradeToCivicScout(uid);
  }
}
