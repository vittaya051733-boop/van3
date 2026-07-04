import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Checks Android permissions needed for full-screen incoming order alerts.
class RiderAlertPermissions {
  RiderAlertPermissions._();

  static const MethodChannel _channel = MethodChannel('van.rider/app_state');

  static Future<bool> canUseFullScreenIntent() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }
    try {
      final result =
          await _channel.invokeMethod<bool>('can_use_full_screen_intent');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<bool> canDrawOverlays() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }
    try {
      final result = await _channel.invokeMethod<bool>('can_draw_overlays');
      return result ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> openFullScreenIntentSettings() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('open_full_screen_intent_settings');
    } catch (_) {}
  }

  static Future<void> openOverlaySettings() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('open_overlay_settings');
    } catch (_) {}
  }

  static Future<void> dismissNativeOrderOverlay() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('dismiss_order_alert_overlay');
    } catch (_) {}
  }

  static Future<RiderAlertPermissionStatus> checkAll() async {
    final fullScreen = await canUseFullScreenIntent();
    final overlay = await canDrawOverlays();
    return RiderAlertPermissionStatus(
      fullScreenIntentGranted: fullScreen,
      overlayGranted: overlay,
    );
  }
}

class RiderAlertPermissionStatus {
  const RiderAlertPermissionStatus({
    required this.fullScreenIntentGranted,
    required this.overlayGranted,
  });

  final bool fullScreenIntentGranted;
  final bool overlayGranted;

  bool get isFullyReady =>
      fullScreenIntentGranted && overlayGranted;

  bool get needsFullScreenIntent => !fullScreenIntentGranted;

  bool get needsOverlay => !overlayGranted;
}
