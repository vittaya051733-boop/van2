/// Mobile has no embedded fallback — browser-restricted web keys cannot call Places REST.
/// Android/iOS use Cloud Functions (`placesAutocomplete`) with server-side key instead.
const String kGoogleMapsWebApiKeyFallback = '';