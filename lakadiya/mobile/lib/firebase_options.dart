// AUTO-GENERATED — replace with output of: flutterfire configure
//
// Steps to generate this file:
//   1. Install FlutterFire CLI:   dart pub global activate flutterfire_cli
//   2. Create Firebase project at https://console.firebase.google.com
//   3. Run from this directory:   flutterfire configure --project=YOUR_PROJECT_ID
//
// Until then, Firebase will be disabled and OTP falls back to console log in dev.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android: return android;
      case TargetPlatform.iOS:     return ios;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ── Replace all placeholder values below after running `flutterfire configure` ──

  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'REPLACE_WITH_ANDROID_API_KEY',
    appId:             'REPLACE_WITH_ANDROID_APP_ID',
    messagingSenderId: 'REPLACE_WITH_SENDER_ID',
    projectId:         'REPLACE_WITH_PROJECT_ID',
    storageBucket:     'REPLACE_WITH_PROJECT_ID.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey:            'REPLACE_WITH_IOS_API_KEY',
    appId:             'REPLACE_WITH_IOS_APP_ID',
    messagingSenderId: 'REPLACE_WITH_SENDER_ID',
    projectId:         'REPLACE_WITH_PROJECT_ID',
    storageBucket:     'REPLACE_WITH_PROJECT_ID.appspot.com',
    iosBundleId:       'com.lakadiya.lakadiya',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey:            'REPLACE_WITH_WEB_API_KEY',
    appId:             'REPLACE_WITH_WEB_APP_ID',
    messagingSenderId: 'REPLACE_WITH_SENDER_ID',
    projectId:         'REPLACE_WITH_PROJECT_ID',
    storageBucket:     'REPLACE_WITH_PROJECT_ID.appspot.com',
  );
}
