import 'package:cloud_firestore/cloud_firestore.dart';

bool isPayAtDestinationOrder(Map<String, dynamic> orderData) {
  String? readString(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  Map<String, dynamic>? readMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
    }
    return null;
  }

  String? normalizeKey(String? value) => value?.trim().toLowerCase();

  if (orderData['payAtDestination'] == true ||
      orderData['paymentAtDestination'] == true ||
      orderData['isCod'] == true ||
      orderData['cashOnDelivery'] == true) {
    return true;
  }

  final paymentStatus =
      readString(orderData['paymentStatus'])?.toLowerCase();
  if (paymentStatus == 'cash_on_delivery') {
    return true;
  }

  final paymentMap = readMap(orderData['payment']);
  final candidates = <String?>[
    readString(orderData['paymentMethod']),
    readString(orderData['payMethod']),
    readString(orderData['paymentType']),
    readString(orderData['paymentChannel']),
    paymentMap == null ? null : readString(paymentMap['method']),
    paymentMap == null ? null : readString(paymentMap['paymentMethod']),
    paymentMap == null ? null : readString(paymentMap['type']),
    paymentMap == null ? null : readString(paymentMap['channel']),
  ].whereType<String>().toList(growable: false);

  String? key;
  for (final value in candidates) {
    final normalized = normalizeKey(value);
    if (normalized != null && normalized.isNotEmpty) {
      key = normalized;
      break;
    }
  }

  if (key == null) {
    return false;
  }

  return key.contains('cash_on_delivery') ||
      key.contains('cod') ||
      key.contains('pay_at_destination') ||
      key.contains('destination');
}

double? _readDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

double resolveOrderShippingFee(
  Map<String, dynamic> orderData, {
  double? fallbackGrossShippingFee,
}) {
  if (fallbackGrossShippingFee != null && fallbackGrossShippingFee > 0) {
    return fallbackGrossShippingFee;
  }

  return _readDouble(orderData['shippingFee']) ??
      _readDouble(orderData['deliveryFee']) ??
      _readDouble(orderData['deliveryCharge']) ??
      _readDouble(orderData['shipping']) ??
      0.0;
}

double computeRiderNetShippingIncome(double grossShippingFee) {
  if (grossShippingFee <= 0) {
    return 0;
  }
  return double.parse((grossShippingFee * 0.85).toStringAsFixed(1));
}

double resolvePayAtDestinationHoldAmount(Map<String, dynamic> orderData) {
  final shippingFee = resolveOrderShippingFee(orderData);

  final productsSubtotal =
      _readDouble(orderData['subtotal']) ?? _readDouble(orderData['totalPrice']);

  final grandTotal = _readDouble(orderData['grandTotal']);
  if (grandTotal != null && grandTotal > 0) {
    return grandTotal;
  }

  final total = _readDouble(orderData['total']) ?? _readDouble(orderData['totalAmount']);
  if (total != null && total > 0) {
    if (productsSubtotal != null && productsSubtotal > 0 && shippingFee > 0) {
      const epsilon = 0.01;
      final expected = productsSubtotal + shippingFee;
      if ((total - expected).abs() < epsilon) {
        return total;
      }
      if ((total - productsSubtotal).abs() < epsilon) {
        return total + shippingFee;
      }
    }
    return total;
  }

  if (productsSubtotal != null && productsSubtotal > 0) {
    return productsSubtotal + (shippingFee > 0 ? shippingFee : 0.0);
  }

  return 0.0;
}

/// ยอดคืนเครดิตเดิม (เลิกใช้แล้ว) — ค่าส่งจ่ายผ่าน settlement โอนภายหลัง
@Deprecated('Shipping payout uses settlement.riderPayout, not credit release.')
double resolvePayAtDestinationCreditReleaseAmount(
  Map<String, dynamic> orderData, {
  double? grossShippingFee,
}) {
  final gross = resolveOrderShippingFee(
    orderData,
    fallbackGrossShippingFee: grossShippingFee,
  );
  return computeRiderNetShippingIncome(gross);
}

Map<String, dynamic> buildDeliveryFinancialSnapshot({
  required Map<String, dynamic> orderData,
  required double grossShippingFee,
  required Timestamp completedAt,
  required String completedSource,
}) {
  final safeGross = double.parse(
    resolveOrderShippingFee(
      orderData,
      fallbackGrossShippingFee: grossShippingFee,
    ).toStringAsFixed(1),
  );
  final platformFee = double.parse((safeGross * 0.15).toStringAsFixed(1));
  final riderNetIncome = double.parse((safeGross - platformFee).toStringAsFixed(1));

  if (isPayAtDestinationOrder(orderData)) {
    final collectedAmount = double.parse(
      resolvePayAtDestinationHoldAmount(orderData).toStringAsFixed(1),
    );

    return <String, dynamic>{
      'deliverySettlementType': 'pay_at_destination',
      'deliveryGrossShippingFee': safeGross,
      'deliveryPlatformFee': platformFee,
      'deliveryRiderNetIncome': riderNetIncome,
      'deliveryCollectedAmount': collectedAmount,
      'deliveryCreditReleaseAmount': 0,
      'deliveryCompletedSource': completedSource,
      'deliveryFinancials': <String, dynamic>{
        'settlementType': 'pay_at_destination',
        'grossShippingFee': safeGross,
        'platformFee': platformFee,
        'riderNetIncome': riderNetIncome,
        'collectedAmount': collectedAmount,
        'creditReleaseAmount': 0,
        'deductionRate': 0.15,
        'currency': 'THB',
        'completedAt': completedAt,
        'completedSource': completedSource,
      },
    };
  }

  return <String, dynamic>{
    'deliverySettlementType': 'shipping_fee',
    'deliveryGrossShippingFee': safeGross,
    'deliveryPlatformFee': platformFee,
    'deliveryRiderNetIncome': riderNetIncome,
    'deliveryCompletedSource': completedSource,
    'deliveryFinancials': <String, dynamic>{
      'settlementType': 'shipping_fee',
      'grossShippingFee': safeGross,
      'platformFee': platformFee,
      'riderNetIncome': riderNetIncome,
      'deductionRate': 0.15,
      'currency': 'THB',
      'completedAt': completedAt,
      'completedSource': completedSource,
    },
  };
}

/// เดิมคืนเครดิตค่าส่งสุทธิเมื่อส่งสำเร็จ — เลิกใช้แล้ว (จ่ายผ่าน settlement โอนภายหลัง)
void releasePayAtDestinationHold({
  required Transaction transaction,
  required String orderId,
  required String riderUid,
  required double releaseAmount,
  required String completedSource,
}) {
  // No-op: rider keeps cash from customer; net shipping is paid via settlement.
}

Map<String, dynamic>? _readMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries) entry.key.toString(): entry.value,
    };
  }
  return null;
}

double? readRiderNetShippingIncome(Map<String, dynamic> data) {
  final financials = _readMap(data['deliveryFinancials']);

  final persisted =
      _readDouble(data['deliveryRiderNetIncome']) ??
      _readDouble(financials?['riderNetIncome']);
  if (persisted != null) {
    return persisted > 0 ? persisted : 0;
  }

  final shippingFee = resolveOrderShippingFee(data);
  if (shippingFee <= 0) {
    return 0;
  }
  return computeRiderNetShippingIncome(shippingFee);
}
