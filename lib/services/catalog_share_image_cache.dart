import 'dart:async';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:http/http.dart' as http;

/// Keeps product image bytes ready so share can attach a photo immediately.
class CatalogShareImageCache {
  CatalogShareImageCache._();

  static final CatalogShareImageCache instance = CatalogShareImageCache._();

  final Map<String, Uint8List> _bytesByUrl = <String, Uint8List>{};
  final Map<String, Future<Uint8List?>> _loadsByUrl = <String, Future<Uint8List?>>{};

  void warm(String? imageUrl) {
    final normalized = _normalizeUrl(imageUrl);
    if (normalized == null || _bytesByUrl.containsKey(normalized)) {
      return;
    }
    _loadsByUrl.putIfAbsent(normalized, () => _load(normalized));
    unawaited(_loadsByUrl[normalized]);
  }

  Uint8List? peek(String? imageUrl) {
    final normalized = _normalizeUrl(imageUrl);
    if (normalized == null) {
      return null;
    }
    return _bytesByUrl[normalized];
  }

  Future<Uint8List?> resolve(String? imageUrl) async {
    final normalized = _normalizeUrl(imageUrl);
    if (normalized == null) {
      return null;
    }

    final cached = _bytesByUrl[normalized];
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final pending = _loadsByUrl[normalized];
    if (pending != null) {
      return pending;
    }

    final loaded = _load(normalized);
    _loadsByUrl[normalized] = loaded;
    return loaded;
  }

  Future<Uint8List?> toShareJpeg(Uint8List bytes) async {
    if (bytes.isEmpty) {
      return null;
    }
    if (kIsWeb) {
      return bytes;
    }
    try {
      final jpeg = await FlutterImageCompress.compressWithList(
        bytes,
        format: CompressFormat.jpeg,
        quality: 90,
      );
      if (jpeg.isNotEmpty) {
        return jpeg;
      }
    } catch (_) {}
    return bytes;
  }

  String? _normalizeUrl(String? imageUrl) {
    final normalized = imageUrl?.trim();
    if (normalized == null || normalized.isEmpty) {
      return null;
    }
    return normalized;
  }

  Future<Uint8List?> _load(String url) async {
    try {
      final firebaseBytes = await _tryFirebaseStorageBytes(url);
      if (firebaseBytes != null && firebaseBytes.isNotEmpty) {
        _bytesByUrl[url] = firebaseBytes;
        return firebaseBytes;
      }

      try {
        final cachedFile = await DefaultCacheManager()
            .getFileFromCache(url)
            .timeout(const Duration(seconds: 3));
        final file = cachedFile?.file;
        if (file != null && await file.length() > 0) {
          final bytes = await file.readAsBytes();
          _bytesByUrl[url] = bytes;
          return bytes;
        }
      } catch (_) {}

      try {
        final cached = await DefaultCacheManager().getSingleFile(url).timeout(
          const Duration(seconds: 5),
        );
        if (await cached.length() > 0) {
          final bytes = await cached.readAsBytes();
          _bytesByUrl[url] = bytes;
          return bytes;
        }
      } catch (_) {}

      final response = await http.get(Uri.parse(url)).timeout(
            const Duration(seconds: 8),
          );
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        _bytesByUrl[url] = response.bodyBytes;
        return response.bodyBytes;
      }
    } catch (_) {}

    return null;
  }

  Future<Uint8List?> _tryFirebaseStorageBytes(String url) async {
    if (!url.contains('firebasestorage.googleapis.com')) {
      return null;
    }
    try {
      final ref = FirebaseStorage.instance.refFromURL(url);
      return ref.getData(8 * 1024 * 1024).timeout(const Duration(seconds: 5));
    } catch (_) {
      return null;
    }
  }
}
