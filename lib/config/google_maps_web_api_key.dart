/// Web service key for Places / Geocoding / Directions REST calls.
///
/// Override at build time with:
/// `--dart-define=GOOGLE_MAPS_WEB_API_KEY=...`
const String googleMapsWebApiKey = String.fromEnvironment(
  'GOOGLE_MAPS_WEB_API_KEY',
  defaultValue: 'AIzaSyB6Q5DE_VkpqO3qTn3bqPBawQjxzGEngxY',
);
