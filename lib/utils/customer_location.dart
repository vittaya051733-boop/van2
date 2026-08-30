import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../map_picker_screen.dart';

Future<PickedLocation> buildPickedLocation({
  required double latitude,
  required double longitude,
  required String fallbackTitle,
}) async {
  try {
    final placemarks = await placemarkFromCoordinates(latitude, longitude);
    if (placemarks.isNotEmpty) {
      final place = placemarks.first;
      final titleParts = <String>[
        if ((place.name ?? '').trim().isNotEmpty) place.name!.trim(),
        if ((place.subLocality ?? '').trim().isNotEmpty)
          place.subLocality!.trim(),
      ];
      final subtitleParts = <String>[
        if ((place.locality ?? '').trim().isNotEmpty) place.locality!.trim(),
        if ((place.administrativeArea ?? '').trim().isNotEmpty)
          place.administrativeArea!.trim(),
        if ((place.country ?? '').trim().isNotEmpty) place.country!.trim(),
      ];

      return PickedLocation(
        latitude: latitude,
        longitude: longitude,
        title: titleParts.isEmpty ? fallbackTitle : titleParts.join(', '),
        subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(', '),
      );
    }
  } catch (_) {
    // Fall back to coordinates when reverse geocoding is unavailable.
  }

  return PickedLocation(
    latitude: latitude,
    longitude: longitude,
    title: fallbackTitle,
  );
}

/// คงข้อความที่ผู้ใช้ค้นหาเป็นชื่อหลัก — ใช้ reverse geocode แค่เป็นคำอธิบายเพิ่ม
Future<PickedLocation> buildPickedLocationFromSearch({
  required double latitude,
  required double longitude,
  required String searchQuery,
}) async {
  final trimmedQuery = searchQuery.trim();
  final resolved = await buildPickedLocation(
    latitude: latitude,
    longitude: longitude,
    fallbackTitle: trimmedQuery,
  );

  final resolvedLabel = resolved.subtitle == null ||
          resolved.subtitle!.trim().isEmpty
      ? resolved.title.trim()
      : '${resolved.title.trim()}, ${resolved.subtitle!.trim()}';

  final subtitle = resolvedLabel.toLowerCase() == trimmedQuery.toLowerCase()
      ? resolved.subtitle
      : resolvedLabel;

  return PickedLocation(
    latitude: latitude,
    longitude: longitude,
    title: trimmedQuery,
    subtitle: subtitle == null || subtitle.trim().isEmpty
        ? null
        : subtitle.trim(),
  );
}

Future<PickedLocation?> tryDetectCurrentLocation() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    return null;
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      return null;
    }
  }

  if (permission == LocationPermission.deniedForever) {
    return null;
  }

  if (!kIsWeb) {
    final lastKnown = await Geolocator.getLastKnownPosition();
    if (lastKnown != null) {
      return buildPickedLocation(
        latitude: lastKnown.latitude,
        longitude: lastKnown.longitude,
        fallbackTitle: 'พิกัดล่าสุดของฉัน',
      );
    }
  }

  final position = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.medium,
      timeLimit: Duration(seconds: 15),
    ),
  );

  return buildPickedLocation(
    latitude: position.latitude,
    longitude: position.longitude,
    fallbackTitle: 'พิกัดปัจจุบันของฉัน',
  );
}

/// Placeholder location so home can paint before geolocation finishes.
PickedLocation startupFallbackLocation() {
  return const PickedLocation(
    latitude: 17.279915312140325,
    longitude: 102.87070264132565,
    title: 'อุดรธานี',
    subtitle: 'จะอัปเดตเมื่อได้รับพิกัดจากอุปกรณ์',
  );
}
