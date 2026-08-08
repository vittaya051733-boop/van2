import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

BitmapDescriptor? _pickupMarkerCache;
BitmapDescriptor? _destinationMarkerCache;

Path _mapPinPath(double width, double height) {
  final cx = width / 2;
  return Path()
    ..moveTo(cx, height)
    ..quadraticBezierTo(0, height * 0.58, 0, height * 0.34)
    ..arcToPoint(
      Offset(width, height * 0.34),
      radius: Radius.circular(width / 2),
    )
    ..quadraticBezierTo(width, height * 0.58, cx, height)
    ..close();
}

Future<BitmapDescriptor> _coloredPinMarker(Color color) async {
  const double width = 34;
  const double height = 46;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawPath(
    _mapPinPath(width, height).shift(const Offset(0, 1)),
    Paint()..color = const Color(0x55000000),
  );
  canvas.drawPath(
    _mapPinPath(width, height),
    Paint()..color = color,
  );
  canvas.drawCircle(
    Offset(width / 2, height * 0.34 / 2 + 1),
    5,
    Paint()..color = Colors.white,
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(width.toInt(), height.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    return BitmapDescriptor.defaultMarker;
  }

  return BitmapDescriptor.bytes(byteData.buffer.asUint8List());
}

Future<BitmapDescriptor> travelPlannerPickupMarker() {
  final cached = _pickupMarkerCache;
  if (cached != null) {
    return Future<BitmapDescriptor>.value(cached);
  }

  return _coloredPinMarker(const Color(0xFF16A34A)).then((marker) {
    _pickupMarkerCache = marker;
    return marker;
  });
}

Future<BitmapDescriptor> travelPlannerDestinationMarker() {
  final cached = _destinationMarkerCache;
  if (cached != null) {
    return Future<BitmapDescriptor>.value(cached);
  }

  return _coloredPinMarker(const Color(0xFFF57C00)).then((marker) {
    _destinationMarkerCache = marker;
    return marker;
  });
}
