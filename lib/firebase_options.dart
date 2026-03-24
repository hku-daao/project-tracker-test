// FlutterFire-style options (same project as lib/config/firebase_config.dart).
// See: https://firebase.flutter.dev/docs/manual-installation
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show kIsWeb;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    throw UnsupportedError(
      'DefaultFirebaseOptions: add Android/iOS in firebase_options.dart if needed.',
    );
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA3nBRcqo2MG3XOjVjtZ0iNY1CHJgJNBo0',
    appId: '1:767884507730:web:aedb77f7b2fbf7e3b37d8b',
    messagingSenderId: '767884507730',
    projectId: 'daao-a20c6',
    authDomain: 'daao-a20c6.firebaseapp.com',
    storageBucket: 'daao-a20c6.firebasestorage.app',
    measurementId: 'G-HWZBX7573J',
  );
}
