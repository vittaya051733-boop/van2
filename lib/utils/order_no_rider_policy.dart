import 'package:cloud_firestore/cloud_firestore.dart';

/// When to show no-rider customer actions (wait / refund) for travel and shop orders.
class OrderNoRiderPolicy {
  OrderNoRiderPolicy._();

  static const Duration immediateThreshold = Duration(minutes: 15);
  static const Duration scheduledLeadTime = Duration(minutes: 15);
  static const Duration customerExtraWait = Duration(minutes: 15);

  static DateTime? readTimestamp(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  static bool isTravelOrder(Map<String, dynamic> data) {
    final orderType = (data['orderType'] as String?)?.trim();
    final serviceType = (data['serviceType'] as String?)?.trim();
    return orderType == 'travel_passenger' || serviceType == 'travel_passenger';
  }

  static bool isScheduledTravelOrder(Map<String, dynamic> data) {
    if (!isTravelOrder(data)) {
      return false;
    }
    if (data['isImmediate'] == false) {
      return true;
    }
    final travelRequest = data['travelRequest'];
    if (travelRequest is Map && travelRequest['isImmediate'] == false) {
      return true;
    }
    return false;
  }

  static DateTime? readScheduledAt(Map<String, dynamic> data) {
    final direct = readTimestamp(data['scheduledAt']);
    if (direct != null) {
      return direct;
    }
    final travelRequest = data['travelRequest'];
    if (travelRequest is Map) {
      return readTimestamp(travelRequest['scheduledAt']);
    }
    return null;
  }

  static String? readScheduleLabel(Map<String, dynamic> data) {
    final direct = (data['scheduleLabel'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    final travelRequest = data['travelRequest'];
    if (travelRequest is Map) {
      final nested = (travelRequest['scheduleLabel'] as String?)?.trim();
      if (nested != null && nested.isNotEmpty) {
        return nested;
      }
    }
    return null;
  }

  static DateTime? riderWaitStartedAt(Map<String, dynamic> data) {
    return readTimestamp(data['customerWaitRequestedAt']) ??
        readTimestamp(data['reassignedAt']) ??
        readTimestamp(data['assignedRiderAt']) ??
        readTimestamp(data['customerConfirmedAt']) ??
        readTimestamp(data['createdAt']);
  }

  static bool isCustomerWaiting(Map<String, dynamic> data) {
    final waitUntil = readTimestamp(data['customerWaitUntil']);
    if (waitUntil == null) {
      return false;
    }
    return waitUntil.isAfter(DateTime.now());
  }

  static bool isTerminalStatus(Map<String, dynamic> data) {
    final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
    return status == 'cancelled' ||
        status == 'refund' ||
        status == 'refunded' ||
        status == 'completed' ||
        status == 'delivered';
  }

  static bool isNearOrPastScheduledTime(DateTime scheduledAt, DateTime now) {
    return !now.isBefore(scheduledAt.subtract(scheduledLeadTime));
  }

  static bool allowExtraWait(Map<String, dynamic> data) {
    if (!isScheduledTravelOrder(data)) {
      return true;
    }
    final scheduledAt = readScheduledAt(data);
    if (scheduledAt == null) {
      return true;
    }
    return !isNearOrPastScheduledTime(scheduledAt, DateTime.now());
  }

  static bool hasUnmatchedRiderState(Map<String, dynamic> data) {
    final status = (data['status'] as String?)?.trim() ?? '';
    final driverId = (data['driverId'] as String?)?.trim() ?? '';
    if (status == 'awaiting_rider' && driverId.isEmpty) {
      return true;
    }
    if (status == 'pending' && driverId.isNotEmpty) {
      return true;
    }
    return false;
  }

  static bool shouldShowNoRiderActions(Map<String, dynamic> data) {
    if (isTerminalStatus(data)) {
      return false;
    }

    if (readTimestamp(data['acceptedAt']) != null) {
      return false;
    }

    if (isCustomerWaiting(data)) {
      return true;
    }

    final reassignFailed =
        (data['reassignFailureReason'] as String?)?.trim();
    if (reassignFailed != null && reassignFailed.isNotEmpty) {
      return true;
    }

    if (!hasUnmatchedRiderState(data)) {
      return false;
    }

    if (isScheduledTravelOrder(data)) {
      final scheduledAt = readScheduledAt(data);
      if (scheduledAt == null) {
        return _shouldShowImmediateNoRiderActions(data);
      }
      return isNearOrPastScheduledTime(scheduledAt, DateTime.now());
    }

    return _shouldShowImmediateNoRiderActions(data);
  }

  static bool _shouldShowImmediateNoRiderActions(Map<String, dynamic> data) {
    final waitStartedAt = riderWaitStartedAt(data);
    if (waitStartedAt == null) {
      return false;
    }
    return DateTime.now().difference(waitStartedAt) >= immediateThreshold;
  }
}
