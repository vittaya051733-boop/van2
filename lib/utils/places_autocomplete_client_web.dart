import 'dart:js_interop';
import 'dart:js_util' as js_util;

import '../config/google_maps_web_api_key.dart';
import 'places_autocomplete_types.dart';
@JS('vanPlacesFetchSuggestions')
external JSPromise _vanPlacesFetchSuggestions(
  JSString input,
  JSNumber? lat,
  JSNumber? lng,
);

@JS('vanPlacesResolvePlace')
external JSPromise _vanPlacesResolvePlace(JSString placeId);

class PlacesAutocompleteClient {
  PlacesAutocompleteClient._();

  static bool get isConfigured => effectiveGoogleMapsWebApiKey.isNotEmpty;

  static Future<PlacesAutocompleteResult> fetchSuggestions({
    required String query,
    double? originLat,
    double? originLng,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < 2) {
      return const PlacesAutocompleteResult(suggestions: <PlaceSuggestion>[]);
    }

    if (!isConfigured) {
      return const PlacesAutocompleteResult(
        suggestions: <PlaceSuggestion>[],
        failureMessage: 'ยังไม่ได้ตั้ง GOOGLE_MAPS_WEB_API_KEY',
      );
    }

    try {
      final latJs = originLat != null && originLat.isFinite
          ? originLat.toJS
          : null;
      final lngJs = originLng != null && originLng.isFinite
          ? originLng.toJS
          : null;
      final raw = js_util.dartify(
        await _vanPlacesFetchSuggestions(
          trimmedQuery.toJS,
          latJs,
          lngJs,
        ).toDart,
      );
      return _parseSuggestionsResult(raw);
    } catch (error) {
      return PlacesAutocompleteResult(
        suggestions: const <PlaceSuggestion>[],
        failureMessage: 'Places Autocomplete: $error',
      );
    }
  }

  static PlacesAutocompleteResult _parseSuggestionsResult(Object? raw) {
    if (raw is! List) {
      return const PlacesAutocompleteResult(
        suggestions: <PlaceSuggestion>[],
        failureMessage: 'Places Autocomplete ตอบกลับไม่ถูกต้อง',
      );
    }

    final suggestions = raw
        .map(_parseSuggestionMap)
        .whereType<PlaceSuggestion>()
        .toList(growable: false);

    return PlacesAutocompleteResult(suggestions: suggestions);
  }

  static PlaceSuggestion? _parseSuggestionMap(Object? item) {
    if (item is! Map) {
      return null;
    }

    final placeId = item['placeId']?.toString().trim();
    if (placeId == null || placeId.isEmpty) {
      return null;
    }

    final primaryText = item['primaryText']?.toString().trim() ?? '';
    if (primaryText.isEmpty) {
      return null;
    }

    final secondaryText = item['secondaryText']?.toString().trim() ?? '';
    final description =
        item['description']?.toString().trim() ?? primaryText;

    return PlaceSuggestion(
      placeId: placeId,
      primaryText: primaryText,
      secondaryText: secondaryText,
      description: description,
    );
  }

  static Future<ResolvedPlace?> resolvePlace(String placeId) async {
    final trimmedPlaceId = placeId.trim();
    if (!isConfigured || trimmedPlaceId.isEmpty) {
      return null;
    }

    try {
      final raw = js_util.dartify(
        await _vanPlacesResolvePlace(trimmedPlaceId.toJS).toDart,
      );
      return _parseResolvedPlace(raw, trimmedPlaceId);
    } catch (_) {
      return null;
    }
  }

  static ResolvedPlace? _parseResolvedPlace(Object? raw, String fallbackId) {
    if (raw is! Map) {
      return null;
    }

    final latitude = raw['latitude'];
    final longitude = raw['longitude'];
    if (latitude is! num || longitude is! num) {
      return null;
    }

    final title = raw['title']?.toString().trim() ?? '';
    if (title.isEmpty) {
      return null;
    }

    final subtitle = raw['subtitle']?.toString().trim() ?? '';
    final resolvedPlaceId =
        raw['placeId']?.toString().trim() ?? fallbackId;

    return ResolvedPlace(
      placeId: resolvedPlaceId,
      title: title,
      subtitle: subtitle,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
    );
  }
}
