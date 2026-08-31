import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecurityPinService {
  SecurityPinService._();

  static final SecurityPinService instance = SecurityPinService._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _pinHashPrefix = 'security_pin_hash';
  static const _biometricUnlockKey = 'app_unlock_biometric_enabled';

  String _hashPin(String pin, String uid) {
    final bytes = utf8.encode('$uid::$pin::van_security_v1');
    return sha256.convert(bytes).toString();
  }

  bool isValidPinFormat(String pin) => RegExp(r'^\d{6}$').hasMatch(pin);

  Future<bool> hasPin(String uid) async {
    try {
      final hash = await _storage.read(key: '$_pinHashPrefix:$uid');
      return hash != null && hash.isNotEmpty;
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('SecurityPinService.hasPin failed: $error\n$stack');
      }
      return false;
    }
  }

  Future<void> setPin(String uid, String pin) async {
    if (!isValidPinFormat(pin)) {
      throw ArgumentError('PIN must be 6 digits');
    }
    await _storage.write(
      key: '$_pinHashPrefix:$uid',
      value: _hashPin(pin, uid),
    );
  }

  Future<bool> verifyPin(String uid, String pin) async {
    if (!isValidPinFormat(pin)) {
      return false;
    }
    try {
      final stored = await _storage.read(key: '$_pinHashPrefix:$uid');
      if (stored == null || stored.isEmpty) {
        return false;
      }
      return stored == _hashPin(pin, uid);
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('SecurityPinService.verifyPin failed: $error\n$stack');
      }
      return false;
    }
  }

  Future<bool> isBiometricUnlockEnabled() async {
    try {
      return (await _storage.read(key: _biometricUnlockKey)) == 'true';
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint(
          'SecurityPinService.isBiometricUnlockEnabled failed: $error\n$stack',
        );
      }
      return false;
    }
  }

  Future<void> setBiometricUnlockEnabled(bool enabled) async {
    await _storage.write(
      key: _biometricUnlockKey,
      value: enabled ? 'true' : 'false',
    );
  }
}
