import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cart_screen.dart';
import '../tax_pricing_policy.dart';

/// Persists cart locally and syncs stock holds on the server (1 hour).
class CartSessionService {
  CartSessionService._();

  static const Duration cartHoldDuration = Duration(hours: 1);
  static const String _localCartKeyPrefix = 'van2_local_cart_v1';

  static final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );

  static String? _storageUid() {
    final uid = FirebaseAuth.instance.currentUser?.uid.trim();
    if (uid == null || uid.isEmpty) {
      return null;
    }
    return uid;
  }

  static Future<void> saveLocalCart({
    required List<CartLineItem> cartItems,
    required List<CartLineItem> nationwideCartItems,
  }) async {
    final uid = _storageUid();
    if (uid == null) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'savedAt': DateTime.now().toIso8601String(),
        'cart': cartItems.map(_lineItemToJson).toList(growable: false),
        'nationwide': nationwideCartItems
            .map(_lineItemToJson)
            .toList(growable: false),
      };
      await prefs.setString('$_localCartKeyPrefix:$uid', jsonEncode(payload));
    } catch (error) {
      debugPrint('CartSessionService.saveLocalCart failed: $error');
    }
  }

  static Future<({
    List<CartLineItem> cart,
    List<CartLineItem> nationwide,
    bool expired,
  })> loadLocalCart() async {
    final uid = _storageUid();
    if (uid == null) {
      return (cart: <CartLineItem>[], nationwide: <CartLineItem>[], expired: false);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_localCartKeyPrefix:$uid');
      if (raw == null || raw.isEmpty) {
        return (cart: <CartLineItem>[], nationwide: <CartLineItem>[], expired: false);
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return (cart: <CartLineItem>[], nationwide: <CartLineItem>[], expired: false);
      }
      final savedAtRaw = decoded['savedAt']?.toString();
      final savedAt =
          savedAtRaw == null ? null : DateTime.tryParse(savedAtRaw);
      final expired = savedAt != null &&
          DateTime.now().difference(savedAt) >= cartHoldDuration;

      final cart = _decodeLineItems(decoded['cart']);
      final nationwide = _decodeLineItems(decoded['nationwide']);
      return (cart: cart, nationwide: nationwide, expired: expired);
    } catch (error) {
      debugPrint('CartSessionService.loadLocalCart failed: $error');
      return (cart: <CartLineItem>[], nationwide: <CartLineItem>[], expired: false);
    }
  }

  static Future<void> clearLocalCart() async {
    final uid = _storageUid();
    if (uid == null) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_localCartKeyPrefix:$uid');
    } catch (_) {}
  }

  static Future<void> syncStockHold(List<CartLineItem> cartItems) async {
    if (FirebaseAuth.instance.currentUser == null) {
      return;
    }
    try {
      final callable = _functions.httpsCallable('syncVan2CartStockHold');
      await callable.call(<String, dynamic>{
        'items': cartItems.map(_lineItemToHoldPayload).toList(growable: false),
        'releaseMode': 'sync',
      });
    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'CartSessionService.syncStockHold: ${error.code} ${error.message}',
      );
      rethrow;
    } catch (error) {
      debugPrint('CartSessionService.syncStockHold failed: $error');
      rethrow;
    }
  }

  /// After successful checkout — keep stock deducted, drop server session only.
  static Future<void> consumeStockHold() async {
    if (FirebaseAuth.instance.currentUser == null) {
      return;
    }
    try {
      final callable = _functions.httpsCallable('syncVan2CartStockHold');
      await callable.call(<String, dynamic>{
        'items': <Map<String, dynamic>>[],
        'releaseMode': 'consume',
      });
    } catch (error) {
      debugPrint('CartSessionService.consumeStockHold failed: $error');
    }
  }

  /// Cart expired or cleared — restore product stock on the server.
  static Future<void> restoreStockHold() async {
    if (FirebaseAuth.instance.currentUser == null) {
      return;
    }
    try {
      final callable = _functions.httpsCallable('syncVan2CartStockHold');
      await callable.call(<String, dynamic>{
        'items': <Map<String, dynamic>>[],
        'releaseMode': 'restore',
      });
    } catch (error) {
      debugPrint('CartSessionService.restoreStockHold failed: $error');
    }
  }

  static Map<String, dynamic> _lineItemToHoldPayload(CartLineItem item) {
    return <String, dynamic>{
      'productId': item.productId,
      'quantity': item.quantity,
    };
  }

  static Map<String, dynamic> _lineItemToJson(CartLineItem item) {
    return <String, dynamic>{
      'productId': item.productId,
      'shopId': item.shopId,
      'shopName': item.shopName,
      'shopLatitude': item.shopLatitude,
      'shopLongitude': item.shopLongitude,
      'productName': item.productName,
      'unitPrice': item.unitPrice,
      'merchantBasePrice': item.merchantBasePrice,
      'discountPercent': item.discountPercent,
      'merchantUnitPayout': item.merchantUnitPayout,
      'imageUrl': item.imageUrl,
      'selectedToppings': item.selectedToppings,
      'quantity': item.quantity,
      'availableStock': item.availableStock,
      'preparationTimeMinutes': item.preparationTimeMinutes,
      'parcelWeightGrams': item.parcelWeightGrams,
      'parcelLengthCm': item.parcelLengthCm,
      'parcelWidthCm': item.parcelWidthCm,
      'parcelHeightCm': item.parcelHeightCm,
    };
  }

  static List<CartLineItem> _decodeLineItems(Object? raw) {
    if (raw is! List) {
      return <CartLineItem>[];
    }
    final items = <CartLineItem>[];
    for (final entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(entry);
      final productId = map['productId']?.toString().trim() ?? '';
      final shopId = map['shopId']?.toString().trim() ?? '';
      if (productId.isEmpty || shopId.isEmpty) {
        continue;
      }
      items.add(
        CartLineItem(
          productId: productId,
          shopId: shopId,
          shopName: map['shopName']?.toString() ?? '',
          shopLatitude: (map['shopLatitude'] as num?)?.toDouble(),
          shopLongitude: (map['shopLongitude'] as num?)?.toDouble(),
          productName: map['productName']?.toString() ?? '',
          unitPrice: (map['unitPrice'] as num?) ?? 0,
          merchantBasePrice: (map['merchantBasePrice'] as num?) ?? 0,
          discountPercent: TaxPricingPolicy.parseDiscountPercent(
            map['discountPercent'],
          ),
          merchantUnitPayout: (map['merchantUnitPayout'] as num?) ??
              TaxPricingPolicy.resolveMerchantUnitPayout(<String, dynamic>{
                'price': map['merchantBasePrice'] ?? map['unitPrice'] ?? 0,
                'discountPercent': map['discountPercent'],
              }),
          imageUrl: map['imageUrl']?.toString(),
          selectedToppings: ((map['selectedToppings'] as List?) ?? const <dynamic>[])
              .map((value) => value.toString())
              .toList(growable: false),
          quantity: (map['quantity'] as num?)?.toInt() ?? 1,
          availableStock: (map['availableStock'] as num?)?.toInt(),
          preparationTimeMinutes:
              (map['preparationTimeMinutes'] as num?)?.toInt() ?? 10,
          parcelWeightGrams: (map['parcelWeightGrams'] as num?)?.toInt() ?? 1000,
          parcelLengthCm: (map['parcelLengthCm'] as num?)?.toDouble(),
          parcelWidthCm: (map['parcelWidthCm'] as num?)?.toDouble(),
          parcelHeightCm: (map['parcelHeightCm'] as num?)?.toDouble(),
        ),
      );
    }
    return items;
  }
}
