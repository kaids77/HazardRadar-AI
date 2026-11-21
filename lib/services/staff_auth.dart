import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

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

  /// True when the current account can also sign in with email and password.
  bool get hasPassword;

  /// Adds a password to a Google-linked account (or changes it), so the staff email
  /// form also works with the Google email. The uid, role, and points stay the same.
  /// Throws [StaffSignInFailed] with a user-facing message.
  Future<void> setPassword(String password);
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
  bool get hasPassword => isEmailSession;

  static const int minPasswordLength = 8;

  @override
  Future<void> setPassword(String password) async {
    final user = _auth.currentUser;
    final email = googleEmail;
    if (user == null || email == null || email.isEmpty) {
      throw const StaffSignInFailed('Sign in with Google first.');
    }
    if (password.length < minPasswordLength) {
      throw const StaffSignInFailed('Use at least $minPasswordLength characters.');
    }
    try {
      if (hasPassword) {
        await user.updatePassword(password);
      } else {
        await user.linkWithCredential(EmailAuthProvider.credential(email: email, password: password));
      }
      await user.reload();
    } on FirebaseAuthException catch (error) {
      throw StaffSignInFailed(switch (error.code) {
        'operation-not-allowed' =>
          'Email sign-in is off for this project. In the Firebase console, turn on Email/Password under Authentication > Sign-in method.',
        'requires-recent-login' => 'For security, sign out, sign in with Google again, then set the password.',
        'weak-password' => 'That password is too weak. Use at least $minPasswordLength characters.',
        'email-already-in-use' || 'credential-already-in-use' =>
          'Another account already uses this email with a password.',
        'network-request-failed' => 'No connection. Try again when you are online.',
        _ => 'Could not save the password. Try again.',
      });
    }
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
  Future<void> signOut() async {
    // Also forget the Google account on Android, so the next "Continue with Google"
    // shows the account chooser instead of silently reusing the same account.
    if (!kIsWeb && googleEmail != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } on Object {
        // Not initialized or already signed out. Firebase sign-out below is what matters.
      }
    }
    await _auth.signOut();
  }
}
