import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Defines storage buckets so different media types are separated on disk.
enum MediaCacheBucket {
  image,
  thumbnail,
  video,
  videoThumbnail,
}

/// Simple local cache that maps remote media URLs to files stored on-device.
class MediaCacheService {
  MediaCacheService._();

  static final MediaCacheService instance = MediaCacheService._();

  static const String _indexKey = 'media_cache_index_v1';

  final Map<String, String> _index = <String, String>{};
  bool _indexLoaded = false;

  Future<File?> cacheUploadedFile({
    required File source,
    required String url,
    required MediaCacheBucket bucket,
  }) async {
    if (url.isEmpty) return null;
    try {
      final targetDir = await _ensureBucketDir(bucket);
      final extension = p.extension(source.path).isNotEmpty
          ? p.extension(source.path)
          : '.bin';
      final hashedName = _hashUrl(url);
      final targetPath = p.join(targetDir.path, '$hashedName$extension');
      final cachedFile = await source.copy(targetPath);
      await _updateIndex(url, cachedFile.path);
      return cachedFile;
    } catch (_) {
      return null;
    }
  }

  Future<String?> getCachedPath(String url) async {
    if (url.isEmpty) return null;
    await _ensureIndexLoaded();
    final existingPath = _index[url];
    if (existingPath == null) return null;
    final file = File(existingPath);
    if (await file.exists()) {
      return file.path;
    }
    _index.remove(url);
    await _persistIndex();
    return null;
  }

  Future<void> remove(String url) async {
    if (url.isEmpty) return;
    await _ensureIndexLoaded();
    final existingPath = _index.remove(url);
    if (existingPath != null) {
      final file = File(existingPath);
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (_) {
          // Ignore local cache cleanup failures.
        }
      }
    }
    await _persistIndex();
  }

  Future<void> clear() async {
    _index.clear();
    _indexLoaded = true;
    final baseDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(baseDir.path, 'media_cache'));
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_indexKey);
  }

  Future<void> _ensureIndexLoaded() async {
    if (_indexLoaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_indexKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _index
          ..clear()
          ..addEntries(
            decoded.entries.map(
              (entry) => MapEntry(entry.key, entry.value as String),
            ),
          );
      } catch (_) {
        await prefs.remove(_indexKey);
        _index.clear();
      }
    }
    _indexLoaded = true;
  }

  Future<void> _updateIndex(String url, String path) async {
    await _ensureIndexLoaded();
    _index[url] = path;
    await _persistIndex();
  }

  Future<void> _persistIndex() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_indexKey, jsonEncode(_index));
  }

  Future<Directory> _ensureBucketDir(MediaCacheBucket bucket) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final dir = Directory(
      p.join(baseDir.path, 'media_cache', _bucketName(bucket)),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _bucketName(MediaCacheBucket bucket) {
    switch (bucket) {
      case MediaCacheBucket.image:
        return 'images';
      case MediaCacheBucket.thumbnail:
        return 'thumbnails';
      case MediaCacheBucket.video:
        return 'videos';
      case MediaCacheBucket.videoThumbnail:
        return 'video_thumbnails';
    }
  }

  String _hashUrl(String url) {
    final encoded = base64Url.encode(utf8.encode(url));
    return encoded.replaceAll('=', '');
  }
}
