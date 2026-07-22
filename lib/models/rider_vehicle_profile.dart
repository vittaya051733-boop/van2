import 'package:cloud_firestore/cloud_firestore.dart';

import '../travel_vehicle_type.dart';

class RiderVehicleProfile {
  const RiderVehicleProfile({
    required this.riderId,
    required this.displayName,
    this.profilePhotoUrl,
    this.phoneNumber,
    this.rating,
    this.licensePlate,
    this.vehicleColor,
    this.vehicleBrandModel,
    this.vehicleType,
    this.isElectricVehicle = false,
    this.latitude,
    this.longitude,
  });

  final String riderId;
  final String displayName;
  final String? profilePhotoUrl;
  final String? phoneNumber;
  final double? rating;
  final String? licensePlate;
  final String? vehicleColor;
  final String? vehicleBrandModel;
  final TravelVehicleType? vehicleType;
  final bool isElectricVehicle;
  final double? latitude;
  final double? longitude;

  factory RiderVehicleProfile.fromFirestore(
    String riderId,
    Map<String, dynamic>? data,
  ) {
    final map = data ?? const <String, dynamic>{};
    return RiderVehicleProfile(
      riderId: riderId,
      displayName: (map['displayName'] as String?)?.trim().isNotEmpty == true
          ? (map['displayName'] as String).trim()
          : 'ไรเดอร์',
      profilePhotoUrl: _readPhotoUrl(map),
      phoneNumber: (map['phoneNumber'] ?? map['phone'])?.toString(),
      rating: (map['rating'] as num?)?.toDouble(),
      licensePlate: (map['licensePlate'] as String?)?.trim(),
      vehicleColor: (map['vehicleColor'] as String?)?.trim(),
      vehicleBrandModel: (map['vehicleBrandModel'] as String?)?.trim(),
      vehicleType: _readVehicleType(map),
      isElectricVehicle: map['isElectricVehicle'] == true,
      latitude: _readCoordinate(map, isLatitude: true),
      longitude: _readCoordinate(map, isLatitude: false),
    );
  }

  static String? _readPhotoUrl(Map<String, dynamic> map) {
    for (final key in <String>[
      'profilePhotoUrl',
      'photoUrl',
      'imageUrl',
    ]) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static TravelVehicleType? _readVehicleType(Map<String, dynamic> map) {
    return readRiderTravelVehicleType(map);
  }

  static double? _readCoordinate(
    Map<String, dynamic> map, {
    required bool isLatitude,
  }) {
    final geo = map['currentLocation'];
    if (geo is GeoPoint) {
      return isLatitude ? geo.latitude : geo.longitude;
    }
    final key = isLatitude ? 'latitude' : 'longitude';
    final value = map[key];
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  String get vehicleSummary {
    final parts = <String>[
      if (vehicleColor?.isNotEmpty == true) vehicleColor!,
      if (vehicleBrandModel?.isNotEmpty == true) vehicleBrandModel!,
    ];
    if (parts.isEmpty) {
      return vehicleType?.label ?? 'ยานพาหนะ';
    }
    return parts.join(' • ');
  }

  bool get hasCoordinates =>
      latitude != null &&
      longitude != null &&
      !(latitude == 0 && longitude == 0);
}
