import 'package:firebase_storage/firebase_storage.dart';

import 'firebase_options.dart';

class StorageHelper {
  StorageHelper._();

  static const String _bucketOverride = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  static FirebaseStorage get instance {
    final configuredBucket = _bucketOverride.isNotEmpty
        ? _bucketOverride
        : DefaultFirebaseOptions.currentPlatform.storageBucket;

    if (configuredBucket != null && configuredBucket.isNotEmpty) {
      return FirebaseStorage.instanceFor(bucket: configuredBucket);
    }

    return FirebaseStorage.instance;
  }
}
