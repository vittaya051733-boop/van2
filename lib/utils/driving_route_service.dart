import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../config/google_maps_web_api_key.dart';
import 'app_check_guard.dart';

enum DrivingRouteProvider { cloudFunction, googleDirections, osrm }

class DrivingRouteResult {
  const DrivingRouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.provider,
  });

  final List<LatLng> points;
  final int distanceMeters;
  final int durationSeconds;
  final DrivingRouteProvider provider;
}

class DrivingRouteFetchResult {
  const DrivingRouteFetchResult({
    this.route,
    this.failureMessage,
  });

  final DrivingRouteResult? route;
  final String? failureMessage;

  bool get isSuccess => route != null;
}

class DrivingRouteService {
  DrivingRouteService._();

  static const Duration _requestTimeout = Duration(seconds: 15);
  static const String _functionsRegion = 'asia-southeast1';

  static bool get isGoogleConfigured => effectiveGoogleMapsWebApiKey.isNotEmpty;

  static Future<DrivingRouteFetchResult> fetchDrivingRoute({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    final cloudResult = await _fetchFromCloudFunction(
      originLat: originLat,
      originLng: originLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
    );
    if (cloudResult != null) {
      return DrivingRouteFetchResult(route: cloudResult);
    }

    if (isGoogleConfigured) {
      final googleResult = await _fetchGoogleDirections(
        originLat: originLat,
        originLng: originLng,
        destinationLat: destinationLat,
        destinationLng: destinationLng,
      );
      if (googleResult.route != null) {
        return googleResult;
      }
    }

    final osrmResult = await _fetchOsrmRoute(
      originLat: originLat,
      originLng: originLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
    );
    if (osrmResult != null) {
      return DrivingRouteFetchResult(route: osrmResult);
    }

    return const DrivingRouteFetchResult(
      failureMessage: 'ไม่สามารถคำนวณเส้นทางตามถนนได้ กรุณาลองใหม่อีกครั้ง',
    );
  }

  static Future<DrivingRouteResult?> _fetchFromCloudFunction({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    if (FirebaseAuth.instance.currentUser == null) {
      return null;
    }

    try {
      await AppCheckGuard.ensureCheckoutReady();
      final callable = FirebaseFunctions.instanceFor(
        region: _functionsRegion,
      ).httpsCallable('computeRouteMetrics');

      final result = await callable
          .call(<String, Object>{
            'originLatitude': originLat,
            'originLongitude': originLng,
            'destinationLatitude': destinationLat,
            'destinationLongitude': destinationLng,
          })
          .timeout(_requestTimeout);

      final payload = result.data;
      if (payload is! Map) {
        return null;
      }

      final distanceMeters = payload['distanceMeters'];
      final durationSeconds = payload['durationSeconds'];
      final encodedPolyline = payload['encodedPolyline'];
      if (distanceMeters is! num ||
          durationSeconds is! num ||
          encodedPolyline is! String ||
          encodedPolyline.isEmpty) {
        return null;
      }

      final points = decodeEncodedPolyline(encodedPolyline);
      if (points.length < 2) {
        return null;
      }

      return DrivingRouteResult(
        points: points,
        distanceMeters: distanceMeters.round(),
        durationSeconds: durationSeconds.round(),
        provider: DrivingRouteProvider.cloudFunction,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<DrivingRouteFetchResult> _fetchGoogleDirections({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/directions/json',
      <String, String>{
        'origin': '$originLat,$originLng',
        'destination': '$destinationLat,$destinationLng',
        'mode': 'driving',
        'language': 'th',
        'region': 'th',
        'key': effectiveGoogleMapsWebApiKey,
      },
    );

    try {
      final response = await http.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) {
        return DrivingRouteFetchResult(
          failureMessage: 'Google Directions HTTP ${response.statusCode}',
        );
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        return const DrivingRouteFetchResult(
          failureMessage: 'Google Directions ตอบกลับไม่ถูกต้อง',
        );
      }

      final status = payload['status'];
      if (status != 'OK') {
        final errorMessage = payload['error_message'];
        return DrivingRouteFetchResult(
          failureMessage: errorMessage is String && errorMessage.isNotEmpty
              ? errorMessage
              : 'Google Directions: $status',
        );
      }

      final route = _parseGoogleDirectionsPayload(payload);
      if (route == null) {
        return const DrivingRouteFetchResult(
          failureMessage: 'Google Directions ไม่พบเส้นทาง',
        );
      }

      return DrivingRouteFetchResult(
        route: route.copyWithProvider(DrivingRouteProvider.googleDirections),
      );
    } catch (error) {
      return DrivingRouteFetchResult(
        failureMessage: 'Google Directions: $error',
      );
    }
  }

  static DrivingRouteResult? _parseGoogleDirectionsPayload(
    Map<String, dynamic> payload,
  ) {
    final routes = payload['routes'];
    if (routes is! List || routes.isEmpty) {
      return null;
    }

    final route = routes.first;
    if (route is! Map<String, dynamic>) {
      return null;
    }

    final overviewPolyline = route['overview_polyline'];
    if (overviewPolyline is! Map<String, dynamic>) {
      return null;
    }

    final encoded = overviewPolyline['points'];
    if (encoded is! String || encoded.isEmpty) {
      return null;
    }

    final legs = route['legs'];
    if (legs is! List || legs.isEmpty) {
      return null;
    }

    final leg = legs.first;
    if (leg is! Map<String, dynamic>) {
      return null;
    }

    final distance = leg['distance'];
    final duration = leg['duration'];
    final distanceMeters = distance is Map ? distance['value'] : null;
    final durationSeconds = duration is Map ? duration['value'] : null;

    if (distanceMeters is! num || durationSeconds is! num) {
      return null;
    }

    final points = decodeEncodedPolyline(encoded);
    if (points.length < 2) {
      return null;
    }

    return DrivingRouteResult(
      points: points,
      distanceMeters: distanceMeters.round(),
      durationSeconds: durationSeconds.round(),
      provider: DrivingRouteProvider.googleDirections,
    );
  }

  static Future<DrivingRouteResult?> _fetchOsrmRoute({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    final uri = Uri.https(
      'router.project-osrm.org',
      '/route/v1/driving/$originLng,$originLat;$destinationLng,$destinationLat',
      <String, String>{
        'overview': 'full',
        'geometries': 'polyline',
        'steps': 'false',
      },
    );

    try {
      final response = await http.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) {
        return null;
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        return null;
      }

      if (payload['code'] != 'Ok') {
        return null;
      }

      final routes = payload['routes'];
      if (routes is! List || routes.isEmpty) {
        return null;
      }

      final route = routes.first;
      if (route is! Map<String, dynamic>) {
        return null;
      }

      final encoded = route['geometry'];
      final distanceMeters = route['distance'];
      final durationSeconds = route['duration'];
      if (encoded is! String ||
          encoded.isEmpty ||
          distanceMeters is! num ||
          durationSeconds is! num) {
        return null;
      }

      final points = decodeEncodedPolyline(encoded);
      if (points.length < 2) {
        return null;
      }

      return DrivingRouteResult(
        points: points,
        distanceMeters: distanceMeters.round(),
        durationSeconds: durationSeconds.round(),
        provider: DrivingRouteProvider.osrm,
      );
    } catch (_) {
      return null;
    }
  }
}

extension _DrivingRouteResultProvider on DrivingRouteResult {
  DrivingRouteResult copyWithProvider(DrivingRouteProvider provider) {
    return DrivingRouteResult(
      points: points,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      provider: provider,
    );
  }
}

List<LatLng> decodeEncodedPolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  while (index < encoded.length) {
    var shift = 0;
    var result = 0;
    int byte;

    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    final deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lat += deltaLat;

    shift = 0;
    result = 0;

    do {
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);

    final deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
    lng += deltaLng;

    points.add(LatLng(lat / 1e5, lng / 1e5));
  }

  return points;
}
