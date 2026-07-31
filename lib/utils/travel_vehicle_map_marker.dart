import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../travel_vehicle_type.dart';

final Map<TravelVehicleType, BitmapDescriptor> _markerCache =
    <TravelVehicleType, BitmapDescriptor>{};

Path _mapPinPath(double width, double height) {
  final cx = width / 2;
  final path = Path()
    ..moveTo(cx, height)
    ..quadraticBezierTo(0, height * 0.58, 0, height * 0.34)
    ..arcToPoint(
      Offset(width, height * 0.34),
      radius: Radius.circular(width / 2),
    )
    ..quadraticBezierTo(width, height * 0.58, cx, height)
    ..close();
  return path;
}

Future<BitmapDescriptor> travelVehicleMapMarker(TravelVehicleType type) async {
  final cached = _markerCache[type];
  if (cached != null) {
    return cached;
  }

  const double width = 34;
  const double height = 46;
  const double iconSize = 17;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawPath(
    _mapPinPath(width, height).shift(const Offset(0, 1)),
    Paint()..color = const Color(0x55000000),
  );

  canvas.drawPath(
    _mapPinPath(width, height),
    Paint()..color = type.accentColor,
  );

  final icon = type.mapMarkerIcon;
  final textPainter = TextPainter(textDirection: TextDirection.ltr);
  textPainter.text = TextSpan(
    text: String.fromCharCode(icon.codePoint),
    style: TextStyle(
      fontSize: iconSize,
      fontFamily: icon.fontFamily,
      package: icon.fontPackage,
      color: Colors.white,
    ),
  );
  textPainter.layout();
  textPainter.paint(
    canvas,
    Offset(
      (width - textPainter.width) / 2,
      height * 0.34 / 2 - textPainter.height / 2 + 1,
    ),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(width.toInt(), height.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (byteData == null) {
    return BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed);
  }

  final descriptor = BitmapDescriptor.bytes(byteData.buffer.asUint8List());
  _markerCache[type] = descriptor;
  return descriptor;
}
