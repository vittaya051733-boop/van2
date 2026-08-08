import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'cart_screen.dart';
import 'catalog_product_search_screen.dart';
import 'category_catalog_screen.dart';
import 'favorites_screen.dart';
import 'firebase_options.dart';
import 'home_product_discovery_service.dart';
import 'home_product_shelf.dart';
import 'public_catalog_local_cache.dart';
import 'services/home_catalog_bootstrap.dart';
import 'services/rider_availability_service.dart';
import 'services/home_product_image_prefetch.dart';
import 'login_screen.dart';
import 'map_picker_screen.dart';
import 'nationwide_cart_screen.dart';
import 'nationwide_category_picker_screen.dart';
import 'notification_screen.dart';
import 'order_roadmap_screen.dart';
import 'services/order_reorder_service.dart';
import 'privacy_launch_gate.dart';
import 'models/omise_payment_channel.dart';
import 'models/promotion_models.dart';
import 'services/omise_payment_service.dart';
import 'pricing_config_service.dart';
import 'services/locale_service.dart';
import 'services/promotion_catalog_service.dart';
import 'services/promotion_display_config_service.dart';
import 'services/claimable_coupon_service.dart';
import 'services/user_coupon_wallet_service.dart';
import 'widgets/home_promo_carousel.dart';
import 'widgets/claimable_coupon_popup.dart';
import 'widgets/claimable_coupon_strip.dart';
import 'widgets/my_coupons_sheet.dart';
import 'public_catalog_service.dart';
import 'services/cart_session_service.dart';
import 'services/favorites_service.dart';
import 'services/notification_service.dart';
import 'services/observability_service.dart';
import 'services/privacy_consent_service.dart';
import 'services/travel_fare_quote_service.dart';
import 'widgets/rider_unavailable_dialog.dart';
import 'settings_screen.dart';
import 'shop_map_screen.dart';
import 'shop_qr_scanner_screen.dart';
import 'travel_planner_screen.dart';
import 'travel_tracking_screen.dart';
import 'travel_vehicle_type.dart';
import 'utils/app_check_guard.dart'
    show AppCheckGuard, kAppCheckRecaptchaSiteKey, kVan2AppCheckDebugToken;
import 'utils/customer_location.dart';

const bool kAppCheckForceDebug = bool.fromEnvironment(
  'APP_CHECK_DEBUG',
  defaultValue: false,
);

/// Debug-only App Check token pinned for van2 dev/emulator builds.
/// Register this exact token once in Firebase Console → App Check → van2 → Debug tokens.
/// Override at build time with --dart-define=VAN2_APP_CHECK_DEBUG_TOKEN=...
const bool kDebugMapPicker = bool.fromEnvironment(
  'DEBUG_MAP_PICKER',
  defaultValue: false,
);

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
    await ObservabilityService.instance.initialize(appName: 'van2_customer');
  } catch (_) {}

  final useDebugAppCheck = !kReleaseMode || kAppCheckForceDebug;
  try {
    if (kIsWeb) {
      if (kAppCheckRecaptchaSiteKey.isNotEmpty) {
        await FirebaseAppCheck.instance
            .activate(
              providerWeb: ReCaptchaV3Provider(kAppCheckRecaptchaSiteKey),
            )
            .timeout(const Duration(seconds: 5));
        await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
        try {
          await FirebaseAppCheck.instance
              .getToken(true)
              .timeout(const Duration(seconds: 5));
        } catch (error, stack) {
          if (kDebugMode) {
            debugPrint('Could not get App Check token on web startup: $error');
          } else {
            unawaited(
              ObservabilityService.instance.recordError(error, stack),
            );
          }
        }
      }
    } else {
      await FirebaseAppCheck.instance
          .activate(
            providerAndroid: useDebugAppCheck
                ? AndroidDebugProvider(debugToken: kVan2AppCheckDebugToken)
                : const AndroidPlayIntegrityProvider(),
            providerApple: useDebugAppCheck
                ? const AppleDebugProvider()
                : const AppleDeviceCheckProvider(),
          )
          .timeout(const Duration(seconds: 5));
      await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

      if (useDebugAppCheck) {
        debugPrint(
          'App Check debug token (register once in Firebase Console): '
          '$kVan2AppCheckDebugToken',
        );
      }

      try {
        await FirebaseAppCheck.instance
            .getToken(true)
            .timeout(const Duration(seconds: 5));
      } catch (error, stack) {
        if (useDebugAppCheck) {
          debugPrint('Could not get App Check token on startup: $error');
        } else {
          unawaited(
            ObservabilityService.instance.recordError(error, stack),
          );
        }
      }
    }
  } catch (error, stack) {
    if (useDebugAppCheck) {
      debugPrint('App Check activate failed: $error');
    } else {
      unawaited(
        ObservabilityService.instance.recordError(error, stack),
      );
    }
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

  if (!kIsWeb) {
    try {
      await NotificationService().initialize();
    } catch (_) {}
  }

  try {
    await LocaleService.instance.load();
  } catch (_) {}

  try {
    await PricingConfigService.instance.loadAndApplyOnce();
  } catch (_) {}

  try {
    await PublicCatalogLocalCache.ensureProductsHydrated();
    await PublicCatalogLocalCache.ensurePublicShopsHydrated();
    await AppImagePrefetch.warmBootstrapQuickActionCategories().timeout(
      const Duration(seconds: 15),
    );
  } catch (_) {
    // Home + catalog still warm images after launch.
  }

  unawaited(HomeCatalogBootstrap.warmForHome());
  unawaited(RiderAvailabilityService.instance.warmUp());
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

class _VerifiedSlipCheckout {
  const _VerifiedSlipCheckout({
    required this.paymentGroupId,
    required this.storagePath,
    required this.downloadUrl,
    required this.fileName,
    required this.sizeBytes,
    required this.verificationFeedbackId,
    required this.verificationMessage,
  });

  final String paymentGroupId;
  final String storagePath;
  final String downloadUrl;
  final String fileName;
  final int sizeBytes;
  final String verificationFeedbackId;
  final String verificationMessage;
}

class _OmiseVerifiedCheckout {
  const _OmiseVerifiedCheckout({
    required this.paymentSessionId,
    this.omiseChargeId,
  });

  final String paymentSessionId;
  final String? omiseChargeId;
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
    PromotionDisplayConfigService.instance.start();
    LocaleService.instance.addListener(_onLocaleChanged);
  }

  void _onLocaleChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    LocaleService.instance.removeListener(_onLocaleChanged);
    unawaited(PricingConfigService.instance.dispose());
    PromotionDisplayConfigService.instance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'แว๊นตลาด',
      debugShowCheckedModeBanner: false,
      navigatorKey: MyApp.navigatorKey,
      locale: LocaleService.instance.locale,
      supportedLocales: const <Locale>[Locale('th', 'TH'), Locale('en', 'US')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF57C00)),
        scaffoldBackgroundColor: const Color(0xFFFFF7ED),
      ),
      home: kDebugMapPicker
          ? const MapPickerScreen(
              title: 'Debug Map Picker',
              confirmLabel: 'ยืนยัน',
            )
          : const SplashScreen(),
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
        builder: (context) => PrivacyLaunchGate(
          app: PrivacyAppKey.van2Customer,
          child: detectedLocation == null
              ? const LocationSetupScreen(autoDetectionFailed: true)
              : HomeScreen(userLocation: detectedLocation),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(HomeCatalogBootstrap.warmForHome());
    _navigationTimer = Timer(const Duration(seconds: 2), _proceedFromSplash);
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logoBoxSize = (MediaQuery.sizeOf(context).shortestSide * 0.92)
        .clamp(220.0, 660.0)
        .toDouble();
    final logoPadding = (logoBoxSize * 18 / 220).clamp(18.0, 54.0).toDouble();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.white,
        systemNavigationBarColor: Colors.white,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: ColoredBox(
          color: Colors.white,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: logoBoxSize,
                  height: logoBoxSize,
                  child: Padding(
                    padding: EdgeInsets.all(logoPadding),
                    child: Image.asset(
                      'assets/app_logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'ตลาดโนนสูง ออนไลน์ เดลิเวอรี่',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF9A3412),
                  ),
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
        if (kIsWeb) {
          _showSnackBar(
            'เบราว์เซอร์ไม่รองรับการระบุตำแหน่ง กรุณาเลือกพิกัดบนแผนที่แทน',
          );
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
            _showSnackBar(
              'ไม่สามารถเปิดหน้าตั้งค่าตำแหน่งได้ กรุณาเปิด Location ในเครื่องด้วยตนเอง',
            );
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
        if (kIsWeb) {
          _showSnackBar(
            'กรุณากดไอคอนแม่กุญแจในแถบที่อยู่ของเบราว์เซอร์ แล้วอนุญาตการเข้าถึงตำแหน่ง',
          );
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
            _showSnackBar(
              'ไม่สามารถเปิดหน้า App Settings ได้ กรุณาเปิดสิทธิ์ตำแหน่งในตั้งค่าแอปด้วยตนเอง',
            );
          }
        }
        return;
      }

      if (permission == LocationPermission.denied) {
        _showSnackBar(
          kIsWeb
              ? 'กรุณาอนุญาตตำแหน่งเมื่อเบราว์เซอร์ถาม หรือเลือกพิกัดบนแผนที่'
              : 'ยังไม่ได้รับสิทธิ์ตำแหน่ง กรุณาอนุญาตเพื่อใช้งานต่อ',
        );
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
      if (!mounted) {
        return;
      }
      _enterHomeScreen();
      return;
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
    _enterHomeScreen();
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
      _enterHomeScreen();
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
      backgroundColor: Colors.white,
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
                  'assets/app_logo.png',
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

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late PickedLocation _userLocation;
  PickedLocation? _destinationLocation;
  TravelRideSelection? _travelRideSelection;
  int _selectedBottomTab = 0;
  List<String> _roadmapFocusOrderIds = const <String>[];
  int _unreadNotificationCount = 0;
  StreamSubscription<User?>? _authStateSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _unreadNotificationSubscription;
  _ActiveCatalog? _activeCatalog;
  final List<CartLineItem> _cartItems = <CartLineItem>[];
  final List<CartLineItem> _nationwideCartItems = <CartLineItem>[];
  bool _showNationwideCart = false;
  Timer? _cartSyncDebounce;
  Timer? _cartExpiryTimer;
  DateTime? _lastRootBackPressAt;
  final String _couponPopupSessionId =
      DateTime.now().millisecondsSinceEpoch.toString();
  String? _pendingCartCouponCode;
  int _couponUiRevision = 0;

  static const Color _quickActionIconColor = Color(0xFFEF8A17);

  static const List<_QuickActionItem> _quickActions = <_QuickActionItem>[
    _QuickActionItem(
      label: 'เดินทาง',
      icon: Icons.directions_car_outlined,
      iconColor: _quickActionIconColor,
      actionKey: 'travel',
    ),
    _QuickActionItem(
      label: 'ร้านอาหาร',
      icon: Icons.restaurant_outlined,
      iconColor: _quickActionIconColor,
      serviceType: 'ร้านอาหาร',
    ),
    _QuickActionItem(
      label: 'ตลาด',
      icon: Icons.storefront_outlined,
      iconColor: _quickActionIconColor,
      serviceType: 'ตลาด',
    ),
    _QuickActionItem(
      label: 'ร้านค้า',
      icon: Icons.shopping_bag_outlined,
      iconColor: _quickActionIconColor,
      serviceType: 'ร้านค้า',
    ),
    _QuickActionItem(
      label: 'ร้านขายยา',
      icon: Icons.local_pharmacy_outlined,
      iconColor: _quickActionIconColor,
      serviceType: 'ร้านขายยา',
    ),
    _QuickActionItem(
      label: 'แผนที่',
      icon: Icons.location_on_outlined,
      iconColor: _quickActionIconColor,
      actionKey: 'shop-map',
    ),
    _QuickActionItem(
      label: 'สินค้าส่งทั่วประเทศ',
      icon: Icons.inventory_2_outlined,
      iconColor: _quickActionIconColor,
      actionKey: 'nationwide-shipping',
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
    WidgetsBinding.instance.addObserver(this);
    _userLocation = widget.userLocation;
    _authStateSubscription = FirebaseAuth.instance.authStateChanges().listen((_) {
      _listenUnreadNotifications();
    });
    _listenUnreadNotifications();
    unawaited(FavoritesService.instance.ensureLoaded());
    unawaited(_restorePersistedCart());
  }

  @override
  void dispose() {
    _cartSyncDebounce?.cancel();
    _cartExpiryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _authStateSubscription?.cancel();
    _unreadNotificationSubscription?.cancel();
    unawaited(
      CartSessionService.saveLocalCart(
        cartItems: List<CartLineItem>.from(_cartItems),
        nationwideCartItems: List<CartLineItem>.from(_nationwideCartItems),
      ),
    );
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(
        CartSessionService.saveLocalCart(
          cartItems: List<CartLineItem>.from(_cartItems),
          nationwideCartItems: List<CartLineItem>.from(_nationwideCartItems),
        ),
      );
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_restorePersistedCart());
    }
  }

  List<CartLineItem> get _allCartItems => <CartLineItem>[
    ..._cartItems,
    ..._nationwideCartItems,
  ];

  void _resetCartExpiryTimer() {
    _cartExpiryTimer?.cancel();
    if (_allCartItems.isEmpty) {
      return;
    }
    _cartExpiryTimer = Timer(CartSessionService.cartHoldDuration, () {
      unawaited(_expireCartDueToTimeout());
    });
  }

  Future<void> _expireCartDueToTimeout() async {
    await CartSessionService.restoreStockHold();
    await CartSessionService.clearLocalCart();
    if (!mounted) {
      return;
    }
    setState(() {
      _cartItems.clear();
      _nationwideCartItems.clear();
      _showNationwideCart = false;
      if (_selectedBottomTab == 1) {
        _selectedBottomTab = 0;
      }
    });
    _showSnackBar('ตะกร้าหมดเวลา 1 ชั่วโมง คืนสต๊อกสินค้าแล้ว');
  }

  void _scheduleCartSessionSync() {
    _cartSyncDebounce?.cancel();
    _cartSyncDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(_syncCartSession());
    });
  }

  Future<void> _syncCartSession() async {
    final items = _allCartItems;
    if (items.isEmpty) {
      await CartSessionService.restoreStockHold();
      await CartSessionService.clearLocalCart();
      _cartExpiryTimer?.cancel();
      return;
    }

    try {
      await CartSessionService.syncStockHold(items);
      await CartSessionService.saveLocalCart(
        cartItems: List<CartLineItem>.from(_cartItems),
        nationwideCartItems: List<CartLineItem>.from(_nationwideCartItems),
      );
      _resetCartExpiryTimer();
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.message?.trim();
      _showSnackBar(
        message == null || message.isEmpty
            ? 'ไม่สามารถจองสต๊อกสินค้าได้'
            : 'ไม่สามารถจองสต๊อกสินค้าได้ ($message)',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      _showSnackBar('ไม่สามารถจองสต๊อกสินค้าได้');
    }
  }

  Future<void> _restorePersistedCart() async {
    final loaded = await CartSessionService.loadLocalCart();
    if (loaded.expired) {
      await CartSessionService.restoreStockHold();
      await CartSessionService.clearLocalCart();
      if (!mounted) {
        return;
      }
      if (_cartItems.isNotEmpty || _nationwideCartItems.isNotEmpty) {
        setState(() {
          _cartItems.clear();
          _nationwideCartItems.clear();
          _showNationwideCart = false;
        });
        _showSnackBar('ตะกร้าหมดเวลา 1 ชั่วโมง คืนสต๊อกสินค้าแล้ว');
      }
      return;
    }

    if (!mounted) {
      return;
    }
    if (loaded.cart.isEmpty && loaded.nationwide.isEmpty) {
      return;
    }

    setState(() {
      _cartItems
        ..clear()
        ..addAll(loaded.cart);
      _nationwideCartItems
        ..clear()
        ..addAll(loaded.nationwide);
    });
    await _syncCartSession();
  }

  Future<void> _clearCartAfterCheckout() async {
    await CartSessionService.consumeStockHold();
    await CartSessionService.clearLocalCart();
    _cartExpiryTimer?.cancel();
    if (!mounted) {
      return;
    }
    setState(() {
      _cartItems.clear();
      _nationwideCartItems.clear();
    });
  }

  bool _handleRootBackPress() {
    if (_activeCatalog != null || _showNationwideCart) {
      setState(() {
        _activeCatalog = null;
        _showNationwideCart = false;
        _selectedBottomTab = 0;
      });
      return true;
    }

    if (_selectedBottomTab != 0) {
      setState(() {
        _selectedBottomTab = 0;
        _activeCatalog = null;
        _showNationwideCart = false;
      });
      return true;
    }

    final now = DateTime.now();
    if (_lastRootBackPressAt != null &&
        now.difference(_lastRootBackPressAt!) < const Duration(seconds: 2)) {
      return false;
    }
    _lastRootBackPressAt = now;
    _showSnackBar('กดปุ่มกลับอีกครั้งเพื่อออกจากแอป');
    return true;
  }

  void _listenUnreadNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    _unreadNotificationSubscription?.cancel();
    _unreadNotificationSubscription = null;

    if (user == null || user.isAnonymous) {
      if (mounted) {
        setState(() => _unreadNotificationCount = 0);
      }
      return;
    }

    _unreadNotificationSubscription = FirebaseFirestore.instance
        .collection('app_notifications')
        .where('recipientUid', isEqualTo: user.uid)
        .limit(50)
        .snapshots()
        .listen(
          (snapshot) {
            var totalUnread = 0;
            for (final doc in snapshot.docs) {
              final data = doc.data();
              final targetApp = (data['targetApp'] ?? '').toString().trim();
              if (targetApp.isNotEmpty && targetApp != 'van2') {
                continue;
              }
              if (data['isRead'] == true ||
                  data['read'] == true ||
                  data['readAt'] != null) {
                continue;
              }
              totalUnread += 1;
            }

            if (!mounted) {
              return;
            }
            setState(() => _unreadNotificationCount = totalUnread);
          },
          onError: (Object error, StackTrace stack) {
            debugPrint('Unread notifications listener error: $error');
            if (mounted) {
              setState(() => _unreadNotificationCount = 0);
            }
          },
        );
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

  Future<void> _startTravelPlannerFresh() async {
    final result = await Navigator.of(context).push<TravelPlannerResult>(
      MaterialPageRoute<TravelPlannerResult>(
        builder: (context) => TravelPlannerScreen(
          initialPickup: _userLocation,
          initialDestination: null,
          initialRideSelection: null,
          onConfirmCashOnDelivery: _confirmTravelCashOnDeliveryOrder,
          onSubmitOmisePayment: _submitOmiseTravelOrder,
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

  Future<void> _reorderProductsFromHistory(
    Map<String, dynamic> orderData,
  ) async {
    final allowed = await _ensureLoggedIn();
    if (!allowed || !mounted) {
      return;
    }

    final result = await OrderReorderService.buildSelectionsFromOrder(orderData);
    if (!mounted) {
      return;
    }

    if (!result.hasSelections) {
      _showSnackBar(
        result.messages.isNotEmpty
            ? result.messages.first
            : 'ไม่พบสินค้าที่สั่งซ้ำได้',
      );
      return;
    }

    setState(() {
      for (final selection in result.selections) {
        _cartItems.add(
          CartLineItem(
            productId: selection.productId,
            shopId: selection.shopId,
            shopName: selection.shopName,
            shopLatitude: selection.shopLatitude,
            shopLongitude: selection.shopLongitude,
            productName: selection.productName,
            unitPrice: selection.unitPrice,
            merchantBasePrice: selection.merchantBasePrice,
            discountPercent: selection.discountPercent,
            merchantUnitPayout: selection.merchantUnitPayout,
            imageUrl: selection.imageUrl,
            selectedToppings: selection.selectedToppings,
            quantity: selection.quantity,
            availableStock: selection.availableStock,
            preparationTimeMinutes: selection.preparationTimeMinutes,
            parcelWeightGrams: selection.parcelWeightGrams,
            parcelLengthCm: selection.parcelLengthCm,
            parcelWidthCm: selection.parcelWidthCm,
            parcelHeightCm: selection.parcelHeightCm,
          ),
        );
      }
    });
    _scheduleCartSessionSync();
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    _openCartTab();

    if (result.messages.isNotEmpty) {
      _showSnackBar(result.messages.first);
    } else {
      _showSnackBar('เพิ่มสินค้าในตะกร้าแล้ว — ตรวจสอบราคาปัจจุบันก่อนชำระเงิน');
    }
  }

  Future<void> _startTravelPlanner() async {
    final result = await Navigator.of(context).push<TravelPlannerResult>(
      MaterialPageRoute<TravelPlannerResult>(
        builder: (context) => TravelPlannerScreen(
          initialPickup: _userLocation,
          initialDestination: _destinationLocation,
          initialRideSelection: _travelRideSelection,
          onConfirmCashOnDelivery: _confirmTravelCashOnDeliveryOrder,
          onSubmitOmisePayment: _submitOmiseTravelOrder,
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
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
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
      _showSnackBar(
        'ไม่พบพิกัดในลิงก์นี้ ลองแชร์แบบมีพิกัดหรือปักหมุดจากแผนที่แทน',
      );
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

    final urlMatch = RegExp(
      r'https?://[^\s]+',
      caseSensitive: false,
    ).firstMatch(text);
    final candidateUrl = urlMatch?.group(0) ?? text;
    final candidateUri = Uri.tryParse(candidateUrl);
    if (candidateUri == null || !candidateUri.hasScheme) {
      return rawValue;
    }
    if (!_shouldTryExpandingShareLink(candidateUri)) {
      return rawValue;
    }

    final expandedUrl = await _expandShortUrl(candidateUri);
    if (expandedUrl == null ||
        expandedUrl.isEmpty ||
        expandedUrl == candidateUrl) {
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
            headers: const <String, String>{'User-Agent': 'Mozilla/5.0'},
          )
          .timeout(const Duration(seconds: 8));
      final finalUrl = response.request?.url.toString();
      if (finalUrl != null &&
          finalUrl.isNotEmpty &&
          finalUrl != uri.toString()) {
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

      for (final key in <String>[
        'q',
        'query',
        'll',
        'daddr',
        'destination',
        'text',
        'u',
      ]) {
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
      RegExp(
        r'geo:\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)',
        caseSensitive: false,
      ),
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

  (double, double)? _toValidCoordinates(
    String? latitudeRaw,
    String? longitudeRaw,
  ) {
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
    return latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;
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

  Future<void> _ensureCatalogFirebaseSession() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        await FirebaseAuth.instance.signInAnonymously();
        return;
      }
      await user.getIdToken();
    } catch (_) {
      // PublicCatalogService retries auth and surfaces Firestore errors in UI.
    }
  }

  Future<void> _handleQuickActionTap(_QuickActionItem item) async {
    if (item.actionKey == 'travel') {
      await _runProtectedAction(() async {
        await _startTravelPlanner();
      });
      return;
    }

    if (item.actionKey == 'shop-map') {
      await _ensureCatalogFirebaseSession();
      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ShopMapScreen(
            userLatitude: _userLocation.latitude,
            userLongitude: _userLocation.longitude,
            userLocationLabel: _userLocation.title,
            onConfirmOrder: _addToCart,
            onNavigateToCart: _openCartTab,
          ),
        ),
      );
      return;
    }

    if (item.actionKey == 'nationwide-shipping') {
      await _ensureCatalogFirebaseSession();
      if (!mounted) {
        return;
      }
      unawaited(AppImagePrefetch.continueWarmNationwide());
      await _openNationwideCategoryPicker();
      return;
    }

    if (item.serviceType == null) {
      _showSnackBar('หมวด ${item.label} ยังไม่ได้เชื่อมต่อข้อมูลร้านค้า');
      return;
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _selectedBottomTab = 0;
      _activeCatalog = _ActiveCatalog(
        title: item.label,
        serviceType: item.serviceType!,
      );
    });
    unawaited(AppImagePrefetch.continueWarmForServiceType(item.serviceType!));
    unawaited(_ensureCatalogFirebaseSession());
  }

  Future<void> _openGlobalProductSearch() async {
    await _ensureCatalogFirebaseSession();
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CatalogProductSearchScreen(
          title: 'ค้นหาสินค้า',
          sectionsStream: PublicCatalogService.streamAllSections(),
          searchHint: 'ค้นหาทุกสินค้าในแว๊นตลาด',
          customerLatitude: _userLocation.latitude,
          customerLongitude: _userLocation.longitude,
          onConfirmOrder: _addToCart,
          onNavigateToCart: _openCartTab,
        ),
      ),
    );
  }

  Future<void> _openFavoritesScreen() async {
    await _ensureCatalogFirebaseSession();
    if (!mounted) {
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FavoritesScreen(
          customerLatitude: _userLocation.latitude,
          customerLongitude: _userLocation.longitude,
          onConfirmOrder: _addToCart,
          onNavigateToCart: _openCartTab,
        ),
      ),
    );
  }

  void _openShopCatalogFromProduct(PublicCatalogProduct product) {
    setState(() {
      _selectedBottomTab = 0;
      _showNationwideCart = false;
      _activeCatalog = _ActiveCatalog(
        title: product.shopName?.trim().isNotEmpty == true
            ? product.shopName!.trim()
            : 'สินค้าร้าน',
        shopIdFilter: product.shopId,
      );
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
          merchantBasePrice: selection.merchantBasePrice,
          discountPercent: selection.discountPercent,
          merchantUnitPayout: selection.merchantUnitPayout,
          imageUrl: selection.imageUrl,
          selectedToppings: selection.selectedToppings,
          quantity: selection.quantity,
          availableStock: selection.availableStock,
          preparationTimeMinutes: selection.preparationTimeMinutes,
          parcelWeightGrams: selection.parcelWeightGrams,
          parcelLengthCm: selection.parcelLengthCm,
          parcelWidthCm: selection.parcelWidthCm,
          parcelHeightCm: selection.parcelHeightCm,
        ),
      );
    });
    _scheduleCartSessionSync();
  }

  void _addToNationwideCart(CartProductSelection selection) {
    setState(() {
      _nationwideCartItems.add(
        CartLineItem(
          productId: selection.productId,
          shopId: selection.shopId,
          shopName: selection.shopName,
          shopLatitude: selection.shopLatitude,
          shopLongitude: selection.shopLongitude,
          productName: selection.productName,
          unitPrice: selection.unitPrice,
          merchantBasePrice: selection.merchantBasePrice,
          discountPercent: selection.discountPercent,
          merchantUnitPayout: selection.merchantUnitPayout,
          imageUrl: selection.imageUrl,
          selectedToppings: selection.selectedToppings,
          quantity: selection.quantity,
          availableStock: selection.availableStock,
          preparationTimeMinutes: selection.preparationTimeMinutes,
          parcelWeightGrams: selection.parcelWeightGrams,
          parcelLengthCm: selection.parcelLengthCm,
          parcelWidthCm: selection.parcelWidthCm,
          parcelHeightCm: selection.parcelHeightCm,
        ),
      );
    });
    _scheduleCartSessionSync();
  }

  void _openCartTab() {
    setState(() {
      _selectedBottomTab = 1;
      _activeCatalog = null;
      _showNationwideCart = false;
    });
  }

  void _openMyCouponsWallet() {
    unawaited(
      _runProtectedAction(() async {
        if (!mounted) {
          return;
        }
        await showMyCouponsSheet(
          context,
          onApplyToCart: (code) {
            setState(() {
              _pendingCartCouponCode = code;
              _selectedBottomTab = 1;
              _activeCatalog = null;
              _showNationwideCart = false;
            });
          },
        );
      }),
    );
  }

  void _onCouponClaimed() {
    if (!mounted) {
      return;
    }
    setState(() => _couponUiRevision++);
  }

  Widget _buildClaimableCouponPopupOverlay() {
    final user = FirebaseAuth.instance.currentUser;
    if (_selectedBottomTab != 0 ||
        _activeCatalog != null ||
        _showNationwideCart ||
        user == null ||
        user.isAnonymous) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<List<ClaimableCouponOffer>>(
      stream: ClaimableCouponService.instance.watchActiveClaimableCoupons(),
      builder: (context, couponsSnapshot) {
        return StreamBuilder<Set<String>>(
          stream: UserCouponWalletService.instance.watchClaimedCouponIds(user.uid),
          builder: (context, claimedSnapshot) {
            final coupons = couponsSnapshot.data ?? const <ClaimableCouponOffer>[];
            final claimedIds = claimedSnapshot.data ?? <String>{};
            if (coupons.isEmpty) {
              return const SizedBox.shrink();
            }
            return ClaimableCouponPopupHost(
              key: ValueKey<String>(
                'coupon-popup-$_couponUiRevision-${coupons.map((c) => c.id).join(',')}',
              ),
              coupons: coupons,
              claimedCouponIds: claimedIds,
              sessionId: _couponPopupSessionId,
              onClaimed: _onCouponClaimed,
            );
          },
        );
      },
    );
  }

  void _openNationwideCart() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _selectedBottomTab = 0;
      _activeCatalog = null;
      _showNationwideCart = true;
    });
  }

  Future<void> _openNationwideCategoryPicker() async {
    if (!mounted) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => NationwideCategoryPickerScreen(
          customerLatitude: _userLocation.latitude,
          customerLongitude: _userLocation.longitude,
          onConfirmOrder: _addToNationwideCart,
          onNavigateToCart: _openNationwideCart,
        ),
      ),
    );
  }

  void _removeCartItem(int index) {
    if (index < 0 || index >= _cartItems.length) {
      return;
    }
    setState(() {
      _cartItems.removeAt(index);
    });
    _scheduleCartSessionSync();
  }

  void _removeNationwideCartItem(int index) {
    if (index < 0 || index >= _nationwideCartItems.length) {
      return;
    }
    setState(() {
      _nationwideCartItems.removeAt(index);
    });
    _scheduleCartSessionSync();
  }

  Future<User> _requireCheckoutUser() async {
    final allowed = await _ensureLoggedIn();
    if (!allowed || !mounted) {
      throw Exception('กรุณาเข้าสู่ระบบก่อนยืนยันคำสั่งซื้อ');
    }

    await AppCheckGuard.ensureCheckoutReady();
    if (!mounted) {
      throw Exception('กรุณาลองใหม่อีกครั้ง');
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

  Future<List<String>> _confirmCashOnDeliveryOrder(
    CartCheckoutContext checkoutContext,
  ) async {
    final user = await _requireCheckoutUser();
    if (!mounted) {
      throw Exception('กรุณาลองใหม่อีกครั้ง');
    }
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
      checkoutContext: checkoutContext,
    );
    return result.orderIds;
  }

  Future<List<String>> _confirmTravelCashOnDeliveryOrder(
    TravelPlannerResult request,
  ) async {
    final user = await _requireCheckoutUser();
    if (!mounted) {
      throw Exception('กรุณาลองใหม่อีกครั้ง');
    }
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

  Future<List<String>> _submitOmiseCheckoutOrder(
    OmisePaymentChannel channel,
    CartCheckoutContext checkoutContext,
    double grandTotal,
  ) async {
    final user = await _requireCheckoutUser();
    if (!mounted) {
      throw Exception('กรุณาลองใหม่อีกครั้ง');
    }
    final checkoutQuoteId = checkoutContext.checkoutQuoteId?.trim();
    if (checkoutQuoteId == null || checkoutQuoteId.isEmpty) {
      throw Exception('ยังไม่มี checkout quote กรุณารอระบบคำนวณยอดสักครู่');
    }

    final session = await OmisePaymentService().startCheckout(
      context: context,
      channel: channel,
      amount: grandTotal,
      checkoutQuoteId: checkoutQuoteId,
    );
    if (!mounted) {
      throw Exception('กรุณาลองใหม่อีกครั้ง');
    }

    final creation = await _createCheckoutOrders(
      user: user,
      paymentMethod: channel.methodId,
      paymentMethodLabel: channel.paymentMethodLabel,
      paymentStatus: 'verified',
      paymentStatusLabel: 'ชำระเงินแล้ว',
      auditSource: 'omise_payment_sheet',
      riderNotifyReady: true,
      notifyRider: true,
      createdEventLabel: 'ลูกค้าชำระเงินผ่าน Omise และสร้างออเดอร์แล้ว',
      checkoutContext: checkoutContext,
      omisePayment: _OmiseVerifiedCheckout(
        paymentSessionId: session.sessionId,
        omiseChargeId: session.omiseChargeId,
      ),
    );

    if (creation.orderIds.isEmpty) {
      throw Exception('ไม่สามารถสร้างออเดอร์ได้');
    }

    return creation.orderIds;
  }

  Future<List<String>> _submitOmiseTravelOrder(
    TravelPlannerResult request,
    OmisePaymentChannel channel,
  ) async {
    final user = await _requireCheckoutUser();
    if (!mounted) {
      throw Exception('กรุณาลองใหม่อีกครั้ง');
    }
    final quote = await TravelFareQuoteService.fetchQuote(request);
    if (!mounted) {
      throw Exception('กรุณาลองใหม่อีกครั้ง');
    }

    final paidSession = await OmisePaymentService().startCheckout(
      context: context,
      channel: channel,
      amount: quote.fare,
      checkoutQuoteId: '',
      purpose: 'travel',
    );
    if (!mounted) {
      throw Exception('กรุณาลองใหม่อีกครั้ง');
    }

    final creation = await _createTravelOrder(
      user: user,
      request: request,
      paymentMethod: channel.methodId,
      paymentMethodLabel: channel.paymentMethodLabel,
      paymentStatus: 'verified',
      paymentStatusLabel: 'ชำระเงินแล้ว',
      auditSource: 'travel_omise_payment_sheet',
      riderNotifyReady: true,
      notifyRider: true,
      createdEventLabel: 'ลูกค้าชำระเงินผ่าน Omise และสร้างคำขอเดินทางแล้ว',
      omisePayment: _OmiseVerifiedCheckout(
        paymentSessionId: paidSession.sessionId,
        omiseChargeId: paidSession.omiseChargeId,
      ),
    );

    if (creation.orderIds.isEmpty) {
      throw Exception('ไม่สามารถสร้างออเดอร์เดินทางได้');
    }

    return creation.orderIds;
  }

  Future<void> _recordCheckoutDiscounts({
    required List<String> orderIds,
    required CartDiscountSnapshot discounts,
    required String checkoutQuoteId,
  }) async {
    if (orderIds.isEmpty || discounts.discountTotal <= 0) {
      return;
    }

    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await AppCheckGuard.ensureCheckoutReady();
        final functions = FirebaseFunctions.instanceFor(
          region: 'asia-southeast1',
        );
        await functions.httpsCallable('recordCheckoutDiscounts').call(
          <String, dynamic>{
            'checkoutQuoteId': checkoutQuoteId,
            'orderIds': orderIds,
            'discountTotal': discounts.discountTotal,
            'discountLines': discounts.discountLines
                .map((line) => line.toPayload())
                .toList(growable: false),
          },
        );
        return;
      } catch (error, stack) {
        lastError = error;
        unawaited(
          ObservabilityService.instance.recordError(error, stack),
        );
      }
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          lastError is FirebaseFunctionsException
              ? (lastError.message ??
                    'บันทึกการใช้ส่วนลดไม่สำเร็จ กรุณาติดต่อผู้ดูแลระบบ')
              : 'บันทึกการใช้ส่วนลดไม่สำเร็จ กรุณาติดต่อผู้ดูแลระบบ',
        ),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<({List<String> orderIds, double combinedGrandTotal})>
  _createCheckoutOrders({
    required User user,
    required String paymentMethod,
    required String paymentMethodLabel,
    required String paymentStatus,
    required String paymentStatusLabel,
    required String auditSource,
    required bool riderNotifyReady,
    required bool notifyRider,
    required String createdEventLabel,
    CartCheckoutContext? checkoutContext,
    _VerifiedSlipCheckout? verifiedSlip,
    _OmiseVerifiedCheckout? omisePayment,
  }) async {
    if (_cartItems.isEmpty) {
      throw Exception('ไม่มีสินค้าในตะกร้า');
    }

    final checkoutQuoteId = checkoutContext?.checkoutQuoteId?.trim();
    if (checkoutQuoteId == null || checkoutQuoteId.isEmpty) {
      throw Exception('ยังไม่มี checkout quote กรุณารอระบบคำนวณยอดสักครู่');
    }

    final cartSnapshot = List<CartLineItem>.from(_cartItems);
    final discounts =
        checkoutContext?.discounts ?? CartDiscountSnapshot.empty;

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('createCheckoutOrders');
      final response = await callable.call(<String, dynamic>{
        'items': cartSnapshot
            .map(
              (item) => <String, dynamic>{
                'productId': item.productId,
                'shopId': item.shopId,
                'quantity': item.quantity,
                'selectedToppings': item.selectedToppings,
                'shopLatitude': item.shopLatitude,
                'shopLongitude': item.shopLongitude,
              },
            )
            .toList(growable: false),
        'customerLatitude': _userLocation.latitude,
        'customerLongitude': _userLocation.longitude,
        'customerLocation': <String, dynamic>{
          'latitude': _userLocation.latitude,
          'longitude': _userLocation.longitude,
          'label': _userLocation.title,
        },
        'paymentMethod': paymentMethod,
        'paymentMethodLabel': paymentMethodLabel,
        'paymentStatus': paymentStatus,
        'paymentStatusLabel': paymentStatusLabel,
        'auditSource': auditSource,
        'notifyRider': notifyRider,
        'riderNotifyReady': riderNotifyReady,
        'createdEventLabel': createdEventLabel,
        'checkoutQuoteId': checkoutQuoteId,
        if (checkoutContext?.couponCode != null &&
            checkoutContext!.couponCode!.isNotEmpty)
          'couponCode': checkoutContext.couponCode,
        if (verifiedSlip != null) ...<String, dynamic>{
          'paymentGroupId': verifiedSlip.paymentGroupId,
          'verificationFeedbackId': verifiedSlip.verificationFeedbackId,
          'slipStoragePath': verifiedSlip.storagePath,
          'slipDownloadUrl': verifiedSlip.downloadUrl,
          'slipFileName': verifiedSlip.fileName,
          'slipSizeBytes': verifiedSlip.sizeBytes,
          'verificationMessage': verifiedSlip.verificationMessage,
        },
        if (omisePayment != null) ...<String, dynamic>{
          'paymentSessionId': omisePayment.paymentSessionId,
          'paymentGroupId': omisePayment.paymentSessionId,
          'verificationFeedbackId': omisePayment.paymentSessionId,
          if (omisePayment.omiseChargeId != null)
            'omiseChargeId': omisePayment.omiseChargeId,
        },
      });

      final payload = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final orderIds =
          (payload['orderIds'] as List?)
              ?.map((id) => id.toString())
              .toList(growable: false) ??
          const <String>[];
      final combinedGrandTotal =
          (payload['combinedGrandTotal'] as num?)?.toDouble() ?? 0.0;
      final shopsWithoutRider =
          (payload['shopsWithoutRider'] as List?)
              ?.map((shop) => shop.toString())
              .toList(growable: false) ??
          const <String>[];

      if (orderIds.isEmpty) {
        throw Exception('ไม่สามารถสร้างออเดอร์ได้');
      }

      if (mounted && shopsWithoutRider.isNotEmpty) {
        await showRiderUnavailableDialog(
          context,
          shopNames: shopsWithoutRider,
          orderIds: orderIds,
        );
      }

      if (mounted) {
        await _clearCartAfterCheckout();
        _focusRoadmapOrders(orderIds);
        _showSnackBar('สั่งซื้อสำเร็จ — ติดตามสถานะได้ที่แท็บลูกค้า');
      }

      await _recordCheckoutDiscounts(
        orderIds: orderIds,
        discounts: discounts,
        checkoutQuoteId: checkoutQuoteId,
      );

      return (
        orderIds: orderIds,
        combinedGrandTotal: combinedGrandTotal,
      );
    } catch (e) {
      throw Exception('ไม่สามารถสร้างออเดอร์ได้: $e');
    }
  }

  Future<({List<String> orderIds, double combinedGrandTotal})>
  _createTravelOrder({
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
    _VerifiedSlipCheckout? verifiedSlip,
    _OmiseVerifiedCheckout? omisePayment,
  }) async {
    if (verifiedSlip != null) {
      throw Exception('การชำระด้วยสลิปสำหรับเดินทางยังไม่รองรับ');
    }

    final idempotencyKey = request.idempotencyKey.trim().isNotEmpty
        ? request.idempotencyKey.trim()
        : '${user.uid}_${DateTime.now().microsecondsSinceEpoch}';

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-southeast1',
      ).httpsCallable('createTravelOrder');
      final response = await callable.call(<String, dynamic>{
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
        'scheduledAt': request.rideSelection.scheduledAt.toIso8601String(),
        'scheduleLabel': request.rideSelection.scheduleLabel,
        'isImmediate': request.rideSelection.isImmediate,
        'paymentMethod': paymentMethod,
        'paymentMethodLabel': paymentMethodLabel,
        'paymentStatus': paymentStatus,
        'paymentStatusLabel': paymentStatusLabel,
        'auditSource': auditSource,
        'notifyRider': notifyRider,
        'riderNotifyReady': riderNotifyReady,
        'createdEventLabel': createdEventLabel,
        'idempotencyKey': idempotencyKey,
        if (omisePayment != null) 'paymentSessionId': omisePayment.paymentSessionId,
      });

      final payload = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};
      final orderIds =
          (payload['orderIds'] as List?)
              ?.map((id) => id.toString())
              .toList(growable: false) ??
          const <String>[];
      final combinedGrandTotal =
          (payload['combinedGrandTotal'] as num?)?.toDouble() ?? 0.0;
      final hasAssignedRider = payload['hasAssignedRider'] == true;

      if (orderIds.isEmpty) {
        throw Exception('ไม่สามารถสร้างออเดอร์เดินทางได้');
      }

      if (mounted && !hasAssignedRider) {
        await showRiderUnavailableDialog(
          context,
          shopNames: const <String>['บริการเดินทาง'],
          orderIds: orderIds,
          isTravelOrder: true,
        );
      }

      return (orderIds: orderIds, combinedGrandTotal: combinedGrandTotal);
    } catch (e) {
      throw Exception('ไม่สามารถสร้างออเดอร์เดินทางได้: $e');
    }
  }

  void _focusRoadmapOrders(List<String> orderIds) {
    final uniqueOrderIds = orderIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (!mounted || uniqueOrderIds.isEmpty) {
      return;
    }

    setState(() {
      _roadmapFocusOrderIds = uniqueOrderIds;
      _selectedBottomTab = 2;
      _activeCatalog = null;
      _showNationwideCart = false;
    });
  }

  Future<void> _openOrderRoadmap(
    List<String> orderIds, {
    bool showTravelTracking = true,
  }) async {
    if (!mounted || orderIds.isEmpty) {
      return;
    }

    _focusRoadmapOrders(orderIds);

    final orderId = orderIds.first.trim();
    if (showTravelTracking && orderId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .get();
        final data = doc.data();
        final isTravel = data?['orderType'] == 'travel_passenger' ||
            data?['serviceType'] == 'travel_passenger';
        if (isTravel && mounted) {
          showTravelTrackingScreen(context: context, orderId: orderId);
        }
      } catch (_) {
        // Fall back to roadmap tab only.
      }
    }
  }

  void _onBottomTabSelected(int index) {
    if (index == 0) {
      setState(() {
        _selectedBottomTab = index;
        _activeCatalog = null;
      });
      return;
    }

    unawaited(
      _runProtectedAction(() {
        setState(() {
          _selectedBottomTab = index;
          _activeCatalog = null;
          _showNationwideCart = false;
          if (index == 2) {
            _roadmapFocusOrderIds = const <String>[];
          }
        });

        if (index == 1 || index == 2 || index == 3 || index == 4) {
          return;
        }

        const labels = <String>[
          'โฮม',
          'ตะกร้า',
          'ลูกค้า',
          'แจ้งเตือน',
          'ตั้งค่า',
        ];
        _showSnackBar('หน้า ${labels[index]} กำลังพัฒนา');
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cartQuantity = _cartItems.fold<int>(
      0,
      (totalQuantity, item) => totalQuantity + item.quantity,
    );
    final activeCatalog = _activeCatalog;
    final body = switch (_selectedBottomTab) {
      0 =>
        _showNationwideCart
            ? NationwideCartScreen(
                cartItems: _nationwideCartItems,
                onRemoveItem: _removeNationwideCartItem,
                onBackToCatalog: () {
                  setState(() {
                    _showNationwideCart = false;
                    _activeCatalog = null;
                  });
                  unawaited(_openNationwideCategoryPicker());
                },
                onOrderCreated: (orderIds) async {
                  setState(() {
                    _nationwideCartItems.clear();
                    _showNationwideCart = false;
                    _activeCatalog = null;
                  });
                  if (_cartItems.isEmpty) {
                    await CartSessionService.consumeStockHold();
                  } else {
                    await CartSessionService.syncStockHold(
                      List<CartLineItem>.from(_cartItems),
                    );
                  }
                  await CartSessionService.saveLocalCart(
                    cartItems: List<CartLineItem>.from(_cartItems),
                    nationwideCartItems: const <CartLineItem>[],
                  );
                  _resetCartExpiryTimer();
                  await _openOrderRoadmap(orderIds);
                },
              )
            : activeCatalog == null
            ? _buildHomeBody()
            : CategoryCatalogScreen(
                title: activeCatalog.title,
                serviceType: activeCatalog.serviceType,
                shopIdFilter: activeCatalog.shopIdFilter,
                customerLatitude: _userLocation.latitude,
                customerLongitude: _userLocation.longitude,
                onConfirmOrder: _addToCart,
                onNavigateToCart: _openCartTab,
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
        onSubmitOmisePayment: _submitOmiseCheckoutOrder,
        onOpenOrderRoadmap: _openOrderRoadmap,
        initialCouponCode: _pendingCartCouponCode,
        onOpenMyCoupons: _openMyCouponsWallet,
      ),
      2 => OrderRoadmapScreen(
        orderIds: _roadmapFocusOrderIds,
        onReorderProducts: _reorderProductsFromHistory,
        onTravelAgain: _startTravelPlannerFresh,
      ),
      3 => NotificationScreen(onOpenOrder: _focusRoadmapOrders),
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
                    MaterialPageRoute<void>(
                      builder: (_) => const SplashScreen(),
                    ),
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        if (!_handleRootBackPress()) {
          SystemNavigator.pop();
        }
      },
      child: Stack(
        children: <Widget>[
          Scaffold(
      backgroundColor: _selectedBottomTab == 4
          ? Colors.white
          : const Color(0xFFF4FAFB),
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
            labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((
              states,
            ) {
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
                label: 'ลูกค้า',
              ),
              NavigationDestination(
                icon: _CartNavIcon(
                  icon: Icons.notifications_none_rounded,
                  count: _unreadNotificationCount,
                ),
                selectedIcon: _CartNavIcon(
                  icon: Icons.notifications_rounded,
                  count: _unreadNotificationCount,
                ),
                label: 'แจ้งเตือน',
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
          ),
          _buildClaimableCouponPopupOverlay(),
        ],
      ),
    );
  }

  Widget _buildHomeBody() {
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
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(28),
                                onTap: _openGlobalProductSearch,
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
                                          'ค้นหาทุกสินค้าในแว๊นตลาด',
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
                            ),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: _openFavoritesScreen,
                            borderRadius: BorderRadius.circular(24),
                            child: _HeaderAvatarBadge(
                              icon: Icons.favorite_border,
                              backgroundColor: const Color(0xFFFFC928),
                              foregroundColor: const Color(0xFF7A4B00),
                            ),
                          ),
                          const SizedBox(width: 12),
                          InkWell(
                            onTap: _openMyCouponsWallet,
                            borderRadius: BorderRadius.circular(24),
                            child: _HeaderAvatarBadge(
                              icon: Icons.local_offer_outlined,
                              backgroundColor: const Color(0xFFFFF7ED),
                              foregroundColor: const Color(0xFFE55A00),
                            ),
                          ),
                        ],
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
              childAspectRatio: 0.74,
            ),
          ),
        ),
        if (PromotionDisplayConfigService.instance.current.homePromoBanner)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
            sliver: SliverToBoxAdapter(
              child: StreamBuilder<List<PromotionOffer>>(
                stream: PromotionCatalogService.instance.watchActivePromotions(),
                builder: (context, snapshot) {
                  final promotions = snapshot.data ?? const <PromotionOffer>[];
                  if (promotions.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return HomePromoCarousel(
                    promotions: promotions,
                    onTap: _openCartTab,
                  );
                },
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
          sliver: SliverToBoxAdapter(
            child: StreamBuilder<List<ClaimableCouponOffer>>(
              stream: ClaimableCouponService.instance.watchActiveClaimableCoupons(),
              builder: (context, couponsSnapshot) {
                final user = FirebaseAuth.instance.currentUser;
                return StreamBuilder<Set<String>>(
                  stream: UserCouponWalletService.instance
                      .watchClaimedCouponIds(user?.uid),
                  builder: (context, claimedSnapshot) {
                    final coupons =
                        couponsSnapshot.data ?? const <ClaimableCouponOffer>[];
                    final claimedIds = claimedSnapshot.data ?? <String>{};
                    return ClaimableCouponStrip(
                      coupons: coupons,
                      claimedCouponIds: claimedIds,
                      onClaimed: _onCouponClaimed,
                    );
                  },
                );
              },
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          sliver: SliverToBoxAdapter(
            child: _HomeProductShelves(
              customerLatitude: _userLocation.latitude,
              customerLongitude: _userLocation.longitude,
              onProductTap: _openShopCatalogFromProduct,
              onConfirmOrder: _addToCart,
              onNavigateToCart: _openCartTab,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickActionItem {
  const _QuickActionItem({
    required this.label,
    this.icon,
    this.iconColor,
    this.serviceType,
    this.actionKey,
  });

  final String label;
  final IconData? icon;
  final Color? iconColor;
  final String? serviceType;
  final String? actionKey;
}

class _ActiveCatalog {
  const _ActiveCatalog({
    required this.title,
    this.serviceType = '',
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
          Align(alignment: Alignment.center, child: Icon(icon)),
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
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      child: Center(
        child: Icon(icon, color: foregroundColor, size: 28),
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
    final labelFontSize = item.label.length > 8 ? 10.5 : 13.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF8FA),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            _SquareImagePlaceholder(
              size: 56.0,
              icon: item.icon,
              iconColor: item.iconColor,
            ),
            const SizedBox(height: 4),
            Text(
              item.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: labelFontSize,
                height: 1.12,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1F2937),
              ),
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
    this.icon,
    this.iconColor,
  });

  final double size;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    if (icon != null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
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

class _HomeProductShelves extends StatefulWidget {
  const _HomeProductShelves({
    required this.customerLatitude,
    required this.customerLongitude,
    required this.onProductTap,
    required this.onConfirmOrder,
    required this.onNavigateToCart,
  });

  final double customerLatitude;
  final double customerLongitude;
  final ValueChanged<PublicCatalogProduct> onProductTap;
  final ValueChanged<CartProductSelection> onConfirmOrder;
  final VoidCallback onNavigateToCart;

  @override
  State<_HomeProductShelves> createState() => _HomeProductShelvesState();
}

class _HomeProductShelvesState extends State<_HomeProductShelves> {
  late final Future<List<PublicCatalogProduct>> _featuredFuture;
  Future<
    ({
      List<PublicCatalogProduct> bestSelling,
      List<PublicCatalogProduct> personalized,
    })
  >?
  _secondaryFuture;
  String? _secondaryFutureKey;
  String? _scheduledShelfPrefetchKey;

  @override
  void initState() {
    super.initState();
    unawaited(_ensureCatalogFirebaseSession());
    _featuredFuture = HomeProductDiscoveryService.streamFeaturedShelf()
        .first
        .timeout(const Duration(seconds: 15));
    HomeProductImagePrefetch.startHomeWarmOnce(
      featuredFuture: _featuredFuture,
      secondaryFuture: _secondaryFutureForWarm(),
    );
  }

  Future<
    ({
      List<PublicCatalogProduct> bestSelling,
      List<PublicCatalogProduct> personalized,
    })
  >
  _secondaryFutureForWarm() async {
    final featured = await _featuredFuture;
    final featuredIds = featured.map((product) => product.id).toSet();
    return _loadSecondaryShelves(featuredIds);
  }

  Future<void> _ensureCatalogFirebaseSession() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        await FirebaseAuth.instance.signInAnonymously();
        return;
      }
      await user.getIdToken();
    } catch (_) {}
  }

  Future<
    ({
      List<PublicCatalogProduct> bestSelling,
      List<PublicCatalogProduct> personalized,
    })
  >
  _loadSecondaryShelves(Set<String> excludeFeaturedIds) async {
    final bestSelling = await HomeProductDiscoveryService.loadBestSellingShelf(
      excludeIds: excludeFeaturedIds,
    );
    final combinedExclude = <String>{
      ...excludeFeaturedIds,
      ...bestSelling.map((product) => product.id),
    };
    final personalized =
        await HomeProductDiscoveryService.loadPersonalizedShelf(
          customerLatitude: widget.customerLatitude,
          customerLongitude: widget.customerLongitude,
          excludeIds: combinedExclude,
        );
    final fallbackPersonalized = personalized.isNotEmpty
        ? personalized
        : await HomeProductDiscoveryService.loadPersonalizedShelf(
            customerLatitude: widget.customerLatitude,
            customerLongitude: widget.customerLongitude,
            excludeIds: excludeFeaturedIds,
          );
    return (bestSelling: bestSelling, personalized: fallbackPersonalized);
  }

  Future<
    ({
      List<PublicCatalogProduct> bestSelling,
      List<PublicCatalogProduct> personalized,
    })
  >
  _secondaryFutureForKey(Set<String> featuredIds) {
    final key = featuredIds.join(',');
    if (_secondaryFuture != null && _secondaryFutureKey == key) {
      return _secondaryFuture!;
    }
    _secondaryFutureKey = key;
    _secondaryFuture = _loadSecondaryShelves(featuredIds);
    return _secondaryFuture!;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PublicCatalogProduct>>(
      stream: HomeProductDiscoveryService.streamFeaturedShelf(),
      builder: (context, featuredSnapshot) {
        final featured =
            featuredSnapshot.data ?? const <PublicCatalogProduct>[];
        final featuredIds = featured.map((product) => product.id).toSet();
        final loadingFeatured =
            featuredSnapshot.connectionState == ConnectionState.waiting &&
            featured.isEmpty;

        return FutureBuilder<
          ({
            List<PublicCatalogProduct> bestSelling,
            List<PublicCatalogProduct> personalized,
          })
        >(
          key: ValueKey<String>(featuredIds.join(',')),
          future: loadingFeatured
              ? null
              : _secondaryFutureForKey(featuredIds),
          builder: (context, secondarySnapshot) {
            final secondary = secondarySnapshot.data;
            final loadingSecondary =
                secondarySnapshot.connectionState == ConnectionState.waiting;

            if (!loadingFeatured && featured.isNotEmpty) {
              final prefetchKey = featuredIds.join(',');
              if (_scheduledShelfPrefetchKey != prefetchKey) {
                _scheduledShelfPrefetchKey = prefetchKey;
                HomeProductImagePrefetch.scheduleShelfPrefetch(featured);
              }
            }
            if (secondary != null && !loadingSecondary) {
              HomeProductImagePrefetch.scheduleShelfPrefetch(
                <PublicCatalogProduct>[
                  ...featured,
                  ...secondary.bestSelling,
                  ...secondary.personalized,
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                HomeProductShelfSection(
                  title: 'สินค้าแนะนำ',
                  products: featured,
                  isLoading: loadingFeatured,
                  onProductTap: widget.onProductTap,
                  useCatalogCardStyle: true,
                  customerLatitude: widget.customerLatitude,
                  customerLongitude: widget.customerLongitude,
                  onConfirmOrder: widget.onConfirmOrder,
                  onNavigateToCart: widget.onNavigateToCart,
                ),
                const SizedBox(height: 20),
                HomeProductShelfSection(
                  title: 'สินค้าขายดี',
                  products:
                      secondary?.bestSelling ?? const <PublicCatalogProduct>[],
                  isLoading: loadingFeatured || loadingSecondary,
                  onProductTap: widget.onProductTap,
                  useCatalogCardStyle: true,
                  customerLatitude: widget.customerLatitude,
                  customerLongitude: widget.customerLongitude,
                  onConfirmOrder: widget.onConfirmOrder,
                  onNavigateToCart: widget.onNavigateToCart,
                ),
                const SizedBox(height: 20),
                HomeProductShelfSection(
                  title: 'สินค้าที่คุณอาจรู้จัก',
                  products:
                      secondary?.personalized ?? const <PublicCatalogProduct>[],
                  isLoading: loadingFeatured || loadingSecondary,
                  onProductTap: widget.onProductTap,
                  useCatalogCardStyle: true,
                  customerLatitude: widget.customerLatitude,
                  customerLongitude: widget.customerLongitude,
                  onConfirmOrder: widget.onConfirmOrder,
                  onNavigateToCart: widget.onNavigateToCart,
                  showWhenEmpty: true,
                  emptyMessage: 'ยังไม่มีสินค้าที่ตรงกับประวัติของคุณ',
                ),
              ],
            );
          },
        );
      },
    );
  }
}
