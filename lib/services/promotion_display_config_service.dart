import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/promotion_models.dart';

class PromotionDisplayConfigService {
  PromotionDisplayConfigService._();

  static final PromotionDisplayConfigService instance =
      PromotionDisplayConfigService._();

  static const String collection = 'promotion_display_config';
  static const String documentId = 'global';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  PromotionDisplayConfig _cached = PromotionDisplayConfig.defaults;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;

  PromotionDisplayConfig get current => _cached;

  void start() {
    _subscription?.cancel();
    _subscription = _firestore
        .collection(collection)
        .doc(documentId)
        .snapshots()
        .listen((snapshot) {
      _cached = PromotionDisplayConfig.fromFirestore(snapshot.data());
    });
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
