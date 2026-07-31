import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/google_maps_web_api_key.dart';
import 'app_check_guard.dart';
import 'places_autocomplete_types.dart';

class PlacesAutocompleteClient {
  PlacesAutocompleteClient._();

  static const Duration _requestTimeout = Duration(seconds: 12);
  static const int _searchRadiusMeters = 50000;
  static const String _functionsRegion = 'asia-southeast1';

  /// Logged-in users call Cloud Functions (server key). Direct REST only when
  /// `--dart-define=GOOGLE_MAPS_WEB_API_KEY` is set (dev / unrestricted key).
  static bool get isConfigured =>
      FirebaseAuth.instance.currentUser != null ||
      googleMapsWebApiKey.isNotEmpty;

  static Future<PlacesAutocompleteResult> fetchSuggestions({
    required String query,
    double? originLat,
    double? originLng,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.length < 2) {
      return const PlacesAutocompleteResult(suggestions: <PlaceSuggestion>[]);
    }

    if (FirebaseAuth.instance.currentUser != null) {
      final cloudResult = await _fetchSuggestionsFromCloudFunction(
        query: trimmedQuery,
        originLat: originLat,
        originLng: originLng,
      );
      if (cloudResult != null) {
        return cloudResult;
      }
    }

    if (googleMapsWebApiKey.isEmpty) {
      return PlacesAutocompleteResult(
        suggestions: const <PlaceSuggestion>[],
        failureMessage: FirebaseAuth.instance.currentUser == null
            ? 'กรุณาเข้าสู่ระบบก่อนค้นหาสถานที่'
            : 'ไม่สามารถค้นหาสถานที่ได้ กรุณาลองใหม่อีกครั้ง',
      );
    }

    return _fetchSuggestionsDirect(
      query: trimmedQuery,
      originLat: originLat,
      originLng: originLng,
    );
  }

  static Future<PlacesAutocompleteResult?> _fetchSuggestionsFromCloudFunction({
    required String query,
    double? originLat,
    double? originLng,
  }) async {
    try {
      await AppCheckGuard.ensureCheckoutReady();
      final callable = FirebaseFunctions.instanceFor(
        region: _functionsRegion,
      ).httpsCallable('placesAutocomplete');

      final payload = <String, Object>{
        'input': query,
      };
      if (originLat != null &&
          originLng != null &&
          originLat.isFinite &&
          originLng.isFinite) {
        payload['originLat'] = originLat;
        payload['originLng'] = originLng;
      }

      final result = await callable.call(payload).timeout(_requestTimeout);
      final data = result.data;
      if (data is! Map) {
        return const PlacesAutocompleteResult(
          suggestions: <PlaceSuggestion>[],
          failureMessage: 'Places Autocomplete ตอบกลับไม่ถูกต้อง',
        );
      }

      final rawSuggestions = data['suggestions'];
      if (rawSuggestions is! List) {
        return const PlacesAutocompleteResult(suggestions: <PlaceSuggestion>[]);
      }

      final suggestions = rawSuggestions
          .whereType<Map>()
          .map(_parseCloudSuggestion)
          .whereType<PlaceSuggestion>()
          .toList(growable: false);

      return PlacesAutocompleteResult(suggestions: suggestions);
    } on FirebaseFunctionsException catch (error) {
      return PlacesAutocompleteResult(
        suggestions: const <PlaceSuggestion>[],
        failureMessage: error.message ?? 'Places Autocomplete: ${error.code}',
      );
    } catch (error) {
      return null;
    }
  }

  static PlaceSuggestion? _parseCloudSuggestion(Map<dynamic, dynamic> item) {
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

  static Future<PlacesAutocompleteResult> _fetchSuggestionsDirect({
    required String query,
    double? originLat,
    double? originLng,
  }) async {
    final params = <String, String>{
      'input': query,
      'key': googleMapsWebApiKey,
      'language': 'th',
      'components': 'country:th',
    };

    if (originLat != null &&
        originLng != null &&
        originLat.isFinite &&
        originLng.isFinite) {
      params['location'] = '$originLat,$originLng';
      params['radius'] = '$_searchRadiusMeters';
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      params,
    );

    try {
      final response = await http.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) {
        return PlacesAutocompleteResult(
          suggestions: const <PlaceSuggestion>[],
          failureMessage: 'Places Autocomplete HTTP ${response.statusCode}',
        );
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        return const PlacesAutocompleteResult(
          suggestions: <PlaceSuggestion>[],
          failureMessage: 'Places Autocomplete ตอบกลับไม่ถูกต้อง',
        );
      }

      final status = payload['status'];
      if (status == 'ZERO_RESULTS') {
        return const PlacesAutocompleteResult(suggestions: <PlaceSuggestion>[]);
      }

      if (status != 'OK') {
        final errorMessage = payload['error_message'];
        return PlacesAutocompleteResult(
          suggestions: const <PlaceSuggestion>[],
          failureMessage: errorMessage is String && errorMessage.isNotEmpty
              ? errorMessage
              : 'Places Autocomplete: $status',
        );
      }

      final predictions = payload['predictions'];
      if (predictions is! List) {
        return const PlacesAutocompleteResult(suggestions: <PlaceSuggestion>[]);
      }

      final suggestions = predictions
          .whereType<Map<String, dynamic>>()
          .map(_parsePrediction)
          .whereType<PlaceSuggestion>()
          .toList(growable: false);

      return PlacesAutocompleteResult(suggestions: suggestions);
    } catch (error) {
      return PlacesAutocompleteResult(
        suggestions: const <PlaceSuggestion>[],
        failureMessage: 'Places Autocomplete: $error',
      );
    }
  }

  static PlaceSuggestion? _parsePrediction(Map<String, dynamic> prediction) {
    final placeId = prediction['place_id'];
    if (placeId is! String || placeId.isEmpty) {
      return null;
    }

    final structured = prediction['structured_formatting'];
    final mainText = structured is Map
        ? structured['main_text']?.toString().trim()
        : null;
    final secondaryText = structured is Map
        ? structured['secondary_text']?.toString().trim()
        : null;
    final description = prediction['description']?.toString().trim() ?? '';

    final primary = (mainText == null || mainText.isEmpty)
        ? description
        : mainText;
    if (primary.isEmpty) {
      return null;
    }

    return PlaceSuggestion(
      placeId: placeId,
      primaryText: primary,
      secondaryText: secondaryText ?? '',
      description: description.isEmpty ? primary : description,
    );
  }

  static Future<ResolvedPlace?> resolvePlace(String placeId) async {
    final trimmedPlaceId = placeId.trim();
    if (trimmedPlaceId.isEmpty) {
      return null;
    }

    if (FirebaseAuth.instance.currentUser != null) {
      final cloudPlace = await _resolvePlaceFromCloudFunction(trimmedPlaceId);
      if (cloudPlace != null) {
        return cloudPlace;
      }
    }

    if (googleMapsWebApiKey.isEmpty) {
      return null;
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      <String, String>{
        'place_id': trimmedPlaceId,
        'fields': 'place_id,name,formatted_address,geometry',
        'language': 'th',
        'key': googleMapsWebApiKey,
      },
    );

    try {
      final response = await http.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) {
        return null;
      }

      final payload = jsonDecode(response.body);
      if (payload is! Map<String, dynamic>) {
        return null;
      }

      if (payload['status'] != 'OK') {
        return null;
      }

      final result = payload['result'];
      if (result is! Map<String, dynamic>) {
        return null;
      }

      final geometry = result['geometry'];
      final location = geometry is Map ? geometry['location'] : null;
      final latitude = location is Map ? location['lat'] : null;
      final longitude = location is Map ? location['lng'] : null;
      if (latitude is! num || longitude is! num) {
        return null;
      }

      final name = result['name']?.toString().trim() ?? '';
      final formattedAddress =
          result['formatted_address']?.toString().trim() ?? '';
      final resolvedPlaceId = result['place_id']?.toString().trim() ?? trimmedPlaceId;

      if (name.isEmpty) {
        return null;
      }

      return ResolvedPlace(
        placeId: resolvedPlaceId,
        title: name,
        subtitle: formattedAddress == name || formattedAddress.isEmpty
            ? ''
            : formattedAddress,
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<ResolvedPlace?> _resolvePlaceFromCloudFunction(
    String placeId,
  ) async {
    try {
      await AppCheckGuard.ensureCheckoutReady();
      final callable = FirebaseFunctions.instanceFor(
        region: _functionsRegion,
      ).httpsCallable('placesResolvePlace');

      final result = await callable
          .call(<String, Object>{'placeId': placeId})
          .timeout(_requestTimeout);

      final data = result.data;
      if (data is! Map) {
        return null;
      }

      final latitude = data['latitude'];
      final longitude = data['longitude'];
      if (latitude is! num || longitude is! num) {
        return null;
      }

      final title = data['title']?.toString().trim() ?? '';
      if (title.isEmpty) {
        return null;
      }

      final subtitle = data['subtitle']?.toString().trim() ?? '';
      final resolvedPlaceId =
          data['placeId']?.toString().trim() ?? placeId;

      return ResolvedPlace(
        placeId: resolvedPlaceId,
        title: title,
        subtitle: subtitle,
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}
