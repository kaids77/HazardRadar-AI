import '../models/user_profile.dart';
import 'auth_service.dart';
import 'profile_repository.dart';

/// Brings the app to a ready state: signed in, with a profile loaded.
class SessionService {
  const SessionService({required this.auth, required this.profiles});

  final AuthService auth;
  final ProfileRepository profiles;

  Future<UserProfile> start() async {
    final uid = await auth.ensureSignedIn();
    return profiles.getOrCreateProfile(uid);
  }
}
