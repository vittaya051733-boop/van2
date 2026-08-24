import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/home_quick_action_config.dart';
import '../models/home_shelves_config.dart';

class HomeQuickActionConfigService {
  HomeQuickActionConfigService._();

  static final HomeQuickActionConfigService instance =
      HomeQuickActionConfigService._();

  static const String collection = 'platform_catalog';
  static const String documentId = 'home_shelves';

  HomeShelvesConfig _cached = HomeShelvesConfig.defaults;

  HomeShelvesConfig get current => _cached;

  HomeQuickActionConfig get currentQuickActions => _cached.quickActions;

  Stream<HomeShelvesConfig> watch() {
    return FirebaseFirestore.instance
        .collection(collection)
        .doc(documentId)
        .snapshots()
        .map((snapshot) {
          _cached = HomeShelvesConfig.fromFirestore(snapshot.data());
          return _cached;
        });
  }
}
