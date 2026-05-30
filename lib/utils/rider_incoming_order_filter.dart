import 'package:cloud_firestore/cloud_firestore.dart';

/// Shared filters for van2 → van3 rider order visibility.
class RiderIncomingOrderFilter {
  RiderIncomingOrderFilter._();

  static const Set<String> eligibleVan2OrderSources = <String>{
    'cod_confirm_dialog',
    'travel_cod_confirm_dialog',
    'promptpay_slip_dialog',
    'travel_promptpay_slip_dialog',
  };

  static const Set<String> pendingStatuses = <String>{
    'pending',
    'awaiting_rider',
  };

  static const Set<String> activeJobStatuses = <String>{
    'accepted',
    'ready',
    'delivering',
  };

  static bool isVan2CustomerOrder(Map<String, dynamic> data) {
    return (data['sourceApp'] as String?)?.trim() == 'van2_customer';
  }

  static bool isEligibleVan2CustomerOrder(Map<String, dynamic> data) {
    if (!isVan2CustomerOrder(data)) {
      return false;
    }

    if (data['customerConfirmed'] != true || data['riderNotifyReady'] != true) {
      return false;
    }

    if (data['customerConfirmedAt'] is! Timestamp) {
      return false;
    }

    final audit = data['audit'];
    if (audit is! Map<String, dynamic>) {
      return false;
    }

    final createdSource = (audit['createdSource'] as String?)?.trim();
    return eligibleVan2OrderSources.contains(createdSource);
  }

  static bool isPendingIncomingOrder(Map<String, dynamic> data) {
    if (!isEligibleVan2CustomerOrder(data)) {
      return isVan2CustomerOrder(data) ? false : _isLegacyPendingOrder(data);
    }

    final status = (data['status'] as String?)?.trim() ?? '';
    return pendingStatuses.contains(status);
  }

  static bool isActiveAcceptedOrder(Map<String, dynamic> data) {
    final status = (data['status'] as String?)?.trim() ?? '';
    if (!activeJobStatuses.contains(status)) {
      return false;
    }

    if (isVan2CustomerOrder(data)) {
      return isEligibleVan2CustomerOrder(data);
    }

    return true;
  }

  static bool isDeliveredHistoryOrder(Map<String, dynamic> data) {
    return (data['status'] as String?)?.trim() == 'delivered';
  }

  static bool _isLegacyPendingOrder(Map<String, dynamic> data) {
    final status = (data['status'] as String?)?.trim() ?? '';
    return pendingStatuses.contains(status);
  }
}
