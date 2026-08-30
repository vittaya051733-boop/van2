import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../public_catalog_local_cache.dart';
import 'locale_service.dart';

/// Fetches and caches English product fields via Cloud Function + Firestore.
class ProductTranslationService extends ChangeNotifier {
  ProductTranslationService._();

  static final ProductTranslationService instance = ProductTranslationService._();

  static const String _region = 'asia-southeast1';
  static const int _maxConcurrent = 4;
  static const Duration _notifyDebounce = Duration(milliseconds: 120);

  final Set<String> _inFlight = <String>{};
  final Set<String> _queuedIds = <String>{};
  final List<_TranslationJob> _waitQueue = <_TranslationJob>[];
  final Map<String, Map<String, String>> _runtimeCache =
      <String, Map<String, String>>{};

  int _activeRequests = 0;
  Timer? _notifyTimer;
  bool _notifyPending = false;

  Map<String, String>? runtimeFields(String productId) => _runtimeCache[productId];

  void clearRuntimeCache() {
    if (_runtimeCache.isEmpty) {
      return;
    }
    _runtimeCache.clear();
  }

  Future<Map<String, String>?> ensureEnglish({
    required String productId,
    Map<String, dynamic>? data,
  }) async {
    if (!LocaleService.instance.isEnglish) {
      return null;
    }

    final trimmedId = productId.trim();
    if (trimmedId.isEmpty) {
      return null;
    }

    final cached = _runtimeCache[trimmedId];
    if (_hasEnglishFields(cached)) {
      return cached;
    }

    if (data != null && _hasEnglishFields(_fieldsFromData(data))) {
      final fields = _fieldsFromData(data)!;
      _runtimeCache[trimmedId] = fields;
      return fields;
    }

    await PublicCatalogLocalCache.ensureProductsHydrated();
    final diskData = PublicCatalogLocalCache.productsById[trimmedId];
    if (diskData != null && _hasEnglishFields(_fieldsFromData(diskData))) {
      final fields = _fieldsFromData(diskData)!;
      _runtimeCache[trimmedId] = fields;
      return fields;
    }

    if (_inFlight.contains(trimmedId)) {
      return _runtimeCache[trimmedId];
    }

    final completer = Completer<Map<String, String>?>();
    _waitQueue.add(
      _TranslationJob(
        productId: trimmedId,
        data: data,
        completer: completer,
      ),
    );
    _drainQueue();
    return completer.future;
  }

  void scheduleEnsureEnglish({
    required String productId,
    Map<String, dynamic>? data,
  }) {
    if (!LocaleService.instance.isEnglish) {
      return;
    }

    final trimmedId = productId.trim();
    if (trimmedId.isEmpty) {
      return;
    }
    if (_queuedIds.contains(trimmedId) ||
        _inFlight.contains(trimmedId) ||
        _hasEnglishFields(_runtimeCache[trimmedId])) {
      return;
    }
    if (data != null && _needsTranslation(data) == false) {
      final fields = _fieldsFromData(data);
      if (fields != null) {
        _runtimeCache[trimmedId] = fields;
      }
      return;
    }

    final diskData = PublicCatalogLocalCache.productsById[trimmedId];
    if (diskData != null && _needsTranslation(diskData) == false) {
      final fields = _fieldsFromData(diskData);
      if (fields != null) {
        _runtimeCache[trimmedId] = fields;
      }
      return;
    }

    _queuedIds.add(trimmedId);
    unawaited(
      ensureEnglish(productId: trimmedId, data: data).whenComplete(() {
        _queuedIds.remove(trimmedId);
      }),
    );
  }

  void _drainQueue() {
    while (_activeRequests < _maxConcurrent && _waitQueue.isNotEmpty) {
      final job = _waitQueue.removeAt(0);
      if (_inFlight.contains(job.productId)) {
        if (!job.completer.isCompleted) {
          job.completer.complete(_runtimeCache[job.productId]);
        }
        continue;
      }
      _activeRequests++;
      unawaited(_runJob(job));
    }
  }

  Future<void> _runJob(_TranslationJob job) async {
    _inFlight.add(job.productId);
    Map<String, String>? fields;
    try {
      fields = await _fetchTranslation(job.productId);
      if (fields != null && fields.isNotEmpty) {
        _runtimeCache[job.productId] = fields;
        _mergeIntoLocalCatalog(job.productId, fields, job.data);
        _scheduleNotifyListeners();
      }
      if (!job.completer.isCompleted) {
        job.completer.complete(fields);
      }
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint(
          'ensureProductTranslation failed for ${job.productId}: $error',
        );
        debugPrint('$stackTrace');
      }
      if (!job.completer.isCompleted) {
        job.completer.complete(null);
      }
    } finally {
      _inFlight.remove(job.productId);
      _activeRequests--;
      _drainQueue();
    }
  }

  Future<Map<String, String>?> _fetchTranslation(String productId) async {
    final callable = FirebaseFunctions.instanceFor(
      region: _region,
    ).httpsCallable('ensureProductTranslation');
    final result = await callable.call(<String, dynamic>{
      'productId': productId,
    });
    final payload = Map<String, dynamic>.from(result.data as Map);
    final fields = <String, String>{
      if (payload['nameEn'] != null)
        'nameEn': payload['nameEn'].toString().trim(),
      if (payload['descriptionEn'] != null)
        'descriptionEn': payload['descriptionEn'].toString().trim(),
    };
    return fields.isEmpty ? null : fields;
  }

  void _mergeIntoLocalCatalog(
    String productId,
    Map<String, String> fields,
    Map<String, dynamic>? sourceData,
  ) {
    final existing = Map<String, dynamic>.from(
      PublicCatalogLocalCache.productsById[productId] ??
          Map<String, dynamic>.from(sourceData ?? const <String, dynamic>{}),
    );
    existing.addAll(fields);
    existing['id'] = productId;
    PublicCatalogLocalCache.applyProductDoc(productId, existing);
  }

  void _scheduleNotifyListeners() {
    _notifyPending = true;
    _notifyTimer ??= Timer(_notifyDebounce, () {
      _notifyTimer = null;
      if (!_notifyPending) {
        return;
      }
      _notifyPending = false;
      notifyListeners();
    });
  }

  static bool _needsTranslation(Map<String, dynamic> data) {
    final hasName = (data['nameEn']?.toString().trim() ?? '').isNotEmpty;
    if (!hasName) {
      return true;
    }
    final sourceDescription = data['description']?.toString().trim() ?? '';
    if (sourceDescription.isEmpty) {
      return false;
    }
    return (data['descriptionEn']?.toString().trim() ?? '').isEmpty;
  }

  static bool _hasEnglishFields(Map<String, String>? fields) {
    final nameEn = fields?['nameEn']?.trim();
    return nameEn != null && nameEn.isNotEmpty;
  }

  static Map<String, String>? _fieldsFromData(Map<String, dynamic> data) {
    final nameEn = data['nameEn']?.toString().trim() ?? '';
    final descriptionEn = data['descriptionEn']?.toString().trim() ?? '';
    if (nameEn.isEmpty && descriptionEn.isEmpty) {
      return null;
    }
    return <String, String>{
      if (nameEn.isNotEmpty) 'nameEn': nameEn,
      if (descriptionEn.isNotEmpty) 'descriptionEn': descriptionEn,
    };
  }
}

class _TranslationJob {
  _TranslationJob({
    required this.productId,
    required this.completer,
    this.data,
  });

  final String productId;
  final Map<String, dynamic>? data;
  final Completer<Map<String, String>?> completer;
}
