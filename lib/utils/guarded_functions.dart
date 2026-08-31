import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

import '../l10n/l10n.dart';
import 'app_check_guard.dart';

/// Callable wrapper that refreshes App Check before each protected request.
class GuardedFunctions {
  GuardedFunctions._();

  static const Duration callableTimeout = Duration(seconds: 30);

  static FirebaseFunctions get _region =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  static Future<HttpsCallableResult<dynamic>> call(
    String name, {
    Map<String, dynamic>? parameters,
  }) async {
    await AppCheckGuard.ensureCallableReady();
    try {
      return await _region
          .httpsCallable(name)
          .call(parameters ?? <String, dynamic>{})
          .timeout(callableTimeout);
    } on TimeoutException {
      throw Exception(L10n.serverSlowRetryColdStart);
    }
  }
}
