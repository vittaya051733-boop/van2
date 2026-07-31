import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'services/rider_availability_service.dart';

enum TravelVehicleType { motorcycle, sedan, pickup }

extension TravelVehicleTypePresentation on TravelVehicleType {
  String get wireValue => name;

  String get label {
    switch (this) {
      case TravelVehicleType.motorcycle:
        return 'มอเตอร์ไซค์';
      case TravelVehicleType.sedan:
        return 'รถเก๋ง';
      case TravelVehicleType.pickup:
        return 'รถกระบะ';
    }
  }

  IconData get icon {
    switch (this) {
      case TravelVehicleType.motorcycle:
        return Icons.two_wheeler;
      case TravelVehicleType.sedan:
        return Icons.directions_car_filled_rounded;
      case TravelVehicleType.pickup:
        return Icons.local_shipping_rounded;
    }
  }

  /// Compact map pin icon (scooter-style for motorcycle).
  IconData get mapMarkerIcon {
    switch (this) {
      case TravelVehicleType.motorcycle:
        return Icons.moped;
      case TravelVehicleType.sedan:
        return Icons.directions_car_filled_rounded;
      case TravelVehicleType.pickup:
        return Icons.local_shipping_rounded;
    }
  }

  Color get accentColor {
    switch (this) {
      case TravelVehicleType.motorcycle:
        return const Color(0xFF16A34A);
      case TravelVehicleType.sedan:
        return const Color(0xFF2563EB);
      case TravelVehicleType.pickup:
        return const Color(0xFFB45309);
    }
  }
}

/// ไรเดอร์ที่เปิดรับผู้โดยสาร หรือเปิดรับส่งของพร้อมมีพิกัด — ใช้แสดงจำนวนรถเดินทาง
bool isRiderAvailableForTravel(Map<String, dynamic> data) {
  if (data['passengerReady'] == true || data['onlineReady'] == true) {
    return isRiderTravelLocationFresh(data);
  }
  return false;
}

bool isRiderTravelLocationFresh(Map<String, dynamic> data) {
  final locationStatus =
      (data['locationStatus'] as String?)?.trim().toLowerCase();
  if (locationStatus == 'offline') {
    return false;
  }

  final latitude = _readRiderLatitude(data);
  final longitude = _readRiderLongitude(data);
  if (latitude == null || longitude == null) {
    return false;
  }
  if (latitude == 0.0 && longitude == 0.0) {
    return false;
  }

  final updatedAtRaw = data['locationUpdatedAt'] ?? data['updatedAt'];
  final updatedAt = updatedAtRaw is Timestamp ? updatedAtRaw.toDate() : null;
  if (updatedAt == null) {
    return true;
  }

  return DateTime.now().difference(updatedAt).inMinutes <= 10;
}

double? _readRiderLatitude(Map<String, dynamic> data) {
  final geo = data['currentLocation'];
  if (geo is GeoPoint) {
    return geo.latitude;
  }
  if (geo is Map) {
    return _travelParseDouble(geo['latitude']) ?? _travelParseDouble(geo['lat']);
  }
  return _travelParseDouble(data['latitude']) ?? _travelParseDouble(data['lat']);
}

double? _readRiderLongitude(Map<String, dynamic> data) {
  final geo = data['currentLocation'];
  if (geo is GeoPoint) {
    return geo.longitude;
  }
  if (geo is Map) {
    return _travelParseDouble(geo['longitude']) ?? _travelParseDouble(geo['lng']);
  }
  return _travelParseDouble(data['longitude']) ?? _travelParseDouble(data['lng']);
}

double? _travelParseDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

TravelVehicleType? readTravelOrderVehicleType(Map<String, dynamic> orderData) {
  final travelRequest = orderData['travelRequest'];
  if (travelRequest is! Map) {
    return null;
  }

  final raw = travelRequest['vehicleType']?.toString().trim().toLowerCase();
  if (raw == null || raw.isEmpty) {
    return null;
  }

  for (final vehicleType in TravelVehicleType.values) {
    if (vehicleType.wireValue == raw) {
      return vehicleType;
    }
  }

  return readRiderTravelVehicleType(<String, dynamic>{'vehicleType': raw});
}

TravelVehicleType? readRiderTravelVehicleType(Map<String, dynamic> data) {
  final rawCandidates = <String?>[
    data['vehicleType']?.toString(),
    data['vehicle_type']?.toString(),
    data['vehicle']?.toString(),
    data['vehicleCategory']?.toString(),
    data['vehicleBrandModel']?.toString(),
    data['vehicleName']?.toString(),
  ];

  for (final rawValue in rawCandidates) {
    final normalized = rawValue?.trim().toLowerCase() ?? '';
    if (normalized.isEmpty) {
      continue;
    }

    if (normalized.contains('motor') ||
        normalized.contains('bike') ||
        normalized.contains('motorcycle') ||
        normalized.contains('มอเตอร์')) {
      return TravelVehicleType.motorcycle;
    }

    if (normalized.contains('pickup') ||
        normalized.contains('truck') ||
        normalized.contains('กระบะ')) {
      return TravelVehicleType.pickup;
    }

    if (normalized.contains('sedan') ||
        normalized.contains('car') ||
        normalized.contains('เก๋ง')) {
      return TravelVehicleType.sedan;
    }

    switch (normalized) {
      case 'motorcycle':
      case 'bike':
      case 'motorbike':
        return TravelVehicleType.motorcycle;
      case 'sedan':
        return TravelVehicleType.sedan;
      case 'pickup':
        return TravelVehicleType.pickup;
    }
  }

  if (isRiderAvailableForTravel(data)) {
    return TravelVehicleType.motorcycle;
  }

  return null;
}

Map<TravelVehicleType, int> countOnlineTravelVehicles(
  Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
) {
  final counts = <TravelVehicleType, int>{
    for (final vehicle in TravelVehicleType.values) vehicle: 0,
  };

  for (final doc in docs) {
    final data = doc.data();
    if (!isRiderAvailableForTravel(data)) {
      continue;
    }

    final vehicleType = readRiderTravelVehicleType(data);
    if (vehicleType == null) {
      continue;
    }

    counts[vehicleType] = (counts[vehicleType] ?? 0) + 1;
  }

  return counts;
}

Map<TravelVehicleType, int> parseTravelVehicleCounts(Map<String, int> raw) {
  int readCount(String key) => raw[key] ?? 0;
  return <TravelVehicleType, int>{
    TravelVehicleType.motorcycle: readCount('motorcycle'),
    TravelVehicleType.sedan: readCount('sedan'),
    TravelVehicleType.pickup: readCount('pickup'),
  };
}

Map<TravelVehicleType, int> countOnlineTravelVehiclesFromEntries(
  Iterable<RiderAvailabilityEntry> entries,
) {
  final counts = <TravelVehicleType, int>{
    for (final vehicle in TravelVehicleType.values) vehicle: 0,
  };

  for (final entry in entries) {
    final data = entry.data;
    if (!isRiderAvailableForTravel(data)) {
      continue;
    }

    final vehicleType = readRiderTravelVehicleType(data);
    if (vehicleType == null) {
      continue;
    }

    counts[vehicleType] = (counts[vehicleType] ?? 0) + 1;
  }

  return counts;
}

Stream<Map<TravelVehicleType, int>> watchTravelVehicleCounts() {
  return RiderAvailabilityService.instance.watchTravelVehicleCounts().map(
    parseTravelVehicleCounts,
  );
}

Map<TravelVehicleType, int> peekTravelVehicleCounts() {
  return parseTravelVehicleCounts(
    RiderAvailabilityService.instance.peekTravelVehicleCounts,
  );
}

Stream<List<RiderAvailabilityEntry>> watchTravelAvailableRiders() {
  return RiderAvailabilityService.instance.watchTravelRiderEntries();
}

Future<List<RiderAvailabilityEntry>> fetchTravelAvailableRiders() async {
  return RiderAvailabilityService.instance.fetchTravelRiderEntries();
}
