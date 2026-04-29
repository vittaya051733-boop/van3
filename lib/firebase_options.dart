// File generated manually from existing Firebase config in this workspace.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;

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
      case TargetPlatform.windows:
        return android;
      case TargetPlatform.linux:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB6Q5DE_VkpqO3qTn3bqPBawQjxzGEngxY',
    appId: '1:802503541368:web:652e4356653d7cbcf6a38d',
    messagingSenderId: '802503541368',
    projectId: 'van-merchant',
    authDomain: 'van-merchant.firebaseapp.com',
    storageBucket: 'van-merchant-van3-storage-802503541368',
    measurementId: 'G-WNMT2HGLVF',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAW7bXQ8cCwFYAhTigB9YJDQQZkZsF2eNc',
    appId: '1:802503541368:android:af96e87f3975ce44f6a38d',
    messagingSenderId: '802503541368',
    projectId: 'van-merchant',
    storageBucket: 'van-merchant-van3-storage-802503541368',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCZGWHYh4FvLeAHT_gLTJPk6i1-VdDkFUE',
    appId: '1:802503541368:ios:4e3a354a1945245ff6a38d',
    messagingSenderId: '802503541368',
    projectId: 'van-merchant',
    storageBucket: 'van-merchant-van3-storage-802503541368',
    iosBundleId: 'van3.rider.com',
  );
}
