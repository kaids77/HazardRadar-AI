import 'package:firebase_auth/firebase_auth.dart';

/// A sign-in failure the user can act on. The message is safe to show.
class StaffSignInFailed implements Exception {
  const StaffSignInFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Email and password sign-in for city staff. Accounts are created by an admin in
/// the Firebase console; the app never offers sign-up.
abstract interface class StaffAuth {
  /// Signs in and returns the uid. Replaces the current (usually guest) session.
  Future<String> signIn({required String email, required String password});

  /// Signs out. The next session start creates a new guest account.
  Future<void> signOut();

  /// True when the current account signed in with email and password.
  bool get isEmailSession;

  /// The Google email when the current account is linked to Google, otherwise null.
  /// Google-linked staff get their access from the role on their profile, not a password.
  String? get googleEmail;
}

class FirebaseStaffAuth implements StaffAuth {
  FirebaseStaffAuth({FirebaseAuth? auth}) : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  @override
  bool get isEmailSession =>
      _auth.currentUser?.providerData.any((info) => info.providerId == EmailAuthProvider.PROVIDER_ID) ?? false;

  @override
  String? get googleEmail {
    final google = _auth.currentUser?.providerData
        .where((info) => info.providerId == GoogleAuthProvider.PROVIDER_ID)
        .firstOrNull;
    if (google == null) return null;
    return google.email ?? _auth.currentUser?.email ?? '';
  }

  @override
  Future<String> signIn({required String email, required String password}) async {
    final trimmed = email.trim();
    if (trimmed.isEmpty || password.isEmpty) {
      throw const StaffSignInFailed('Enter your staff email and password.');
    }
    try {
      final credential = await _auth.signInWithEmailAndPassword(email: trimmed, password: password);
      final uid = credential.user?.uid;
      if (uid == null) throw const StaffSignInFailed('Sign-in failed. Try again.');
      return uid;
    } on FirebaseAuthException catch (error) {
      // One message for every credential problem, so the form does not reveal which emails exist.
      throw StaffSignInFailed(switch (error.code) {
        'network-request-failed' => 'No connection. Try again when you are online.',
        'too-many-requests' => 'Too many attempts. Wait a few minutes and try again.',
        'operation-not-allowed' => 'Staff sign-in is not enabled for this project yet.',
        _ => 'Wrong email or password.',
      });
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}
