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

return ios;

 default:

 throw UnsupportedError(

'DefaultFirebaseOptions are not supported for this platform.',

 );

 }

}

  

   static const FirebaseOptions web = FirebaseOptions(

   apiKey: 'AIzaSyC7NUVLZ4ajh-x-dH_hSa-SpHLUs0u7TaU',

   appId: '1:260559428420:web:ef540665fa37580055511',

   messagingSenderId: '260559428420',

   projectId: 'chatkit-8ea73',

   authDomain: 'chatkit-8ea73.firebaseapp.com',

   storageBucket: 'chatkit-8ea73.firebasestorage.app',

   measurementId: 'G-LEJ4WVMBX0',

   );

  

   static const FirebaseOptions android = FirebaseOptions(

   apiKey: 'AIzaSyCtAHJiwvLrUnVnUnDZxUk4FyKQXBo8a_c',

   appId: '1:260559428420:android:ede87278f1f21e28055511',

   messagingSenderId: '260559428420',

   projectId: 'chatkit-8ea73',

   storageBucket: 'chatkit-8ea73.firebasestorage.app',

   );

  

   static const FirebaseOptions ios = FirebaseOptions(

   apiKey: 'AIzaSyDmPOfPP1Kp5Kksl9x5BCaalBxSa4PrMhY',

   appId: '1:260559428420:ios:3eef2fa50cfc78f3055511',

   messagingSenderId: '260559428420',

   projectId: 'chatkit-8ea73',

   storageBucket: 'chatkit-8ea73.firebasestorage.app',

   iosBundleId: 'com.chatkit.app',

   );

}