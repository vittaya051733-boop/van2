/// Estimates delivery travel time from straight-line shop distance.
/// Uses the same road factor and average speed as cart shipping fallback.
class DeliveryEtaPolicy {
  DeliveryEtaPolicy._();

  static const double haversineRoadFactor = 1.35;
  static const double averageSpeedKmh = 30.0;

  static int estimateTravelMinutesFromStraightDistanceKm(
    double? straightDistanceKm,
  ) {
    if (straightDistanceKm == null || straightDistanceKm <= 0) {
      return 0;
    }

    final roadKm = straightDistanceKm * haversineRoadFactor;
    return (roadKm / averageSpeedKmh * 60).ceil().clamp(1, 240);
  }

  static int estimateTotalDeliveryMinutes({
    required int preparationTimeMinutes,
    required double? straightDistanceKm,
  }) {
    final prep = preparationTimeMinutes.clamp(1, 240);
    final travel = estimateTravelMinutesFromStraightDistanceKm(straightDistanceKm);
    if (travel <= 0) {
      return prep;
    }
    return prep + travel;
  }
}
