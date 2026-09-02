// Shared Firebase configuration for the Van ecosystem.
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
      case TargetPlatform.windows:
        return android;
      case TargetPlatform.linux:
        return android;
      case TargetPlatform.macOS:
        throw UnsupportedError('Firebase has not been configured for macOS.');
      default:
        throw UnsupportedError('Firebase is not supported on this platform.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyB6Q5DE_VkpqO3qTn3bqPBawQjxzGEngxY',
    appId: '1:802503541368:web:652e4356653d7cbcf6a38d',
    messagingSenderId: '802503541368',
    projectId: 'van-merchant',
    authDomain: 'vantalad.web.app',
    storageBucket: 'van-merchant-van2-storage-802503541368',
    measurementId: 'G-WNMT2HGLVF',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCuGZF0-EUBTuARrToDWQM5pNBMNDg2yYU',
    appId: String.fromEnvironment(
      'FIREBASE_ANDROID_APP_ID',
      defaultValue: '1:802503541368:android:8512943c62753f90f6a38d',
    ),
    messagingSenderId: '802503541368',
    projectId: 'van-merchant',
    storageBucket: String.fromEnvironment(
      'FIREBASE_ANDROID_STORAGE_BUCKET',
      defaultValue: 'van-merchant-van2-storage-802503541368',
    ),
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCuGZF0-EUBTuARrToDWQM5pNBMNDg2yYU',
    appId: '1:802503541368:ios:ea92f5b881a6c472f6a38d',
    messagingSenderId: '802503541368',
    projectId: 'van-merchant',
    storageBucket: 'van-merchant-van2-storage-802503541368',
    iosBundleId: 'van-merchan',
  );
}