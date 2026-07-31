import 'package:cloud_functions/cloud_functions.dart';

import '../travel_planner_screen.dart';
import '../utils/app_check_guard.dart';

class TravelFareQuote {
  const TravelFareQuote({
    required this.fare,
    required this.billableDistanceKm,
  });

  final double fare;
  final double billableDistanceKm;
}

/// Server-authoritative travel fare before Omise charge (matches createTravelOrder).
class TravelFareQuoteService {
  TravelFareQuoteService._();

  static const String _functionsRegion = 'asia-southeast1';

  static Future<TravelFareQuote> fetchQuote(TravelPlannerResult request) async {
    await AppCheckGuard.ensureCheckoutReady();

    final callable = FirebaseFunctions.instanceFor(
      region: _functionsRegion,
    ).httpsCallable('quoteTravelFare');

    final response = await callable.call(<String, dynamic>{
      'pickup': <String, dynamic>{
        'latitude': request.pickup.latitude,
        'longitude': request.pickup.longitude,
      },
      'destination': <String, dynamic>{
        'latitude': request.destination.latitude,
        'longitude': request.destination.longitude,
      },
      'distanceKm': request.distanceKm,
      'vehicleType': request.rideSelection.vehicleType.name,
    });

    final payload = response.data;
    if (payload is! Map) {
      throw Exception('ไม่สามารถคำนวณค่าเดินทางได้ กรุณาลองใหม่');
    }

    final fare = (payload['fare'] as num?)?.toDouble();
    final billableDistanceKm =
        (payload['billableDistanceKm'] as num?)?.toDouble();
    if (fare == null || fare <= 0 || billableDistanceKm == null) {
      throw Exception('ไม่สามารถคำนวณค่าเดินทางได้ กรุณาคำนวณเส้นทางใหม่');
    }

    return TravelFareQuote(
      fare: fare,
      billableDistanceKm: billableDistanceKm,
    );
  }
}
