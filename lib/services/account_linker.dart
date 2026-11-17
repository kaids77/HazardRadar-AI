import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// A sign-in failure the user can act on. The message is safe to show.
class LinkFailed implements Exception {
  const LinkFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class AccountLinker {
  /// Links a Google account to the current guest and returns the resulting uid.
  ///
  /// If that Google account already belongs to another HazardRadar profile,
  /// the app signs in to that profile instead, so the uid can change.
  /// Returns null when the user cancels. Throws [LinkFailed] otherwise.
  Future<String?> linkGoogle();
}

class FirebaseGoogleLinker implements AccountLinker {
  FirebaseGoogleLinker({
    FirebaseAuth? auth,
    GoogleSignIn? google,
    this.serverClientId,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _google = google ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final GoogleSignIn _google;

  /// Web OAuth client id. Android reads `default_web_client_id` from
  /// google-services.json when this is null.
  final String? serverClientId;

  Future<void>? _initialized;

  @override
  Future<String?> linkGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const LinkFailed(
        'You are signed out. Restart the app and try again.',
      );
    }

    try {
      if (kIsWeb) {
        await user.linkWithPopup(GoogleAuthProvider());
      } else {
        final credential = await _nativeCredential();
        if (credential == null) return null;
        await user.linkWithCredential(credential);
      }
    } on FirebaseAuthException catch (error) {
      switch (error.code) {
        case 'provider-already-linked':
          break;
        case 'credential-already-in-use':
        case 'email-already-in-use':
          final existing = error.credential;
          if (existing == null) {
            throw const LinkFailed(
              'This Google account is already used by another profile.',
            );
          }
          await _auth.signInWithCredential(existing);
        case 'popup-closed-by-user':
        case 'cancelled-popup-request':
        case 'web-context-canceled':
          return null;
        case 'network-request-failed':
          throw const LinkFailed(
            'No connection. Try again when you are online.',
          );
        default:
          throw const LinkFailed('Google sign-in failed. Try again.');
      }
    }

    final linked = _auth.currentUser;
    if (linked == null) {
      throw const LinkFailed('Google sign-in failed. Try again.');
    }
    // The Firestore rule reads the linked provider from the ID token, so refresh it first.
    await linked.getIdToken(true);
    return linked.uid;
  }

  Future<AuthCredential?> _nativeCredential() async {
    await (_initialized ??= _google.initialize(serverClientId: serverClientId));
    try {
      final account = await _google.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const LinkFailed('Google did not return a sign-in token.');
      }
      return GoogleAuthProvider.credential(idToken: idToken);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      if (error.code == GoogleSignInExceptionCode.clientConfigurationError ||
          error.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw const LinkFailed(
          'Google sign-in is not set up for this build yet.',
        );
      }
      throw const LinkFailed('Google sign-in failed. Try again.');
    }
  }
}
