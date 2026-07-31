import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Lightweight rider row from [system/rider_availability] pool.
class RiderAvailabilityEntry {
  const RiderAvailabilityEntry({
    required this.riderId,
    required this.data,
  });

  final String riderId;
  final Map<String, dynamic> data;
}

class RiderPoolSnapshot {
  const RiderPoolSnapshot({
    required this.deliveryOnlineCount,
    required this.deliveryRiders,
    required this.travelVehicleCounts,
    required this.travelRiders,
  });

  static const empty = RiderPoolSnapshot(
    deliveryOnlineCount: 0,
    deliveryRiders: <String, Map<String, dynamic>>{},
    travelVehicleCounts: <String, int>{},
    travelRiders: <String, Map<String, dynamic>>{},
  );

  final int deliveryOnlineCount;
  final Map<String, Map<String, dynamic>> deliveryRiders;
  final Map<String, int> travelVehicleCounts;
  final Map<String, Map<String, dynamic>> travelRiders;
}

/// Single app-wide pool doc — replaces per-screen riders collection listeners.
class RiderAvailabilityService {
  RiderAvailabilityService._();

  static final RiderAvailabilityService instance = RiderAvailabilityService._();

  static const String _poolDocPath = 'system/rider_availability';
  static const Duration _resubscribeDelay = Duration(seconds: 3);

  Stream<RiderPoolSnapshot>? _poolBroadcastStream;
  StreamController<RiderPoolSnapshot>? _poolController;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _poolSub;
  StreamSubscription<User?>? _authSub;
  bool _resubscribeScheduled = false;
  bool _warmStarted = false;
  RiderPoolSnapshot? _lastPool;

  /// Last known pool — instant UI before Firestore round-trip.
  RiderPoolSnapshot? get peekPool => _lastPool;

  int get peekDeliveryOnlineCount =>
      _lastPool?.deliveryOnlineCount ?? 0;

  Map<String, int> get peekTravelVehicleCounts =>
      Map<String, int>.from(_lastPool?.travelVehicleCounts ?? const {});

  List<RiderAvailabilityEntry> get peekDeliveryRiderEntries =>
      _deliveryEntriesFromPool(_lastPool ?? RiderPoolSnapshot.empty);

  List<RiderAvailabilityEntry> get peekTravelRiderEntries =>
      _travelEntriesFromPool(_lastPool ?? RiderPoolSnapshot.empty);

  Stream<RiderPoolSnapshot> watchPool() {
    _ensurePoolSubscription();
    final live = _poolBroadcastStream!;
    final cached = _lastPool;
    if (cached == null) {
      return live;
    }
    return Stream.multi((controller) {
      controller.add(cached);
      final sub = live.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
      controller.onCancel = sub.cancel;
    });
  }

  Stream<int> watchOnlineDeliveryCount() {
    return watchPool().map((pool) => pool.deliveryOnlineCount);
  }

  Stream<Map<String, int>> watchTravelVehicleCounts() {
    return watchPool().map((pool) => pool.travelVehicleCounts);
  }

  Stream<List<RiderAvailabilityEntry>> watchDeliveryRiderEntries() {
    return watchPool().map(_deliveryEntriesFromPool);
  }

  Stream<List<RiderAvailabilityEntry>> watchTravelRiderEntries() {
    return watchPool().map(_travelEntriesFromPool);
  }

  Future<List<RiderAvailabilityEntry>> fetchDeliveryRiderEntries() async {
    try {
      final snapshot = await FirebaseFirestore.instance.doc(_poolDocPath).get();
      return _deliveryEntriesFromPool(_parsePool(snapshot.data()));
    } catch (_) {
      return peekDeliveryRiderEntries;
    }
  }

  Future<List<RiderAvailabilityEntry>> fetchTravelRiderEntries() async {
    try {
      final snapshot = await FirebaseFirestore.instance.doc(_poolDocPath).get();
      return _travelEntriesFromPool(_parsePool(snapshot.data()));
    } catch (_) {
      return peekTravelRiderEntries;
    }
  }

  /// Prefetch pool during app startup (after sign-in) so travel/cart screens paint fast.
  Future<void> warmUp() async {
    if (_warmStarted && _lastPool != null) {
      return;
    }
    _warmStarted = true;
    _ensurePoolSubscription();

    if (FirebaseAuth.instance.currentUser == null) {
      _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          unawaited(_prefetchPoolDocument());
        }
      });
      return;
    }

    await _prefetchPoolDocument();
  }

  Future<void> _prefetchPoolDocument() async {
    final docRef = FirebaseFirestore.instance.doc(_poolDocPath);

    try {
      final cached = await docRef.get(const GetOptions(source: Source.cache));
      if (cached.exists) {
        _publishPool(_parsePool(cached.data()));
      }
    } catch (_) {
      // No local cache yet.
    }

    try {
      final fresh = await docRef.get(const GetOptions(source: Source.server));
      if (fresh.exists) {
        _publishPool(_parsePool(fresh.data()));
      }
    } catch (_) {
      // Realtime listener still updates when online.
    }
  }

  void _ensurePoolSubscription() {
    if (_poolSub != null) {
      return;
    }
    _poolController ??= StreamController<RiderPoolSnapshot>.broadcast();
    _poolBroadcastStream ??= _poolController!.stream;
    _attachPoolListener();
  }

  void _attachPoolListener() {
    _poolSub?.cancel();
    _poolSub = FirebaseFirestore.instance.doc(_poolDocPath).snapshots().listen(
      (snapshot) {
        _publishPool(_parsePool(snapshot.data()));
      },
      onError: (Object error, StackTrace stackTrace) {
        _poolController?.addError(error, stackTrace);
        _schedulePoolResubscribe();
      },
      onDone: () {
        _poolSub = null;
        _schedulePoolResubscribe();
      },
    );
  }

  void _publishPool(RiderPoolSnapshot pool) {
    _lastPool = pool;
    if (_poolController != null && !_poolController!.isClosed) {
      _poolController!.add(pool);
    }
  }

  void _schedulePoolResubscribe() {
    if (_resubscribeScheduled || _poolController == null) {
      return;
    }
    _resubscribeScheduled = true;
    unawaited(
      Future<void>.delayed(_resubscribeDelay, () {
        _resubscribeScheduled = false;
        if (_poolController == null || _poolController!.isClosed) {
          return;
        }
        _attachPoolListener();
      }),
    );
  }

  List<RiderAvailabilityEntry> _entriesFromMap(
    Map<String, Map<String, dynamic>> riders,
  ) {
    return riders.entries
        .map(
          (entry) => RiderAvailabilityEntry(
            riderId: entry.key,
            data: Map<String, dynamic>.from(entry.value),
          ),
        )
        .toList(growable: false);
  }

  List<RiderAvailabilityEntry> _deliveryEntriesFromPool(RiderPoolSnapshot pool) {
    return _entriesFromMap(pool.deliveryRiders);
  }

  List<RiderAvailabilityEntry> _travelEntriesFromPool(RiderPoolSnapshot pool) {
    return _entriesFromMap(pool.travelRiders);
  }

  Map<String, Map<String, dynamic>> _parseRiderMap(Object? raw) {
    final riders = <String, Map<String, dynamic>>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final value = entry.value;
        if (value is Map) {
          riders['${entry.key}'] = Map<String, dynamic>.from(value);
        }
      }
    }
    return riders;
  }

  RiderPoolSnapshot _parsePool(Map<String, dynamic>? raw) {
    if (raw == null || raw.isEmpty) {
      return RiderPoolSnapshot.empty;
    }

    final travelCountsRaw = raw['travelVehicleCounts'];
    final travelCounts = <String, int>{};
    if (travelCountsRaw is Map) {
      for (final entry in travelCountsRaw.entries) {
        final count = entry.value;
        if (count is num) {
          travelCounts['${entry.key}'] = count.toInt();
        }
      }
    }

    final deliveryRiders = _parseRiderMap(raw['deliveryRiders']);
    final travelRiders = _parseRiderMap(raw['travelRiders']);

    final deliveryCount = raw['deliveryOnlineCount'];
    return RiderPoolSnapshot(
      deliveryOnlineCount: deliveryCount is num
          ? deliveryCount.toInt()
          : deliveryRiders.length,
      deliveryRiders: deliveryRiders,
      travelVehicleCounts: travelCounts,
      travelRiders: travelRiders,
    );
  }
}
