class PromptPayQrPayload {
  PromptPayQrPayload._();

  /// Builds a Thai QR Payment payload from a PromptPay phone (9–10 digits)
  /// or national/tax ID (13 digits).
  static String? build({
    required String promptPayId,
    required double amount,
  }) {
    final digits = _digitsOnly(promptPayId);
    if (digits.length == 13) {
      return fromNationalIdOrTaxId(nationalIdOrTaxId: digits, amount: amount);
    }
    if (digits.length >= 9 && digits.length <= 10) {
      return fromPhoneNumber(phoneNumber: digits, amount: amount);
    }
    return null;
  }

  static String fromPhoneNumber({
    required String phoneNumber,
    required double amount,
  }) {
    final normalizedDigits = _digitsOnly(phoneNumber);
    if (normalizedDigits.length < 9 || normalizedDigits.length > 10) {
      throw ArgumentError('PromptPay phone number must have 9-10 digits.');
    }

    final local = normalizedDigits.startsWith('0')
        ? normalizedDigits.substring(1)
        : normalizedDigits;
    final proxyValue = '0066$local';
    return _buildPayload(proxyType: '01', proxyValue: proxyValue, amount: amount);
  }

  static String fromNationalIdOrTaxId({
    required String nationalIdOrTaxId,
    required double amount,
  }) {
    final digits = _digitsOnly(nationalIdOrTaxId);
    if (digits.length != 13) {
      throw ArgumentError('PromptPay national ID or tax ID must have 13 digits.');
    }

    return _buildPayload(proxyType: '02', proxyValue: digits, amount: amount);
  }

  static String _buildPayload({
    required String proxyType,
    required String proxyValue,
    required double amount,
  }) {
    final normalizedAmount = amount <= 0 ? '' : amount.toStringAsFixed(2);
    final merchantAccountInfo = _field(
      '29',
      _field('00', 'A000000677010111') + _field(proxyType, proxyValue),
    );

    final payloadWithoutCrc = <String>[
      _field('00', '01'),
      _field('01', normalizedAmount.isEmpty ? '11' : '12'),
      merchantAccountInfo,
      _field('52', '0000'),
      _field('53', '764'),
      if (normalizedAmount.isNotEmpty) _field('54', normalizedAmount),
      _field('58', 'TH'),
      _field('59', 'VAN MARKET'),
      _field('60', 'BANGKOK'),
      '6304',
    ].join();

    final crc = _crc16CcittFalse(payloadWithoutCrc);
    return '$payloadWithoutCrc$crc';
  }

  static String _field(String id, String value) {
    final length = value.length.toString().padLeft(2, '0');
    return '$id$length$value';
  }

  static String _digitsOnly(String input) {
    return input.replaceAll(RegExp(r'\D'), '');
  }

  /// Last 4 digits for on-screen display (never show full national ID).
  static String maskedLastFour(String promptPayId) {
    final digits = _digitsOnly(promptPayId);
    if (digits.length >= 4) {
      return digits.substring(digits.length - 4);
    }
    return '';
  }

  static String maskedDisplayLabel(String promptPayId) {
    final suffix = maskedLastFour(promptPayId);
    if (suffix.isEmpty) {
      return 'PromptPay';
    }
    return 'PromptPay ••••$suffix';
  }

  static String _crc16CcittFalse(String value) {
    var crc = 0xFFFF;
    for (final codeUnit in value.codeUnits) {
      crc ^= codeUnit << 8;
      for (var bit = 0; bit < 8; bit += 1) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }
}
