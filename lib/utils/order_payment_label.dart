String? resolveOrderPaymentLabel(Map<String, dynamic> orderData) {
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

  final explicit =
      readString(orderData['paymentMethodLabel']) ??
      readString(orderData['paymentLabel']) ??
      readString(orderData['paymentMethodText']) ??
      readString(orderData['paymentDisplay']) ??
      readString(orderData['paymentDisplayName']);
  if (explicit != null) {
    return explicit;
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

  final isCod = orderData['isCod'] == true || orderData['cashOnDelivery'] == true;
  if (key == null && isCod) {
    return 'จ่ายปลายทาง';
  }

  final destinationPayment = readString(orderData['destinationPaymentMethod']) ??
      readString(orderData['payAtDestinationMethod']);
  final destinationKey = normalizeKey(destinationPayment);

  bool isPayAtDestination(String? value) {
    if (value == null) return false;
    return value.contains('cash_on_delivery') ||
        value.contains('cod') ||
        value.contains('pay_at_destination') ||
        value.contains('destination');
  }

  bool isQrPayment(String? value) {
    if (value == null) return false;
    return value.contains('promptpay') ||
        value.contains('qr') ||
        value.contains('scan') ||
        value.contains('qrcode') ||
        value.contains('true_money') ||
        value.contains('truemoney');
  }

  bool isTransfer(String? value) {
    if (value == null) return false;
    return value.contains('transfer') ||
        value.contains('bank') ||
        value.contains('promptpay');
  }

  final hasDestinationFlag = orderData['payAtDestination'] == true ||
      orderData['paymentAtDestination'] == true;

  if (hasDestinationFlag && destinationKey != null && isTransfer(destinationKey)) {
    return 'โอนปลายทาง';
  }

  if (key != null) {
    if (isPayAtDestination(key)) {
      if (destinationKey != null && isTransfer(destinationKey)) {
        return 'โอนปลายทาง';
      }
      return 'จ่ายปลายทาง';
    }

    if (isQrPayment(key)) {
      return 'สแกนจ่าย';
    }

    if (key.contains('cash')) {
      return 'เงินสด';
    }

    if (key.contains('transfer')) {
      return 'โอนเงิน';
    }
  }

  final statusLabel = readString(orderData['paymentStatusLabel']);
  if (statusLabel != null) {
    return statusLabel;
  }

  return null;
}
