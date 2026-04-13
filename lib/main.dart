import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'cart_screen.dart';
import 'category_catalog_screen.dart';
import 'chat_screen.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'map_picker_screen.dart';
import 'services/notification_service.dart';
import 'settings_screen.dart';
import 'shop_map_screen.dart';
import 'shop_qr_scanner_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } on FirebaseException catch (e) {
    // Hot restart / debugger attach can transiently race and report duplicate default app.
    if (e.code != 'duplicate-app') {
      rethrow;
    }
  }

  try {
    await NotificationService().initialize();
  } catch (_) {}

  runApp(const MyApp());
}

bool supportsEmbeddedMap() {
  if (kIsWeb) {
    return true;
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => true,
    TargetPlatform.iOS => true,
    _ => false,
  };
}

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

  final position = await Geolocator.getCurrentPosition(
    desiredAccuracy: LocationAccuracy.high,
  );

  return buildPickedLocation(
    latitude: position.latitude,
    longitude: position.longitude,
    fallbackTitle: 'พิกัดปัจจุบันของฉัน',
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'แว๊นตลาด',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF57C00)),
        scaffoldBackgroundColor: const Color(0xFFFFF7ED),
      ),
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _navigationTimer = Timer(const Duration(seconds: 2), () async {
      final detectedLocation = await tryDetectCurrentLocation();

      if (!mounted) {
        return;
      }

      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => detectedLocation == null
              ? const LocationSetupScreen(autoDetectionFailed: true)
              : HomeScreen(userLocation: detectedLocation),
        ),
      );
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        color: Colors.white,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 220,
              height: 220,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(32),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 28,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Image.asset('assets/logo.png', fit: BoxFit.contain),
            ),
            const SizedBox(height: 24),
            Text(
              'แว๊นตลาด',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF9A3412),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Delivery starts here',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: const Color(0xFFB45309)),
            ),
            const SizedBox(height: 32),
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFF57C00)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class LocationSetupScreen extends StatefulWidget {
  const LocationSetupScreen({super.key, this.autoDetectionFailed = false});

  final bool autoDetectionFailed;

  @override
  State<LocationSetupScreen> createState() => _LocationSetupScreenState();
}

class _LocationSetupScreenState extends State<LocationSetupScreen> {
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  PickedLocation? _selectedLocation;
  bool _isDetectingLocation = false;
  bool _isSavingManualLocation = false;
  String? _statusMessage;

  bool get _supportsMapSelection => supportsEmbeddedMap();

  @override
  void initState() {
    super.initState();
    if (widget.autoDetectionFailed) {
      _statusMessage =
          'ไม่สามารถระบุตำแหน่งอัตโนมัติได้ กรุณาเลือกพิกัดบนแผนที่แล้วกดยืนยัน';
    } else {
      _detectLocationAutomatically();
    }
  }

  Future<void> _detectLocationAutomatically() async {
    setState(() {
      _isDetectingLocation = true;
      _statusMessage = 'กำลังค้นหาพิกัดปัจจุบันของคุณ...';
    });

    try {
      final location = await tryDetectCurrentLocation();
      if (location == null) {
        setState(() {
          _statusMessage =
              'ไม่สามารถระบุตำแหน่งอัตโนมัติได้ กรุณาเลือกพิกัดบนแผนที่แล้วกดยืนยัน';
        });
        return;
      }

      if (!mounted) {
        return;
      }

      _setSelectedLocation(location);
      setState(() {
        _statusMessage =
            'พบตำแหน่งของคุณแล้ว กรุณากดยืนยันเพื่อเข้าสู่หน้าหลัก';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _statusMessage =
            'ไม่สามารถระบุตำแหน่งอัตโนมัติได้ กรุณาเลือกพิกัดบนแผนที่แล้วกดยืนยัน';
      });
      _showSnackBar('ดึงตำแหน่งอัตโนมัติไม่สำเร็จ: $error');
    } finally {
      if (mounted) {
        setState(() => _isDetectingLocation = false);
      }
    }
  }

  void _setSelectedLocation(PickedLocation location) {
    setState(() {
      _selectedLocation = location;
      _latitudeController.text = location.latitude.toStringAsFixed(6);
      _longitudeController.text = location.longitude.toStringAsFixed(6);
    });
  }

  Future<void> _pickLocationOnMap() async {
    final selected = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute<PickedLocation>(
        builder: (context) => MapPickerScreen(
          title: 'เลือกพิกัดของคุณ',
          confirmLabel: 'ยืนยันพิกัดนี้',
          initialLocation: _selectedLocation,
        ),
      ),
    );

    if (!mounted || selected == null) {
      return;
    }

    _setSelectedLocation(selected);
    setState(() {
      _statusMessage =
          'เลือกพิกัดเรียบร้อยแล้ว กรุณากดยืนยันเพื่อเข้าสู่หน้าหลัก';
    });
  }

  Future<void> _applyManualCoordinates() async {
    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());

    if (latitude == null || longitude == null) {
      _showSnackBar('กรุณากรอกละติจูดและลองจิจูดให้ถูกต้อง');
      return;
    }

    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      _showSnackBar('ค่าพิกัดอยู่นอกช่วงที่ใช้งานได้');
      return;
    }

    setState(() => _isSavingManualLocation = true);

    try {
      final location = await buildPickedLocation(
        latitude: latitude,
        longitude: longitude,
        fallbackTitle: 'พิกัดที่กรอกเอง',
      );

      if (!mounted) {
        return;
      }

      _setSelectedLocation(location);
      setState(() {
        _statusMessage =
            'บันทึกพิกัดเรียบร้อยแล้ว กรุณากดยืนยันเพื่อเข้าสู่หน้าหลัก';
      });
    } finally {
      if (mounted) {
        setState(() => _isSavingManualLocation = false);
      }
    }
  }

  void _enterHomeScreen() {
    final selectedLocation = _selectedLocation;
    if (selectedLocation == null) {
      _showSnackBar('กรุณาระบุตำแหน่งก่อนเข้าสู่หน้าหลัก');
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (context) => HomeScreen(userLocation: selectedLocation),
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'ยืนยันตำแหน่ง',
          style: TextStyle(
            color: Color(0xFF9A3412),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Image.asset(
                  'assets/logo.png',
                  width: 120,
                  height: 120,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'ระบุตำแหน่งก่อนเข้าใช้งาน',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF9A3412),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _statusMessage ??
                    'แอพจะลองหาพิกัดของคุณอัตโนมัติก่อน หากไม่ได้คุณสามารถเลือกพิกัดเองแล้วกดยืนยันเพื่อเข้าสู่หน้าหลัก',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: const Color(0xFF7C2D12)),
              ),
              const SizedBox(height: 24),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const <BoxShadow>[
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 18,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'ตำแหน่งที่พร้อมใช้งาน',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF9A3412),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _selectedLocation?.title ?? 'ยังไม่มีตำแหน่งที่ยืนยัน',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827),
                            ),
                      ),
                      if (_selectedLocation?.subtitle != null) ...<Widget>[
                        const SizedBox(height: 6),
                        Text(
                          _selectedLocation!.subtitle!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF6B7280)),
                        ),
                      ],
                      if (_selectedLocation != null) ...<Widget>[
                        const SizedBox(height: 8),
                        Text(
                          'Lat ${_selectedLocation!.latitude.toStringAsFixed(6)} • Lng ${_selectedLocation!.longitude.toStringAsFixed(6)}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF9CA3AF)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (_supportsMapSelection)
                FilledButton.icon(
                  onPressed: _pickLocationOnMap,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF57C00),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('เลือกพิกัดเองบนแผนที่'),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        TextField(
                          controller: _latitudeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitude',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _longitudeController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitude',
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _isSavingManualLocation
                              ? null
                              : _applyManualCoordinates,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFFF59E0B),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          icon: _isSavingManualLocation
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.pin_drop_outlined),
                          label: const Text('บันทึกพิกัดที่กรอกเอง'),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isDetectingLocation
                    ? null
                    : _detectLocationAutomatically,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF9A3412),
                  side: const BorderSide(color: Color(0xFFFED7AA)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: _isDetectingLocation
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('ลองระบุตำแหน่งอัตโนมัติอีกครั้ง'),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _selectedLocation == null ? null : _enterHomeScreen,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9A3412),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: const Icon(Icons.check_circle),
                label: const Text('ยืนยันและเข้าสู่หน้าหลัก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.userLocation});

  final PickedLocation userLocation;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const PickedLocation _defaultDestination = PickedLocation(
    latitude: 13.7563,
    longitude: 100.5018,
    title: 'ตลาดแว๊น',
    subtitle: 'จุดหมายเริ่มต้นในระบบ',
  );

  late PickedLocation _userLocation;
  PickedLocation _destinationLocation = _defaultDestination;
  bool _isFetchingCurrentLocation = false;
  int _selectedBottomTab = 0;
  _ActiveCatalog? _activeCatalog;
  final List<CartLineItem> _cartItems = <CartLineItem>[];

  static const List<_QuickActionItem> _quickActions = <_QuickActionItem>[
    _QuickActionItem(
      label: 'เดินทาง',
      badge: 'ใหม่',
      assetPath: 'assets/rider.png',
    ),
    _QuickActionItem(label: 'ร้านอาหาร', assetPath: 'assets/food.png', serviceType: 'ร้านอาหาร'),
    _QuickActionItem(label: 'ตลาด', assetPath: 'assets/market.png', serviceType: 'ตลาด'),
    _QuickActionItem(
      label: 'ร้านค้า',
      badge: 'ดีล',
      assetPath: 'assets/shopping.png',
      serviceType: 'ร้านค้า',
    ),
    _QuickActionItem(label: 'ร้านขายยา', assetPath: 'assets/pharmacy.png', serviceType: 'ร้านขายยา'),
    _QuickActionItem(
      label: 'แผนที่',
      icon: Icons.map_outlined,
      iconColor: Color(0xFFEF8A17),
      actionKey: 'shop-map',
    ),
    _QuickActionItem(
      label: 'Coins',
      icon: Icons.monetization_on_outlined,
      iconColor: Color(0xFFEF8A17),
    ),
    _QuickActionItem(
      label: 'เพิ่มเติม',
      icon: Icons.grid_view_rounded,
      iconColor: Color(0xFFEF8A17),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _userLocation = widget.userLocation;
  }

  double? get _distanceKm {
    final meters = Geolocator.distanceBetween(
      _userLocation.latitude,
      _userLocation.longitude,
      _destinationLocation.latitude,
      _destinationLocation.longitude,
    );
    return meters / 1000;
  }

  Future<void> _setCurrentLocation() async {
    setState(() => _isFetchingCurrentLocation = true);

    try {
      final granted = await _ensureLocationPermission();
      if (!granted) {
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final pickedLocation = await buildPickedLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        fallbackTitle: 'พิกัดปัจจุบันของฉัน',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _userLocation = pickedLocation;
      });
    } catch (error) {
      _showSnackBar('ไม่สามารถดึงตำแหน่งปัจจุบันได้: $error');
    } finally {
      if (mounted) {
        setState(() => _isFetchingCurrentLocation = false);
      }
    }
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('กรุณาเปิดบริการระบุตำแหน่งของอุปกรณ์');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('กรุณาอนุญาตให้แอพเข้าถึงตำแหน่ง');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar('กรุณาเปิดสิทธิ์ตำแหน่งจากการตั้งค่าเครื่อง');
      return false;
    }

    return true;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _isLoggedIn {
    final user = FirebaseAuth.instance.currentUser;
    return user != null && !user.isAnonymous;
  }

  Future<bool> _ensureLoggedIn() async {
    if (_isLoggedIn) {
      return true;
    }

    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => LoginScreen(
          categoryLabel: 'แว๊นตลาด',
          firebaseEnabled: Firebase.apps.isNotEmpty,
          onLoggedIn: (loginContext) {
            Navigator.of(loginContext).pop(true);
          },
        ),
      ),
    );

    return mounted && loggedIn == true;
  }

  Future<void> _runProtectedAction(FutureOr<void> Function() action) async {
    final allowed = await _ensureLoggedIn();
    if (!allowed || !mounted) {
      return;
    }
    await action();
  }

  Future<void> _openShopQrScanner() async {
    final allowed = await _ensureLoggedIn();
    if (!allowed || !mounted) {
      return;
    }

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ShopQrScannerScreen()),
    );

    if (!mounted || result == null) return;
    _openCatalogFromQr(result);
  }

  void _openCatalogFromQr(String rawValue) {
    final shopId = _extractShopIdFromQr(rawValue);
    if (shopId == null) {
      _showSnackBar('QR นี้ไม่ใช่ QR ร้านค้า');
      return;
    }

    setState(() {
      _selectedBottomTab = 0;
      _activeCatalog = _ActiveCatalog(
        title: 'สินค้าร้านจาก QR',
        serviceType: '',
        shopIdFilter: shopId,
      );
    });
  }

  String? _extractShopIdFromQr(String rawValue) {
    final raw = rawValue.trim();
    if (raw.isEmpty) return null;

    if (raw.startsWith('SHOP:')) {
      final id = raw.substring(5).trim();
      return id.isEmpty ? null : id;
    }

    final uri = Uri.tryParse(raw);
    final uidFromQuery = uri?.queryParameters['uid']?.trim();
    if (uidFromQuery != null && uidFromQuery.isNotEmpty) {
      return uidFromQuery;
    }

    final looksLikeUid = RegExp(r'^[A-Za-z0-9_-]{20,}$').hasMatch(raw);
    if (looksLikeUid) {
      return raw;
    }

    return null;
  }

  Future<void> _handleQuickActionTap(_QuickActionItem item) async {
    if (item.actionKey == 'shop-map') {
      await _runProtectedAction(() async {
        if (!mounted) {
          return;
        }

        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ShopMapScreen(
              userLatitude: _userLocation.latitude,
              userLongitude: _userLocation.longitude,
              userLocationLabel: _userLocation.title,
            ),
          ),
        );
      });
      return;
    }

    if (item.serviceType == null) {
      _showSnackBar('หมวด ${item.label} ยังไม่ได้เชื่อมต่อข้อมูลร้านค้า');
      return;
    }

    await _runProtectedAction(() {
      setState(() {
        _selectedBottomTab = 0;
        _activeCatalog = _ActiveCatalog(
          title: item.label,
          serviceType: item.serviceType!,
        );
      });
    });
  }

  void _addToCart(CartProductSelection selection) {
    setState(() {
      _cartItems.add(
        CartLineItem(
          productId: selection.productId,
          shopId: selection.shopId,
          shopName: selection.shopName,
          shopLatitude: selection.shopLatitude,
          shopLongitude: selection.shopLongitude,
          productName: selection.productName,
          unitPrice: selection.unitPrice,
          imageUrl: selection.imageUrl,
          selectedToppings: selection.selectedToppings,
          quantity: selection.quantity,
          availableStock: selection.availableStock,
        ),
      );
    });
  }

  void _onBottomTabSelected(int index) {
    if (index == 0) {
      setState(() {
        _selectedBottomTab = index;
        _activeCatalog = null;
      });
      return;
    }

    unawaited(_runProtectedAction(() {
      setState(() {
        _selectedBottomTab = index;
        _activeCatalog = null;
      });

      if (index == 1 || index == 2 || index == 3) {
        return;
      }

      const labels = <String>['โฮม', 'ตะกร้า', 'ข้อความ'];
      _showSnackBar('หน้า ${labels[index]} กำลังพัฒนา');
    }));
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = _distanceKm;
    final cartQuantity = _cartItems.fold<int>(0, (sum, item) => sum + item.quantity);
    final body = switch (_selectedBottomTab) {
      0 => _activeCatalog == null
          ? _buildHomeBody(distanceKm)
          : CategoryCatalogScreen(
              title: _activeCatalog!.title,
              serviceType: _activeCatalog!.serviceType,
              shopIdFilter: _activeCatalog!.shopIdFilter,
              customerLatitude: _userLocation.latitude,
              customerLongitude: _userLocation.longitude,
              onConfirmOrder: _addToCart,
              embedded: true,
              onBack: () => setState(() => _activeCatalog = null),
            ),
      1 => CartScreen(
          cartItems: _cartItems,
          customerLatitude: _userLocation.latitude,
          customerLongitude: _userLocation.longitude,
          customerLocationLabel: _userLocation.title,
        ),
      2 => const ChatScreen(),
      _ => SettingsScreen(
          onLoggedOut: () {
            if (!mounted) {
              return;
            }
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(
                builder: (_) => LoginScreen(
                  categoryLabel: 'แว๊นตลาด',
                  firebaseEnabled: Firebase.apps.isNotEmpty,
                  onLoggedIn: (loginContext) {
                    Navigator.of(loginContext).pushAndRemoveUntil(
                      MaterialPageRoute<void>(builder: (_) => const SplashScreen()),
                      (route) => false,
                    );
                  },
                ),
              ),
              (route) => false,
            );
          },
        ),
    };

    return Scaffold(
      backgroundColor: const Color(0xFFF4FAFB),
      body: body,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFFFFC247),
              Color(0xFFFF8A1E),
              Color(0xFFE55A00),
            ],
            stops: <double>[0.0, 0.52, 1.0],
          ),
        ),
        child: NavigationBarTheme(
          data: NavigationBarThemeData(
            backgroundColor: Colors.transparent,
            indicatorColor: const Color(0x40FFFFFF),
            iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
              if (states.contains(WidgetState.selected)) {
                return const IconThemeData(color: Colors.white);
              }
              return const IconThemeData(color: Color(0xFFFFF2D6));
            }),
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
              if (states.contains(WidgetState.selected)) {
                return const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                );
              }
              return const TextStyle(
                color: Color(0xFFFFF2D6),
                fontWeight: FontWeight.w600,
              );
            }),
          ),
          child: NavigationBar(
            height: 74,
            selectedIndex: _selectedBottomTab,
            onDestinationSelected: _onBottomTabSelected,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: <NavigationDestination>[
              const NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'โฮม',
              ),
              NavigationDestination(
                icon: _CartNavIcon(
                  icon: Icons.shopping_cart_outlined,
                  count: cartQuantity,
                ),
                selectedIcon: _CartNavIcon(
                  icon: Icons.shopping_cart,
                  count: cartQuantity,
                ),
                label: 'ตะกร้า',
              ),
              const NavigationDestination(
                icon: Icon(Icons.message_outlined),
                selectedIcon: Icon(Icons.message),
                label: 'ข้อความ',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'ตั้งค่า',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeBody(double? distanceKm) {
    return CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color(0xFFFFC247),
                    Color(0xFFFF8A1E),
                    Color(0xFFE55A00),
                  ],
                  stops: <double>[0.0, 0.52, 1.0],
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(28),
                  bottomRight: Radius.circular(28),
                ),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Color(0x33E55A00),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    top: 6,
                    right: 18,
                    child: Icon(
                      Icons.auto_awesome,
                      color: Color(0xFFFFF2C7),
                      size: 22,
                    ),
                  ),
                  Positioned(
                    top: 34,
                    right: 54,
                    child: Icon(
                      Icons.auto_awesome,
                      color: Color(0xFFFFE3A3),
                      size: 12,
                    ),
                  ),
                  Positioned(
                    top: -28,
                    right: -6,
                    child: Container(
                      width: 126,
                      height: 126,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x26FFFFFF),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 92,
                    left: -18,
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0x18FFFFFF),
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Column(
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            _HeaderCircleButton(
                              icon: Icons.qr_code_scanner_rounded,
                              onTap: _openShopQrScanner,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                height: 54,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(28),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    const Icon(
                                      Icons.search,
                                      color: Color(0xFF6B7280),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        'ค้นหาในแอพ แว๊นตลาด',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: const Color(0xFF6B7280),
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _HeaderAvatarBadge(
                              label: 'G',
                              backgroundColor: const Color(0xFFFFC928),
                              foregroundColor: const Color(0xFF7A4B00),
                            ),
                            const SizedBox(width: 10),
                            const _HeaderAvatarBadge(
                              icon: Icons.person,
                              backgroundColor: Color(0xFF58BFC1),
                              foregroundColor: Colors.white,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0x26FFF7EE),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0x4DFFF3DB)),
                          ),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    const Text(
                                      'ตำแหน่งของคุณ',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _userLocation.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton(
                                onPressed: _isFetchingCurrentLocation
                                    ? null
                                    : _setCurrentLocation,
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFFB64700),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: _isFetchingCurrentLocation
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('อัปเดตพิกัด'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate((
                BuildContext context,
                int index,
              ) {
                final item = _quickActions[index];
                return _DashboardTile(
                  item: item,
                  onTap: () => _handleQuickActionTap(item),
                );
              }, childCount: _quickActions.length),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 8,
                crossAxisSpacing: 12,
                childAspectRatio: 0.82,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: _InfoCard(
                          title: 'ตำแหน่งล่าสุด',
                          primary: _userLocation.title,
                          secondary:
                              _userLocation.subtitle ??
                              'Lat ${_userLocation.latitude.toStringAsFixed(4)} • Lng ${_userLocation.longitude.toStringAsFixed(4)}',
                          trailing: const _SquareImagePlaceholder(size: 46),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _InfoCard(
                          title: 'ระยะทางถึงจุดหมาย',
                          primary: distanceKm == null
                              ? '-'
                              : '${distanceKm.toStringAsFixed(1)} กม.',
                          secondary: _destinationLocation.title,
                          trailing: Container(
                            width: 46,
                            height: 46,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFFF1C2),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Text(
                                'G',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFE8A400),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _WideSummaryCard(
                    destination: _destinationLocation,
                    distanceKm: distanceKm,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
  }

  Widget _buildPlaceholderBody(String title, IconData icon, {String? message}) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 42, color: const Color(0xFF9CA3AF)),
              const SizedBox(height: 10),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1F2937),
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                message ?? 'ส่วนนี้กำลังพัฒนา',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF6B7280),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionItem {
  const _QuickActionItem({
    required this.label,
    this.badge,
    this.assetPath,
    this.icon,
    this.iconColor,
    this.serviceType,
    this.actionKey,
  });

  final String label;
  final String? badge;
  final String? assetPath;
  final IconData? icon;
  final Color? iconColor;
  final String? serviceType;
  final String? actionKey;
}

class _ActiveCatalog {
  const _ActiveCatalog({
    required this.title,
    required this.serviceType,
    this.shopIdFilter,
  });

  final String title;
  final String serviceType;
  final String? shopIdFilter;
}

class _CartNavIcon extends StatelessWidget {
  const _CartNavIcon({required this.icon, required this.count});

  final IconData icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return Icon(icon);
    }

    final badgeText = count > 99 ? '99+' : '$count';
    return SizedBox(
      width: 28,
      height: 28,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          Align(
            alignment: Alignment.center,
            child: Icon(icon),
          ),
          Positioned(
            top: -4,
            right: -10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFDC2626),
                borderRadius: BorderRadius.circular(999),
              ),
              constraints: const BoxConstraints(minWidth: 16),
              child: Text(
                badgeText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCircleButton extends StatelessWidget {
  const _HeaderCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

class _HeaderAvatarBadge extends StatelessWidget {
  const _HeaderAvatarBadge({
    this.label,
    this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String? label;
  final IconData? icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: Center(
        child: icon != null
            ? Icon(icon, color: foregroundColor, size: 28)
            : Text(
                label ?? '',
                style: TextStyle(
                  color: foregroundColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                ),
              ),
      ),
    );
  }
}

class _DashboardTile extends StatelessWidget {
  const _DashboardTile({required this.item, required this.onTap});

  final _QuickActionItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final placeholderSize = item.badge == null ? 68.0 : 62.0;
    final iconLiftOffset = placeholderSize * 0.30;
    final labelLiftUpOffset = placeholderSize * 0.20;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF8FA),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Stack(
          children: <Widget>[
            if (item.badge != null)
              Align(
                alignment: Alignment.topLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6A00),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    item.badge!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                Transform.translate(
                  offset: Offset(0, -iconLiftOffset),
                  child: _SquareImagePlaceholder(
                    size: placeholderSize,
                    assetPath: item.assetPath,
                    icon: item.icon,
                    iconColor: item.iconColor,
                  ),
                ),
                const SizedBox(height: 5),
                Transform.translate(
                  offset: Offset(0, -labelLiftUpOffset),
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontSize: 13,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1F2937),
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
}

class _SquareImagePlaceholder extends StatelessWidget {
  const _SquareImagePlaceholder({
    required this.size,
    this.assetPath,
    this.icon,
    this.iconColor,
  });

  final double size;
  final String? assetPath;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    if (assetPath != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: const Color(0x66DDEEF1)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(size * 0.24),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Image.asset(assetPath!, fit: BoxFit.contain),
          ),
        ),
      );
    }

    if (icon != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0x14FFFFFF),
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: const Color(0x66DDEEF1)),
        ),
        child: Icon(
          icon,
          color: iconColor ?? const Color(0xFF0D6B45),
          size: size * 0.68,
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(color: const Color(0x66DDEEF1)),
      ),
      child: Icon(Icons.add, color: const Color(0xFFB8CDD3), size: size * 0.45),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.primary,
    required this.secondary,
    required this.trailing,
  });

  final String title;
  final String primary;
  final String secondary;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      primary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      secondary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing,
            ],
          ),
        ],
      ),
    );
  }
}

class _WideSummaryCard extends StatelessWidget {
  const _WideSummaryCard({required this.destination, required this.distanceKm});

  final PickedLocation destination;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final distanceText = distanceKm == null
        ? 'รอการคำนวณระยะทาง'
        : 'จากตำแหน่งปัจจุบัน ${distanceKm!.toStringAsFixed(1)} กม.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          const _SquareImagePlaceholder(
            size: 72,
            assetPath: 'assets/market.png',
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'ปลายทางเริ่มต้น',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  destination.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  distanceText,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF0D6B45),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
