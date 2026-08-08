import 'dart:js_interop';
import 'dart:js_util' as js_util;

import 'package:google_maps_flutter/google_maps_flutter.dart';

@JS('vanTravelShowRoute')
external JSPromise _vanTravelShowRoute(
  JSNumber originLat,
  JSNumber originLng,
  JSNumber destLat,
  JSNumber destLng,
  JSAny? routePoints,
);

@JS('vanTravelClearDirectionsRoute')
external void _vanTravelClearDirectionsRoute();

Future<bool> showGoogleMapsWebRoute({
  required double originLat,
  required double originLng,
  required double destinationLat,
  required double destinationLng,
  required List<LatLng> routePoints,
}) async {
  final payload = routePoints
      .map(
        (point) => <String, double>{
          'lat': point.latitude,
          'lng': point.longitude,
        },
      )
      .toList(growable: false);

  try {
    final result = js_util.dartify(
      await _vanTravelShowRoute(
        originLat.toJS,
        originLng.toJS,
        destinationLat.toJS,
        destinationLng.toJS,
        js_util.jsify(payload),
      ).toDart,
    );
    return result == true;
  } catch (_) {
    return false;
  }
}

void clearGoogleMapsWebDirectionsRoute() {
  _vanTravelClearDirectionsRoute();
}
