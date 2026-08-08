import 'dart:js_interop';
import 'dart:js_util' as js_util;

import 'package:google_maps_flutter/google_maps_flutter.dart';

@JS('vanTravelSetRoutePolyline')
external JSPromise _vanTravelSetRoutePolyline(JSAny? points);

@JS('vanTravelClearRoutePolyline')
external void _vanTravelClearRoutePolyline();

Future<bool> setGoogleMapsWebRoutePolyline(List<LatLng> points) async {
  if (points.length < 2) {
    clearGoogleMapsWebRoutePolyline();
    return true;
  }

  final payload = points
      .map(
        (point) => <String, double>{
          'lat': point.latitude,
          'lng': point.longitude,
        },
      )
      .toList(growable: false);

  try {
    final result = js_util.dartify(
      await _vanTravelSetRoutePolyline(js_util.jsify(payload)).toDart,
    );
    return result == true;
  } catch (_) {
    return false;
  }
}

void clearGoogleMapsWebRoutePolyline() {
  _vanTravelClearRoutePolyline();
}
