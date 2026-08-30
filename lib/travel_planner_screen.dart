import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'models/omise_payment_channel.dart';
import 'map_picker_screen.dart';
import 'l10n/l10n.dart';
import 'shipping_pricing_policy.dart';
import 'travel_payment_flow.dart';
import 'travel_tracking_screen.dart';
import 'travel_vehicle_type.dart';
import 'utils/customer_location.dart';
import 'utils/customer_location_gate.dart';
import 'utils/driving_route_service.dart';
import 'utils/google_maps_web_directions_route.dart';
import 'utils/google_maps_web_resize.dart';
import 'utils/places_autocomplete_service.dart';
import 'utils/travel_planner_map_marker.dart';
import 'widgets/online_rider_slider.dart';

enum _TravelActivePin { pickup, destination }

class TravelPlannerResult {
  const TravelPlannerResult({
    required this.pickup,
    required this.destination,
    required this.rideSelection,
    required this.distanceKm,
    required this.idempotencyKey,
  });

  final PickedLocation pickup;
  final PickedLocation destination;
  final TravelRideSelection rideSelection;
  final double distanceKm;
  final String idempotencyKey;
}

class TravelRideSelection {
  const TravelRideSelection({
    required this.vehicleType,
    required this.scheduledAt,
    required this.isImmediate,
    required this.estimatedFare,
  });

  final TravelVehicleType vehicleType;
  final DateTime scheduledAt;
  final bool isImmediate;
  final double estimatedFare;

  String get scheduleLabel {
    if (isImmediate) {
      return L10n.departNow;
    }

    final hour = scheduledAt.hour.toString().padLeft(2, '0');
    final minute = scheduledAt.minute.toString().padLeft(2, '0');
    return L10n.thaiDateTime(
      scheduledAt.day,
      scheduledAt.month,
      scheduledAt.year,
      '$hour:$minute',
    );
  }
}

class TravelPlannerScreen extends StatefulWidget {
  const TravelPlannerScreen({
    super.key,
    required this.initialPickup,
    this.initialDestination,
    this.initialRideSelection,
    this.onConfirmCashOnDelivery,
    this.onSubmitOmisePayment,
    this.onOpenOrderRoadmap,
  });

  final PickedLocation initialPickup;
  final PickedLocation? initialDestination;
  final TravelRideSelection? initialRideSelection;
  final Future<List<String>> Function(TravelPlannerResult request)? onConfirmCashOnDelivery;
  final Future<List<String>> Function(
    TravelPlannerResult request,
    OmisePaymentChannel channel,
  )? onSubmitOmisePayment;
  final Future<void> Function(
    List<String> orderIds, {
    bool showTravelTracking,
  })? onOpenOrderRoadmap;

  @override
  State<TravelPlannerScreen> createState() => _TravelPlannerScreenState();
}

class _TravelPlannerScreenState extends State<TravelPlannerScreen>
    with WidgetsBindingObserver {
  final TextEditingController _destinationSearchController =
      TextEditingController();
  final FocusNode _destinationFocusNode = FocusNode();

  GoogleMapController? _mapController;
  late PickedLocation _pickup;
  PickedLocation? _destination;
  TravelRideSelection? _rideSelection;
  late bool _locationsConfirmed;

  _TravelActivePin _activePin = _TravelActivePin.destination;
  bool _pickupReady = false;
  bool _isLoadingPickup = false;
  bool _isSearchingDestination = false;
  bool _retryPickupOnResume = false;
  bool _isRequestingLocationGate = false;
  List<LatLng> _routePoints = const <LatLng>[];
  double? _routeDistanceKm;
  bool _isLoadingRoute = false;
  Timer? _routeRefreshDebounce;
  Timer? _cameraFitDebounce;
  int _routeRequestId = 0;
  List<PlaceSuggestion> _placeSuggestions = const <PlaceSuggestion>[];
  bool _isLoadingSuggestions = false;
  bool _showSuggestions = false;
  Timer? _suggestionRefreshDebounce;
  bool _mapReady = !kIsWeb;
  bool _routeOverlayReady = !kIsWeb;
  bool _webMapMountReady = !kIsWeb;
  int _suggestionsRequestId = 0;
  bool _isSubmittingOrder = false;
  String? _activeIdempotencyKey;
  BitmapDescriptor? _pickupMarkerIcon;
  BitmapDescriptor? _destinationMarkerIcon;
  bool _hasInitializedPickupGps = false;
  String? _lastRouteOverlaySignature;

  static const double _pickupGpsMinMoveMeters = 40;

  static const double _minBoundsSpanDegrees = 0.003;
  static const double _minCameraZoom = 11;
  static const double _maxCameraZoom = 16;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pickup = widget.initialPickup;
    _destination = widget.initialDestination;
    _rideSelection = widget.initialRideSelection;
    _locationsConfirmed = widget.initialRideSelection != null;
    _pickupReady = true;

    if (_destination != null) {
      _destinationSearchController.text = _destination!.title;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _destinationFocusNode.requestFocus();
      if (kIsWeb) {
        scheduleGoogleMapsWebResize(delay: const Duration(milliseconds: 50));
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) {
            return;
          }
          setState(() => _webMapMountReady = true);
          scheduleGoogleMapsWebResize(delay: const Duration(milliseconds: 200));
        });
      }
      unawaited(_refreshPickupFromGps(forceGate: true));
      if (_hasDestination) {
        _scheduleDrivingRouteRefresh();
      }
      unawaited(_loadTravelPlannerMarkerIcons());
    });
  }

  Future<void> _loadTravelPlannerMarkerIcons() async {
    final results = await Future.wait<BitmapDescriptor>(<Future<BitmapDescriptor>>[
      travelPlannerPickupMarker(),
      travelPlannerDestinationMarker(),
    ]);
    if (!mounted) {
      return;
    }
    setState(() {
      _pickupMarkerIcon = results[0];
      _destinationMarkerIcon = results[1];
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _routeRefreshDebounce?.cancel();
    _cameraFitDebounce?.cancel();
    _suggestionRefreshDebounce?.cancel();
    if (kIsWeb) {
      clearGoogleMapsWebDirectionsRoute();
      _lastRouteOverlaySignature = null;
    }
    _destinationSearchController.dispose();
    _destinationFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || !_retryPickupOnResume) {
      return;
    }

    _retryPickupOnResume = false;
    unawaited(_refreshPickupFromGps(forceGate: true));
  }

  bool get _hasDestination => _destination != null;

  double? get _distanceKm {
    if (!_hasDestination) {
      return null;
    }
    return _routeDistanceKm;
  }

  double? get _startingFare {
    final distanceKm = _distanceKm;
    if (distanceKm == null) {
      return null;
    }
    return ShippingPricingPolicy.computeTravelFareForVehicle(
      distanceKm,
      TravelVehicleType.motorcycle,
    );
  }

  LatLng get _mapCenter => LatLng(_pickup.latitude, _pickup.longitude);

  Set<Marker> get _markers {
    final markers = <Marker>{
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(_pickup.latitude, _pickup.longitude),
        draggable: true,
        icon: _pickupMarkerIcon ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        onDragEnd: (position) {
          unawaited(_updatePickupFromLatLng(position));
        },
        onTap: () {
          setState(() => _activePin = _TravelActivePin.pickup);
        },
      ),
    };

    if (_hasDestination) {
      markers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(
            _destination!.latitude,
            _destination!.longitude,
          ),
          draggable: true,
          icon: _destinationMarkerIcon ??
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
          onDragEnd: (position) {
            unawaited(_updateDestinationFromLatLng(position));
          },
          onTap: () {
            setState(() => _activePin = _TravelActivePin.destination);
          },
        ),
      );
    }

    return markers;
  }

  Set<Polyline> get _polylines {
    // Flutter Web's native polyline can render a long straight artifact while
    // the JavaScript DirectionsRenderer below owns the real road overlay.
    if (kIsWeb) {
      return const <Polyline>{};
    }
    if (!_mapReady || !_routeOverlayReady) {
      return const <Polyline>{};
    }
    final displayPoints = _displayRoutePoints;
    if (displayPoints.length < 2) {
      return const <Polyline>{};
    }

    return <Polyline>{
      Polyline(
        polylineId: const PolylineId('route'),
        points: displayPoints,
        color: const Color(0xFFF57C00),
        width: 5,
        geodesic: !kIsWeb,
      ),
    };
  }

  List<LatLng> get _displayRoutePoints {
    if (!kIsWeb || _routePoints.length <= 64) {
      return _routePoints;
    }
    return _simplifyRoutePointsForWeb(_routePoints, maxPoints: 64);
  }

  static List<LatLng> _simplifyRoutePointsForWeb(
    List<LatLng> points, {
    required int maxPoints,
  }) {
    if (points.length <= maxPoints) {
      return points;
    }

    final simplified = <LatLng>[];
    final step = (points.length - 1) / (maxPoints - 1);
    for (var index = 0; index < maxPoints; index++) {
      simplified.add(points[(index * step).round()]);
    }
    if (simplified.last != points.last) {
      simplified[simplified.length - 1] = points.last;
    }
    return simplified;
  }

  Future<void> _syncWebRouteOverlay() async {
    if (!kIsWeb || !_mapReady || !_hasDestination || _routePoints.length < 2) {
      return;
    }

    final signature =
        '${_pickup.latitude.toStringAsFixed(5)},${_pickup.longitude.toStringAsFixed(5)},'
        '${_destination!.latitude.toStringAsFixed(5)},${_destination!.longitude.toStringAsFixed(5)},'
        '${_routePoints.length}';
    if (_lastRouteOverlaySignature == signature) {
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) {
      return;
    }

    final drawn = await showGoogleMapsWebRoute(
      originLat: _pickup.latitude,
      originLng: _pickup.longitude,
      destinationLat: _destination!.latitude,
      destinationLng: _destination!.longitude,
      routePoints: _routePoints,
    );
    if (drawn && mounted) {
      _lastRouteOverlaySignature = signature;
    }
  }

  Future<void> _refreshWebMapLayout({GoogleMapController? controller}) async {
    if (!kIsWeb) {
      return;
    }
    scheduleGoogleMapsWebResize();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    scheduleGoogleMapsWebResize();
    final mapController = controller ?? _mapController;
    if (mapController != null && mounted && !_hasDestination) {
      try {
        await mapController.moveCamera(
          CameraUpdate.newLatLng(_mapCenter),
        );
      } catch (_) {}
    }
  }

  void _scheduleDrivingRouteRefresh() {
    _routeRefreshDebounce?.cancel();
    _routeRefreshDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_refreshDrivingRoute());
    });
  }

  Future<void> _refreshDrivingRoute() async {
    if (!_hasDestination) {
      if (!mounted) {
        return;
      }
      if (kIsWeb) {
        clearGoogleMapsWebDirectionsRoute();
        _lastRouteOverlaySignature = null;
      }
      setState(() {
        _routePoints = const <LatLng>[];
        _routeDistanceKm = null;
        _isLoadingRoute = false;
      });
      return;
    }

    final requestId = ++_routeRequestId;
    if (mounted) {
      setState(() => _isLoadingRoute = true);
    }

    try {
      final fetchResult = await DrivingRouteService.fetchDrivingRoute(
        originLat: _pickup.latitude,
        originLng: _pickup.longitude,
        destinationLat: _destination!.latitude,
        destinationLng: _destination!.longitude,
      );

      if (!mounted || requestId != _routeRequestId) {
        return;
      }

      final result = fetchResult.route;
      setState(() {
        _routePoints = result?.points ?? const <LatLng>[];
        _routeDistanceKm =
            result != null ? result.distanceMeters / 1000 : null;
        _isLoadingRoute = false;
      });

      if (_routePoints.length >= 2 || _hasDestination) {
        _scheduleMapCameraFit(
          delay: kIsWeb
              ? const Duration(milliseconds: 450)
              : const Duration(milliseconds: 200),
        );
      } else if (fetchResult.failureMessage != null) {
        _showSnackBar(fetchResult.failureMessage!);
      }
    } catch (_) {
      if (!mounted || requestId != _routeRequestId) {
        return;
      }
      setState(() {
        _routePoints = const <LatLng>[];
        _routeDistanceKm = null;
        _isLoadingRoute = false;
      });
    }
  }

  String _formatLocationLabel(PickedLocation location) {
    final subtitle = location.subtitle?.trim();
    if (subtitle == null || subtitle.isEmpty || subtitle == location.title) {
      return location.title;
    }
    return '${location.title} - $subtitle';
  }

  String _pickupReadout() {
    return _formatLocationLabel(_pickup);
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _moveCamera(LatLng target, {double zoom = 16}) async {
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(target, zoom),
    );
  }

  EdgeInsets _mapOverlayPadding(BuildContext context) {
    if (kIsWeb) {
      return EdgeInsets.zero;
    }
    final media = MediaQuery.of(context);
    return EdgeInsets.fromLTRB(
      32,
      media.padding.top + 196,
      32,
      media.padding.bottom + 152,
    );
  }

  void _scheduleMapCameraFit({
    Duration delay = const Duration(milliseconds: 400),
  }) {
    _cameraFitDebounce?.cancel();
    _cameraFitDebounce = Timer(delay, () {
      unawaited(_fitRouteBounds());
    });
  }

  LatLngBounds _pickupDestinationBounds() {
    final destination = _destination!;
    var minLat = _pickup.latitude < destination.latitude
        ? _pickup.latitude
        : destination.latitude;
    var maxLat = _pickup.latitude > destination.latitude
        ? _pickup.latitude
        : destination.latitude;
    var minLng = _pickup.longitude < destination.longitude
        ? _pickup.longitude
        : destination.longitude;
    var maxLng = _pickup.longitude > destination.longitude
        ? _pickup.longitude
        : destination.longitude;

    final latSpan = maxLat - minLat;
    if (latSpan < _minBoundsSpanDegrees) {
      final pad = (_minBoundsSpanDegrees - latSpan) / 2;
      minLat -= pad;
      maxLat += pad;
    }

    final lngSpan = maxLng - minLng;
    if (lngSpan < _minBoundsSpanDegrees) {
      final pad = (_minBoundsSpanDegrees - lngSpan) / 2;
      minLng -= pad;
      maxLng += pad;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  LatLngBounds? _routePointsBounds() {
    if (_routePoints.length < 2) {
      return null;
    }

    var minLat = _routePoints.first.latitude;
    var maxLat = _routePoints.first.latitude;
    var minLng = _routePoints.first.longitude;
    var maxLng = _routePoints.first.longitude;

    for (final point in _routePoints) {
      minLat = minLat < point.latitude ? minLat : point.latitude;
      maxLat = maxLat > point.latitude ? maxLat : point.latitude;
      minLng = minLng < point.longitude ? minLng : point.longitude;
      maxLng = maxLng > point.longitude ? maxLng : point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  LatLngBounds _unionBounds(LatLngBounds a, LatLngBounds b) {
    return LatLngBounds(
      southwest: LatLng(
        a.southwest.latitude < b.southwest.latitude
            ? a.southwest.latitude
            : b.southwest.latitude,
        a.southwest.longitude < b.southwest.longitude
            ? a.southwest.longitude
            : b.southwest.longitude,
      ),
      northeast: LatLng(
        a.northeast.latitude > b.northeast.latitude
            ? a.northeast.latitude
            : b.northeast.latitude,
        a.northeast.longitude > b.northeast.longitude
            ? a.northeast.longitude
            : b.northeast.longitude,
      ),
    );
  }

  Future<void> _clampCameraZoom() async {
    final controller = _mapController;
    if (controller == null) {
      return;
    }

    try {
      final zoom = await controller.getZoomLevel();
      if (zoom > _maxCameraZoom) {
        await controller.animateCamera(
          CameraUpdate.zoomTo(_maxCameraZoom),
        );
      } else if (zoom < _minCameraZoom) {
        await controller.animateCamera(
          CameraUpdate.zoomTo(_minCameraZoom),
        );
      }
    } catch (_) {}
  }

  double _zoomForBoundsSpan(double spanDegrees) {
    if (spanDegrees <= 0.004) {
      return 15;
    }
    if (spanDegrees <= 0.01) {
      return 14;
    }
    if (spanDegrees <= 0.025) {
      return 13;
    }
    if (spanDegrees <= 0.06) {
      return 12;
    }
    return _minCameraZoom;
  }

  double _zoomForDistanceKm(double distanceKm) {
    if (distanceKm <= 0.8) {
      return 15;
    }
    if (distanceKm <= 1.5) {
      return 14;
    }
    if (distanceKm <= 3) {
      return 13;
    }
    if (distanceKm <= 6) {
      return 12;
    }
    return _minCameraZoom;
  }

  Future<void> _fitRouteCameraWeb() async {
    final bounds = _pickupDestinationBounds();
    final center = LatLng(
      (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
      (bounds.northeast.longitude + bounds.southwest.longitude) / 2,
    );
    final latSpan = bounds.northeast.latitude - bounds.southwest.latitude;
    final lngSpan = bounds.northeast.longitude - bounds.southwest.longitude;
    final span = latSpan > lngSpan ? latSpan : lngSpan;

    var zoom = _zoomForBoundsSpan(span);
    final distanceKm = _routeDistanceKm ?? _distanceKm;
    if (distanceKm != null) {
      final distanceZoom = _zoomForDistanceKm(distanceKm);
      if (distanceZoom < zoom) {
        zoom = distanceZoom;
      }
    }
    zoom = zoom.clamp(_minCameraZoom, _maxCameraZoom);

    await _mapController!.animateCamera(
      CameraUpdate.newLatLngZoom(center, zoom),
    );
  }

  Future<void> _fitRouteBounds() async {
    if (!_hasDestination || _mapController == null || !_mapReady) {
      return;
    }

    if (kIsWeb) {
      await _fitRouteCameraWeb();
      if (_routePoints.length >= 2) {
        await _syncWebRouteOverlay();
      }
      return;
    }

    var bounds = _pickupDestinationBounds();
    final routeBounds = _routePointsBounds();
    if (routeBounds != null) {
      bounds = _unionBounds(bounds, routeBounds);
    }

    try {
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, 64),
      );
      await _clampCameraZoom();
    } catch (_) {
      final destination = _destination!;
      final center = LatLng(
        (_pickup.latitude + destination.latitude) / 2,
        (_pickup.longitude + destination.longitude) / 2,
      );
      await _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(center, 14),
      );
    }
  }

  Future<void> _refreshPickupFromGps({required bool forceGate}) async {
    if (_locationsConfirmed || _isLoadingPickup || _isRequestingLocationGate) {
      return;
    }

    setState(() => _isLoadingPickup = true);

    try {
      if (forceGate) {
        setState(() => _isRequestingLocationGate = true);
        final gateResult = await ensureCustomerLocationAccess(
          context,
          onSnackBar: _showSnackBar,
        );
        if (!mounted) {
          return;
        }

        if (gateResult == CustomerLocationGateResult.retryOnResume) {
          _retryPickupOnResume = true;
          return;
        }

        if (gateResult != CustomerLocationGateResult.granted) {
          setState(() => _pickupReady = false);
          return;
        }
      }

      final location = await tryDetectCurrentLocation();
      if (!mounted) {
        return;
      }

      if (location == null) {
        setState(() => _pickupReady = true);
        return;
      }

      if (_hasInitializedPickupGps) {
        final movedMeters = Geolocator.distanceBetween(
          _pickup.latitude,
          _pickup.longitude,
          location.latitude,
          location.longitude,
        );
        if (movedMeters < _pickupGpsMinMoveMeters) {
          setState(() => _pickupReady = true);
          return;
        }
      } else {
        _hasInitializedPickupGps = true;
      }

      setState(() {
        _pickup = location;
        _pickupReady = true;
        _locationsConfirmed = false;
      });

      if (_hasDestination) {
        _scheduleDrivingRouteRefresh();
      } else {
        await _moveCamera(LatLng(location.latitude, location.longitude));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPickup = false;
          _isRequestingLocationGate = false;
        });
      }
    }
  }

  Future<void> _updatePickupFromLatLng(LatLng position) async {
    final picked = await buildPickedLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      fallbackTitle: L10n.selectedPickup,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _pickup = picked;
      _locationsConfirmed = false;
    });

    if (kIsWeb) {
      _lastRouteOverlaySignature = null;
    }

    if (_hasDestination) {
      _scheduleDrivingRouteRefresh();
    }
  }

  Future<void> _updateDestinationFromLatLng(LatLng position) async {
    final picked = await buildPickedLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      fallbackTitle: L10n.selectedDestination,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _destination = picked;
      _destinationSearchController.text = picked.title;
      _locationsConfirmed = false;
    });

    if (kIsWeb) {
      _lastRouteOverlaySignature = null;
    }
    _scheduleDrivingRouteRefresh();
  }

  void _hidePlaceSuggestions() {
    if (!_showSuggestions && _placeSuggestions.isEmpty && !_isLoadingSuggestions) {
      return;
    }
    setState(() {
      _showSuggestions = false;
      _placeSuggestions = const <PlaceSuggestion>[];
      _isLoadingSuggestions = false;
    });
  }

  void _scheduleSuggestionRefresh() {
    _suggestionRefreshDebounce?.cancel();
    _suggestionRefreshDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_refreshPlaceSuggestions());
    });
  }

  Future<void> _refreshPlaceSuggestions() async {
    final query = _destinationSearchController.text.trim();
    if (query.length < 2) {
      if (!mounted) {
        return;
      }
      setState(() {
        _placeSuggestions = const <PlaceSuggestion>[];
        _showSuggestions = false;
        _isLoadingSuggestions = false;
      });
      return;
    }

    final requestId = ++_suggestionsRequestId;
    if (mounted) {
      setState(() {
        _isLoadingSuggestions = true;
        _showSuggestions = true;
      });
    }

    final result = await PlacesAutocompleteService.fetchSuggestions(
      query: query,
      originLat: _pickup.latitude,
      originLng: _pickup.longitude,
    );

    if (!mounted || requestId != _suggestionsRequestId) {
      return;
    }

    setState(() {
      _placeSuggestions = result.suggestions;
      _isLoadingSuggestions = false;
      _showSuggestions =
          result.suggestions.isNotEmpty || result.failureMessage != null;
    });

    if (result.failureMessage != null && result.suggestions.isEmpty) {
      if (_isPlacesBackendKeyError(result.failureMessage)) {
        final fallback = await _geocodeFallbackSuggestions(query);
        if (!mounted || requestId != _suggestionsRequestId) {
          return;
        }
        if (fallback.isNotEmpty) {
          setState(() {
            _placeSuggestions = fallback;
            _isLoadingSuggestions = false;
            _showSuggestions = true;
          });
          return;
        }
      }
      _showSnackBar(result.failureMessage!);
    }
  }

  static bool _isPlacesBackendKeyError(String? message) {
    if (message == null || message.isEmpty) {
      return false;
    }
    final lower = message.toLowerCase();
    return lower.contains('not authorized') ||
        lower.contains('referer restrictions') ||
        lower.contains('request_denied');
  }

  Future<List<PlaceSuggestion>> _geocodeFallbackSuggestions(String query) async {
    try {
      final locations = await locationFromAddress(query);
      if (locations.isEmpty) {
        return const <PlaceSuggestion>[];
      }

      final first = locations.first;
      final placeId = 'geocode:${first.latitude},${first.longitude}';
      return <PlaceSuggestion>[
        PlaceSuggestion(
          placeId: placeId,
          primaryText: query,
          secondaryText: L10n.geocodingFallback,
          description: query,
        ),
      ];
    } catch (_) {
      return const <PlaceSuggestion>[];
    }
  }

  Future<void> _applyResolvedPlace(ResolvedPlace resolved) async {
    final picked = PickedLocation(
      latitude: resolved.latitude,
      longitude: resolved.longitude,
      title: resolved.title,
      subtitle: resolved.subtitle.isEmpty ? null : resolved.subtitle,
    );

    if (!mounted) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _destination = picked;
      _destinationSearchController.text = picked.title;
      _activePin = _TravelActivePin.destination;
      _locationsConfirmed = false;
      _showSuggestions = false;
      _placeSuggestions = const <PlaceSuggestion>[];
    });

    _scheduleDrivingRouteRefresh();
  }

  Future<void> _applyPlaceSuggestion(PlaceSuggestion suggestion) async {
    setState(() => _isSearchingDestination = true);

    try {
      final geocodeMatch = RegExp(r'^geocode:(-?\d+\.?\d*),(-?\d+\.?\d*)$')
          .firstMatch(suggestion.placeId.trim());
      if (geocodeMatch != null) {
        final latitude = double.tryParse(geocodeMatch.group(1)!);
        final longitude = double.tryParse(geocodeMatch.group(2)!);
        if (latitude != null && longitude != null) {
          final picked = await buildPickedLocationFromSearch(
            latitude: latitude,
            longitude: longitude,
            searchQuery: suggestion.primaryText,
          );
          await _applyResolvedPlace(
            ResolvedPlace(
              placeId: suggestion.placeId,
              title: picked.title,
              subtitle: picked.subtitle ?? '',
              latitude: latitude,
              longitude: longitude,
            ),
          );
          return;
        }
      }

      final resolved = await PlacesAutocompleteService.resolvePlace(
        suggestion.placeId,
      );
      if (!mounted) {
        return;
      }

      if (resolved == null) {
        _showSnackBar(L10n.placeDetailsLoadFailed);
        return;
      }

      await _applyResolvedPlace(resolved);
    } finally {
      if (mounted) {
        setState(() => _isSearchingDestination = false);
      }
    }
  }

  Future<PlaceSuggestion?> _pickPlaceSuggestionSheet(
    List<PlaceSuggestion> suggestions,
  ) {
    return showModalBottomSheet<PlaceSuggestion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _TravelPlaceSuggestionSheet(suggestions: suggestions);
      },
    );
  }

  Future<void> _fallbackSearchDestination(String query) async {
    final locations = await locationFromAddress(query);
    if (locations.isEmpty) {
      _showSnackBar(L10n.searchLocationNotFound);
      return;
    }

    final first = locations.first;
    final target = LatLng(first.latitude, first.longitude);
    final picked = await buildPickedLocationFromSearch(
      latitude: target.latitude,
      longitude: target.longitude,
      searchQuery: query,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _destination = picked;
      _destinationSearchController.text = picked.title;
      _activePin = _TravelActivePin.destination;
      _locationsConfirmed = false;
      _showSuggestions = false;
      _placeSuggestions = const <PlaceSuggestion>[];
    });

    _scheduleDrivingRouteRefresh();
  }

  Future<void> _searchDestination() async {
    final query = _destinationSearchController.text.trim();
    if (query.isEmpty) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() {
      _isSearchingDestination = true;
      _showSuggestions = false;
    });

    try {
      final result = await PlacesAutocompleteService.fetchSuggestions(
        query: query,
        originLat: _pickup.latitude,
        originLng: _pickup.longitude,
      );

      if (!mounted) {
        return;
      }

      final suggestions = result.suggestions;
      if (suggestions.isEmpty) {
        if (result.failureMessage != null &&
            PlacesAutocompleteService.isConfigured) {
          _showSnackBar(result.failureMessage!);
        }
        await _fallbackSearchDestination(query);
        return;
      }

      if (suggestions.length == 1) {
        await _applyPlaceSuggestion(suggestions.first);
        return;
      }

      final selected = await _pickPlaceSuggestionSheet(suggestions);
      if (!mounted || selected == null) {
        setState(() {
          _placeSuggestions = suggestions;
          _showSuggestions = true;
        });
        return;
      }

      await _applyPlaceSuggestion(selected);
    } catch (error) {
      if (mounted) {
        _showSnackBar(L10n.placeSearchFailed(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isSearchingDestination = false);
      }
    }
  }

  void _onMapTap(LatLng position) {
    _hidePlaceSuggestions();
    if (_activePin == _TravelActivePin.pickup) {
      unawaited(_updatePickupFromLatLng(position));
      return;
    }

    unawaited(_updateDestinationFromLatLng(position));
  }

  Future<void> _confirmLocations() async {
    if (!_hasDestination) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _locationsConfirmed = true);
    await _configureRide();
  }

  Future<void> _configureRide() async {
    final rideSelection = await showModalBottomSheet<TravelRideSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _TravelRideSetupSheet(
          distanceKm: _distanceKm!,
          initialSelection: _rideSelection,
          pickupLatitude: _pickup.latitude,
          pickupLongitude: _pickup.longitude,
        );
      },
    );

    if (!mounted || rideSelection == null) {
      return;
    }

    setState(() => _rideSelection = rideSelection);
    await _submit(rideSelection);
  }

  TravelPlannerResult _buildSubmissionResult() {
    final rideSelection = _rideSelection!;
    final idempotencyKey = _activeIdempotencyKey ??
        'travel_${DateTime.now().microsecondsSinceEpoch}';
    return TravelPlannerResult(
      pickup: _pickup,
      destination: _destination!,
      rideSelection: rideSelection,
      distanceKm: _distanceKm!,
      idempotencyKey: idempotencyKey,
    );
  }

  Future<void> _completeOrderAndReleaseLock(List<String> orderIds) async {
    try {
      await _completeOrder(orderIds);
    } finally {
      if (mounted) {
        setState(() {
          _isSubmittingOrder = false;
          _activeIdempotencyKey = null;
        });
      }
    }
  }

  Future<void> _completeOrder(List<String> orderIds) async {
    if (orderIds.isEmpty) {
      return;
    }

    final orderId = orderIds.first.trim();
    if (orderId.isEmpty) {
      return;
    }

    if (widget.onOpenOrderRoadmap != null) {
      await widget.onOpenOrderRoadmap!(
        orderIds,
        showTravelTracking: false,
      );
    }

    if (!mounted) {
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }

    if (!mounted) {
      return;
    }

    await navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => TravelTrackingScreen(orderId: orderId),
      ),
    );
  }

  Future<void> _submit([TravelRideSelection? selection]) async {
    if (_isSubmittingOrder) {
      return;
    }

    final rideSelection = selection ?? _rideSelection;
    if (rideSelection == null) {
      _showSnackBar(L10n.selectTimeAndVehicleFirst);
      return;
    }

    setState(() {
      _isSubmittingOrder = true;
      _activeIdempotencyKey = 'travel_${DateTime.now().microsecondsSinceEpoch}';
    });

    await showTravelPaymentFlow(
      context: context,
      grandTotal: rideSelection.estimatedFare,
      pickupLabel: _formatLocationLabel(_pickup),
      destinationLabel: _formatLocationLabel(_destination!),
      distanceKm: _distanceKm!,
      vehicleTypeLabel: rideSelection.vehicleType.label,
      scheduleLabel: rideSelection.scheduleLabel,
      onConfirmCashOnDelivery: widget.onConfirmCashOnDelivery == null
          ? null
          : () => widget.onConfirmCashOnDelivery!(_buildSubmissionResult()),
      onSubmitOmisePayment: widget.onSubmitOmisePayment == null
          ? null
          : (channel) =>
              widget.onSubmitOmisePayment!(_buildSubmissionResult(), channel),
      onOrderCompleted: _completeOrderAndReleaseLock,
    );

    if (mounted && _isSubmittingOrder) {
      setState(() {
        _isSubmittingOrder = false;
        _activeIdempotencyKey = null;
      });
    }
  }

  void _skipLocationGate() {
    setState(() {
      _pickupReady = true;
      _retryPickupOnResume = false;
    });
    _showSnackBar(L10n.tapMapForPickup);
  }

  Widget _buildLocationGateOverlay() {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.45),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 28),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.location_off_outlined,
                  size: 48,
                  color: Color(0xFFF57C00),
                ),
                const SizedBox(height: 16),
                Text(
                  L10n.enableLocationForTravel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  kIsWeb
                      ? L10n.webLocationPermissionHint
                      : L10n.locationRequiredForPickup,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B7280),
                      ),
                ),
                if (kIsWeb) ...<Widget>[
                  const SizedBox(height: 12),
                  Text(
                    L10n.webLocationBlockHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF9A3412),
                          height: 1.4,
                        ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isRequestingLocationGate
                        ? null
                        : () => unawaited(
                              _refreshPickupFromGps(forceGate: true),
                            ),
                    icon: _isRequestingLocationGate
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(L10n.enableLocation),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed:
                        _isRequestingLocationGate ? null : _skipLocationGate,
                    child: Text(L10n.pickPickupOnMapInstead),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchCard() {
    return Material(
      elevation: 8,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(20),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            InkWell(
              onTap: () => setState(() => _activePin = _TravelActivePin.pickup),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: _activePin == _TravelActivePin.pickup
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF86EFAC),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            L10n.yourLocation,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: const Color(0xFF6B7280),
                                      fontWeight: FontWeight.w600,
                                    ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isLoadingPickup
                                ? L10n.findingLocation
                                : _pickupReadout(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _activePin == _TravelActivePin.destination
                        ? const Color(0xFFF57C00)
                        : const Color(0xFFFED7AA),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _destinationSearchController,
                    focusNode: _destinationFocusNode,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) {
                      setState(() => _activePin = _TravelActivePin.destination);
                      _scheduleSuggestionRefresh();
                    },
                    onSubmitted: (_) => unawaited(_searchDestination()),
                    onTap: () =>
                        setState(() => _activePin = _TravelActivePin.destination),
                    decoration: InputDecoration(
                      hintText: L10n.whereTo,
                      border: InputBorder.none,
                      suffixIcon: _isSearchingDestination
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : IconButton(
                              icon: const Icon(Icons.search),
                              onPressed: () => unawaited(_searchDestination()),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceSuggestionsList() {
    return Material(
      elevation: 8,
      shadowColor: const Color(0x33000000),
      borderRadius: BorderRadius.circular(16),
      color: Colors.white,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.32,
        ),
        child: _isLoadingSuggestions
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            : ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _placeSuggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final suggestion = _placeSuggestions[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.location_on_outlined,
                      color: Color(0xFFF57C00),
                    ),
                    title: Text(
                      suggestion.primaryText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: suggestion.secondaryText.isEmpty
                        ? null
                        : Text(
                            suggestion.secondaryText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                    onTap: () => unawaited(_applyPlaceSuggestion(suggestion)),
                  );
                },
              ),
      ),
    );
  }

  Widget _buildBottomSheet() {
    final distanceKm = _distanceKm;
    final startingFare = _startingFare;

    return Material(
      elevation: 12,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6D3D1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (!_hasDestination)
                Text(
                  L10n.pickDestinationHint,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                )
              else if (_isLoadingRoute)
                Text(
                  L10n.calculatingRoadRoute,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                )
              else if (distanceKm != null) ...<Widget>[
                Text(
                  L10n.distanceKmFormatted(distanceKm),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF111827),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  L10n.startingFareApprox(startingFare!.round()),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF0D6B45),
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ] else
                Text(
                  L10n.roadRouteFailed,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFF9A3412),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _hasDestination &&
                        !_isLoadingRoute &&
                        distanceKm != null
                    ? (_locationsConfirmed ? _configureRide : _confirmLocations)
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF57C00),
                  disabledBackgroundColor: const Color(0xFFE5E7EB),
                  foregroundColor: Colors.white,
                  disabledForegroundColor: const Color(0xFF9CA3AF),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.route_rounded),
                label: Text(
                  _locationsConfirmed
                      ? L10n.selectVehicleType
                      : L10n.confirmTrip,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMapSearchOverlay() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildSearchCard(),
            if (_showSuggestions || _isLoadingSuggestions)
              _buildPlaceSuggestionsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildGoogleMap() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SizedBox(
          width: constraints.maxWidth,
          height: constraints.maxHeight,
          child: GoogleMap(
            padding: _mapOverlayPadding(context),
            initialCameraPosition: CameraPosition(
              target: _mapCenter,
              zoom: 15,
            ),
            onMapCreated: (controller) async {
              _mapController = controller;
              if (kIsWeb) {
                await _refreshWebMapLayout(controller: controller);
                await Future<void>.delayed(
                  const Duration(milliseconds: 300),
                );
                if (!mounted) {
                  return;
                }
                setState(() => _mapReady = true);
                await _refreshWebMapLayout(controller: controller);
              } else {
                setState(() => _mapReady = true);
              }
            },
            onCameraIdle: () {
              if (!_routeOverlayReady) {
                setState(() => _routeOverlayReady = true);
              }
            },
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: _pickupReady,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onTap: _onMapTap,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && !_webMapMountReady) {
      return Scaffold(
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            const ColoredBox(
              color: Color(0xFFE5E7EB),
              child: Center(child: CircularProgressIndicator()),
            ),
            _buildMapSearchOverlay(),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildBottomSheet(),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned.fill(child: _buildGoogleMap()),
          _buildMapSearchOverlay(),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomSheet(),
          ),
          if (!_pickupReady) _buildLocationGateOverlay(),
        ],
      ),
    );
  }
}

class _TravelPlaceSuggestionSheet extends StatelessWidget {
  const _TravelPlaceSuggestionSheet({required this.suggestions});

  final List<PlaceSuggestion> suggestions;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD6D3D1),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  L10n.pickPlace,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                itemCount: suggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final suggestion = suggestions[index];
                  return ListTile(
                    leading: const Icon(
                      Icons.place_outlined,
                      color: Color(0xFFF57C00),
                    ),
                    title: Text(
                      suggestion.primaryText,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: suggestion.secondaryText.isEmpty
                        ? null
                        : Text(suggestion.secondaryText),
                    onTap: () => Navigator.of(context).pop(suggestion),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelRideSetupSheet extends StatefulWidget {
  const _TravelRideSetupSheet({
    required this.distanceKm,
    required this.pickupLatitude,
    required this.pickupLongitude,
    this.initialSelection,
  });

  final double distanceKm;
  final double pickupLatitude;
  final double pickupLongitude;
  final TravelRideSelection? initialSelection;

  @override
  State<_TravelRideSetupSheet> createState() => _TravelRideSetupSheetState();
}

class _TravelRideSetupSheetState extends State<_TravelRideSetupSheet> {
  static const Locale _thaiLocale = Locale('th', 'TH');

  late TravelVehicleType _selectedVehicle;
  late bool _isImmediate;
  DateTime? _scheduledAt;
  bool _didApplyDefaultVehicle = false;

  @override
  void initState() {
    super.initState();
    _selectedVehicle = widget.initialSelection?.vehicleType ?? TravelVehicleType.motorcycle;
    _isImmediate = widget.initialSelection?.isImmediate ?? true;
    _scheduledAt = widget.initialSelection?.isImmediate == true
        ? null
        : widget.initialSelection?.scheduledAt;
  }

  List<TravelFareQuote> get _fareQuotes =>
      ShippingPricingPolicy.computeTravelFareQuotes(widget.distanceKm);

  TravelFareQuote? _quoteFor(TravelVehicleType vehicleType) {
    for (final quote in _fareQuotes) {
      if (quote.vehicleType == vehicleType) {
        return quote;
      }
    }
    return null;
  }

  List<TravelVehicleType> _sortedVehicleTypes(Map<TravelVehicleType, int> counts) {
    final quoteByType = <TravelVehicleType, double>{
      for (final quote in _fareQuotes) quote.vehicleType: quote.fare,
    };
    final types = List<TravelVehicleType>.from(TravelVehicleType.values);
    types.sort((TravelVehicleType a, TravelVehicleType b) {
      final aOnline = (counts[a] ?? 0) > 0;
      final bOnline = (counts[b] ?? 0) > 0;
      if (aOnline != bOnline) {
        return aOnline ? -1 : 1;
      }
      return (quoteByType[a] ?? 0).compareTo(quoteByType[b] ?? 0);
    });
    return types;
  }

  void _maybeApplyDefaultVehicle(Map<TravelVehicleType, int> counts) {
    if (_didApplyDefaultVehicle || widget.initialSelection != null) {
      return;
    }

    _didApplyDefaultVehicle = true;
    final sorted = _sortedVehicleTypes(counts);
    final defaultVehicle = sorted.firstWhere(
      (vehicle) => (counts[vehicle] ?? 0) > 0,
      orElse: () => sorted.first,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() => _selectedVehicle = defaultVehicle);
      _maybeForceScheduledWhenOffline(counts);
    });
  }

  bool _canBookImmediate(Map<TravelVehicleType, int> counts) {
    return (counts[_selectedVehicle] ?? 0) > 0;
  }

  void _maybeForceScheduledWhenOffline(Map<TravelVehicleType, int> counts) {
    if (_canBookImmediate(counts) || !_isImmediate) {
      return;
    }

    setState(() {
      _isImmediate = false;
      _scheduledAt ??= _defaultScheduledAt();
    });
  }

  DateTime _defaultScheduledAt() {
    final now = DateTime.now();
    return _scheduledAt ?? now.add(const Duration(minutes: 30));
  }

  String _formatThaiDate(DateTime value) {
    final buddhistYear = value.year + 543;
    final monthName = L10n.thaiMonthNames[value.month - 1];
    return '${value.day} $monthName $buddhistYear';
  }

  String _formatThaiTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return L10n.thaiTimeSuffix('$hour:$minute');
  }

  Widget _thaiPickerLocalization(BuildContext context, Widget? child) {
    return Localizations.override(
      context: context,
      locale: _thaiLocale,
      delegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: child,
    );
  }

  void _enableScheduledMode() {
    setState(() {
      _isImmediate = false;
      _scheduledAt ??= _defaultScheduledAt();
    });
  }

  Future<void> _pickScheduleDate() async {
    final now = DateTime.now();
    final initial = _defaultScheduledAt();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      locale: _thaiLocale,
      builder: _thaiPickerLocalization,
    );

    if (!mounted || pickedDate == null) {
      return;
    }

    final base = _defaultScheduledAt();

    setState(() {
      _isImmediate = false;
      _scheduledAt = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        base.hour,
        base.minute,
      );
    });
  }

  Future<void> _pickScheduleTime() async {
    final initial = _defaultScheduledAt();

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: _thaiPickerLocalization,
    );

    if (!mounted || pickedTime == null) {
      return;
    }

    setState(() {
      _isImmediate = false;
      final base = _defaultScheduledAt();
      _scheduledAt = DateTime(
        base.year,
        base.month,
        base.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFFFFBF6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, bottomInset + 20),
      child: SafeArea(
        top: false,
        child: StreamBuilder<Map<TravelVehicleType, int>>(
          stream: watchTravelVehicleCounts(),
          initialData: peekTravelVehicleCounts(),
          builder: (context, snapshot) {
            final isLoadingRiders =
                snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData;
            final vehicleCounts = snapshot.data ??
                <TravelVehicleType, int>{
                  for (final vehicle in TravelVehicleType.values) vehicle: 0,
                };
            _maybeApplyDefaultVehicle(vehicleCounts);
            if (!isLoadingRiders &&
                !_canBookImmediate(vehicleCounts) &&
                _isImmediate) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) {
                  return;
                }
                _maybeForceScheduledWhenOffline(vehicleCounts);
              });
            }
            final sortedVehicles = _sortedVehicleTypes(vehicleCounts);
            final selectedQuote = _quoteFor(_selectedVehicle);
            final canBookImmediate = _canBookImmediate(vehicleCounts);
            final canConfirm = selectedQuote != null &&
                (canBookImmediate && _isImmediate ||
                    (!_isImmediate && _scheduledAt != null));

            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD6D3D1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    L10n.selectVehicleType,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isLoadingRiders
                        ? L10n.distanceFindingVehicles(widget.distanceKm)
                        : L10n.distanceOnlineVehicles(
                            widget.distanceKm,
                            vehicleCounts.values.fold<int>(
                              0,
                              (total, item) => total + item,
                            ),
                          ),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  OnlineRiderSlider(
                    mode: OnlineRiderSliderMode.travel,
                    vehicleType: _selectedVehicle,
                    referenceLatitude: widget.pickupLatitude,
                    referenceLongitude: widget.pickupLongitude,
                  ),
                  const SizedBox(height: 16),
                  ...sortedVehicles.map(
                    (vehicle) {
                      final quote = _quoteFor(vehicle);
                      final onlineCount = vehicleCounts[vehicle] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _TravelVehicleFareRow(
                          vehicle: vehicle,
                          isSelected: vehicle == _selectedVehicle,
                          onlineCount: onlineCount,
                          displayFare: quote?.displayFare ?? 0,
                          onTap: () {
                            setState(() => _selectedVehicle = vehicle);
                            _maybeForceScheduledWhenOffline(vehicleCounts);
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    L10n.travelTime,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (!isLoadingRiders && !canBookImmediate)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        L10n.noVehicleOnlineSchedule(_selectedVehicle.label),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF92400E),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      ChoiceChip(
                        label: Text(L10n.now),
                        selected: _isImmediate,
                        onSelected: canBookImmediate
                            ? (_) {
                                setState(() {
                                  _isImmediate = true;
                                  _scheduledAt = null;
                                });
                              }
                            : null,
                      ),
                      ChoiceChip(
                        label: Text(L10n.setDateAndTime),
                        selected: !_isImmediate,
                        onSelected: (_) => _enableScheduledMode(),
                      ),
                    ],
                  ),
                  if (!_isImmediate) ...<Widget>[
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _TravelScheduleFieldCard(
                            label: L10n.travelDate,
                            value: _scheduledAt == null
                                ? L10n.selectDate
                                : _formatThaiDate(_scheduledAt!),
                            icon: Icons.calendar_month_rounded,
                            onTap: _pickScheduleDate,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TravelScheduleFieldCard(
                            label: L10n.travelTime,
                            value: _scheduledAt == null
                                ? L10n.selectTime
                                : _formatThaiTime(_scheduledAt!),
                            icon: Icons.access_time_rounded,
                            onTap: _pickScheduleTime,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _scheduledAt == null
                          ? L10n.scheduleDateTimeRequired
                          : L10n.scheduledTripSummary(
                              _formatThaiDate(_scheduledAt!),
                              _formatThaiTime(_scheduledAt!),
                            ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF6B7280),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: canConfirm
                          ? () {
                              Navigator.of(context).pop(
                                TravelRideSelection(
                                  vehicleType: _selectedVehicle,
                                  scheduledAt: _scheduledAt ?? DateTime.now(),
                                  isImmediate: _isImmediate,
                                  estimatedFare: selectedQuote.fare,
                                ),
                              );
                            }
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF57C00),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.check_circle),
                      label: Text(
                        selectedQuote == null
                            ? L10n.confirmSelection
                            : !canConfirm && !_isImmediate
                                ? L10n.selectDateTimeBeforeConfirm
                                : L10n.confirmFareApprox(
                                    selectedQuote.displayFare,
                                  ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _TravelVehicleFareRow extends StatelessWidget {
  const _TravelVehicleFareRow({
    required this.vehicle,
    required this.isSelected,
    required this.onlineCount,
    required this.displayFare,
    required this.onTap,
  });

  final TravelVehicleType vehicle;
  final bool isSelected;
  final int onlineCount;
  final int displayFare;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isOnline = onlineCount > 0;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF7ED) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? vehicle.accentColor : const Color(0xFFE5E7EB),
            width: isSelected ? 1.6 : 1,
          ),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: vehicle.accentColor.withValues(alpha: isOnline ? 0.12 : 0.06),
                shape: BoxShape.circle,
              ),
              child: Icon(
                vehicle.icon,
                color: vehicle.accentColor.withValues(alpha: isOnline ? 1 : 0.45),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    vehicle.label,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: isOnline
                              ? const Color(0xFF111827)
                              : const Color(0xFF9CA3AF),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isOnline
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFD1D5DB),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOnline
                            ? L10n.onlineVehicleCount(onlineCount)
                            : L10n.offline,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isOnline
                                  ? const Color(0xFF166534)
                                  : const Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Text(
              L10n.fareApprox(displayFare),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isOnline
                        ? const Color(0xFF111827)
                        : const Color(0xFF9CA3AF),
                  ),
            ),
            const SizedBox(width: 10),
            Icon(
              isSelected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: isSelected ? vehicle.accentColor : const Color(0xFFD1D5DB),
            ),
          ],
        ),
      ),
    );
  }
}

class _TravelScheduleFieldCard extends StatelessWidget {
  const _TravelScheduleFieldCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 18, color: const Color(0xFFF57C00)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B7280),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: const Color(0xFF111827),
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}