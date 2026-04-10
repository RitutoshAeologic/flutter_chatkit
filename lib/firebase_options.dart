import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA_MOCK_WEB_KEY',
    appId: '1:1234567890:web:mock1234567890',
    messagingSenderId: '1234567890',
    projectId: 'mock-project-id',
    authDomain: 'mock-project-id.firebaseapp.com',
    storageBucket: 'mock-project-id.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyA_MOCK_ANDROID_KEY',
    appId: '1:1234567890:android:mock1234567890',
    messagingSenderId: '1234567890',
    projectId: 'mock-project-id',
    storageBucket: 'mock-project-id.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA_MOCK_IOS_KEY',
    appId: '1:1234567890:ios:mock1234567890',
    messagingSenderId: '1234567890',
    projectId: 'mock-project-id',
    storageBucket: 'mock-project-id.appspot.com',
    iosBundleId: 'com.example.chatkit',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyA_MOCK_MACOS_KEY',
    appId: '1:1234567890:ios:mock1234567890',
    messagingSenderId: '1234567890',
    projectId: 'mock-project-id',
    storageBucket: 'mock-project-id.appspot.com',
    iosBundleId: 'com.example.chatkit',
  );
}
