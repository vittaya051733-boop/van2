import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'cart_screen.dart';
import 'category_catalog_screen.dart';
import 'chat_screen.dart';
import 'firebase_options.dart';
import 'login_screen.dart';
import 'map_picker_screen.dart';
import 'order_roadmap_screen.dart';
import 'pricing_config_service.dart';
import 'services/notification_service.dart';
import 'settings_screen.dart';
import 'shop_map_screen.dart';
import 'shop_qr_scanner_screen.dart';
import 'storage_helper.dart';
import 'travel_planner_screen.dart';

const bool kAppCheckForceDebug =
  bool.fromEnvironment('APP_CHECK_DEBUG', defaultValue: false);

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

  final useDebugAppCheck = !kReleaseMode || kAppCheckForceDebug;
  try {
    await FirebaseAppCheck.instance
        .activate(
        providerAndroid: useDebugAppCheck
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
        providerApple: useDebugAppCheck
          ? const AppleDebugProvider()
          : const AppleDeviceCheckProvider(),
        )
        .timeout(const Duration(seconds: 5));
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

    if (useDebugAppCheck) {
      FirebaseAppCheck.instance.onTokenChange.listen((token) {
        debugPrint('App Check token: $token');
      });
    }

    try {
      await FirebaseAppCheck.instance
          .getToken(true)
          .timeout(const Duration(seconds: 5));
    } catch (error) {
      if (useDebugAppCheck) {
        debugPrint('Could not get App Check token on startup: $error');
      }
    }
  } catch (error) {
    if (useDebugAppCheck) {
      debugPrint('App Check activate failed: $error');
    }
    // Keep app booting in environments where App Check is not configured yet.
  }

  // Catalog/product reads require a signed-in user in Firestore rules.
  // Keep van2 usable by ensuring a lightweight anonymous session exists.
  try {
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
  } catch (_) {
    // If anonymous auth is disabled, app can still proceed and surface errors in UI.
  }

  try {
    await NotificationService().initialize();
  } catch (_) {}

  try {
    await PricingConfigService.instance.loadAndApplyOnce();
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

  // Emulator can return a valid cached fix faster than a fresh GNSS query.
  final lastKnown = await Geolocator.getLastKnownPosition();
  if (lastKnown != null) {
    return buildPickedLocation(
      latitude: lastKnown.latitude,
      longitude: lastKnown.longitude,
      fallbackTitle: 'พิกัดล่าสุดของฉัน',
    );
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

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    PricingConfigService.instance.startRealtimeSync();
  }

  @override
  void dispose() {
    unawaited(PricingConfigService.instance.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'แว๊นตลาด',
      debugShowCheckedModeBanner: false,
      navigatorKey: MyApp.navigatorKey,
      locale: const Locale('th', 'TH'),
      supportedLocales: const <Locale>[
        Locale('th', 'TH'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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

  Future<void> _proceedFromSplash() async {
    PickedLocation? detectedLocation;
    try {
      detectedLocation = await tryDetectCurrentLocation().timeout(
        const Duration(seconds: 10),
      );
    } catch (_) {
      detectedLocation = null;
    }

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
  }

  @override
  void initState() {
    super.initState();
    _navigationTimer = Timer(const Duration(seconds: 2), _proceedFromSplash);
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

class _LocationSetupScreenState extends State<LocationSetupScreen>
    with WidgetsBindingObserver {
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();

  PickedLocation? _selectedLocation;
  bool _isDetectingLocation = false;
  bool _isSavingManualLocation = false;
  bool _isRequestingLocationPermission = false;
  bool _retryAutoDetectOnResume = false;
  String? _statusMessage;

  bool get _supportsMapSelection => supportsEmbeddedMap();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.autoDetectionFailed) {
      _statusMessage =
          'ไม่สามารถระบุตำแหน่งอัตโนมัติได้ กรุณาเลือกพิกัดบนแผนที่แล้วกดยืนยัน';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _requestCustomerLocationPermission();
      });
    } else {
      _detectLocationAutomatically();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state != AppLifecycleState.resumed || !_retryAutoDetectOnResume) {
      return;
    }

    _retryAutoDetectOnResume = false;
    if (!_isDetectingLocation) {
      unawaited(_detectLocationAutomatically());
    }
  }

  Future<void> _requestCustomerLocationPermission() async {
    if (_isRequestingLocationPermission) {
      return;
    }

    setState(() => _isRequestingLocationPermission = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) {
          return;
        }
        final openLocation = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('เปิดตำแหน่งลูกค้า'),
            content: const Text(
              'ระบบยังปิดตำแหน่งอยู่ ต้องเปิด Location ก่อนจึงจะระบุตำแหน่งอัตโนมัติได้',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('ไปเปิดตำแหน่ง'),
              ),
            ],
          ),
        );

        if (openLocation == true) {
          final opened = await Geolocator.openLocationSettings();
          if (opened) {
            _retryAutoDetectOnResume = true;
            _showSnackBar('กลับเข้าแอปแล้วระบบจะลองระบุตำแหน่งให้อัตโนมัติ');
          } else {
            _showSnackBar('ไม่สามารถเปิดหน้าตั้งค่าตำแหน่งได้ กรุณาเปิด Location ในเครื่องด้วยตนเอง');
          }
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) {
          return;
        }
        final openAppSettings = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ต้องอนุญาตสิทธิ์ตำแหน่ง'),
            content: const Text(
              'คุณปิดสิทธิ์ตำแหน่งแบบถาวรไว้ กรุณาไปที่ตั้งค่าแอปเพื่ออนุญาตสิทธิ์ตำแหน่ง',
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('ไปตั้งค่าแอป'),
              ),
            ],
          ),
        );

        if (openAppSettings == true) {
          final opened = await Geolocator.openAppSettings();
          if (opened) {
            _retryAutoDetectOnResume = true;
            _showSnackBar('กลับเข้าแอปแล้วระบบจะลองระบุตำแหน่งให้อัตโนมัติ');
          } else {
            _showSnackBar('ไม่สามารถเปิดหน้า App Settings ได้ กรุณาเปิดสิทธิ์ตำแหน่งในตั้งค่าแอปด้วยตนเอง');
          }
        }
        return;
      }

      if (permission == LocationPermission.denied) {
        _showSnackBar('ยังไม่ได้รับสิทธิ์ตำแหน่ง กรุณาอนุญาตเพื่อใช้งานต่อ');
        return;
      }

      await _detectLocationAutomatically();
    } finally {
      if (mounted) {
        setState(() => _isRequestingLocationPermission = false);
      }
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
        await _requestCustomerLocationPermission();
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
      await _requestCustomerLocationPermission();
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
    WidgetsBinding.instance.removeObserver(this);
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
  TravelRideSelection? _travelRideSelection;
  bool _isFetchingCurrentLocation = false;
  int _selectedBottomTab = 0;
  int _unreadChatCount = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _unreadChatSubscription;
  _ActiveCatalog? _activeCatalog;
  final List<CartLineItem> _cartItems = <CartLineItem>[];

  static const List<_QuickActionItem> _quickActions = <_QuickActionItem>[
    _QuickActionItem(
      label: 'เดินทาง',
      badge: 'ใหม่',
      assetPath: 'assets/rider.png',
      actionKey: 'travel',
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
    _listenUnreadChats();
  }

  @override
  void dispose() {
    _unreadChatSubscription?.cancel();
    super.dispose();
  }

  void _listenUnreadChats() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    _unreadChatSubscription?.cancel();
    _unreadChatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: user.uid)
        .snapshots()
        .listen((snapshot) {
      var totalUnread = 0;
      for (final doc in snapshot.docs) {
        final unreadMap = doc.data()['unreadCounts'] as Map<String, dynamic>?;
        final unreadValue = unreadMap?[user.uid];
        if (unreadValue is int) {
          totalUnread += unreadValue;
        } else if (unreadValue is num) {
          totalUnread += unreadValue.toInt();
        }
      }

      if (!mounted) {
        return;
      }
      setState(() => _unreadChatCount = totalUnread);
    });
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
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
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

  Future<void> _pickCartCustomerLocation() async {
    final selected = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute<PickedLocation>(
        builder: (context) => MapPickerScreen(
          title: 'เปลี่ยนพิกัดปลายทาง',
          confirmLabel: 'ใช้พิกัดนี้',
          initialLocation: _userLocation,
        ),
      ),
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _userLocation = selected;
    });
    _showSnackBar('อัปเดตพิกัดปลายทางเรียบร้อยแล้ว');
  }

  Future<void> _startTravelPlanner() async {
    final result = await Navigator.of(context).push<TravelPlannerResult>(
      MaterialPageRoute<TravelPlannerResult>(
        builder: (context) => TravelPlannerScreen(
          initialPickup: _userLocation,
          initialDestination: _destinationLocation,
          initialRideSelection: _travelRideSelection,
          onConfirmCashOnDelivery: _confirmTravelCashOnDeliveryOrder,
          onSubmitPromptPaySlip: _submitTravelPromptPaySlipOrder,
          onOpenOrderRoadmap: _openOrderRoadmap,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _userLocation = result.pickup;
      _destinationLocation = result.destination;
      _travelRideSelection = result.rideSelection;
    });

    _showSnackBar('ตั้งค่าจุดรับ จุดส่ง เวลา และประเภทรถเรียบร้อยแล้ว');
  }

  Future<void> _applySharedLocationToCart() async {
    final controller = TextEditingController();
    final rawValue = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('วางพิกัดที่แชร์มา'),
          content: TextField(
            controller: controller,
            autofocus: true,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'เช่น 13.7563,100.5018 หรือ Google Maps URL',
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('ใช้พิกัดนี้'),
            ),
          ],
        );
      },
    );

    if (!mounted || rawValue == null || rawValue.isEmpty) {
      return;
    }

    final resolvedInput = await _resolveSharedLocationInput(rawValue);
    final coordinates = _parseSharedCoordinates(resolvedInput);
    if (coordinates == null) {
      _showSnackBar('ไม่พบพิกัดในลิงก์นี้ ลองแชร์แบบมีพิกัดหรือปักหมุดจากแผนที่แทน');
      return;
    }

    try {
      final picked = await buildPickedLocation(
        latitude: coordinates.$1,
        longitude: coordinates.$2,
        fallbackTitle: 'พิกัดที่แชร์มา',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _userLocation = picked;
      });
      _showSnackBar('อัปเดตปลายทางจากพิกัดที่แชร์มาแล้ว');
    } catch (error) {
      _showSnackBar('ไม่สามารถใช้พิกัดที่แชร์มาได้: $error');
    }
  }

  Future<String> _resolveSharedLocationInput(String rawValue) async {
    final text = rawValue.trim();
    if (text.isEmpty) {
      return rawValue;
    }

    final urlMatch = RegExp(r'https?://[^\s]+', caseSensitive: false).firstMatch(text);
    final candidateUrl = urlMatch?.group(0) ?? text;
    final candidateUri = Uri.tryParse(candidateUrl);
    if (candidateUri == null || !candidateUri.hasScheme) {
      return rawValue;
    }
    if (!_shouldTryExpandingShareLink(candidateUri)) {
      return rawValue;
    }

    final expandedUrl = await _expandShortUrl(candidateUri);
    if (expandedUrl == null || expandedUrl.isEmpty || expandedUrl == candidateUrl) {
      return rawValue;
    }
    return '$rawValue\n$expandedUrl';
  }

  bool _shouldTryExpandingShareLink(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'maps.app.goo.gl' ||
        host == 'goo.gl' ||
        host == 'g.co' ||
        host == 't.co' ||
        host == 'bit.ly' ||
        host == 'tinyurl.com';
  }

  Future<String?> _expandShortUrl(Uri uri) async {
    try {
      final response = await http
          .get(
            uri,
            headers: const <String, String>{
              'User-Agent': 'Mozilla/5.0',
            },
          )
          .timeout(const Duration(seconds: 8));
      final finalUrl = response.request?.url.toString();
      if (finalUrl != null && finalUrl.isNotEmpty && finalUrl != uri.toString()) {
        return _sanitizeSharedUrl(finalUrl);
      }

      final extractedFromHtml = _extractUrlFromHtml(response.body);
      if (extractedFromHtml != null) {
        return extractedFromHtml;
      }

      if (finalUrl == null || finalUrl.isEmpty) {
        return null;
      }
      return _sanitizeSharedUrl(finalUrl);
    } catch (_) {
      return null;
    }
  }

  String? _extractUrlFromHtml(String html) {
    if (html.isEmpty) {
      return null;
    }

    final candidates = <RegExp>[
      RegExp(r'https://www\.google\.com/maps[^\s<]+', caseSensitive: false),
      RegExp(r'https://maps\.google\.com[^\s<]+', caseSensitive: false),
      RegExp(r'https://www\.google\.com/maps\?q=[^\s<]+', caseSensitive: false),
    ];

    for (final pattern in candidates) {
      final match = pattern.firstMatch(html);
      if (match == null) {
        continue;
      }
      final raw = match.group(0);
      if (raw == null || raw.isEmpty) {
        continue;
      }
      final normalized = raw
          .replaceAll(r'\u0026', '&')
          .replaceAll('&amp;', '&')
          .replaceAll('\\/', '/');
      return _sanitizeSharedUrl(normalized);
    }

    return null;
  }

  String _sanitizeSharedUrl(String value) {
    return value.trim().replaceFirst(RegExp(r'[)\].,;]+$'), '');
  }

  (double, double)? _parseSharedCoordinates(String rawValue) {
    final normalized = rawValue.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final seen = <String>{};
    final queue = <String>[];

    void enqueue(String? value) {
      if (value == null) {
        return;
      }
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }
      if (seen.add(trimmed)) {
        queue.add(trimmed);
      }
    }

    enqueue(normalized);

    final embeddedUrlPattern = RegExp(r'https?://[^\s]+', caseSensitive: false);

    while (queue.isNotEmpty) {
      final current = queue.removeLast();

      final direct = _extractCoordinatesFromText(current);
      if (direct != null) {
        return direct;
      }

      for (final decoded in _decodeShareTextVariants(current)) {
        enqueue(decoded);
      }

      for (final match in embeddedUrlPattern.allMatches(current)) {
        enqueue(match.group(0));
      }

      final uri = Uri.tryParse(current);
      if (uri == null) {
        continue;
      }

      enqueue(uri.fragment);
      enqueue(uri.path);

      for (final value in uri.queryParameters.values) {
        enqueue(value);
      }

      for (final key in <String>['q', 'query', 'll', 'daddr', 'destination', 'text', 'u']) {
        enqueue(uri.queryParameters[key]);
      }
    }

    return null;
  }

  Set<String> _decodeShareTextVariants(String input) {
    final results = <String>{};
    var current = input;

    for (var i = 0; i < 3; i++) {
      try {
        final decoded = Uri.decodeFull(current);
        if (decoded != current) {
          results.add(decoded);
          current = decoded;
        }
      } catch (_) {
        break;
      }
    }

    try {
      final componentDecoded = Uri.decodeComponent(input.replaceAll('+', ' '));
      if (componentDecoded != input) {
        results.add(componentDecoded);
      }
    } catch (_) {}

    return results;
  }

  (double, double)? _extractCoordinatesFromText(String text) {
    final patterns = <RegExp>[
      RegExp(
        r'lat(?:itude)?\s*[:=]\s*(-?\d+(?:\.\d+)?)\D+(?:lng|lon|long|longitude)\s*[:=]\s*(-?\d+(?:\.\d+)?)',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:lng|lon|long|longitude)\s*[:=]\s*(-?\d+(?:\.\d+)?)\D+lat(?:itude)?\s*[:=]\s*(-?\d+(?:\.\d+)?)',
        caseSensitive: false,
      ),
      RegExp(r'geo:\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)', caseSensitive: false),
      RegExp(r'@\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)'),
      RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)', caseSensitive: false),
      RegExp(r'(-?\d+(?:\.\d+)?)\s*[,;]\s*(-?\d+(?:\.\d+)?)'),
    ];

    for (var i = 0; i < patterns.length; i++) {
      final match = patterns[i].firstMatch(text);
      if (match == null) {
        continue;
      }

      if (i == 1) {
        final reversed = _toValidCoordinates(match.group(2), match.group(1));
        if (reversed != null) {
          return reversed;
        }
        continue;
      }

      final parsed = _toValidCoordinates(match.group(1), match.group(2));
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  (double, double)? _toValidCoordinates(String? latitudeRaw, String? longitudeRaw) {
    final latitude = double.tryParse(latitudeRaw ?? '');
    final longitude = double.tryParse(longitudeRaw ?? '');
    if (!_isValidCoordinates(latitude, longitude)) {
      return null;
    }
    return (latitude!, longitude!);
  }

  bool _isValidCoordinates(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) {
      return false;
    }
    return latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
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
    if (item.actionKey == 'travel') {
      await _runProtectedAction(() async {
        await _startTravelPlanner();
      });
      return;
    }

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

  void _removeCartItem(int index) {
    if (index < 0 || index >= _cartItems.length) {
      return;
    }
    setState(() {
      _cartItems.removeAt(index);
    });
  }

  Future<User> _requireCheckoutUser() async {
    final allowed = await _ensureLoggedIn();
    if (!allowed) {
      throw Exception('กรุณาเข้าสู่ระบบก่อนยืนยันคำสั่งซื้อ');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw Exception('กรุณาเข้าสู่ระบบก่อนยืนยันคำสั่งซื้อ');
    }

    try {
      await user.getIdToken(true);
    } catch (_) {
      throw Exception('ไม่สามารถยืนยันตัวตนล่าสุดได้ กรุณาลองใหม่อีกครั้ง');
    }

    return user;
  }

  Future<List<String>> _confirmCashOnDeliveryOrder() async {
    final user = await _requireCheckoutUser();
    final result = await _createCheckoutOrders(
      user: user,
      paymentMethod: 'cash_on_delivery',
      paymentMethodLabel: 'จ่ายปลายทาง',
      paymentStatus: 'cash_on_delivery',
      paymentStatusLabel: 'ชำระปลายทาง',
      auditSource: 'cod_confirm_dialog',
      riderNotifyReady: true,
      notifyRider: true,
      createdEventLabel: 'ลูกค้าสร้างออเดอร์แบบจ่ายปลายทาง',
    );
    return result.orderIds;
  }

  Future<List<String>> _confirmTravelCashOnDeliveryOrder(
    TravelPlannerResult request,
  ) async {
    final user = await _requireCheckoutUser();
    final result = await _createTravelOrder(
      user: user,
      request: request,
      paymentMethod: 'cash_on_delivery',
      paymentMethodLabel: 'จ่ายปลายทาง',
      paymentStatus: 'cash_on_delivery',
      paymentStatusLabel: 'ชำระปลายทาง',
      auditSource: 'travel_cod_confirm_dialog',
      riderNotifyReady: true,
      notifyRider: true,
      createdEventLabel: 'ลูกค้าสร้างคำขอเดินทางแบบจ่ายปลายทาง',
    );
    return result.orderIds;
  }

  Future<PaymentSlipSubmissionResult> _submitPromptPaySlipOrder(
    PaymentSlipSubmissionRequest request,
  ) async {
    final user = await _requireCheckoutUser();
    if (request.bytes.isEmpty) {
      throw Exception('ไฟล์สลิปว่างเปล่า');
    }

    final creation = await _createCheckoutOrders(
      user: user,
      paymentMethod: 'promptpay_qr',
      paymentMethodLabel: 'จ่ายด้วยทรูมันนี่',
      paymentStatus: 'awaiting_slip_review',
      paymentStatusLabel: 'รอตรวจสลิป',
      auditSource: 'promptpay_slip_dialog',
      riderNotifyReady: false,
      notifyRider: false,
      createdEventLabel: 'ลูกค้าสร้างออเดอร์และแนบสลิปรอตรวจ',
    );

    if (creation.orderIds.isEmpty) {
      throw Exception('ไม่สามารถสร้างออเดอร์ได้');
    }

    final paymentGroupId = 'PAY-${DateTime.now().millisecondsSinceEpoch}';
    final sanitizedFileName = _sanitizeSlipFileName(request.fileName);
    final storagePath = 'payment_slips/${user.uid}/$paymentGroupId/$sanitizedFileName';

    final uploadTask = await StorageHelper.instance.ref(storagePath).putData(
      request.bytes,
      SettableMetadata(
        contentType: request.contentType ?? 'image/jpeg',
        customMetadata: <String, String>{
          'uploadedBy': user.uid,
          'paymentGroupId': paymentGroupId,
          'orderIds': creation.orderIds.join(','),
        },
      ),
    );
    final downloadUrl = await uploadTask.ref.getDownloadURL();

    await _attachSlipToOrders(
      orderIds: creation.orderIds,
      paymentGroupId: paymentGroupId,
      storagePath: storagePath,
      downloadUrl: downloadUrl,
      fileName: sanitizedFileName,
      contentType: request.contentType,
      sizeBytes: request.sizeBytes,
      uploadedBy: user.uid,
      combinedExpectedAmount: creation.combinedGrandTotal,
    );

    final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('verifyOrderPaymentSlip');
    final response = await callable.call(<String, dynamic>{
      'orderIds': creation.orderIds,
      'storagePath': storagePath,
      'paymentGroupId': paymentGroupId,
      'fileName': sanitizedFileName,
      if (request.contentType != null) 'contentType': request.contentType,
    });

    final payload = response.data;
    final data = payload is Map ? Map<String, dynamic>.from(payload) : const <String, dynamic>{};
    final status = (data['status'] as String?)?.trim() ?? 'submitted';
    final message = (data['message'] as String?)?.trim();

    return PaymentSlipSubmissionResult(
      orderIds: creation.orderIds,
      verificationStatus: status,
      message: message == null || message.isEmpty
          ? 'แนบสลิปเรียบร้อยแล้ว'
          : message,
    );
  }

  Future<PaymentSlipSubmissionResult> _submitTravelPromptPaySlipOrder(
    TravelPlannerResult travel,
    PaymentSlipSubmissionRequest request,
  ) async {
    final user = await _requireCheckoutUser();
    if (request.bytes.isEmpty) {
      throw Exception('ไฟล์สลิปว่างเปล่า');
    }

    final creation = await _createTravelOrder(
      user: user,
      request: travel,
      paymentMethod: 'promptpay_qr',
      paymentMethodLabel: 'จ่ายด้วยทรูมันนี่',
      paymentStatus: 'awaiting_slip_review',
      paymentStatusLabel: 'รอตรวจสลิป',
      auditSource: 'travel_promptpay_slip_dialog',
      riderNotifyReady: false,
      notifyRider: false,
      createdEventLabel: 'ลูกค้าสร้างคำขอเดินทางและแนบสลิปรอตรวจ',
    );

    if (creation.orderIds.isEmpty) {
      throw Exception('ไม่สามารถสร้างออเดอร์เดินทางได้');
    }

    final paymentGroupId = 'TRAVEL-PAY-${DateTime.now().millisecondsSinceEpoch}';
    final sanitizedFileName = _sanitizeSlipFileName(request.fileName);
    final storagePath = 'payment_slips/${user.uid}/$paymentGroupId/$sanitizedFileName';

    final uploadTask = await StorageHelper.instance.ref(storagePath).putData(
      request.bytes,
      SettableMetadata(
        contentType: request.contentType ?? 'image/jpeg',
        customMetadata: <String, String>{
          'uploadedBy': user.uid,
          'paymentGroupId': paymentGroupId,
          'orderIds': creation.orderIds.join(','),
          'orderType': 'travel_passenger',
        },
      ),
    );
    final downloadUrl = await uploadTask.ref.getDownloadURL();

    await _attachSlipToOrders(
      orderIds: creation.orderIds,
      paymentGroupId: paymentGroupId,
      storagePath: storagePath,
      downloadUrl: downloadUrl,
      fileName: sanitizedFileName,
      contentType: request.contentType,
      sizeBytes: request.sizeBytes,
      uploadedBy: user.uid,
      combinedExpectedAmount: creation.combinedGrandTotal,
    );

    final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('verifyOrderPaymentSlip');
    final response = await callable.call(<String, dynamic>{
      'orderIds': creation.orderIds,
      'storagePath': storagePath,
      'paymentGroupId': paymentGroupId,
      'fileName': sanitizedFileName,
      if (request.contentType != null) 'contentType': request.contentType,
    });

    final payload = response.data;
    final data = payload is Map ? Map<String, dynamic>.from(payload) : const <String, dynamic>{};
    final status = (data['status'] as String?)?.trim() ?? 'submitted';
    final message = (data['message'] as String?)?.trim();

    return PaymentSlipSubmissionResult(
      orderIds: creation.orderIds,
      verificationStatus: status,
      message: message == null || message.isEmpty
          ? 'แนบสลิปการเดินทางเรียบร้อยแล้ว'
          : message,
    );
  }

  String _sanitizeSlipFileName(String fileName) {
    final trimmed = fileName.trim();
    final safe = trimmed.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.isEmpty) {
      return 'slip_${DateTime.now().millisecondsSinceEpoch}.jpg';
    }
    return safe;
  }

  Future<void> _attachSlipToOrders({
    required List<String> orderIds,
    required String paymentGroupId,
    required String storagePath,
    required String downloadUrl,
    required String fileName,
    required String? contentType,
    required int sizeBytes,
    required String uploadedBy,
    required double combinedExpectedAmount,
  }) async {
    final ordersRef = FirebaseFirestore.instance.collection('orders');

    for (final orderId in orderIds) {
      await ordersRef.doc(orderId).set(
        <String, dynamic>{
          'paymentGroupId': paymentGroupId,
          'paymentSubmittedAt': FieldValue.serverTimestamp(),
          'paymentStatus': 'awaiting_slip_review',
          'paymentStatusLabel': 'รอตรวจสลิป',
          'paymentSlip': <String, dynamic>{
            'storagePath': storagePath,
            'downloadUrl': downloadUrl,
            'fileName': fileName,
            'contentType': contentType,
            'sizeBytes': sizeBytes,
            'uploadedBy': uploadedBy,
            'uploadedAt': FieldValue.serverTimestamp(),
          },
          'paymentVerification': <String, dynamic>{
            'provider': 'slipok',
            'providerLabel': 'Slip OK',
            'status': 'processing',
            'statusLabel': 'กำลังส่งตรวจสลิป',
            'requestedAt': FieldValue.serverTimestamp(),
            'paymentGroupId': paymentGroupId,
            'expectedCombinedAmount': combinedExpectedAmount,
            'apiEndpoint': 'https://api.slipok.com/api/line/apikey/64492',
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      await ordersRef.doc(orderId).collection('timeline').add(<String, dynamic>{
        'event': 'payment_slip_submitted',
        'eventLabel': 'ลูกค้าแนบสลิปเพื่อรอตรวจสอบ',
        'paymentGroupId': paymentGroupId,
        'orderId': orderId,
        'actorRole': 'customer',
        'actorId': uploadedBy,
        'timestamp': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<({List<String> orderIds, double combinedGrandTotal})> _createCheckoutOrders({
    required User user,
    required String paymentMethod,
    required String paymentMethodLabel,
    required String paymentStatus,
    required String paymentStatusLabel,
    required String auditSource,
    required bool riderNotifyReady,
    required bool notifyRider,
    required String createdEventLabel,
  }) async {
    if (_cartItems.isEmpty) {
      throw Exception('ไม่มีสินค้าในตะกร้า');
    }

    final cartSnapshot = List<CartLineItem>.from(_cartItems);
    final groupedByShop = <String, List<CartLineItem>>{};
    for (final item in cartSnapshot) {
      groupedByShop.putIfAbsent(item.shopId, () => <CartLineItem>[]).add(item);
    }

    try {
      final ordersRef = FirebaseFirestore.instance.collection('orders');
      final createdOrderIds = <String>[];
      var combinedGrandTotal = 0.0;
      final failedShops = <String>[];
      final shopsWithoutRider = <String>[];
      String? lastError;

      for (final entry in groupedByShop.entries) {
        final shopId = entry.key;
        final items = entry.value;
        if (items.isEmpty) {
          continue;
        }

        final docRef = ordersRef.doc();
        final now = DateTime.now();
        final orderCode =
            'ORD-${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${docRef.id.substring(0, 6).toUpperCase()}';
        final subtotal = items.fold<double>(
          0,
          (sumAcc, item) => sumAcc + (item.unitPrice * item.quantity),
        );

        final totalQuantity = items.fold<int>(
          0,
          (qtyAcc, item) => qtyAcc + item.quantity,
        );

        final products = items
            .map(
              (item) {
                final imageUrl = item.imageUrl?.trim();
                return <String, dynamic>{
                  'productId': item.productId,
                  'name': item.productName,
                  'quantity': item.quantity,
                  'unitPrice': item.unitPrice,
                  'selectedToppings': item.selectedToppings,
                  'lineTotal': item.unitPrice * item.quantity,
                  if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
                  if (imageUrl != null && imageUrl.isNotEmpty) 'productImage': imageUrl,
                };
              },
            )
            .toList(growable: false);

        final firstItem = items.first;
        final shippingFee = _estimateShippingFeeForOrder(
          shopLatitude: firstItem.shopLatitude,
          shopLongitude: firstItem.shopLongitude,
          customerLatitude: _userLocation.latitude,
          customerLongitude: _userLocation.longitude,
        );
        final grandTotal = subtotal + shippingFee;
        combinedGrandTotal += grandTotal;
        final riderSearch = await _findNearestRiderForShop(
          shopLatitude: firstItem.shopLatitude,
          shopLongitude: firstItem.shopLongitude,
        );
        final assignedRider = riderSearch.rider;
        if (assignedRider == null) {
          shopsWithoutRider.add(
            '${firstItem.shopName} (${_describeRiderSearchFailure(riderSearch)})',
          );
        }

        final initialOrderStatus = assignedRider == null
          ? (notifyRider ? 'awaiting_rider' : 'awaiting_payment_slip_review')
          : (notifyRider ? 'pending' : 'awaiting_payment_slip_review');
        final initialStatusLabel = assignedRider == null
          ? (notifyRider
            ? 'awaiting_nearest_rider'
            : 'awaiting_payment_slip_review')
          : (notifyRider
            ? 'pending_customer_confirmation'
            : 'awaiting_payment_slip_review');

        try {
          final shouldAssignRiderImmediately = notifyRider;
          await docRef.set(<String, dynamic>{
            'orderId': docRef.id,
            'orderCode': orderCode,
          'status': initialOrderStatus,
          'statusLabel': initialStatusLabel,
            'customerConfirmed': true,
            'customerConfirmedAt': FieldValue.serverTimestamp(),
            'riderNotifyReady': riderNotifyReady,
            'paymentMethod': paymentMethod,
            'paymentMethodLabel': paymentMethodLabel,
            'paymentStatus': paymentStatus,
            'paymentStatusLabel': paymentStatusLabel,
            'sourceApp': 'van2_customer',
            'customerId': user.uid,
            'customerEmail': user.email,
            'customerPhone': user.phoneNumber,
            'customerSnapshot': <String, dynamic>{
              'uid': user.uid,
              'email': user.email,
              'phoneNumber': user.phoneNumber,
            },
            'shopOwnerId': shopId,
            'shopId': shopId,
            'shopName': firstItem.shopName,
            'driverId': shouldAssignRiderImmediately ? assignedRider?.riderId : null,
            'driverName': null,
            'driverPhone': null,
            'assignedRiderAt': !shouldAssignRiderImmediately || assignedRider == null
                ? null
                : FieldValue.serverTimestamp(),
            'customerLocation': <String, dynamic>{
              'latitude': _userLocation.latitude,
              'longitude': _userLocation.longitude,
              'label': _userLocation.title,
            },
            'deliverySnapshot': <String, dynamic>{
              'latitude': _userLocation.latitude,
              'longitude': _userLocation.longitude,
              'locationLabel': _userLocation.title,
            },
            'itemCount': items.length,
            'totalQuantity': totalQuantity,
            'products': products,
            'totalPrice': subtotal,
            'subtotal': subtotal,
            'shippingFee': shippingFee,
            'grandTotal': grandTotal,
            'riderSearch': <String, dynamic>{
              'stepKm': 2,
              'maxRadiusKm': 10,
              'searchedRadiusKm': riderSearch.searchedRadiusKm,
              'onlineRiderCount': riderSearch.onlineRiderCount,
              'eligibleRiderCount': riderSearch.eligibleRiderCount,
              'matched': assignedRider != null,
              'matchedRiderId': assignedRider?.riderId,
              'matchedDistanceKm': assignedRider?.distanceKm,
              if (riderSearch.excludedRiderCount > 0)
                'excludedRiderCount': riderSearch.excludedRiderCount,
              if (riderSearch.excludedBreakdown.isNotEmpty)
                'excludedBreakdown': riderSearch.excludedBreakdown,
              if (riderSearch.reason != null) 'reason': riderSearch.reason,
            },
            'audit': <String, dynamic>{
              'createdBy': user.uid,
              'createdByRole': 'customer',
              'createdSource': auditSource,
            },
            'timestamp': FieldValue.serverTimestamp(),
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          final timelineRef = docRef.collection('timeline').doc();
          try {
            await timelineRef.set(<String, dynamic>{
              'event': 'order_created',
              'eventLabel': createdEventLabel,
              'actorId': user.uid,
              'actorRole': 'customer',
              'orderId': docRef.id,
              'orderCode': orderCode,
              'status': initialOrderStatus,
              'timestamp': FieldValue.serverTimestamp(),
            });
          } catch (_) {
            // Keep the order document even if optional timeline write fails.
          }

          if (notifyRider && assignedRider != null) {
            try {
              await FirebaseFirestore.instance.collection('app_notifications').add({
                'targetApp': 'van3',
                'recipientUid': assignedRider.riderId,
                'orderId': docRef.id,
                'title': 'มีคำสั่งซื้อใหม่',
                'body': orderCode.isNotEmpty
                    ? 'ออเดอร์ $orderCode จาก ${firstItem.shopName}'
                    : 'มีคำสั่งซื้อใหม่จาก ${firstItem.shopName}',
                'read': false,
                'createdAt': FieldValue.serverTimestamp(),
                'source': 'van2_customer',
                'sourceApp': 'van2_customer',
                'action': 'order_created_customer_confirmed',
                'customerConfirmed': true,
                'riderNotifyReady': riderNotifyReady,
              });
            } catch (_) {
              // Keep the order document even if rider notification creation fails.
            }
          }

          createdOrderIds.add(docRef.id);
        } catch (e) {
          failedShops.add(shopId);
          lastError = e.toString();
        }
      }

      if (createdOrderIds.isEmpty) {
        final failedLabel = failedShops.isEmpty ? '' : ' ร้านที่ล้มเหลว: ${failedShops.join(', ')}';
        throw Exception('ไม่สามารถสร้างออเดอร์ได้$failedLabel ${lastError ?? ''}'.trim());
      }

      if (mounted && shopsWithoutRider.isNotEmpty) {
        _showSnackBar(
          'ยังไม่พบไรเดอร์: ${shopsWithoutRider.join(', ')}',
        );
      }

      if (mounted) {
        setState(() {
          _cartItems.clear();
        });
      }

      return (
        orderIds: createdOrderIds,
        combinedGrandTotal: combinedGrandTotal,
      );
    } catch (e) {
      throw Exception('ไม่สามารถสร้างออเดอร์ได้: $e');
    }
  }

  Future<({List<String> orderIds, double combinedGrandTotal})> _createTravelOrder({
    required User user,
    required TravelPlannerResult request,
    required String paymentMethod,
    required String paymentMethodLabel,
    required String paymentStatus,
    required String paymentStatusLabel,
    required String auditSource,
    required bool riderNotifyReady,
    required bool notifyRider,
    required String createdEventLabel,
  }) async {
    final fare = _estimateTravelFare(
      pickupLatitude: request.pickup.latitude,
      pickupLongitude: request.pickup.longitude,
      destinationLatitude: request.destination.latitude,
      destinationLongitude: request.destination.longitude,
    );
    final riderSearch = await _findNearestPassengerRider(
      pickupLatitude: request.pickup.latitude,
      pickupLongitude: request.pickup.longitude,
      vehicleType: request.rideSelection.vehicleType,
    );
    final assignedRider = riderSearch.rider;
    final orderRef = FirebaseFirestore.instance.collection('orders').doc();
    final now = DateTime.now();
    final orderCode =
        'TRV-${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${orderRef.id.substring(0, 6).toUpperCase()}';
    final hasAssignedRider = assignedRider != null;
    final initialOrderStatus = hasAssignedRider
        ? (notifyRider ? 'pending' : 'awaiting_payment_slip_review')
        : (notifyRider ? 'awaiting_rider' : 'awaiting_payment_slip_review');
    final initialStatusLabel = hasAssignedRider
        ? (notifyRider ? 'pending_customer_confirmation' : 'awaiting_payment_slip_review')
        : (notifyRider ? 'awaiting_nearest_rider' : 'awaiting_payment_slip_review');
    final shouldAssignRiderImmediately = notifyRider;

    await orderRef.set(<String, dynamic>{
      'orderId': orderRef.id,
      'orderCode': orderCode,
      'orderType': 'travel_passenger',
      'serviceType': 'travel_passenger',
      'status': initialOrderStatus,
      'statusLabel': initialStatusLabel,
      'customerConfirmed': true,
      'customerConfirmedAt': FieldValue.serverTimestamp(),
      'riderNotifyReady': riderNotifyReady,
      'paymentMethod': paymentMethod,
      'paymentMethodLabel': paymentMethodLabel,
      'paymentStatus': paymentStatus,
      'paymentStatusLabel': paymentStatusLabel,
      'sourceApp': 'van2_customer',
      'customerId': user.uid,
      'customerEmail': user.email,
      'customerPhone': user.phoneNumber,
      'customerSnapshot': <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'phoneNumber': user.phoneNumber,
      },
      'shopOwnerId': 'travel_service',
      'shopId': 'travel_service',
      'shopName': request.pickup.title,
      'shopAddress': request.pickup.subtitle,
      'shopLatitude': request.pickup.latitude,
      'shopLongitude': request.pickup.longitude,
      'driverId': shouldAssignRiderImmediately ? assignedRider?.riderId : null,
      'driverName': null,
      'driverPhone': null,
      'assignedRiderAt': !shouldAssignRiderImmediately || assignedRider == null
          ? null
          : FieldValue.serverTimestamp(),
      'customerLocation': <String, dynamic>{
        'latitude': request.destination.latitude,
        'longitude': request.destination.longitude,
        'label': request.destination.title,
      },
      'deliverySnapshot': <String, dynamic>{
        'latitude': request.destination.latitude,
        'longitude': request.destination.longitude,
        'locationLabel': request.destination.title,
      },
      'itemCount': 1,
      'totalQuantity': 1,
      'products': <Map<String, dynamic>>[
        <String, dynamic>{
          'productId': 'travel_passenger_service',
          'name': 'บริการรับส่งผู้โดยสาร',
          'quantity': 1,
          'unitPrice': fare,
          'lineTotal': fare,
          'note': 'จาก ${request.pickup.title} ไป ${request.destination.title}',
        },
      ],
      'totalPrice': fare,
      'subtotal': fare,
      'shippingFee': 0,
      'grandTotal': fare,
      'travelRequest': <String, dynamic>{
        'pickup': <String, dynamic>{
          'latitude': request.pickup.latitude,
          'longitude': request.pickup.longitude,
          'title': request.pickup.title,
          'subtitle': request.pickup.subtitle,
        },
        'destination': <String, dynamic>{
          'latitude': request.destination.latitude,
          'longitude': request.destination.longitude,
          'title': request.destination.title,
          'subtitle': request.destination.subtitle,
        },
        'distanceKm': request.distanceKm,
        'vehicleType': request.rideSelection.vehicleType.name,
        'vehicleTypeLabel': request.rideSelection.vehicleType.label,
        'scheduledAt': Timestamp.fromDate(request.rideSelection.scheduledAt),
        'scheduleLabel': request.rideSelection.scheduleLabel,
        'isImmediate': request.rideSelection.isImmediate,
        'fare': fare,
      },
      'riderSearch': <String, dynamic>{
        'stepKm': 2,
        'maxRadiusKm': 10,
        'searchedRadiusKm': riderSearch.searchedRadiusKm,
        'onlineRiderCount': riderSearch.onlineRiderCount,
        'eligibleRiderCount': riderSearch.eligibleRiderCount,
        'matched': assignedRider != null,
        'matchedRiderId': assignedRider?.riderId,
        'matchedDistanceKm': assignedRider?.distanceKm,
        if (riderSearch.excludedRiderCount > 0)
          'excludedRiderCount': riderSearch.excludedRiderCount,
        if (riderSearch.excludedBreakdown.isNotEmpty)
          'excludedBreakdown': riderSearch.excludedBreakdown,
        if (riderSearch.reason != null) 'reason': riderSearch.reason,
      },
      'audit': <String, dynamic>{
        'createdBy': user.uid,
        'createdByRole': 'customer',
        'createdSource': auditSource,
      },
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    try {
      await orderRef.collection('timeline').add(<String, dynamic>{
        'event': 'order_created',
        'eventLabel': createdEventLabel,
        'actorId': user.uid,
        'actorRole': 'customer',
        'orderId': orderRef.id,
        'orderCode': orderCode,
        'status': initialOrderStatus,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Keep the travel order even if optional timeline write fails.
    }

    if (notifyRider && assignedRider != null) {
      try {
        await FirebaseFirestore.instance.collection('app_notifications').add({
          'targetApp': 'van3',
          'recipientUid': assignedRider.riderId,
          'orderId': orderRef.id,
          'title': 'มีคำขอเดินทางใหม่',
          'body': orderCode.isNotEmpty
              ? 'งานเดินทาง $orderCode จาก ${request.pickup.title}'
              : 'มีงานเดินทางใหม่จาก ${request.pickup.title}',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
          'source': 'van2_customer',
          'sourceApp': 'van2_customer',
          'action': 'travel_order_created_customer_confirmed',
          'customerConfirmed': true,
          'riderNotifyReady': riderNotifyReady,
        });
      } catch (_) {
        // Keep the order document even if rider notification creation fails.
      }
    }

    if (mounted && !hasAssignedRider) {
      _showSnackBar('ยังไม่พบไรเดอร์รับผู้โดยสารที่พร้อมรับงานใกล้จุดรับ');
    }

    return (orderIds: <String>[orderRef.id], combinedGrandTotal: fare);
  }

  double _estimateShippingFeeForOrder({
    required double? shopLatitude,
    required double? shopLongitude,
    required double customerLatitude,
    required double customerLongitude,
  }) {
    if (shopLatitude == null || shopLongitude == null) {
      return 25;
    }

    final meters = Geolocator.distanceBetween(
      shopLatitude,
      shopLongitude,
      customerLatitude,
      customerLongitude,
    );
    final km = meters <= 0 ? 0.0 : meters / 1000.0;
    final billableKm = km < 1 ? 1.0 : km;
    final fee = 25 + ((billableKm - 1) * 12.5);
    return double.parse(fee.toStringAsFixed(2));
  }

  double _estimateTravelFare({
    required double pickupLatitude,
    required double pickupLongitude,
    required double destinationLatitude,
    required double destinationLongitude,
  }) {
    final meters = Geolocator.distanceBetween(
      pickupLatitude,
      pickupLongitude,
      destinationLatitude,
      destinationLongitude,
    );
    final km = meters <= 0 ? 0.0 : meters / 1000.0;
    final billableKm = km < 1 ? 1.0 : km;
    final fee = 25 + ((billableKm - 1) * 12.5);
    return double.parse(fee.toStringAsFixed(2));
  }

  Future<void> _openOrderRoadmap(List<String> orderIds) async {
    if (!mounted || orderIds.isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderRoadmapScreen(orderIds: orderIds),
      ),
    );
  }

  Future<_RiderSearchResult> _findNearestRiderForShop({
    required double? shopLatitude,
    required double? shopLongitude,
  }) async {
    if (shopLatitude == null || shopLongitude == null) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('riders')
            .where('onlineReady', isEqualTo: true)
            .get();

        if (snapshot.docs.length == 1) {
          return _RiderSearchResult(
            rider: _RiderDistance(riderId: snapshot.docs.first.id, distanceKm: 0),
            searchedRadiusKm: 0,
            onlineRiderCount: 1,
            eligibleRiderCount: 1,
            excludedRiderCount: 0,
            excludedBreakdown: const <String, int>{},
            reason: 'single_online_no_shop_coords_fallback',
          );
        }

        return _RiderSearchResult(
          rider: null,
          searchedRadiusKm: 0,
          onlineRiderCount: snapshot.docs.length,
          eligibleRiderCount: 0,
          excludedRiderCount: snapshot.docs.length,
          excludedBreakdown: const <String, int>{},
          reason: 'missing_shop_coordinates',
        );
      } catch (_) {
        return const _RiderSearchResult(
          rider: null,
          searchedRadiusKm: 0,
          onlineRiderCount: 0,
          eligibleRiderCount: 0,
          excludedRiderCount: 0,
          excludedBreakdown: <String, int>{},
          reason: 'missing_shop_coordinates',
        );
      }
    }

    try {
      const freshLocationThresholdMinutes = 10;
      final snapshot = await FirebaseFirestore.instance
          .collection('riders')
          .where('onlineReady', isEqualTo: true)
          .get();
        final singleOnlineRiderId =
          snapshot.docs.length == 1 ? snapshot.docs.first.id : null;

      final candidates = <_RiderDistance>[];
      final fallbackCandidates = <_RiderDistance>[];
      final excludedBreakdown = <String, int>{};

      void addExcludedReason(String reason) {
        excludedBreakdown[reason] = (excludedBreakdown[reason] ?? 0) + 1;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final geo = data['currentLocation'];
        final lat = geo is GeoPoint
            ? geo.latitude
            : _toDouble(data['latitude']);
        final lng = geo is GeoPoint
            ? geo.longitude
            : _toDouble(data['longitude']);

        if (lat == null || lng == null) {
          addExcludedReason('missing_coordinates');
          continue;
        }

        if ((lat == 0.0 && lng == 0.0) || !_isValidRiderCoordinates(lat, lng)) {
          addExcludedReason('invalid_coordinates');
          continue;
        }

        final meters = Geolocator.distanceBetween(
          shopLatitude,
          shopLongitude,
          lat,
          lng,
        );
        final riderDistance = _RiderDistance(
          riderId: doc.id,
          distanceKm: meters / 1000.0,
        );
        fallbackCandidates.add(riderDistance);

        final locationStatus = (data['locationStatus'] as String?)?.trim() ?? '';
        final locationUpdatedAtRaw = data['locationUpdatedAt'];
        final updatedAtRaw = data['updatedAt'];
        final locationUpdatedAt = locationUpdatedAtRaw is Timestamp
            ? locationUpdatedAtRaw.toDate()
            : (updatedAtRaw is Timestamp ? updatedAtRaw.toDate() : null);

        if (locationStatus == 'offline') {
          addExcludedReason('offline');
          continue;
        }

        if (locationUpdatedAt == null) {
          addExcludedReason('missing_location_timestamp');
          continue;
        }

        final ageMinutes = DateTime.now().difference(locationUpdatedAt).inMinutes;
        if (ageMinutes > freshLocationThresholdMinutes) {
          addExcludedReason('stale_location');
          continue;
        }
        candidates.add(
          riderDistance,
        );
      }

      if (candidates.isEmpty) {
        if (fallbackCandidates.length == 1) {
          return _RiderSearchResult(
            rider: fallbackCandidates.first,
            searchedRadiusKm: 10,
            onlineRiderCount: snapshot.docs.length,
            eligibleRiderCount: 1,
            excludedRiderCount: snapshot.docs.length > 1 ? snapshot.docs.length - 1 : 0,
            excludedBreakdown: Map<String, int>.unmodifiable(excludedBreakdown),
            reason: 'single_online_fallback',
          );
        }

        if (singleOnlineRiderId != null) {
          return _RiderSearchResult(
            rider: _RiderDistance(riderId: singleOnlineRiderId, distanceKm: 0),
            searchedRadiusKm: 10,
            onlineRiderCount: snapshot.docs.length,
            eligibleRiderCount: 1,
            excludedRiderCount: 0,
            excludedBreakdown: Map<String, int>.unmodifiable(excludedBreakdown),
            reason: 'single_online_no_location_fallback',
          );
        }

        return _RiderSearchResult(
          rider: null,
          searchedRadiusKm: 10,
          onlineRiderCount: snapshot.docs.length,
          eligibleRiderCount: 0,
          excludedRiderCount: snapshot.docs.length,
          excludedBreakdown: Map<String, int>.unmodifiable(excludedBreakdown),
          reason: snapshot.docs.isEmpty
              ? 'no_online_riders'
              : 'no_eligible_online_riders',
        );
      }

      for (var radiusKm = 2; radiusKm <= 10; radiusKm += 2) {
        final inRadius = candidates
            .where((candidate) => candidate.distanceKm <= radiusKm)
            .toList(growable: false)
          ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

        if (inRadius.isNotEmpty) {
          return _RiderSearchResult(
            rider: inRadius.first,
            searchedRadiusKm: radiusKm.toDouble(),
            onlineRiderCount: snapshot.docs.length,
            eligibleRiderCount: candidates.length,
            excludedRiderCount: snapshot.docs.length - candidates.length,
            excludedBreakdown: Map<String, int>.unmodifiable(excludedBreakdown),
          );
        }
      }

      if (singleOnlineRiderId != null && candidates.length == 1) {
        return _RiderSearchResult(
          rider: candidates.first,
          searchedRadiusKm: 10,
          onlineRiderCount: snapshot.docs.length,
          eligibleRiderCount: candidates.length,
          excludedRiderCount: snapshot.docs.length - candidates.length,
          excludedBreakdown: Map<String, int>.unmodifiable(excludedBreakdown),
          reason: 'single_online_out_of_radius_fallback',
        );
      }

      // If no one is within the configured 10km radius, still assign the nearest
      // valid online rider to avoid order starvation.
      final nearest = [...candidates]
        ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      return _RiderSearchResult(
        rider: nearest.first,
        searchedRadiusKm: 10,
        onlineRiderCount: snapshot.docs.length,
        eligibleRiderCount: candidates.length,
        excludedRiderCount: snapshot.docs.length - candidates.length,
        excludedBreakdown: Map<String, int>.unmodifiable(excludedBreakdown),
        reason: 'nearest_out_of_radius_fallback',
      );

    } catch (e) {
      return _RiderSearchResult(
        rider: null,
        searchedRadiusKm: 0,
        onlineRiderCount: 0,
        eligibleRiderCount: 0,
        excludedRiderCount: 0,
        excludedBreakdown: const <String, int>{},
        reason: 'rider_query_failed:$e',
      );
    }
  }

  Future<_RiderSearchResult> _findNearestPassengerRider({
    required double pickupLatitude,
    required double pickupLongitude,
    required TravelVehicleType vehicleType,
  }) async {
    try {
      const freshLocationThresholdMinutes = 10;
      final snapshot = await FirebaseFirestore.instance
          .collection('riders')
          .where('passengerReady', isEqualTo: true)
          .get();
      final singleOnlineRiderId = snapshot.docs.length == 1 ? snapshot.docs.first.id : null;

      final candidates = <_RiderDistance>[];
      final fallbackCandidates = <_RiderDistance>[];
      final excludedBreakdown = <String, int>{};

      void addExcludedReason(String reason) {
        excludedBreakdown[reason] = (excludedBreakdown[reason] ?? 0) + 1;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final riderVehicleType = _readPassengerVehicleType(data);
        if (riderVehicleType != vehicleType) {
          addExcludedReason('vehicle_type_mismatch');
          continue;
        }

        final geo = data['currentLocation'];
        final lat = geo is GeoPoint ? geo.latitude : _toDouble(data['latitude']);
        final lng = geo is GeoPoint ? geo.longitude : _toDouble(data['longitude']);

        if (lat == null || lng == null) {
          addExcludedReason('missing_coordinates');
          continue;
        }

        if ((lat == 0.0 && lng == 0.0) || !_isValidRiderCoordinates(lat, lng)) {
          addExcludedReason('invalid_coordinates');
          continue;
        }

        final meters = Geolocator.distanceBetween(pickupLatitude, pickupLongitude, lat, lng);
        final riderDistance = _RiderDistance(riderId: doc.id, distanceKm: meters / 1000.0);
        fallbackCandidates.add(riderDistance);

        final locationStatus = (data['locationStatus'] as String?)?.trim() ?? '';
        final locationUpdatedAtRaw = data['locationUpdatedAt'];
        final updatedAtRaw = data['updatedAt'];
        final locationUpdatedAt = locationUpdatedAtRaw is Timestamp
            ? locationUpdatedAtRaw.toDate()
            : (updatedAtRaw is Timestamp ? updatedAtRaw.toDate() : null);

        if (locationStatus == 'offline') {
          addExcludedReason('offline');
          continue;
        }

        if (locationUpdatedAt == null) {
          addExcludedReason('missing_location_timestamp');
          continue;
        }

        final ageMinutes = DateTime.now().difference(locationUpdatedAt).inMinutes;
        if (ageMinutes > freshLocationThresholdMinutes) {
          addExcludedReason('stale_location');
          continue;
        }

        candidates.add(riderDistance);
      }

      if (candidates.isEmpty) {
        if (fallbackCandidates.length == 1) {
          return _RiderSearchResult(
            rider: fallbackCandidates.first,
            searchedRadiusKm: 10,
            onlineRiderCount: snapshot.docs.length,
            eligibleRiderCount: 1,
            excludedRiderCount: snapshot.docs.length > 1 ? snapshot.docs.length - 1 : 0,
            excludedBreakdown: Map<String, int>.unmodifiable(excludedBreakdown),
            reason: 'single_passenger_ready_fallback',
          );
        }

        if (singleOnlineRiderId != null) {
          return _RiderSearchResult(
            rider: _RiderDistance(riderId: singleOnlineRiderId, distanceKm: 0),
            searchedRadiusKm: 10,
            onlineRiderCount: snapshot.docs.length,
            eligibleRiderCount: 1,
            excludedRiderCount: 0,
            excludedBreakdown: Map<String, int>.unmodifiable(excludedBreakdown),
            reason: 'single_passenger_ready_no_location_fallback',
          );
        }

        return _RiderSearchResult(
          rider: null,
          searchedRadiusKm: 10,
          onlineRiderCount: snapshot.docs.length,
          eligibleRiderCount: 0,
          excludedRiderCount: snapshot.docs.length,
          excludedBreakdown: Map<String, int>.unmodifiable(excludedBreakdown),
          reason: snapshot.docs.isEmpty
              ? 'no_passenger_ready_riders'
              : 'no_eligible_passenger_riders',
        );
      }

      for (var radiusKm = 2; radiusKm <= 10; radiusKm += 2) {
        final inRadius = candidates
            .where((candidate) => candidate.distanceKm <= radiusKm)
            .toList(growable: false)
          ..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));

        if (inRadius.isNotEmpty) {
          return _RiderSearchResult(
            rider: inRadius.first,
            searchedRadiusKm: radiusKm.toDouble(),
            onlineRiderCount: snapshot.docs.length,
            eligibleRiderCount: candidates.length,
            excludedRiderCount: snapshot.docs.length - candidates.length,
            excludedBreakdown: Map<String, int>.unmodifiable(excludedBreakdown),
          );
        }
      }

      final nearest = [...candidates]..sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      return _RiderSearchResult(
        rider: nearest.first,
        searchedRadiusKm: 10,
        onlineRiderCount: snapshot.docs.length,
        eligibleRiderCount: candidates.length,
        excludedRiderCount: snapshot.docs.length - candidates.length,
        excludedBreakdown: Map<String, int>.unmodifiable(excludedBreakdown),
        reason: 'nearest_passenger_out_of_radius_fallback',
      );
    } catch (e) {
      return _RiderSearchResult(
        rider: null,
        searchedRadiusKm: 0,
        onlineRiderCount: 0,
        eligibleRiderCount: 0,
        excludedRiderCount: 0,
        excludedBreakdown: const <String, int>{},
        reason: 'passenger_rider_query_failed:$e',
      );
    }
  }

  TravelVehicleType? _readPassengerVehicleType(Map<String, dynamic> data) {
    final rawCandidates = <String?>[
      data['vehicleType']?.toString(),
      data['vehicle']?.toString(),
      data['type']?.toString(),
      data['vehicleCategory']?.toString(),
    ];

    for (final raw in rawCandidates) {
      final normalized = raw?.trim().toLowerCase();
      switch (normalized) {
        case 'motorcycle':
        case 'bike':
        case 'motorbike':
        case 'motorcycle_taxi':
        case 'มอเตอร์ไซค์':
          return TravelVehicleType.motorcycle;
        case 'sedan':
        case 'car':
        case 'รถเก๋ง':
          return TravelVehicleType.sedan;
        case 'pickup':
        case 'truck':
        case 'กระบะ':
        case 'รถกระบะ':
          return TravelVehicleType.pickup;
      }
    }

    return null;
  }

  bool _isValidRiderCoordinates(double latitude, double longitude) {
    return latitude >= -90 && latitude <= 90 && longitude >= -180 && longitude <= 180;
  }

  String _describeRiderSearchFailure(_RiderSearchResult result) {
    final reason = result.reason ?? 'unknown';
    final base = switch (reason) {
      'missing_shop_coordinates' => 'ร้านไม่มีพิกัด',
      'no_online_riders' => 'ไม่มีไรเดอร์ออนไลน์',
      'no_eligible_online_riders' => 'ไรเดอร์ออนไลน์แต่พิกัดยังไม่พร้อม',
      'no_rider_within_10km' => 'ไม่พบไรเดอร์ในรัศมี 10 กม.',
      'single_online_fallback' => 'เลือกไรเดอร์ออนไลน์คนเดียวแบบสำรอง',
      'single_online_no_shop_coords_fallback' => 'เลือกไรเดอร์ออนไลน์คนเดียว (ร้านยังไม่มีพิกัด)',
      'single_online_no_location_fallback' => 'เลือกไรเดอร์ออนไลน์คนเดียว (พิกัดไรเดอร์ยังไม่ครบ)',
      'single_online_out_of_radius_fallback' => 'เลือกไรเดอร์ออนไลน์คนเดียว (อยู่นอกรัศมี)',
      'nearest_out_of_radius_fallback' => 'เลือกรายที่ใกล้ที่สุดแม้อยู่นอกรัศมี',
      _ when reason.startsWith('rider_query_failed:') => 'ค้นหาไรเดอร์ไม่สำเร็จ',
      _ => reason,
    };

    if (result.excludedBreakdown.isEmpty) {
      return base;
    }

    final topExcluded = result.excludedBreakdown.entries.toList(growable: false)
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = topExcluded.first;
    return '$base (คัดออกมากสุด: ${top.key}=${top.value})';
  }

  double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
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

      if (index == 1 || index == 2 || index == 3 || index == 4) {
        return;
      }

      const labels = <String>['โฮม', 'ตะกร้า', 'โรดแมป', 'ข้อความ', 'ตั้งค่า'];
      _showSnackBar('หน้า ${labels[index]} กำลังพัฒนา');
    }));
  }

  @override
  Widget build(BuildContext context) {
    final distanceKm = _distanceKm;
    final cartQuantity = _cartItems.fold<int>(
      0,
      (totalQuantity, item) => totalQuantity + item.quantity,
    );
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
          onRemoveItem: _removeCartItem,
          onPickCustomerLocation: () {
            unawaited(_pickCartCustomerLocation());
          },
          onApplySharedLocation: () {
            unawaited(_applySharedLocationToCart());
          },
          onConfirmCashOnDelivery: _confirmCashOnDeliveryOrder,
          onSubmitPromptPaySlip: _submitPromptPaySlipOrder,
          onOpenOrderRoadmap: _openOrderRoadmap,
        ),
      2 => OrderRoadmapScreen(),
      3 => const ChatScreen(),
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
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'โรดแมป',
              ),
              NavigationDestination(
                icon: _CartNavIcon(
                  icon: Icons.message_outlined,
                  count: _unreadChatCount,
                ),
                selectedIcon: _CartNavIcon(
                  icon: Icons.message,
                  count: _unreadChatCount,
                ),
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
                  TravelSummaryCard(
                    pickup: _userLocation,
                    destination: _destinationLocation,
                    distanceKm: distanceKm,
                    rideSelection: _travelRideSelection,
                  ),
                ],
              ),
            ),
          ),
        ],
      );
  }

}

class _RiderDistance {
  const _RiderDistance({
    required this.riderId,
    required this.distanceKm,
  });

  final String riderId;
  final double distanceKm;
}

class _RiderSearchResult {
  const _RiderSearchResult({
    required this.rider,
    required this.searchedRadiusKm,
    required this.onlineRiderCount,
    required this.eligibleRiderCount,
    required this.excludedRiderCount,
    required this.excludedBreakdown,
    this.reason,
  });

  final _RiderDistance? rider;
  final double searchedRadiusKm;
  final int onlineRiderCount;
  final int eligibleRiderCount;
  final int excludedRiderCount;
  final Map<String, int> excludedBreakdown;
  final String? reason;
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
          color: Colors.white.withValues(alpha: 0.18),
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

