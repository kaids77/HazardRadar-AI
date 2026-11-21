import 'package:firebase_auth/firebase_auth.dart';

abstract interface class AuthService {
  /// Returns the uid of the signed-in user. On first launch this creates an
  /// anonymous account. Later launches reuse the stored session.
  Future<String> ensureSignedIn();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  Future<String> ensureSignedIn() async {
    final current = _auth.currentUser;
    if (current != null) return current.uid;

    final credential = await _auth.signInAnonymously();
    final user = credential.user;
    if (user == null) {
      throw StateError('Anonymous sign-in returned no user');
    }
    return user.uid;
  }
}
