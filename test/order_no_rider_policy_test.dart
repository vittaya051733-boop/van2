import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:van2/utils/order_no_rider_policy.dart';

void main() {
  group('OrderNoRiderPolicy scheduled travel', () {
    test('does not show actions before scheduled lead window', () {
      final scheduledAt = DateTime.now().add(const Duration(hours: 2));
      final data = <String, dynamic>{
        'orderType': 'travel_passenger',
        'status': 'awaiting_rider',
        'paymentStatus': 'verified',
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'travelRequest': <String, dynamic>{
          'isImmediate': false,
          'scheduledAt': Timestamp.fromDate(scheduledAt),
          'scheduleLabel': '25/07/2569 14:30',
        },
      };

      expect(OrderNoRiderPolicy.shouldShowNoRiderActions(data), isFalse);
    });

    test('shows refund actions near scheduled time without rider', () {
      final scheduledAt = DateTime.now().add(const Duration(minutes: 10));
      final data = <String, dynamic>{
        'orderType': 'travel_passenger',
        'status': 'awaiting_rider',
        'paymentStatus': 'verified',
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(hours: 1)),
        ),
        'travelRequest': <String, dynamic>{
          'isImmediate': false,
          'scheduledAt': Timestamp.fromDate(scheduledAt),
          'scheduleLabel': '25/07/2569 14:30',
        },
      };

      expect(OrderNoRiderPolicy.shouldShowNoRiderActions(data), isTrue);
      expect(OrderNoRiderPolicy.allowExtraWait(data), isFalse);
    });

    test('immediate travel still uses 15 minute threshold', () {
      final data = <String, dynamic>{
        'orderType': 'travel_passenger',
        'status': 'awaiting_rider',
        'createdAt': Timestamp.fromDate(
          DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        'travelRequest': <String, dynamic>{
          'isImmediate': true,
        },
      };

      expect(OrderNoRiderPolicy.shouldShowNoRiderActions(data), isFalse);

      data['createdAt'] = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(minutes: 16)),
      );
      expect(OrderNoRiderPolicy.shouldShowNoRiderActions(data), isTrue);
    });
  });
}
