import '../models/user_profile.dart';
import 'account_linker.dart';
import 'auth_service.dart';
import 'profile_repository.dart';

/// Brings the app to a ready state: signed in, with a profile loaded.
class SessionService {
  const SessionService({
    required this.auth,
    required this.profiles,
    this.linker,
  });

  final AuthService auth;
  final ProfileRepository profiles;

  /// Null in builds or tests without Google sign-in.
  final AccountLinker? linker;

  Future<UserProfile> start() async {
    final uid = await auth.ensureSignedIn();
    return profiles.getOrCreateProfile(uid);
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
