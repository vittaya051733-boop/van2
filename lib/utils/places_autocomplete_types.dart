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
