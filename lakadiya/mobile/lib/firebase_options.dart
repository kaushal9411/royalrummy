// Generated from google-services.json (project: lakadiya-3e18a)
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

  static const FirebaseOptions android = FirebaseOptions(
    apiKey:            'AIzaSyAESQehBcnY0YovN9SbrnYhvaRSOiKJwso',
    appId:             '1:176694108566:android:8eaac8316535ec3845bdb7',
    messagingSenderId: '176694108566',
    projectId:         'lakadiya-3e18a',
    storageBucket:     'lakadiya-3e18a.firebasestorage.app',
  );

  // Add iOS values after downloading GoogleService-Info.plist from Firebase Console
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey:            'REPLACE_WITH_IOS_API_KEY',
    appId:             'REPLACE_WITH_IOS_APP_ID',
    messagingSenderId: '176694108566',
    projectId:         'lakadiya-3e18a',
    storageBucket:     'lakadiya-3e18a.firebasestorage.app',
    iosBundleId:       'com.lakadiya.lakadiya',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey:            'REPLACE_WITH_WEB_API_KEY',
    appId:             'REPLACE_WITH_WEB_APP_ID',
    messagingSenderId: '176694108566',
    projectId:         'lakadiya-3e18a',
    storageBucket:     'lakadiya-3e18a.firebasestorage.app',
  );
}
