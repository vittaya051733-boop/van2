import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../public_catalog_service.dart';

Map<String, dynamic> _sanitizeProductDataMap(Map<String, dynamic> source) {
  final sanitized = _jsonSanitize(source);
  if (sanitized is Map<String, dynamic>) {
    return sanitized;
  }
  if (sanitized is Map) {
    return Map<String, dynamic>.from(sanitized);
  }
  return <String, dynamic>{};
}

dynamic _jsonSanitize(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is Timestamp) {
    return value.toDate().toIso8601String();
  }
  if (value is DateTime) {
    return value.toIso8601String();
  }
  if (value is GeoPoint) {
    return <String, dynamic>{
      'latitude': value.latitude,
      'longitude': value.longitude,
    };
  }
  if (value is Map) {
    return value.map(
      (key, item) => MapEntry(key.toString(), _jsonSanitize(item)),
    );
  }
  if (value is Iterable) {
    return value.map(_jsonSanitize).toList(growable: false);
  }
  if (value is num || value is String || value is bool) {
    return value;
  }
  return value.toString();
}

class CatalogFavorite {
  const CatalogFavorite({
    required this.kind,
    required this.id,
    required this.shopId,
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.serviceType,
    this.productData,
    this.shopName,
    this.shopImageUrl,
    this.shopLatitude,
    this.shopLongitude,
    required this.addedAt,
  });

  static const String kindProduct = 'product';
  static const String kindShop = 'shop';

  final String kind;
  final String id;
  final String shopId;
  final String title;
  final String? subtitle;
  final String? imageUrl;
  final String? serviceType;
  final Map<String, dynamic>? productData;
  final String? shopName;
  final String? shopImageUrl;
  final double? shopLatitude;
  final double? shopLongitude;
  final DateTime addedAt;

  String get storageKey =>
      kind == kindProduct ? 'product:$shopId:$id' : 'shop:$shopId';

  factory CatalogFavorite.fromProduct(PublicCatalogProduct product) {
    final data = product.data;
    final name = (data['name'] ?? '').toString().trim();
    return CatalogFavorite(
      kind: kindProduct,
      id: product.id,
      shopId: product.shopId,
      title: name.isEmpty ? 'สินค้า' : name,
      subtitle: product.shopName?.trim(),
      imageUrl: _readPrimaryImageUrl(data),
      serviceType: (data['serviceType'] ?? '').toString(),
      productData: _sanitizeProductDataMap(data),
      shopName: product.shopName,
      shopImageUrl: product.shopImageUrl,
      shopLatitude: product.shopLatitude,
      shopLongitude: product.shopLongitude,
      addedAt: DateTime.now(),
    );
  }

  factory CatalogFavorite.fromSection(PublicCatalogSection section) {
    final name = section.shopName?.trim().isNotEmpty == true
        ? section.shopName!.trim()
        : 'ร้านค้า';
    final serviceType = section.products.isNotEmpty
        ? (section.products.first.data['serviceType'] ?? '').toString()
        : '';
    return CatalogFavorite(
      kind: kindShop,
      id: section.shopId,
      shopId: section.shopId,
      title: name,
      subtitle: section.shopDescription?.trim(),
      imageUrl: section.shopImageUrl?.trim(),
      serviceType: serviceType,
      shopName: section.shopName,
      shopImageUrl: section.shopImageUrl,
      shopLatitude: section.shopLatitude,
      shopLongitude: section.shopLongitude,
      addedAt: DateTime.now(),
    );
  }

  PublicCatalogProduct? toProduct() {
    if (kind != kindProduct || productData == null) {
      return null;
    }
    return PublicCatalogProduct(
      id: id,
      shopId: shopId,
      shopName: shopName,
      shopImageUrl: shopImageUrl,
      shopLatitude: shopLatitude,
      shopLongitude: shopLongitude,
      data: Map<String, dynamic>.from(productData!),
    );
  }

  factory CatalogFavorite.fromJson(Map<String, dynamic> json) {
    return CatalogFavorite(
      kind: (json['kind'] ?? '').toString(),
      id: (json['id'] ?? '').toString(),
      shopId: (json['shopId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      subtitle: json['subtitle']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      serviceType: json['serviceType']?.toString(),
      productData: json['productData'] is Map
          ? Map<String, dynamic>.from(json['productData'] as Map)
          : null,
      shopName: json['shopName']?.toString(),
      shopImageUrl: json['shopImageUrl']?.toString(),
      shopLatitude: (json['shopLatitude'] as num?)?.toDouble(),
      shopLongitude: (json['shopLongitude'] as num?)?.toDouble(),
      addedAt:
          DateTime.tryParse((json['addedAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'kind': kind,
      'id': id,
      'shopId': shopId,
      'title': title,
      'subtitle': subtitle,
      'imageUrl': imageUrl,
      'serviceType': serviceType,
      'productData': productData == null
          ? null
          : _jsonSanitize(productData),
      'shopName': shopName,
      'shopImageUrl': shopImageUrl,
      'shopLatitude': shopLatitude,
      'shopLongitude': shopLongitude,
      'addedAt': addedAt.toIso8601String(),
    };
  }

  static String? _readPrimaryImageUrl(Map<String, dynamic> data) {
    final thumbnails = ((data['thumbnailUrls'] as List?) ?? const <dynamic>[])
        .whereType<String>()
        .where((url) => url.trim().isNotEmpty)
        .toList();
    if (thumbnails.isNotEmpty) {
      return thumbnails.first;
    }

    final images = ((data['imageUrls'] as List?) ?? const <dynamic>[])
        .whereType<String>()
        .where((url) => url.trim().isNotEmpty)
        .toList();
    if (images.isNotEmpty) {
      return images.first;
    }
    return null;
  }
}

class FavoritesService {
  FavoritesService._();

  static final FavoritesService instance = FavoritesService._();

  final ValueNotifier<List<CatalogFavorite>> favorites =
      ValueNotifier<List<CatalogFavorite>>(<CatalogFavorite>[]);

  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    await reload();
  }

  Future<void> reload() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    final raw = prefs.getString('catalog_favorites_v1_$uid');
    if (raw == null || raw.trim().isEmpty) {
      favorites.value = <CatalogFavorite>[];
      _loaded = true;
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        favorites.value = <CatalogFavorite>[];
      } else {
        favorites.value = decoded
            .whereType<Map>()
            .map(
              (entry) =>
                  CatalogFavorite.fromJson(Map<String, dynamic>.from(entry)),
            )
            .where((item) => item.id.isNotEmpty && item.shopId.isNotEmpty)
            .toList(growable: false);
      }
    } catch (_) {
      favorites.value = <CatalogFavorite>[];
    }
    _loaded = true;
  }

  bool isFavorite(CatalogFavorite item) {
    return favorites.value.any((entry) => entry.storageKey == item.storageKey);
  }

  Future<bool> toggle(CatalogFavorite item) async {
    await ensureLoaded();
    final current = List<CatalogFavorite>.from(favorites.value);
    final index = current.indexWhere(
      (entry) => entry.storageKey == item.storageKey,
    );
    final added = index < 0;
    if (added) {
      current.insert(0, item.copyWithFreshTimestamp());
    } else {
      current.removeAt(index);
    }
    favorites.value = current;
    await _persist(current);
    return added;
  }

  Future<void> remove(CatalogFavorite item) async {
    await ensureLoaded();
    final current = List<CatalogFavorite>.from(favorites.value)
      ..removeWhere((entry) => entry.storageKey == item.storageKey);
    favorites.value = current;
    await _persist(current);
  }

  Future<void> _persist(List<CatalogFavorite> items) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    try {
      final encoded = jsonEncode(items.map((item) => item.toJson()).toList());
      await prefs.setString('catalog_favorites_v1_$uid', encoded);
    } on Object {
      // Keep in-memory favorites even if local persistence fails.
    }
  }
}

extension CatalogFavoriteCopy on CatalogFavorite {
  CatalogFavorite copyWithFreshTimestamp() {
    return CatalogFavorite(
      kind: kind,
      id: id,
      shopId: shopId,
      title: title,
      subtitle: subtitle,
      imageUrl: imageUrl,
      serviceType: serviceType,
      productData: productData == null
          ? null
          : _sanitizeProductDataMap(productData!),
      shopName: shopName,
      shopImageUrl: shopImageUrl,
      shopLatitude: shopLatitude,
      shopLongitude: shopLongitude,
      addedAt: DateTime.now(),
    );
  }
}

class CatalogFavoriteToggleButton extends StatelessWidget {
  const CatalogFavoriteToggleButton({
    super.key,
    required this.favorite,
    this.iconColor,
    this.activeColor = const Color(0xFFDC2626),
    this.inactiveColor,
    this.tooltipAdd = 'เพิ่มรายการโปรด',
    this.tooltipRemove = 'ลบออกจากรายการโปรด',
  });

  final CatalogFavorite favorite;
  final Color? iconColor;
  final Color activeColor;
  final Color? inactiveColor;
  final String tooltipAdd;
  final String tooltipRemove;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<CatalogFavorite>>(
      valueListenable: FavoritesService.instance.favorites,
      builder: (context, items, _) {
        final isActive = items.any(
          (entry) => entry.storageKey == favorite.storageKey,
        );
        final color =
            iconColor ??
            (isActive
                ? activeColor
                : (inactiveColor ?? Theme.of(context).iconTheme.color));
        return IconButton(
          tooltip: isActive ? tooltipRemove : tooltipAdd,
          onPressed: () async {
            final added = await FavoritesService.instance.toggle(favorite);
            if (!context.mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  added ? 'เพิ่มรายการโปรดแล้ว' : 'ลบออกจากรายการโปรดแล้ว',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          icon: Icon(
            isActive ? Icons.favorite : Icons.favorite_border,
            color: color,
          ),
        );
      },
    );
  }
}
