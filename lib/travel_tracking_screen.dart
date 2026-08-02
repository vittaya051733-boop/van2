import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'call_screen.dart';
import 'chat_room_screen.dart';
import 'models/rider_vehicle_profile.dart';
import 'models/user_profile.dart';
import 'services/chat_warmup.dart';
import 'services/notification_service.dart';
import 'travel_vehicle_type.dart';
import 'utils/delivery_eta_policy.dart';
import 'utils/driving_route_service.dart';
import 'utils/order_no_rider_policy.dart';
import 'utils/travel_vehicle_map_marker.dart';
import 'widgets/no_rider_customer_actions_banner.dart';
import 'widgets/travel_driver_profile_card.dart';

void showTravelTrackingScreen({
  required BuildContext context,
  required String orderId,
}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => TravelTrackingScreen(orderId: orderId),
    ),
  );
}

bool isActiveTravelTrackingOrder(Map<String, dynamic> data) {
  final orderType = (data['orderType'] as String?)?.trim();
  final serviceType = (data['serviceType'] as String?)?.trim();
  final isTravel = orderType == 'travel_passenger' ||
      serviceType == 'travel_passenger';
  if (!isTravel) {
    return false;
  }

  final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
  if (status == 'delivered' ||
      status == 'completed' ||
      status == 'cancelled' ||
      status == 'canceled' ||
      status == 'refund' ||
      status == 'refunded') {
    return false;
  }

  return true;
}

class TravelTrackingScreen extends StatefulWidget {
  const TravelTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<TravelTrackingScreen> createState() => _TravelTrackingScreenState();
}

class _TravelTrackingScreenState extends State<TravelTrackingScreen> {
  GoogleMapController? _mapController;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _riderSubscription;
  RiderVehicleProfile? _riderProfile;
  List<LatLng> _routePoints = const <LatLng>[];
  List<LatLng> _legRoutePoints = const <LatLng>[];
  int? _etaMinutes;
  bool _isLoadingRoute = false;
  int _routeRequestId = 0;
  int _legRouteRequestId = 0;
  String? _boundDriverId;
  Map<String, dynamic> _orderData = const <String, dynamic>{};
  DateTime? _lastRouteFetchAt;
  DateTime? _lastLegRouteFetchAt;
  LatLng? _lastRouteOrigin;
  _TravelTrackingStatus? _lastRouteStatus;
  BitmapDescriptor? _riderMarkerIcon;
  TravelVehicleType? _riderMarkerVehicleType;

  static const Duration _routeRefreshMinInterval = Duration(minutes: 1);
  static const double _routeRefreshMinMoveMeters = 120;
  static const Color _routeLineColor = Color(0xFFDC2626);

  @override
  void dispose() {
    _riderSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _syncOrderSnapshot(Map<String, dynamic> orderData) {
    final previousStatus =
        _orderData.isEmpty ? null : _resolveStatus(_orderData);
    _orderData = orderData;
    final status = _resolveStatus(orderData);
    final statusChanged =
        previousStatus != null && previousStatus != status;

    final driverId = (orderData['driverId'] as String?)?.trim();
    if (driverId == null || driverId.isEmpty) {
      _stopRiderListener();
      if (statusChanged || previousStatus == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_fitMapBounds(orderData));
        });
      }
      return;
    }

    if (driverId != _boundDriverId) {
      _boundDriverId = driverId;
      _lastRouteFetchAt = null;
      _lastRouteOrigin = null;
      _lastRouteStatus = null;
      _routePoints = const <LatLng>[];
      _legRoutePoints = const <LatLng>[];
      _lastLegRouteFetchAt = null;
      unawaited(_ensureRiderMarkerIcon(orderData));
      _startRiderListener(driverId);
      return;
    }

    unawaited(_ensureRiderMarkerIcon(orderData));

    if (statusChanged) {
      _maybeRefreshRouteForCurrentRider(forceStatusChange: true);
      _maybeRefreshLegRoute(force: true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_fitMapBounds(orderData));
      });
    } else if (_riderProfile?.hasCoordinates == true) {
      _maybeRefreshRouteForCurrentRider();
      _maybeRefreshLegRoute();
    }
  }

  void _stopRiderListener() {
    _riderSubscription?.cancel();
    _riderSubscription = null;
    _boundDriverId = null;
    if (_riderProfile != null) {
      setState(() => _riderProfile = null);
    }
  }

  void _startRiderListener(String driverId) {
    _riderSubscription?.cancel();
    _riderSubscription = FirebaseFirestore.instance
        .collection('riders')
        .doc(driverId)
        .snapshots()
        .listen(
      (snapshot) {
        if (!mounted) {
          return;
        }
        final profile = RiderVehicleProfile.fromFirestore(
          driverId,
          snapshot.data(),
        );
        setState(() => _riderProfile = profile);
        unawaited(_ensureRiderMarkerIcon(_orderData));
        _onRiderLocationUpdated(profile);
      },
      onError: (_) {
        // Ignore transient listener errors; order stream will retry bind.
      },
    );
  }

  void _onRiderLocationUpdated(RiderVehicleProfile profile) {
    if (!profile.hasCoordinates || _orderData.isEmpty) {
      return;
    }

    final status = _resolveStatus(_orderData);
    final target = _routeTargetForStatus(_orderData, status);
    if (target != null) {
      final distanceKm = Geolocator.distanceBetween(
            profile.latitude!,
            profile.longitude!,
            target.latitude,
            target.longitude,
          ) /
          1000;
      setState(() {
        _etaMinutes =
            DeliveryEtaPolicy.estimateTravelMinutesFromStraightDistanceKm(
          distanceKm,
        );
      });
    }

    _maybeRefreshRouteForCurrentRider(profile: profile);
    _maybeRefreshLegRoute();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_fitMapBounds(_orderData));
    });
  }

  void _maybeRefreshRouteForCurrentRider({
    RiderVehicleProfile? profile,
    bool forceStatusChange = false,
  }) {
    final rider = profile ?? _riderProfile;
    if (rider == null || !rider.hasCoordinates || _orderData.isEmpty) {
      return;
    }

    final status = _resolveStatus(_orderData);
    final statusChanged = forceStatusChange && _lastRouteStatus != status;
    _lastRouteStatus = status;

    final origin = LatLng(rider.latitude!, rider.longitude!);
    if (!_shouldRefreshRoute(origin, statusChanged: statusChanged)) {
      return;
    }

    final target = _routeTargetForStatus(_orderData, status);
    if (target == null) {
      return;
    }

    _lastRouteFetchAt = DateTime.now();
    _lastRouteOrigin = origin;
    unawaited(
      _refreshRoute(
        originLat: origin.latitude,
        originLng: origin.longitude,
        destinationLat: target.latitude,
        destinationLng: target.longitude,
        orderData: _orderData,
      ),
    );
  }

  bool _shouldRefreshRoute(LatLng origin, {required bool statusChanged}) {
    if (statusChanged) {
      return true;
    }
    final lastFetch = _lastRouteFetchAt;
    if (lastFetch == null) {
      return true;
    }
    if (DateTime.now().difference(lastFetch) >= _routeRefreshMinInterval) {
      return true;
    }
    final previousOrigin = _lastRouteOrigin;
    if (previousOrigin == null) {
      return true;
    }
    final movedMeters = Geolocator.distanceBetween(
      previousOrigin.latitude,
      previousOrigin.longitude,
      origin.latitude,
      origin.longitude,
    );
    return movedMeters >= _routeRefreshMinMoveMeters;
  }

  Future<void> _refreshRoute({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    required Map<String, dynamic> orderData,
  }) async {
    final requestId = ++_routeRequestId;
    setState(() => _isLoadingRoute = true);
    final result = await DrivingRouteService.fetchDrivingRoute(
      originLat: originLat,
      originLng: originLng,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
    );
    if (!mounted || requestId != _routeRequestId) {
      return;
    }
    setState(() {
      _isLoadingRoute = false;
      _routePoints = result.route?.points ?? <LatLng>[
        LatLng(originLat, originLng),
        LatLng(destinationLat, destinationLng),
      ];
      final durationSeconds = result.route?.durationSeconds;
      if (durationSeconds != null && durationSeconds > 0) {
        _etaMinutes = (durationSeconds / 60).ceil().clamp(1, 240);
      }
    });
    await _fitMapBounds(orderData);
  }

  void _maybeRefreshLegRoute({bool force = false}) {
    if (_orderData.isEmpty) {
      return;
    }

    final status = _resolveStatus(_orderData);
    if (status != _TravelTrackingStatus.pickedUp) {
      if (_legRoutePoints.isNotEmpty) {
        setState(() => _legRoutePoints = const <LatLng>[]);
      }
      return;
    }

    final pickup = _readPickupLatLng(_orderData);
    final destination = _readDestinationLatLng(_orderData);
    if (pickup == null || destination == null) {
      return;
    }

    final lastFetch = _lastLegRouteFetchAt;
    if (!force &&
        lastFetch != null &&
        DateTime.now().difference(lastFetch) < _routeRefreshMinInterval) {
      return;
    }

    _lastLegRouteFetchAt = DateTime.now();
    unawaited(_fetchLegRoute(pickup: pickup, destination: destination));
  }

  Future<void> _fetchLegRoute({
    required LatLng pickup,
    required LatLng destination,
  }) async {
    final requestId = ++_legRouteRequestId;
    final result = await DrivingRouteService.fetchDrivingRoute(
      originLat: pickup.latitude,
      originLng: pickup.longitude,
      destinationLat: destination.latitude,
      destinationLng: destination.longitude,
    );
    if (!mounted || requestId != _legRouteRequestId) {
      return;
    }

    setState(() {
      _legRoutePoints = result.route?.points ??
          <LatLng>[pickup, destination];
    });
    await _fitMapBounds(_orderData);
  }

  LatLng? _readPickupLatLng(Map<String, dynamic> orderData) {
    final travelRequest = orderData['travelRequest'];
    if (travelRequest is Map) {
      final pickup = travelRequest['pickup'];
      if (pickup is Map) {
        final lat = _toDouble(pickup['latitude']);
        final lng = _toDouble(pickup['longitude']);
        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }
    }

    final lat = _toDouble(orderData['shopLatitude']);
    final lng = _toDouble(orderData['shopLongitude']);
    if (lat == null || lng == null) {
      return null;
    }
    return LatLng(lat, lng);
  }

  LatLng? _readDestinationLatLng(Map<String, dynamic> orderData) {
    final travelRequest = orderData['travelRequest'];
    if (travelRequest is Map) {
      final destination = travelRequest['destination'];
      if (destination is Map) {
        final lat = _toDouble(destination['latitude']);
        final lng = _toDouble(destination['longitude']);
        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }
    }

    for (final key in <String>['customerLocation', 'deliverySnapshot']) {
      final location = orderData[key];
      if (location is Map) {
        final lat = _toDouble(location['latitude']);
        final lng = _toDouble(location['longitude']);
        if (lat != null && lng != null) {
          return LatLng(lat, lng);
        }
      }
    }

    return null;
  }

  String? _readDestinationLabel(Map<String, dynamic> orderData) {
    final travelRequest = orderData['travelRequest'];
    if (travelRequest is Map) {
      final destination = travelRequest['destination'];
      if (destination is Map) {
        final title = destination['title']?.toString().trim();
        if (title != null && title.isNotEmpty) {
          return title;
        }
        final subtitle = destination['subtitle']?.toString().trim();
        if (subtitle != null && subtitle.isNotEmpty) {
          return subtitle;
        }
      }
    }

    final customerLocation = orderData['customerLocation'];
    if (customerLocation is Map) {
      final label = customerLocation['label']?.toString().trim();
      if (label != null && label.isNotEmpty) {
        return label;
      }
    }

    final deliverySnapshot = orderData['deliverySnapshot'];
    if (deliverySnapshot is Map) {
      final label = deliverySnapshot['locationLabel']?.toString().trim();
      if (label != null && label.isNotEmpty) {
        return label;
      }
    }

    return null;
  }

  LatLng? _routeTargetForStatus(
    Map<String, dynamic> orderData,
    _TravelTrackingStatus status,
  ) {
    final pickup = _readPickupLatLng(orderData);
    final destination = _readDestinationLatLng(orderData);
    switch (status) {
      case _TravelTrackingStatus.pickedUp:
      case _TravelTrackingStatus.arrived:
        return destination ?? pickup;
      case _TravelTrackingStatus.searching:
      case _TravelTrackingStatus.driverAssigned:
      case _TravelTrackingStatus.driverComing:
        return pickup ?? destination;
    }
  }

  TravelVehicleType _resolveVehicleType(Map<String, dynamic> orderData) {
    return _riderProfile?.vehicleType ??
        readTravelOrderVehicleType(orderData) ??
        TravelVehicleType.motorcycle;
  }

  Future<void> _ensureRiderMarkerIcon(Map<String, dynamic> orderData) async {
    if (orderData.isEmpty) {
      return;
    }

    final vehicleType = _resolveVehicleType(orderData);
    if (vehicleType == _riderMarkerVehicleType && _riderMarkerIcon != null) {
      return;
    }

    final icon = await travelVehicleMapMarker(vehicleType);
    if (!mounted) {
      return;
    }

    setState(() {
      _riderMarkerVehicleType = vehicleType;
      _riderMarkerIcon = icon;
    });
  }

  double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  Future<void> _fitMapBounds(Map<String, dynamic> orderData) async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    final pickup = _readPickupLatLng(orderData);
    final destination = _readDestinationLatLng(orderData);
    final rider = _riderProfile;
    final points = <LatLng>[
      if (pickup != null) pickup,
      if (destination != null) destination,
      if (rider?.hasCoordinates == true)
        LatLng(rider!.latitude!, rider.longitude!),
      ..._legRoutePoints,
      ..._routePoints,
    ];
    if (points.isEmpty) {
      return;
    }
    if (points.length == 1) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, 15),
      );
      return;
    }

    var minLat = points.first.latitude;
    var maxLat = points.first.latitude;
    var minLng = points.first.longitude;
    var maxLng = points.first.longitude;
    for (final point in points) {
      minLat = math.min(minLat, point.latitude);
      maxLat = math.max(maxLat, point.latitude);
      minLng = math.min(minLng, point.longitude);
      maxLng = math.max(maxLng, point.longitude);
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        110,
      ),
    );
  }

  Set<Marker> _buildMarkers(Map<String, dynamic> orderData) {
    final markers = <Marker>{};
    final pickup = _readPickupLatLng(orderData);
    if (pickup != null) {
      final pickupLabel = (orderData['travelRequest'] is Map
              ? ((orderData['travelRequest'] as Map)['pickup']?['title']
                  ?.toString())
              : null) ??
          (orderData['shopName'] as String?) ??
          'จุดรับ';
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: 'จุดรับ',
            snippet: pickupLabel,
          ),
        ),
      );
    }

    final destination = _readDestinationLatLng(orderData);
    if (destination != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: destination,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: 'ปลายทาง',
            snippet: _readDestinationLabel(orderData) ?? '',
          ),
        ),
      );
    }

    final rider = _riderProfile;
    if (rider?.hasCoordinates == true) {
      final vehicleType = _resolveVehicleType(orderData);
      markers.add(
        Marker(
          markerId: const MarkerId('rider'),
          position: LatLng(rider!.latitude!, rider.longitude!),
          icon: _riderMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          anchor: const Offset(0.5, 1.0),
          infoWindow: InfoWindow(
            title: rider.displayName,
            snippet: vehicleType.label,
          ),
        ),
      );
    }
    return markers;
  }

  List<LatLng> _resolveRouteDisplayPoints(Map<String, dynamic> orderData) {
    final status = _resolveStatus(orderData);
    if (status == _TravelTrackingStatus.pickedUp &&
        _legRoutePoints.length >= 2) {
      return _legRoutePoints;
    }

    if (_routePoints.length >= 2) {
      return _routePoints;
    }

    final rider = _riderProfile;
    final target = _routeTargetForStatus(orderData, status);
    if (rider?.hasCoordinates != true || target == null) {
      return const <LatLng>[];
    }

    return <LatLng>[
      LatLng(rider!.latitude!, rider.longitude!),
      target,
    ];
  }

  Set<Polyline> _buildPolylines(Map<String, dynamic> orderData) {
    final status = _resolveStatus(orderData);
    final points = _resolveRouteDisplayPoints(orderData);
    if (points.length < 2) {
      return const <Polyline>{};
    }

    final isPreview = status != _TravelTrackingStatus.pickedUp &&
        _routePoints.length < 2;

    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('rider_route_outline'),
        points: points,
        color: Colors.white,
        width: isPreview ? 9 : 12,
        geodesic: true,
      ),
      Polyline(
        polylineId: const PolylineId('rider_route'),
        points: points,
        color: _routeLineColor,
        width: isPreview ? 5 : 7,
        geodesic: true,
        patterns: isPreview
            ? <PatternItem>[PatternItem.dash(18), PatternItem.gap(10)]
            : <PatternItem>[],
      ),
    };
  }

  _TravelTrackingStatus _resolveStatus(Map<String, dynamic> data) {
    final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
    if (status == 'completed' || status == 'delivered') {
      return _TravelTrackingStatus.arrived;
    }
    if (status == 'delivering' ||
        data['scannedAt'] != null ||
        status.contains('picked')) {
      return _TravelTrackingStatus.pickedUp;
    }
    if (status == 'ready' || data['pickupArrivedAt'] != null) {
      return _TravelTrackingStatus.driverComing;
    }
    if (data['acceptedAt'] != null ||
        status == 'accepted' ||
        status == 'in_progress') {
      return _TravelTrackingStatus.driverComing;
    }
    if ((data['driverId'] as String?)?.trim().isNotEmpty == true) {
      return _TravelTrackingStatus.driverAssigned;
    }
    return _TravelTrackingStatus.searching;
  }

  Future<void> _openChat({
    required UserProfile riderProfile,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    ChatWarmup.prefetchRoom(myUid: user.uid, peer: riderProfile);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatRoomScreen(
          friendProfile: riderProfile,
          orderId: widget.orderId,
        ),
      ),
    );
  }

  Future<void> _startCall({
    required UserProfile riderProfile,
    String? phone,
  }) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    final callerUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (callerUid.isEmpty) {
      return;
    }

    try {
      final callerDoc = await FirebaseFirestore.instance
          .collection('customer_users')
          .doc(callerUid)
          .get();
      final callerData = callerDoc.data() ?? const <String, dynamic>{};
      final caller = UserProfile.fromMap(callerUid, callerData);
      final callee = riderProfile;

      final callData = await NotificationService().initiateCall(
        caller: caller,
        callee: callee,
        isVideo: false,
      );

      if (!mounted) {
        return;
      }

      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => CallScreen(
            channelName:
                (callData['channelId'] as String?) ??
                'call_${caller.uid}_${callee.uid}',
            isVideo: false,
            targetProfile: callee,
            appIdOverride: callData['appId'] as String?,
            tokenOverride: callData['token'] as String?,
            isIncoming: false,
          ),
        ),
      );
    } catch (_) {
      final trimmedPhone = phone?.trim();
      if (trimmedPhone != null && trimmedPhone.isNotEmpty) {
        final ok = await launchUrl(
          Uri(scheme: 'tel', path: trimmedPhone),
          mode: LaunchMode.externalApplication,
        );
        if (!ok && mounted) {
          messenger?.showSnackBar(
            const SnackBar(content: Text('ไม่สามารถโทรออกได้')),
          );
        }
        return;
      }
      if (mounted) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('ไม่สามารถโทรหาไรเดอร์ได้')),
        );
      }
    }
  }

  UserProfile _toChatProfile(RiderVehicleProfile rider) {
    return UserProfile(
      uid: rider.riderId,
      displayName: rider.displayName,
      phoneNumber: rider.phoneNumber,
      photoUrl: rider.profilePhotoUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.orderId)
          .snapshots(),
      builder: (context, snapshot) {
        final orderData = snapshot.data?.data() ?? const <String, dynamic>{};
        if (orderData.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) {
              return;
            }
            _syncOrderSnapshot(orderData);
          });
        }

        final status = _resolveStatus(orderData);
        final pickup = _readPickupLatLng(orderData);
        final destination = _readDestinationLatLng(orderData);
        final rider = _riderProfile;
        final hasRider = rider != null;
        final initialTarget = pickup ??
            destination ??
            (rider?.hasCoordinates == true
                ? LatLng(rider!.latitude!, rider.longitude!)
                : const LatLng(13.7563, 100.5018));

        return Scaffold(
          body: Stack(
            children: <Widget>[
              GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: initialTarget,
                  zoom: 14,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                  unawaited(_fitMapBounds(orderData));
                },
                markers: _buildMarkers(orderData),
                polylines: _buildPolylines(orderData),
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 4,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              ),
              if (_isLoadingRoute)
                const SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: EdgeInsets.only(top: 64),
                      child: Card(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Text('กำลังอัปเดตเส้นทาง...'),
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _TravelTrackingSheet(
                  orderId: widget.orderId,
                  orderData: orderData,
                  status: status,
                  etaMinutes: _etaMinutes,
                  rider: rider,
                  pickupLabel: (orderData['shopAddress'] as String?) ??
                      (orderData['travelRequest'] is Map
                          ? ((orderData['travelRequest']
                                  as Map)['pickup']?['title']
                              ?.toString())
                          : null) ??
                      'จุดรับผู้โดยสาร',
                  canContact: hasRider &&
                      (orderData['driverId'] as String?)?.trim().isNotEmpty ==
                          true,
                  onChat: hasRider
                      ? () => unawaited(
                            _openChat(riderProfile: _toChatProfile(rider)),
                          )
                      : null,
                  onCall: hasRider
                      ? () => unawaited(
                            _startCall(
                              riderProfile: _toChatProfile(rider),
                              phone: rider.phoneNumber,
                            ),
                          )
                      : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

enum _TravelTrackingStatus {
  searching,
  driverAssigned,
  driverComing,
  pickedUp,
  arrived,
}

class _TravelTrackingSheet extends StatelessWidget {
  const _TravelTrackingSheet({
    required this.orderId,
    required this.orderData,
    required this.status,
    required this.etaMinutes,
    required this.rider,
    required this.pickupLabel,
    required this.canContact,
    this.onChat,
    this.onCall,
  });

  final String orderId;
  final Map<String, dynamic> orderData;
  final _TravelTrackingStatus status;
  final int? etaMinutes;
  final RiderVehicleProfile? rider;
  final String pickupLabel;
  final bool canContact;
  final VoidCallback? onChat;
  final VoidCallback? onCall;

  bool get _shouldShowEtaInCard {
    if (etaMinutes == null) {
      return false;
    }
    return status == _TravelTrackingStatus.driverAssigned ||
        status == _TravelTrackingStatus.driverComing ||
        status == _TravelTrackingStatus.pickedUp;
  }

  String get _etaTargetLabel {
    return status == _TravelTrackingStatus.pickedUp ? 'ปลายทาง' : 'จุดรับ';
  }

  String get _statusTitle {
    switch (status) {
      case _TravelTrackingStatus.searching:
        return 'กำลังหาไรเดอร์';
      case _TravelTrackingStatus.driverAssigned:
        return 'รอไรเดอร์รับงาน';
      case _TravelTrackingStatus.driverComing:
        return 'คนขับกำลังมา';
      case _TravelTrackingStatus.pickedUp:
        return 'กำลังเดินทางไปปลายทาง';
      case _TravelTrackingStatus.arrived:
        return 'ถึงจุดหมายแล้ว';
    }
  }

  String get _statusSubtitle {
    switch (status) {
      case _TravelTrackingStatus.searching:
        if (OrderNoRiderPolicy.isScheduledTravelOrder(orderData)) {
          final scheduleLabel =
              OrderNoRiderPolicy.readScheduleLabel(orderData);
          if (scheduleLabel != null) {
            return 'กำหนดเดินทาง $scheduleLabel — ระบบจะจับคู่ไรเดอร์ก่อนเวลาเดินทาง';
          }
          return 'ระบบจะจับคู่ไรเดอร์ก่อนเวลาเดินทางที่คุณกำหนด';
        }
        return 'ระบบกำลังจับคู่ไรเดอร์ที่ใกล้ที่สุด';
      case _TravelTrackingStatus.driverAssigned:
        return 'ระบบจับคู่ไรเดอร์แล้ว รอไรเดอร์ยืนยันรับงาน';
      case _TravelTrackingStatus.driverComing:
        return 'ขึ้นรถทันที คนขับไม่สามารถจอดรอได้';
      case _TravelTrackingStatus.pickedUp:
        return 'ติดตามเส้นทางจากจุดรับไปปลายทาง (อัปเดตทุก ~1 นาที)';
      case _TravelTrackingStatus.arrived:
        return 'ขอให้เดินทางปลอดภัย';
    }
  }

  @override
  Widget build(BuildContext context) {
    final riderProfile = rider;
    final rating = riderProfile?.rating ?? 5.0;
    final showEta = _shouldShowEtaInCard;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          _statusTitle,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF111827),
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _statusSubtitle,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: const Color(0xFF6B7280),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                  if (showEta)
                    Text(
                      '$etaMinutes นาที',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF111827),
                          ),
                    ),
                ],
              ),
              NoRiderCustomerActionsBanner(
                orderId: orderId,
                data: orderData,
                firestore: FirebaseFirestore.instance,
              ),
              if (riderProfile != null) ...<Widget>[
                const SizedBox(height: 16),
                TravelDriverProfileCard(
                  rider: riderProfile,
                  rating: rating,
                  showSectionLabel: false,
                  etaMinutes: _shouldShowEtaInCard ? etaMinutes : null,
                  etaTargetLabel: _etaTargetLabel,
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Material(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        onTap: canContact ? onChat : null,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(
                                Icons.chat_bubble_outline,
                                color: canContact
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF9CA3AF),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'แชทหาคนขับ',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: canContact
                                          ? const Color(0xFF111827)
                                          : const Color(0xFF9CA3AF),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: const Color(0xFFF3F4F6),
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: canContact ? onCall : null,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Icon(
                          Icons.phone,
                          color: canContact
                              ? const Color(0xFF111827)
                              : const Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
