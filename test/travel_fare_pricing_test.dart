import 'package:flutter_test/flutter_test.dart';
import 'package:van2/shipping_pricing_policy.dart';
import 'package:van2/travel_vehicle_type.dart';

void main() {
  group('Travel fare matches server createTravelOrder formula', () {
    setUp(() {
      ShippingPricingPolicy.configure(
        shippingBaseFee: 25,
        shippingPerKmFee: 8,
        shippingMinBillableKm: 1,
        shippingMissingCoordsFee: 35,
        travelBaseFee: 25,
        travelPerKmFee: 8,
        travelMinBillableKm: 1,
        nationwideBaseFee: 45,
        nationwidePerKgFee: 18,
        nationwideRemoteSurcharge: 30,
      );
    });

    test('short distance uses base fee only', () {
      final fare = ShippingPricingPolicy.computeTravelFareForVehicle(
        0.51,
        TravelVehicleType.motorcycle,
      );
      expect(fare, 25);
    });

    test('5.2 km motorcycle uses min-adjusted per-km', () {
      final fare = ShippingPricingPolicy.computeTravelFareForVehicle(
        5.2,
        TravelVehicleType.motorcycle,
      );
      expect(fare, 58.6);
    });

    test('sedan multiplier applies after distance fee', () {
      final fare = ShippingPricingPolicy.computeTravelFareForVehicle(
        5.2,
        TravelVehicleType.sedan,
      );
      expect(fare, closeTo(73.25, 0.001));
    });
  });
}
