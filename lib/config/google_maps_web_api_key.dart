import 'google_maps_web_api_key_fallback_stub.dart'
    if (dart.library.html) 'google_maps_web_api_key_fallback_web.dart'
    if (dart.library.io) 'google_maps_web_api_key_fallback_io.dart';

/// Web service key for Places / Geocoding / Directions REST calls.
///
/// Override at build time via `--dart-define=GOOGLE_MAPS_WEB_API_KEY=...`
/// When omitted, uses [kGoogleMapsWebApiKeyFallback] (see index.html on web/mobile).
const String googleMapsWebApiKey = String.fromEnvironment(
  'GOOGLE_MAPS_WEB_API_KEY',
);

String get effectiveGoogleMapsWebApiKey => googleMapsWebApiKey.isNotEmpty
    ? googleMapsWebApiKey
    : kGoogleMapsWebApiKeyFallback;
