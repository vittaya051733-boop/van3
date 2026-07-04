import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as overlay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
  as fln;
import 'package:permission_handler/permission_handler.dart';

import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'incoming_order_screen.dart';
import 'utils/rider_incoming_order_filter.dart';
import 'login_screen.dart';
import 'privacy_launch_gate.dart';
import 'rider_onboarding_gate.dart';
import 'rider_registration_screen.dart';
import 'rider_jobs_screen.dart';
import 'notifications_screen.dart';
import 'services/fcm_token_sync_service.dart';
import 'services/notification_service.dart';
import 'services/observability_service.dart';
import 'services/privacy_consent_service.dart';
import 'services/rider_alert_permissions.dart';
import 'services/rider_orders_service.dart';
import 'welcome_screen.dart';
import 'utils/app_colors.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final type = message.data['type']?.toString();
  if (type == 'call' || type == 'call_cancel' || type == 'chat') {
    return;
  }
  final action = message.data['action']?.toString().trim();
  if (action == 'admin_announcement') {
    // แถบแจ้งเตือนระบบมาจาก FCM notification payload (pushAppNotification)
    return;
  }
  if (!await OverlayAlertService.shouldDisplayMessage(message)) {
    return;
  }
  await OverlayAlertService.showOverlayFromMessage(message);
}

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SizedBox.shrink(),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } on FirebaseException catch (e) {
    if (e.code != 'duplicate-app') {
      rethrow;
    }
  }

  try {
    await FirebaseAppCheck.instance
        .activate(
          providerAndroid: kReleaseMode
              ? const AndroidPlayIntegrityProvider()
              : const AndroidDebugProvider(),
          providerApple: kReleaseMode
              ? const AppleDeviceCheckProvider()
              : const AppleDebugProvider(),
        )
        .timeout(const Duration(seconds: 5));
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  } catch (e) {
    if (kDebugMode) {
      debugPrint('App Check activate failed: $e');
    }
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  try {
    await ObservabilityService.instance.initialize(appName: 'van3_rider');
  } catch (_) {}
  await NotificationService().initialize();
  await OverlayAlertService.initialize();
  await FcmTokenSyncService.instance.initialize();
  RiderOrdersService.instance.initialize();
  await GlobalOrderAlertService.instance.initialize();
  runApp(const Van3RiderApp());
}

class OverlayAlertService {
  static bool _isInitialized = false;
  static bool _isShowingInAppOrderAlert = false;
  static final Set<String> _shownOrderAlertKeys = <String>{};
  static final fln.FlutterLocalNotificationsPlugin _localNotifications =
      fln.FlutterLocalNotificationsPlugin();
  static const fln.AndroidNotificationChannel _urgentChannel =
      fln.AndroidNotificationChannel(
        'rider_jobs_urgent_sound',
        'Rider Jobs Urgent',
        description: 'Urgent rider job alerts with sound',
        importance: fln.Importance.max,
      );
  static const fln.AndroidNotificationChannel _announcementChannel =
      fln.AndroidNotificationChannel(
        'rider_announcements',
        'ประกาศจากแอดมิน',
        description: 'ประกาศและแจ้งเตือนทั่วไปจากแพลตฟอร์ม',
        importance: fln.Importance.high,
      );

  static Future<void> initialize() async {
    if (_isInitialized) return;

    await _initializeLocalNotifications();
    await _requestNotificationPermission();
    await _requestOverlayPermission();
    _listenForegroundMessages();
    await _handleInitialMessage();

    _isInitialized = true;
  }

  static Future<void> _requestNotificationPermission() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: true,
      provisional: false,
    );
    await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }

  static Future<void> _initializeLocalNotifications() async {
    const settings = fln.InitializationSettings(
      android: fln.AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: fln.DarwinInitializationSettings(),
    );
    await _localNotifications.initialize(settings);

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_urgentChannel);
    await androidPlugin?.createNotificationChannel(_announcementChannel);
  }

  static Future<void> _requestOverlayPermission() async {
    final isGranted = await overlay.FlutterOverlayWindow.isPermissionGranted();
    if (!isGranted) {
      await overlay.FlutterOverlayWindow.requestPermission();
    }
  }

  static void _listenForegroundMessages() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      final type = message.data['type']?.toString();
      if (type == 'call' || type == 'call_cancel' || type == 'chat') {
        return;
      }
      if (_isConfirmedVan2OrderMessage(message.data)) {
        await GlobalOrderAlertService.instance.handleRemoteOrderAlert(message.data);
        return;
      }
      if (!await shouldDisplayMessage(message)) {
        return;
      }
      final action = message.data['action']?.toString().trim();
      if (action == 'admin_announcement') {
        await _showAnnouncementAlert(message);
        return;
      }
      await showOverlayFromMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      final type = message.data['type']?.toString();
      if (type == 'call' || type == 'call_cancel' || type == 'chat') {
        return;
      }
      if (_isConfirmedVan2OrderMessage(message.data)) {
        await GlobalOrderAlertService.instance.handleRemoteOrderAlert(message.data);
        return;
      }
      if (!await shouldDisplayMessage(message)) {
        return;
      }
      final action = message.data['action']?.toString().trim();
      if (action == 'admin_announcement') {
        await _openNotificationsFromTap();
        return;
      }
      await showOverlayFromMessage(message);
    });
  }

  static Future<void> _handleInitialMessage() async {
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      final type = initialMessage.data['type']?.toString();
      if (type == 'call' || type == 'call_cancel' || type == 'chat') {
        return;
      }
      if (_isConfirmedVan2OrderMessage(initialMessage.data)) {
        await GlobalOrderAlertService.instance.handleRemoteOrderAlert(initialMessage.data);
        return;
      }
      if (!await shouldDisplayMessage(initialMessage)) {
        return;
      }
      final action = initialMessage.data['action']?.toString().trim();
      if (action == 'admin_announcement') {
        await _openNotificationsFromTap();
        return;
      }
      await showOverlayFromMessage(initialMessage);
    }
  }

  static Future<void> _showAnnouncementAlert(RemoteMessage message) async {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'ประกาศจากแอดมิน';
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        '';

    await _showAnnouncementLocalNotification(title: title, body: body);

    final navigatorState = Van3RiderApp.navigatorKey.currentState;
    final context =
        navigatorState?.overlay?.context ?? Van3RiderApp.navigatorKey.currentContext;
    if (navigatorState == null || context == null) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(body.isNotEmpty ? body : title),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('ปิด'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              unawaited(_openNotificationsFromTap());
            },
            child: const Text('ดูทั้งหมด'),
          ),
        ],
      ),
    );
  }

  static Future<void> _showAnnouncementLocalNotification({
    required String title,
    required String body,
  }) async {
    try {
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _localNotifications.show(
        id,
        title,
        body.isNotEmpty ? body : title,
        fln.NotificationDetails(
          android: fln.AndroidNotificationDetails(
            _announcementChannel.id,
            _announcementChannel.name,
            channelDescription: _announcementChannel.description,
            importance: fln.Importance.high,
            priority: fln.Priority.high,
            playSound: true,
            enableVibration: true,
          ),
          iOS: const fln.DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: 'admin_announcement',
      );
    } catch (_) {
      // Ignore local notification failures in foreground edge cases.
    }
  }

  static Future<void> _openNotificationsFromTap({int retryCount = 30}) async {
    final navigatorState = Van3RiderApp.navigatorKey.currentState;
    if (navigatorState == null) {
      if (retryCount <= 0) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await _openNotificationsFromTap(retryCount: retryCount - 1);
      return;
    }

    await navigatorState.push(
      MaterialPageRoute<void>(
        builder: (_) => const RiderNotificationsScreen(),
      ),
    );
  }

  static Future<bool> shouldDisplayMessage(RemoteMessage message) async {
    final type = message.data['type']?.toString();
    if (type == 'call' || type == 'call_cancel' || type == 'chat') {
      return false;
    }

    if (_isConfirmedVan2OrderMessage(message.data)) {
      // Confirmed van2 order alerts are handled by the global order listener
      // in-app and by the native Android FCM service when the app is off-screen.
      return false;
    }

    final payloadSourceApp = message.data['sourceApp']?.toString().trim();
    if (payloadSourceApp == 'van2_customer') {
      final payloadConfirmed = _asBool(message.data['customerConfirmed']);
      final riderNotifyReady = _asBool(message.data['riderNotifyReady']);
      if (payloadConfirmed != true || riderNotifyReady != true) {
        return false;
      }
    }

    final orderId = _extractOrderId(message.data);
    if (type == 'app_notification' && (orderId == null || orderId.isEmpty)) {
      final action = message.data['action']?.toString().trim();
      if (action == 'admin_announcement') {
        return true;
      }
      return false;
    }
    if (orderId == null || orderId.isEmpty) {
      return true;
    }

    try {
      final orderSnapshot =
          await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
      final order = orderSnapshot.data();
      if (order == null) {
        return true;
      }

      final sourceApp = (order['sourceApp'] as String?)?.trim();
      if (sourceApp == 'van2_customer') {
        return order['customerConfirmed'] == true && order['riderNotifyReady'] == true;
      }
    } catch (_) {
      // Do not suppress legitimate alerts when lookup fails.
      return true;
    }

    return true;
  }

  static bool _isConfirmedVan2OrderMessage(Map<String, dynamic> data) {
    final type = data['type']?.toString().trim();
    final sourceApp = data['sourceApp']?.toString().trim();
    final orderId = _extractOrderId(data);
    final customerConfirmed = _asBool(data['customerConfirmed']);
    final riderNotifyReady = _asBool(data['riderNotifyReady']);
    return type == 'app_notification' &&
        sourceApp == 'van2_customer' &&
        orderId != null &&
        orderId.isNotEmpty &&
        customerConfirmed == true &&
        riderNotifyReady == true;
  }

  static String? _extractOrderId(Map<String, dynamic> data) {
    final candidates = <String?>[
      data['orderId']?.toString(),
      data['jobId']?.toString(),
      data['order_id']?.toString(),
      data['job_id']?.toString(),
    ];

    for (final candidate in candidates) {
      final text = candidate?.trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  static bool? _asBool(Object? value) {
    if (value is bool) {
      return value;
    }
    final text = value?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1') {
      return true;
    }
    if (text == 'false' || text == '0') {
      return false;
    }
    return null;
  }

  static Future<void> showOverlayFromMessage(RemoteMessage message) async {
    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        'มีงานใหม่';
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        'มีคำขอเรียกรถใหม่ กรุณาตรวจสอบทันที';
    final orderId = _extractOrderId(message.data);

    if (_shouldShowInAppDialog(message.data)) {
      await _showInAppOrderAlert(
        title: title,
        body: body,
        orderId: orderId,
      );
    }

    await _showUrgentLocalNotification(title: title, body: body, data: message.data);

    try {
      final hasPermission = await overlay.FlutterOverlayWindow.isPermissionGranted();
      if (!hasPermission) {
        await overlay.FlutterOverlayWindow.requestPermission();
      }

      await overlay.FlutterOverlayWindow.showOverlay(
        height: 260,
        width: overlay.WindowSize.matchParent,
        alignment: overlay.OverlayAlignment.center,
        flag: overlay.OverlayFlag.defaultFlag,
        visibility: overlay.NotificationVisibility.visibilityPublic,
        overlayTitle: title,
        overlayContent: body,
        enableDrag: true,
      );
    } catch (_) {
      // Avoid crashing app in background isolate when overlay cannot be shown.
    }
  }

  static bool _shouldShowInAppDialog(Map<String, dynamic> data) {
    final type = data['type']?.toString();
    if (type == 'call' || type == 'call_cancel') {
      return false;
    }
    final navigatorState = Van3RiderApp.navigatorKey.currentState;
    return navigatorState != null;
  }

  static Future<void> _showInAppOrderAlert({
    required String title,
    required String body,
    String? orderId,
  }) async {
    final navigatorState = Van3RiderApp.navigatorKey.currentState;
    final context = navigatorState?.overlay?.context ?? Van3RiderApp.navigatorKey.currentContext;
    if (navigatorState == null || context == null) {
      return;
    }

    final alertKey = (orderId != null && orderId.trim().isNotEmpty)
        ? orderId.trim()
        : '$title|$body';
    if (_isShowingInAppOrderAlert || !_shownOrderAlertKeys.add(alertKey)) {
      return;
    }

    _isShowingInAppOrderAlert = true;
    try {
      final action = await showGeneralDialog<String>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'incoming-order-alert',
        barrierColor: Colors.black.withValues(alpha: 0.62),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (dialogContext, animation, secondaryAnimation) {
          return SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    width: 420,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const <BoxShadow>[
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 28,
                          offset: Offset(0, 16),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(
                                color: Color(0xFFFFF3E8),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.local_shipping_rounded,
                                color: AppColors.accent,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    orderId?.isNotEmpty == true
                                        ? 'Order ID: $orderId'
                                        : 'มีออเดอร์ใหม่เข้ามาแล้ว',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF6B7280),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          body,
                          style: const TextStyle(
                            fontSize: 15,
                            height: 1.45,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const SizedBox(height: 18),
                        const Text(
                          'ออเดอร์นี้ถูกยืนยันแล้ว คุณสามารถเปิดหน้ารับงานได้ทันที',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF9A3412),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(dialogContext).pop('dismiss'),
                                child: const Text('ปิดก่อน'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => Navigator.of(dialogContext).pop('open_jobs'),
                                icon: const Icon(Icons.assignment_turned_in_rounded),
                                label: const Text('เปิดหน้ารับงาน'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
        transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      );

      if (action == 'open_jobs' && navigatorState.mounted) {
        await navigatorState.push(
          MaterialPageRoute<void>(builder: (_) => const RiderJobsScreen()),
        );
      }
    } finally {
      _isShowingInAppOrderAlert = false;
      Future<void>.delayed(const Duration(seconds: 12), () {
        _shownOrderAlertKeys.remove(alertKey);
      });
    }
  }

  static Future<void> _showUrgentLocalNotification({
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await _localNotifications.show(
        id,
        title,
        body,
        fln.NotificationDetails(
          android: fln.AndroidNotificationDetails(
            _urgentChannel.id,
            _urgentChannel.name,
            channelDescription: _urgentChannel.description,
            importance: fln.Importance.max,
            priority: fln.Priority.max,
            playSound: true,
            enableVibration: true,
            visibility: fln.NotificationVisibility.public,
            category: fln.AndroidNotificationCategory.call,
            fullScreenIntent: true,
            ticker: 'rider-job-alert',
          ),
          iOS: const fln.DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: data['jobId']?.toString(),
      );
    } catch (_) {
      // Ignore local notification failures in background isolate edge cases.
    }
  }
}

class GlobalOrderAlertService {
  GlobalOrderAlertService._();

  static final GlobalOrderAlertService instance = GlobalOrderAlertService._();
  static const MethodChannel _orderIntentChannel = MethodChannel('van.rider/order_intents');
  static const String _methodDrainPendingOrderIntents = 'drain_pending_order_intents';

  final Set<String> _seenOrderIds = <String>{};
  bool _initialized = false;
  bool _isDialogOpen = false;
  bool _orderIntentBridgeAttached = false;
  final Map<String, Map<String, dynamic>> _pendingPlatformOrders =
      <String, Map<String, dynamic>>{};
  Timer? _pendingOrderRetryTimer;
  int _pendingOrderRetryAttempt = 0;
  static const int _maxPendingPlatformOrderRetries = 24;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _setupOrderIntentBridge();
    _initialized = true;
  }

  Future<void> handleRemoteOrderAlert(Map<String, dynamic> data) async {
    final orderId = _extractOrderId(data);
    if (orderId == null || orderId.isEmpty) {
      return;
    }

    await _handleIncomingOrderPayload(<String, dynamic>{
      'orderId': orderId,
      'title': data['title']?.toString(),
      'body': data['body']?.toString(),
      'appWasForeground': true,
      'fromRemoteMessage': true,
    });
  }

  String? _extractOrderId(Map<String, dynamic> data) {
    final candidates = <String?>[
      data['orderId']?.toString(),
      data['jobId']?.toString(),
      data['order_id']?.toString(),
      data['job_id']?.toString(),
    ];
    for (final candidate in candidates) {
      final text = candidate?.trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }
    return null;
  }

  Map<String, dynamic> _fallbackOrderData(String orderId) {
    return <String, dynamic>{
      'sourceApp': 'van2_customer',
      'customerConfirmed': true,
      'riderNotifyReady': true,
      'status': 'awaiting_rider',
      'orderId': orderId,
    };
  }

  bool _isPlatformConfirmedOrder(Map<String, dynamic>? payload) {
    return payload != null && _extractOrderId(payload) != null;
  }

  void _setupOrderIntentBridge() {
    if (_orderIntentBridgeAttached) {
      return;
    }
    _orderIntentBridgeAttached = true;
    _orderIntentChannel.setMethodCallHandler((call) async {
      if (call.method != 'incoming_order_intent') {
        return;
      }
      await _handleIncomingOrderPayload(call.arguments);
    });
    unawaited(_drainPendingPlatformOrderIntents());
  }

  Future<void> _drainPendingPlatformOrderIntents() async {
    try {
      final List<dynamic>? pending =
          await _orderIntentChannel.invokeListMethod<dynamic>(_methodDrainPendingOrderIntents);
      if (pending == null) return;
      for (final dynamic rawPayload in pending) {
        await _handleIncomingOrderPayload(rawPayload);
      }
    } catch (error) {
      debugPrint('Unable to drain order intents: $error');
    }
  }

  Future<void> _handleIncomingOrderPayload(dynamic payloadData) async {
    final payload = _normalizePlatformPayload(payloadData);
    if (payload == null) {
      return;
    }

    final orderId = payload['orderId']?.toString().trim();
    if (orderId == null || orderId.isEmpty) {
      return;
    }

    debugPrint('[GlobalOrderAlertService] incoming order intent orderId=$orderId');
    _pendingPlatformOrders[orderId] = payload;
    _pendingOrderRetryAttempt = 0;
    unawaited(_flushPendingPlatformOrders());
  }

  Map<String, dynamic>? _normalizePlatformPayload(dynamic arguments) {
    if (arguments is! Map) {
      return null;
    }
    final normalized = <String, dynamic>{};
    arguments.forEach((key, value) {
      normalized[key.toString()] = value;
    });
    return normalized;
  }

  Future<void> _flushPendingPlatformOrders() async {
    _pendingOrderRetryTimer?.cancel();
    _pendingOrderRetryTimer = null;
    if (_pendingPlatformOrders.isEmpty) {
      return;
    }

    final pendingEntries = _pendingPlatformOrders.entries.toList(growable: false);
    for (final entry in pendingEntries) {
      final shown = await _openIncomingOrderById(
        entry.key,
        payload: entry.value,
      );
      if (shown) {
        _pendingPlatformOrders.remove(entry.key);
      }
    }

    if (_pendingPlatformOrders.isNotEmpty) {
      _schedulePendingOrderRetry();
    }
  }

  void _schedulePendingOrderRetry() {
    _pendingOrderRetryTimer?.cancel();
    _pendingOrderRetryAttempt += 1;
    final delayMs = (_pendingOrderRetryAttempt <= 6)
        ? 350
        : (_pendingOrderRetryAttempt <= 12 ? 700 : 1200);
    _pendingOrderRetryTimer = Timer(
      Duration(milliseconds: delayMs),
      () => unawaited(_flushPendingPlatformOrders()),
    );
  }

  Future<bool> _openIncomingOrderById(
    String orderId, {
    Map<String, dynamic>? payload,
  }) async {
    if (_seenOrderIds.contains(orderId)) {
      return true;
    }

    try {
      final snapshot =
          await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
      final data = snapshot.data();
      final platformConfirmed = _isPlatformConfirmedOrder(payload);
      if (data != null && (_shouldShowOrder(data) || platformConfirmed)) {
        final shown = await _showOrderDialog(orderId: orderId, data: data);
        if (shown) {
          _seenOrderIds.add(orderId);
          _pendingOrderRetryAttempt = 0;
          return true;
        }

        debugPrint(
          '[GlobalOrderAlertService] navigator not ready for orderId=$orderId; retry scheduled',
        );
        _pendingPlatformOrders[orderId] = <String, dynamic>{
          ...?payload,
          'orderId': orderId,
          'retryCount': ((payload?['retryCount'] as int?) ?? 0),
        };
        _schedulePendingOrderRetry();
        return false;
      }

      if (platformConfirmed) {
        final shown = await _showOrderDialog(
          orderId: orderId,
          data: _fallbackOrderData(orderId),
        );
        if (shown) {
          _seenOrderIds.add(orderId);
          _pendingOrderRetryAttempt = 0;
          return true;
        }

        _pendingPlatformOrders[orderId] = <String, dynamic>{
          ...?payload,
          'orderId': orderId,
          'retryCount': ((payload?['retryCount'] as int?) ?? 0),
        };
        _schedulePendingOrderRetry();
        return false;
      }
    } catch (error) {
      debugPrint('Unable to open incoming order from platform intent: $error');
    }

    if (payload == null) {
      _schedulePendingOrderRetry();
      return false;
    }

    final nextRetryCount = ((payload['retryCount'] as int?) ?? 0) + 1;
    if (nextRetryCount >= _maxPendingPlatformOrderRetries) {
      debugPrint(
        'Dropping platform order intent because Firestore order never became eligible: $orderId',
      );
      _pendingPlatformOrders.remove(orderId);
      return false;
    }

    _pendingPlatformOrders[orderId] = <String, dynamic>{
      ...payload,
      'retryCount': nextRetryCount,
    };
    _schedulePendingOrderRetry();
    return false;
  }

  bool _shouldShowOrder(Map<String, dynamic> data) {
    return RiderIncomingOrderFilter.isPendingIncomingOrder(data);
  }

  Future<bool> _showOrderDialog({
    required String orderId,
    required Map<String, dynamic> data,
  }) async {
    if (_isDialogOpen) {
      debugPrint('[GlobalOrderAlertService] dialog already open; queue orderId=$orderId');
      return false;
    }

    final navigatorState = Van3RiderApp.navigatorKey.currentState;
    final context = navigatorState?.overlay?.context ?? Van3RiderApp.navigatorKey.currentContext;
    if (navigatorState == null || context == null) {
      debugPrint('[GlobalOrderAlertService] navigator unavailable for orderId=$orderId');
      return false;
    }

    _isDialogOpen = true;
    try {
      debugPrint('[GlobalOrderAlertService] opening IncomingOrderScreen orderId=$orderId');
      await RiderAlertPermissions.dismissNativeOrderOverlay();
      await navigatorState.push(
        MaterialPageRoute<void>(
          builder: (_) => IncomingOrderScreen(
            orderId: orderId,
            initialData: data,
          ),
        ),
      );
      return true;
    } finally {
      _isDialogOpen = false;
      if (_pendingPlatformOrders.isNotEmpty) {
        _schedulePendingOrderRetry();
      }
    }
  }
}

class Van3RiderApp extends StatelessWidget {
  const Van3RiderApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Future<FirebaseApp> _initializeFirebase() {
    if (Firebase.apps.isNotEmpty) {
      return Future.value(Firebase.apps.first);
    }
    return Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FirebaseApp>(
      future: _initializeFirebase(),
      builder: (context, snapshot) {
        return MaterialApp(
          title: 'Van3 Rider',
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent),
            appBarTheme: const AppBarTheme(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              centerTitle: true,
            ),
            elevatedButtonTheme: ElevatedButtonThemeData(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          routes: {
            '/login': (context) => const LoginScreen(),
            '/forgot': (context) => const ForgotPasswordScreen(),
            '/home': (context) => const RiderOnboardingGate(
              child: PrivacyLaunchGate(
                app: PrivacyAppKey.van3Rider,
                child: HomeScreen(),
              ),
            ),
            '/welcome': (context) => const WelcomeScreen(),
            '/register': (context) => const RiderRegistrationScreen(),
            '/registration-pending': (context) =>
                const RiderRegistrationPendingScreen(),
          },
          home: _buildHome(snapshot),
        );
      },
    );
  }

  Widget _buildHome(AsyncSnapshot<FirebaseApp> snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (snapshot.hasError) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'ตั้งค่า Firebase ไม่สมบูรณ์ กรุณาเชื่อมโปรเจกต์ก่อนใช้งานล็อกอิน',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        if (authSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return authSnapshot.hasData
            ? const RiderOnboardingGate(
                child: PrivacyLaunchGate(
                  app: PrivacyAppKey.van3Rider,
                  child: HomeScreen(),
                ),
              )
            : const WelcomeScreen();
      },
    );
  }
}
