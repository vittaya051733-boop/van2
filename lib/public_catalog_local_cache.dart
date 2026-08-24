import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// แคช catalog ลงเครื่อง — โหลดจากดิสก์ก่อน แล้วอัปเดตเฉพาะ doc ที่เปลี่ยน
class PublicCatalogLocalCache {
  PublicCatalogLocalCache._();

  static const String _productsKey = 'van2_catalog_products_v1';
  static const String _publicShopsKey = 'van2_catalog_public_shops_v1';

  static Map<String, Map<String, dynamic>> _productsById =
      <String, Map<String, dynamic>>{};
  static Map<String, Map<String, dynamic>> _publicShopsById =
      <String, Map<String, dynamic>>{};
  static bool _productsHydrated = false;
  static bool _publicShopsHydrated = false;
  static Timer? _productsPersistTimer;
  static Timer? _publicShopsPersistTimer;

  static Map<String, Map<String, dynamic>> get productsById =>
      Map<String, Map<String, dynamic>>.unmodifiable(_productsById);

  static Map<String, Map<String, dynamic>> get publicShopsById =>
      Map<String, Map<String, dynamic>>.unmodifiable(_publicShopsById);

  static Future<void> ensureProductsHydrated() async {
    if (_productsHydrated) {
      return;
    }
    _productsHydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_productsKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      _productsById = decoded.map(
        (key, value) => MapEntry(
          key.toString(),
          _decodeValue(value) as Map<String, dynamic>,
        ),
      );
    } catch (_) {
      _productsById = <String, Map<String, dynamic>>{};
    }
  }

  static Future<void> ensurePublicShopsHydrated() async {
    if (_publicShopsHydrated) {
      return;
    }
    _publicShopsHydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_publicShopsKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return;
      }
      _publicShopsById = decoded.map(
        (key, value) => MapEntry(
          key.toString(),
          _decodeValue(value) as Map<String, dynamic>,
        ),
      );
    } catch (_) {
      _publicShopsById = <String, Map<String, dynamic>>{};
    }
  }

  static void applyProductSnapshot(QuerySnapshot<Map<String, dynamic>> snapshot) {
    for (final change in snapshot.docChanges) {
      final id = change.doc.id;
      switch (change.type) {
        case DocumentChangeType.added:
        case DocumentChangeType.modified:
          _productsById[id] = _encodeFirestoreMap(change.doc.data() ?? {});
        case DocumentChangeType.removed:
          _productsById.remove(id);
      }
    }
    _scheduleProductsPersist();
  }

  /// Replaces the entire product cache from a full query read/listener snapshot.
  static void replaceProductSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    _productsById = {
      for (final doc in snapshot.docs)
        doc.id: _encodeFirestoreMap(doc.data()),
    };
    _scheduleProductsPersist();
  }

  static void applyProductDoc(String id, Map<String, dynamic> data) {
    _productsById[id] = _encodeFirestoreMap(data);
    _scheduleProductsPersist();
  }

  static void replacePublicShops(Map<String, Map<String, dynamic>> shops) {
    _publicShopsById = shops.map(
      (key, value) => MapEntry(key, _encodeFirestoreMap(value)),
    );
    _schedulePublicShopsPersist();
  }

  static void _scheduleProductsPersist() {
    _productsPersistTimer?.cancel();
    _productsPersistTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persistProducts());
    });
  }

  static void _schedulePublicShopsPersist() {
    _publicShopsPersistTimer?.cancel();
    _publicShopsPersistTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persistPublicShops());
    });
  }

  static Future<void> _persistProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _productsById.map((key, value) => MapEntry(key, _encodeValue(value))),
      );
      await prefs.setString(_productsKey, encoded);
    } catch (_) {}
  }

  static Future<void> _persistPublicShops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _publicShopsById.map(
          (key, value) => MapEntry(key, _encodeValue(value)),
        ),
      );
      await prefs.setString(_publicShopsKey, encoded);
    } catch (_) {}
  }

  static Map<String, dynamic> _encodeFirestoreMap(Map<String, dynamic> source) {
    return source.map((key, value) => MapEntry(key, _encodeValue(value)));
  }

  static dynamic _encodeValue(dynamic value) {
    if (value is Timestamp) {
      return <String, dynamic>{
        '_type': 'timestamp',
        'ms': value.millisecondsSinceEpoch,
      };
    }
    if (value is GeoPoint) {
      return <String, dynamic>{
        '_type': 'geopoint',
        'lat': value.latitude,
        'lng': value.longitude,
      };
    }
    if (value is Map) {
      return value.map(
        (key, nested) => MapEntry(key.toString(), _encodeValue(nested)),
      );
    }
    if (value is List) {
      return value.map(_encodeValue).toList(growable: false);
    }
    return value;
  }

  static dynamic _decodeValue(dynamic value) {
    if (value is Map) {
      final type = value['_type']?.toString();
      if (type == 'timestamp' && value['ms'] is num) {
        return Timestamp.fromMillisecondsSinceEpoch((value['ms'] as num).toInt());
      }
      if (type == 'geopoint' && value['lat'] is num && value['lng'] is num) {
        return GeoPoint(
          (value['lat'] as num).toDouble(),
          (value['lng'] as num).toDouble(),
        );
      }
      return value.map(
        (key, nested) => MapEntry(key.toString(), _decodeValue(nested)),
      );
    }
    if (value is List) {
      return value.map(_decodeValue).toList(growable: false);
    }
    return value;
  }
}
