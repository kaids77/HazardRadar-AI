// Firebase client configuration for the hazardradarai project.
// These identifiers are public. Access is controlled by Firestore and Storage
// rules and by API key restrictions in Google Cloud, not by hiding this file.
//
// Android values come from android/app/google-services.json.
// Web values come from the Firebase console (project settings, web app).

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'Firebase is not configured for this platform. Supported: Android and web.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAQbfayiVMynPG-jX3JrxPfrlyDy4-5_eQ',
    appId: '1:368757984421:web:06c0b1284849bf1e07114c',
    messagingSenderId: '368757984421',
    projectId: 'hazardradarai',
    authDomain: 'hazardradarai.firebaseapp.com',
    storageBucket: 'hazardradarai.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC1ODZlY2AhE9dT-4EkVTx1RgpJAm-fpB8',
    appId: '1:368757984421:android:18376951e51ec1aa07114c',
    messagingSenderId: '368757984421',
    projectId: 'hazardradarai',
    storageBucket: 'hazardradarai.firebasestorage.app',
  );
}
