import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/google_maps_web_api_key.dart';

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
    required this.description,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;
  final String description;
}

class ResolvedPlace {
  const ResolvedPlace({
    required this.placeId,
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
  });

  final String placeId;
  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;
}

class PlacesAutocompleteResult {
  const PlacesAutocompleteResult({
    required this.suggestions,
    this.failureMessage,
  });

  final List<PlaceSuggestion> suggestions;
  final String? failureMessage;

  bool get isSuccess => failureMessage == null;
}

class PlacesAutocompleteService {
  PlacesAutocompleteService._();

  static const Duration _requestTimeout = Duration(seconds: 12);
  static const int _searchRadiusMeters = 50000;

  static bool get isConfigured => googleMapsWebApiKey.isNotEmpty;

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

    final params = <String, String>{
      'input': trimmedQuery,
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
    if (!isConfigured || placeId.trim().isEmpty) {
      return null;
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      <String, String>{
        'place_id': placeId,
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
      final resolvedPlaceId = result['place_id']?.toString().trim() ?? placeId;

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
}
