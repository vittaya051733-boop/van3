import 'package:cloud_firestore/cloud_firestore.dart';

import 'order_pay_at_destination.dart';

class SettlementPayoutInfo {
  const SettlementPayoutInfo({
    required this.amount,
    required this.status,
    required this.displayStatus,
  });

  final double amount;
  final String status;
  final String displayStatus;
}

String formatSettlementPayoutDisplayStatus(String? rawStatus) {
  final status = rawStatus?.trim().toLowerCase() ?? '';
  switch (status) {
    case 'paid':
      return 'จ่ายแล้ว';
    case 'failed':
      return 'โอนไม่สำเร็จ';
    case 'pending':
    case 'exported':
    case '':
      return 'รอชำระ';
    default:
      return 'รอชำระ';
  }
}

bool isSettlementPayoutPaid(String? rawStatus) {
  return rawStatus?.trim().toLowerCase() == 'paid';
}

SettlementPayoutInfo? readRiderPayoutInfo(Map<String, dynamic> orderData) {
  final settlement = _readMap(orderData['settlement']);
  final payout = _readMap(settlement?['riderPayout']);
  final status = payout?['status']?.toString() ?? 'pending';
  final amount = _readDouble(payout?['amount']) ??
      readRiderNetShippingIncome(orderData) ??
      0;
  if (amount <= 0) {
    return null;
  }
  return SettlementPayoutInfo(
    amount: amount,
    status: status,
    displayStatus: formatSettlementPayoutDisplayStatus(status),
  );
}

SettlementPayoutInfo? readShopPayoutInfo(Map<String, dynamic> orderData) {
  final settlement = _readMap(orderData['settlement']);
  final payout = _readMap(settlement?['shopPayout']);
  final status = payout?['status']?.toString() ?? 'pending';
  final amount = _readDouble(payout?['amount']) ?? _estimateShopNetAmount(orderData);
  if (amount <= 0) {
    return null;
  }
  return SettlementPayoutInfo(
    amount: amount,
    status: status,
    displayStatus: formatSettlementPayoutDisplayStatus(status),
  );
}

double resolveRiderPayoutAmount(Map<String, dynamic> orderData) {
  return readRiderNetShippingIncome(orderData) ?? 0;
}

double resolveShopPayoutAmount(Map<String, dynamic> orderData) {
  final existing = readShopPayoutInfo(orderData);
  if (existing != null && existing.amount > 0) {
    return existing.amount;
  }
  return _estimateShopNetAmount(orderData);
}

Map<String, dynamic> buildPendingSettlementPatch({
  required Map<String, dynamic> orderData,
  required double riderNetAmount,
  required double shopNetAmount,
  required Timestamp now,
}) {
  return <String, dynamic>{
    'settlement': <String, dynamic>{
      'riderPayout': <String, dynamic>{
        'status': 'pending',
        'amount': double.parse(riderNetAmount.toStringAsFixed(2)),
        'updatedAt': now,
      },
      if (shopNetAmount > 0)
        'shopPayout': <String, dynamic>{
          'status': 'pending',
          'amount': double.parse(shopNetAmount.toStringAsFixed(2)),
          'updatedAt': now,
        },
    },
  };
}

Future<void> enqueuePayoutPendingNotifications({
  required String orderId,
  required Map<String, dynamic> orderData,
  required double riderNetAmount,
  required double shopNetAmount,
}) async {
  final orderCode = (orderData['orderCode'] as String?)?.trim();
  final orderLabel = orderCode?.isNotEmpty == true
      ? '#$orderCode'
      : '#${orderId.substring(0, orderId.length.clamp(0, 8))}';
  final shopOwnerId = _readRecipientUid(
    orderData['shopOwnerId'] ?? orderData['merchantId'] ?? orderData['shopId'],
  );
  final riderId = _readRecipientUid(
    orderData['driverId'] ?? orderData['riderId'],
  );
  final notifications = FirebaseFirestore.instance.collection('app_notifications');
  final now = FieldValue.serverTimestamp();

  if (shopOwnerId != null && shopNetAmount > 0) {
    await notifications.add(<String, dynamic>{
      'targetApp': 'van1',
      'recipientUid': shopOwnerId,
      'orderId': orderId,
      'title': 'มียอดเงินเข้า',
      'body':
          'ออเดอร์ $orderLabel ${shopNetAmount.toStringAsFixed(2)} บาท • รอชำระ',
      'action': 'payout_pending',
      'read': false,
      'isRead': false,
      'createdAt': now,
    });
  }

  if (riderId != null && riderNetAmount > 0) {
    await notifications.add(<String, dynamic>{
      'targetApp': 'van3',
      'recipientUid': riderId,
      'orderId': orderId,
      'title': 'มียอดเงินเข้า',
      'body':
          'ออเดอร์ $orderLabel ${riderNetAmount.toStringAsFixed(2)} บาท • รอชำระ',
      'action': 'payout_pending',
      'read': false,
      'isRead': false,
      'createdAt': now,
    });
  }
}

Future<void> enqueuePayoutPaidNotifications({
  required String orderId,
  required Map<String, dynamic> orderData,
  required String payoutType,
  required double amount,
}) async {
  if (amount <= 0) {
    return;
  }

  final orderCode = (orderData['orderCode'] as String?)?.trim();
  final orderLabel = orderCode?.isNotEmpty == true
      ? '#$orderCode'
      : '#${orderId.substring(0, orderId.length.clamp(0, 8))}';
  final notifications = FirebaseFirestore.instance.collection('app_notifications');
  final now = FieldValue.serverTimestamp();
  final body =
      'ออเดอร์ $orderLabel ${amount.toStringAsFixed(2)} บาท • จ่ายแล้ว';

  if (payoutType == 'shop') {
    final shopOwnerId = _readRecipientUid(
      orderData['shopOwnerId'] ?? orderData['merchantId'] ?? orderData['shopId'],
    );
    if (shopOwnerId == null) {
      return;
    }
    await notifications.add(<String, dynamic>{
      'targetApp': 'van1',
      'recipientUid': shopOwnerId,
      'orderId': orderId,
      'title': 'โอนเงินสำเร็จ',
      'body': body,
      'action': 'payout_paid',
      'read': false,
      'isRead': false,
      'createdAt': now,
    });
    return;
  }

  if (payoutType == 'rider') {
    final riderId = _readRecipientUid(
      orderData['driverId'] ?? orderData['riderId'],
    );
    if (riderId == null) {
      return;
    }
    await notifications.add(<String, dynamic>{
      'targetApp': 'van3',
      'recipientUid': riderId,
      'orderId': orderId,
      'title': 'โอนเงินสำเร็จ',
      'body': body,
      'action': 'payout_paid',
      'read': false,
      'isRead': false,
      'createdAt': now,
    });
  }
}

double _estimateShopNetAmount(Map<String, dynamic> orderData) {
  final merchantSubtotal = _readDouble(orderData['merchantSubtotal']);
  if (merchantSubtotal != null && merchantSubtotal > 0) {
    return merchantSubtotal;
  }

  final subtotal = _readDouble(orderData['subtotal']) ?? 0;
  if (subtotal > 0) {
    return subtotal;
  }

  final grandTotal = _readDouble(orderData['grandTotal']) ?? 0;
  final shipping = _readDouble(orderData['shippingFee']) ??
      _readDouble(orderData['deliveryFee']) ??
      0;
  final fallback = grandTotal - shipping;
  return fallback > 0 ? fallback : grandTotal;
}

String? _readRecipientUid(Object? value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  return text;
}

Map<String, dynamic>? _readMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return null;
}

double? _readDouble(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}
