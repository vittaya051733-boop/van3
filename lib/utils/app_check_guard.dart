import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import '../l10n/l10n.dart';

/// Ensures App Check token is available before protected callables.
class AppCheckGuard {
  const AppCheckGuard._();

  static const String debugTokenHint =
      '7e1d581a-5018-46b9-ae4f-66967a8fe773';

  static Future<void> ensureCallableReady() async {
    await _ensureToken(
      releaseMessage: L10n.appCheckDeviceSecurityFailed,
      // Do not hard-crash debug builds — show error in wallet UI instead.
      requiredInDebug: false,
    );
  }

  static Future<void> _ensureToken({
    required String releaseMessage,
    bool requiredInDebug = false,
  }) async {
    Object? lastError;
    for (final forceRefresh in [false, true]) {
      try {
        await FirebaseAppCheck.instance
            .getToken(forceRefresh)
            .timeout(const Duration(seconds: 8));
        return;
      } catch (error) {
        lastError = error;
      }
    }

    if (kReleaseMode || requiredInDebug) {
      if (kDebugMode && requiredInDebug) {
        throw Exception(L10n.appCheckDebugNotReady(debugTokenHint));
      }
      throw Exception(releaseMessage);
    }
    if (kDebugMode && lastError != null) {
      debugPrint('App Check token unavailable (debug): $lastError');
    }
  }
}
