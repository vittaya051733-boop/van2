import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// Customer-initiated order lifecycle actions (cancel / refund / wait).
class CustomerOrderActionsService {
  CustomerOrderActionsService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
    bool? useCloudFunctions,
  })  : _functions = functions,
        _firestore = firestore,
        _useCloudFunctions = useCloudFunctions ?? firestore == null;

  final FirebaseFunctions? _functions;
  final FirebaseFirestore? _firestore;
  final bool _useCloudFunctions;

  factory CustomerOrderActionsService.production() {
    return CustomerOrderActionsService(
      functions: FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
      useCloudFunctions: true,
    );
  }

  factory CustomerOrderActionsService.forTesting(FirebaseFirestore firestore) {
    return CustomerOrderActionsService(
      firestore: firestore,
      useCloudFunctions: false,
    );
  }

  Future<void> shopWait15Min({
    required String orderId,
  }) {
    return _invoke(
      orderId: orderId,
      action: 'shop_wait_15_min',
      directUpdate: {
        'status': 'accepted',
        'customerShopWaitUntil': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 15)),
        ),
        'customerShopWaitRequestedAt': FieldValue.serverTimestamp(),
        'customerShopChoice': 'wait_15_min',
        'shopDecisionStatus': FieldValue.delete(),
        'shopRejectedAt': FieldValue.delete(),
        'shopRejectedBy': FieldValue.delete(),
        'cancelReason': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> shopCancel({
    required String orderId,
    required bool shopRejected,
    Map<String, String>? refundInfo,
  }) {
    final update = <String, dynamic>{
      'status': 'cancelled',
      'statusLabel': 'ยกเลิกออเดอร์',
      'cancelledAt': FieldValue.serverTimestamp(),
      'cancelReason': shopRejected
          ? 'customer_cancelled_after_shop_rejected'
          : 'customer_cancelled_after_shop_no_response',
      'customerShopChoice': 'cancel',
      'customerCancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (refundInfo != null) {
      update.addAll({
        'refundRequested': true,
        'refundRequestedAt': FieldValue.serverTimestamp(),
        'refundStatus': 'requested',
        ...refundInfo,
      });
    }
    return _invoke(
      orderId: orderId,
      action: 'shop_cancel',
      refundInfo: refundInfo,
      directUpdate: update,
      directCancelledBy: true,
      directRefundRequestedBy: refundInfo != null,
    );
  }

  Future<void> noRiderWait15Min({
    required String orderId,
  }) {
    return _invoke(
      orderId: orderId,
      action: 'no_rider_wait_15_min',
      directUpdate: {
        'customerWaitUntil': Timestamp.fromDate(
          DateTime.now().add(const Duration(minutes: 15)),
        ),
        'customerWaitRequestedAt': FieldValue.serverTimestamp(),
        'customerNoRiderChoice': 'wait_15_min',
        'reassignFailureReason': FieldValue.delete(),
        'needsReassign': true,
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<void> noRiderCancel({
    required String orderId,
    required bool scheduledTravel,
  }) {
    return _invoke(
      orderId: orderId,
      action: 'no_rider_cancel',
      directUpdate: {
        'status': 'cancelled',
        'statusLabel': 'ยกเลิกออเดอร์',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelReason': scheduledTravel
            ? 'scheduled_travel_no_rider_customer_cancelled'
            : 'no_rider_available_customer_cancelled',
        'customerNoRiderChoice': 'cancel',
        'needsReassign': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      directCancelledBy: true,
    );
  }

  Future<void> noRiderRefund({
    required String orderId,
    required bool scheduledTravel,
    required Map<String, String> refundInfo,
  }) {
    return _invoke(
      orderId: orderId,
      action: 'no_rider_refund',
      refundInfo: refundInfo,
      directUpdate: {
        'status': 'refund',
        'cancelledAt': FieldValue.serverTimestamp(),
        'cancelReason': scheduledTravel
            ? 'scheduled_travel_no_rider_refund_requested'
            : 'no_rider_available_refund_requested',
        'refundRequested': true,
        'refundRequestedAt': FieldValue.serverTimestamp(),
        'refundStatus': 'requested',
        ...refundInfo,
        'customerNoRiderChoice': 'refund',
        'needsReassign': false,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      directRefundRequestedBy: true,
    );
  }

  Future<void> _invoke({
    required String orderId,
    required String action,
    Map<String, String>? refundInfo,
    Map<String, dynamic>? directUpdate,
    bool directCancelledBy = false,
    bool directRefundRequestedBy = false,
  }) async {
    if (!_useCloudFunctions) {
      final firestore = _firestore;
      final update = Map<String, dynamic>.from(directUpdate ?? {});
      if (directCancelledBy) {
        update['cancelledBy'] = 'test-user';
      }
      if (directRefundRequestedBy) {
        update['refundRequestedBy'] = 'test-user';
      }
      await firestore!.collection('orders').doc(orderId).set(
            update,
            SetOptions(merge: true),
          );
      return;
    }

    try {
      await _functions!.httpsCallable('customerOrderAction').call(<String, dynamic>{
        'orderId': orderId,
        'action': action,
        if (refundInfo != null) 'refundInfo': refundInfo,
      });
    } on FirebaseFunctionsException catch (error) {
      debugPrint('customerOrderAction failed: ${error.code} ${error.message}');
      rethrow;
    }
  }
}
