import 'places_autocomplete_types.dart';
import 'places_autocomplete_client_io.dart'
    if (dart.library.html) 'places_autocomplete_client_web.dart';

export 'places_autocomplete_types.dart';

class PlacesAutocompleteService {
  PlacesAutocompleteService._();

  static bool get isConfigured => PlacesAutocompleteClient.isConfigured;

  static Future<PlacesAutocompleteResult> fetchSuggestions({
    required String query,
    double? originLat,
    double? originLng,
  }) {
    return PlacesAutocompleteClient.fetchSuggestions(
      query: query,
      originLat: originLat,
      originLng: originLng,
    );
  }

  static Future<ResolvedPlace?> resolvePlace(String placeId) {
    return PlacesAutocompleteClient.resolvePlace(placeId);
  }
}
