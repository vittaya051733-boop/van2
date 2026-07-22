import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'utils/delivery_eta_policy.dart';
import 'utils/driving_route_service.dart';
import 'utils/order_no_rider_policy.dart';
import 'widgets/no_rider_customer_actions_banner.dart';

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

class TravelTrackingScreen extends StatefulWidget {
  const TravelTrackingScreen({super.key, required this.orderId});

  final String orderId;

  @override
  State<TravelTrackingScreen> createState() => _TravelTrackingScreenState();
}

class _TravelTrackingScreenState extends State<TravelTrackingScreen> {
  GoogleMapController? _mapController;
  Timer? _locationTimer;
  RiderVehicleProfile? _riderProfile;
  List<LatLng> _routePoints = const <LatLng>[];
  int? _etaMinutes;
  bool _isLoadingRoute = false;
  int _routeRequestId = 0;
  String? _trackedDriverId;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshRiderLocation());
    _locationTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => unawaited(_refreshRiderLocation()),
    );
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _refreshRiderLocation() async {
    final orderSnap = await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .get();
    final orderData = orderSnap.data();
    if (!mounted || orderData == null) {
      return;
    }

    final driverId = (orderData['driverId'] as String?)?.trim();
    if (driverId == null || driverId.isEmpty) {
      return;
    }

    final riderSnap =
        await FirebaseFirestore.instance.collection('riders').doc(driverId).get();
    if (!mounted) {
      return;
    }

    final profile = RiderVehicleProfile.fromFirestore(
      driverId,
      riderSnap.data(),
    );
    setState(() => _riderProfile = profile);

    final pickup = _readPickupLatLng(orderData);
    if (profile.hasCoordinates && pickup != null) {
      final distanceKm = Geolocator.distanceBetween(
            profile.latitude!,
            profile.longitude!,
            pickup.latitude,
            pickup.longitude,
          ) /
          1000;
      setState(() {
        _etaMinutes =
            DeliveryEtaPolicy.estimateTravelMinutesFromStraightDistanceKm(
          distanceKm,
        );
      });
      await _refreshRoute(
        originLat: profile.latitude!,
        originLng: profile.longitude!,
        destinationLat: pickup.latitude,
        destinationLng: pickup.longitude,
      );
    }
  }

  Future<void> _refreshRoute({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
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
    await _fitMapBounds();
  }

  LatLng? _readPickupLatLng(Map<String, dynamic> orderData) {
    final lat = _toDouble(orderData['shopLatitude']);
    final lng = _toDouble(orderData['shopLongitude']);
    if (lat == null || lng == null) {
      return null;
    }
    return LatLng(lat, lng);
  }

  double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.tryParse(value?.toString() ?? '');
  }

  Future<void> _fitMapBounds() async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    final orderSnap = await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .get();
    final pickup = _readPickupLatLng(orderSnap.data() ?? const {});
    final rider = _riderProfile;
    final points = <LatLng>[
      if (pickup != null) pickup,
      if (rider?.hasCoordinates == true)
        LatLng(rider!.latitude!, rider.longitude!),
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
        72,
      ),
    );
  }

  Set<Marker> _buildMarkers(Map<String, dynamic> orderData) {
    final markers = <Marker>{};
    final pickup = _readPickupLatLng(orderData);
    if (pickup != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(
            title: 'จุดรับ',
            snippet: (orderData['shopAddress'] as String?) ?? '',
          ),
        ),
      );
    }

    final rider = _riderProfile;
    if (rider?.hasCoordinates == true) {
      markers.add(
        Marker(
          markerId: const MarkerId('rider'),
          position: LatLng(rider!.latitude!, rider.longitude!),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(title: rider.displayName),
        ),
      );
    }
    return markers;
  }

  Set<Polyline> _buildPolylines() {
    if (_routePoints.length < 2) {
      return const <Polyline>{};
    }
    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('rider_route'),
        points: _routePoints,
        color: const Color(0xFF16A34A),
        width: 5,
      ),
    };
  }

  _TravelTrackingStatus _resolveStatus(Map<String, dynamic> data) {
    final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
    if (status == 'completed' || status == 'delivered') {
      return _TravelTrackingStatus.arrived;
    }
    if (data['scannedAt'] != null || status.contains('picked')) {
      return _TravelTrackingStatus.pickedUp;
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
        final driverId = (orderData['driverId'] as String?)?.trim();
        if (driverId != null &&
            driverId.isNotEmpty &&
            driverId != _trackedDriverId) {
          _trackedDriverId = driverId;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(_refreshRiderLocation());
          });
        }
        final status = _resolveStatus(orderData);
        final pickup = _readPickupLatLng(orderData);
        final rider = _riderProfile;
        final hasRider = rider != null;
        final initialTarget = pickup ??
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
                  unawaited(_fitMapBounds());
                },
                markers: _buildMarkers(orderData),
                polylines: _buildPolylines(),
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

  String get _statusTitle {
    switch (status) {
      case _TravelTrackingStatus.searching:
        return 'กำลังหาไรเดอร์';
      case _TravelTrackingStatus.driverAssigned:
        return 'ไรเดอร์รับงานแล้ว';
      case _TravelTrackingStatus.driverComing:
        return 'คนขับกำลังมา';
      case _TravelTrackingStatus.pickedUp:
        return 'ไรเดอร์ถึงจุดรับแล้ว';
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
        return 'ไรเดอร์กำลังเตรียมออกเดินทางมาหาคุณ';
      case _TravelTrackingStatus.driverComing:
        return 'ขึ้นรถทันที คนขับไม่สามารถจอดรอได้';
      case _TravelTrackingStatus.pickedUp:
        return 'กรุณาเดินไปที่จุดรับ $pickupLabel';
      case _TravelTrackingStatus.arrived:
        return 'ขอให้เดินทางปลอดภัย';
    }
  }

  @override
  Widget build(BuildContext context) {
    final riderProfile = rider;
    final rating = riderProfile?.rating ?? 5.0;

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
                  if (etaMinutes != null &&
                      status == _TravelTrackingStatus.driverComing)
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: const Color(0xFFE5E7EB),
                          backgroundImage: riderProfile.profilePhotoUrl != null
                              ? NetworkImage(riderProfile.profilePhotoUrl!)
                              : null,
                          child: riderProfile.profilePhotoUrl == null
                              ? Text(
                                  riderProfile.displayName
                                              .trim()
                                              .isNotEmpty
                                      ? riderProfile.displayName
                                          .trim()
                                          .substring(0, 1)
                                          .toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 22,
                                  ),
                                )
                              : null,
                        ),
                        if (riderProfile.isElectricVehicle)
                          Positioned(
                            right: -2,
                            bottom: -2,
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: const Icon(
                                Icons.bolt,
                                size: 14,
                                color: Color(0xFF16A34A),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (riderProfile.licensePlate?.isNotEmpty == true)
                            Text(
                              riderProfile.licensePlate!,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.5,
                                  ),
                            ),
                          Text(
                            riderProfile.vehicleSummary,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: const Color(0xFF4B5563),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: <Widget>[
                              Text(
                                riderProfile.displayName,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.star,
                                size: 16,
                                color: Color(0xFFF59E0B),
                              ),
                              const SizedBox(width: 2),
                              Text(
                                rating.toStringAsFixed(1),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
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
