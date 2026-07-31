import 'package:geolocator/geolocator.dart';

import '../services/rider_availability_service.dart';
import '../travel_vehicle_type.dart';

/// ไรเดอร์เปิดรับส่งของพร้อมพิกัดสด
bool isRiderDeliveryOnline(Map<String, dynamic> data) {
  if (data['onlineReady'] != true) {
    return false;
  }
  return isRiderTravelLocationFresh(data);
}

class RiderSliderItem {
  const RiderSliderItem({
    required this.entry,
    this.distanceKm,
  });

  final RiderAvailabilityEntry entry;
  final double? distanceKm;
}

double? riderDistanceKmFromReference({
  required Map<String, dynamic> data,
  required double? referenceLatitude,
  required double? referenceLongitude,
}) {
  if (referenceLatitude == null || referenceLongitude == null) {
    return null;
  }

  final latitude = _readRiderLatitude(data);
  final longitude = _readRiderLongitude(data);
  if (latitude == null || longitude == null) {
    return null;
  }
  if (latitude == 0.0 && longitude == 0.0) {
    return null;
  }

  final meters = Geolocator.distanceBetween(
    referenceLatitude,
    referenceLongitude,
    latitude,
    longitude,
  );
  return meters / 1000.0;
}

double? _readRiderLatitude(Map<String, dynamic> data) {
  final geo = data['currentLocation'];
  if (geo is Map) {
    return _parseDouble(geo['latitude']) ?? _parseDouble(geo['lat']);
  }
  return _parseDouble(data['latitude']) ?? _parseDouble(data['lat']);
}

double? _readRiderLongitude(Map<String, dynamic> data) {
  final geo = data['currentLocation'];
  if (geo is Map) {
    return _parseDouble(geo['longitude']) ?? _parseDouble(geo['lng']);
  }
  return _parseDouble(data['longitude']) ?? _parseDouble(data['lng']);
}

double? _parseDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

List<RiderSliderItem> buildDeliverySliderItems({
  required Iterable<RiderAvailabilityEntry> entries,
  double? referenceLatitude,
  double? referenceLongitude,
}) {
  final items = <RiderSliderItem>[];
  for (final entry in entries) {
    if (!isRiderDeliveryOnline(entry.data)) {
      continue;
    }
    items.add(
      RiderSliderItem(
        entry: entry,
        distanceKm: riderDistanceKmFromReference(
          data: entry.data,
          referenceLatitude: referenceLatitude,
          referenceLongitude: referenceLongitude,
        ),
      ),
    );
  }

  items.sort((RiderSliderItem a, RiderSliderItem b) {
    final aDistance = a.distanceKm;
    final bDistance = b.distanceKm;
    if (aDistance != null && bDistance != null) {
      return aDistance.compareTo(bDistance);
    }
    if (aDistance != null) {
      return -1;
    }
    if (bDistance != null) {
      return 1;
    }
    return a.entry.riderId.compareTo(b.entry.riderId);
  });

  return items;
}

List<RiderSliderItem> buildTravelSliderItems({
  required Iterable<RiderAvailabilityEntry> entries,
  required TravelVehicleType vehicleType,
  double? referenceLatitude,
  double? referenceLongitude,
}) {
  final items = <RiderSliderItem>[];
  for (final entry in entries) {
    final data = entry.data;
    if (!isRiderAvailableForTravel(data)) {
      continue;
    }
    if (readRiderTravelVehicleType(data) != vehicleType) {
      continue;
    }
    items.add(
      RiderSliderItem(
        entry: entry,
        distanceKm: riderDistanceKmFromReference(
          data: data,
          referenceLatitude: referenceLatitude,
          referenceLongitude: referenceLongitude,
        ),
      ),
    );
  }

  items.sort((RiderSliderItem a, RiderSliderItem b) {
    final aDistance = a.distanceKm;
    final bDistance = b.distanceKm;
    if (aDistance != null && bDistance != null) {
      return aDistance.compareTo(bDistance);
    }
    if (aDistance != null) {
      return -1;
    }
    if (bDistance != null) {
      return 1;
    }
    return a.entry.riderId.compareTo(b.entry.riderId);
  });

  return items;
}

String readRiderDisplayLabel(Map<String, dynamic> data) {
  final displayName = (data['displayName'] as String?)?.trim();
  if (displayName != null && displayName.isNotEmpty) {
    return displayName;
  }
  return 'ไรเดอร์';
}

String? readRiderVehicleLabel(Map<String, dynamic> data) {
  final vehicleType = readRiderTravelVehicleType(data);
  return vehicleType?.label;
}

String formatDistanceKm(double? distanceKm) {
  if (distanceKm == null) {
    return 'ระยะไม่ทราบ';
  }
  if (distanceKm < 1) {
    return '${(distanceKm * 1000).round()} ม.';
  }
  return '${distanceKm.toStringAsFixed(1)} กม.';
}
