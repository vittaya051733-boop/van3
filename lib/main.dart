import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as overlay;
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:permission_handler/permission_handler.dart';

import 'forgot_password_screen.dart';
import 'home_screen.dart';
import 'incoming_order_screen.dart';
import 'login_screen.dart';
import 'rider_jobs_screen.dart';
import 'services/fcm_token_sync_service.dart';
import 'services/notification_service.dart';
import 'welcome_screen.dart';
import 'utils/app_colors.dart';
import 'firebase_options.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final type = message.data['type']?.toString();
  if (type == 'call' || type == 'call_cancel' || type == 'chat') {
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
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await NotificationService().initialize();
  await OverlayAlertService.initialize();
  await FcmTokenSyncService.instance.initialize();
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
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
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
      if (!await shouldDisplayMessage(message)) {
        return;
      }
      await showOverlayFromMessage(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      final type = message.data['type']?.toString();
      if (type == 'call' || type == 'call_cancel' || type == 'chat') {
        return;
      }
      if (!await shouldDisplayMessage(message)) {
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
      if (!await shouldDisplayMessage(initialMessage)) {
        return;
      }
      await showOverlayFromMessage(initialMessage);
    }
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
      return false;
    }
    if (orderId == null || orderId.isEmpty) {
      return true;
    }

    try {
      final orderSnapshot = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .get();
      final order = orderSnapshot.data();
      if (order == null) {
        return true;
      }

      final sourceApp = (order['sourceApp'] as String?)?.trim();
      if (sourceApp == 'van2_customer') {
        return order['customerConfirmed'] == true &&
            order['riderNotifyReady'] == true;
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
    final title =
        message.notification?.title ??
        message.data['title']?.toString() ??
        'มีงานใหม่';
    final body =
        message.notification?.body ??
        message.data['body']?.toString() ??
        'มีคำขอเรียกรถใหม่ กรุณาตรวจสอบทันที';
    final orderId = _extractOrderId(message.data);

    if (_shouldShowInAppDialog(message.data)) {
      await _showInAppOrderAlert(title: title, body: body, orderId: orderId);
    }

    await _showUrgentLocalNotification(
      title: title,
      body: body,
      data: message.data,
    );

    try {
      final hasPermission =
          await overlay.FlutterOverlayWindow.isPermissionGranted();
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
    final context =
        navigatorState?.overlay?.context ??
        Van3RiderApp.navigatorKey.currentContext;
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
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
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop('dismiss'),
                                child: const Text('ปิดก่อน'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => Navigator.of(
                                  dialogContext,
                                ).pop('open_jobs'),
                                icon: const Icon(
                                  Icons.assignment_turned_in_rounded,
                                ),
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
        transitionBuilder:
            (dialogContext, animation, secondaryAnimation, child) {
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
  static const MethodChannel _orderIntentChannel = MethodChannel(
    'van.rider/order_intents',
  );
  static const String _methodDrainPendingOrderIntents =
      'drain_pending_order_intents';
  static const Set<String> _eligibleVan2OrderSources = <String>{
    'cod_confirm_dialog',
    'travel_cod_confirm_dialog',
    'promptpay_slip_dialog',
    'travel_promptpay_slip_dialog',
  };

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _orderSubscription;
  final Set<String> _seenOrderIds = <String>{};
  bool _initialized = false;
  bool _primed = false;
  bool _isDialogOpen = false;
  bool _orderIntentBridgeAttached = false;
  DateTime? _listenerStartedAt;
  final Map<String, Map<String, dynamic>> _pendingPlatformOrders =
      <String, Map<String, dynamic>>{};
  Timer? _pendingOrderRetryTimer;
  static const int _maxPendingPlatformOrderRetries = 8;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    _setupOrderIntentBridge();

    FirebaseAuth.instance.authStateChanges().listen((user) {
      _orderSubscription?.cancel();
      _seenOrderIds.clear();
      _primed = false;
      _listenerStartedAt = null;

      if (user == null) {
        return;
      }

      _listenerStartedAt = DateTime.now();
      _orderSubscription = FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .listen(_handleSnapshot);
    });

    _initialized = true;
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
      final List<dynamic>? pending = await _orderIntentChannel
          .invokeListMethod<dynamic>(_methodDrainPendingOrderIntents);
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

    _pendingPlatformOrders[orderId] = payload;
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

    final pendingEntries = _pendingPlatformOrders.entries.toList(
      growable: false,
    );
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
    _pendingOrderRetryTimer = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_flushPendingPlatformOrders()),
    );
  }

  Future<bool> _openIncomingOrderById(
    String orderId, {
    Map<String, dynamic>? payload,
  }) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .get();
      final data = snapshot.data();
      if (data != null && _shouldShowOrder(data)) {
        _seenOrderIds.add(orderId);
        return await _showOrderDialog(orderId: orderId, data: data);
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

  Future<void> _handleSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) async {
    if (!_primed) {
      for (final doc in snapshot.docs) {
        if (_shouldShowOrder(doc.data())) {
          _seenOrderIds.add(doc.id);
        }
      }
      _primed = true;
      return;
    }

    for (final change in snapshot.docChanges) {
      if (change.type != DocumentChangeType.added) {
        continue;
      }

      final doc = change.doc;
      final data = doc.data();
      if (data == null || !_shouldShowOrder(data)) {
        continue;
      }
      if (!_isFreshOrder(data)) {
        _seenOrderIds.add(doc.id);
        continue;
      }
      if (!_seenOrderIds.add(doc.id)) {
        continue;
      }

      await _showOrderDialog(orderId: doc.id, data: data);
    }
  }

  bool _shouldShowOrder(Map<String, dynamic> data) {
    final sourceApp = (data['sourceApp'] as String?)?.trim();
    if (sourceApp != 'van2_customer') {
      return false;
    }
    if (data['customerConfirmed'] != true || data['riderNotifyReady'] != true) {
      return false;
    }
    final confirmedAt = _toDateTime(data['customerConfirmedAt']);
    if (confirmedAt == null) {
      return false;
    }
    final audit = data['audit'];
    if (audit is! Map<String, dynamic>) {
      return false;
    }
    final createdSource = (audit['createdSource'] as String?)?.trim();
    if (!_eligibleVan2OrderSources.contains(createdSource)) {
      return false;
    }
    final status = (data['status'] as String?)?.trim();
    return status == 'pending' || status == 'awaiting_rider';
  }

  bool _isFreshOrder(Map<String, dynamic> data) {
    final startedAt = _listenerStartedAt;
    if (startedAt == null) {
      return true;
    }
    final candidates = <DateTime?>[
      _toDateTime(data['assignedRiderAt']),
      _toDateTime(data['createdAt']),
      _toDateTime(data['timestamp']),
    ].whereType<DateTime>().toList(growable: false);
    if (candidates.isEmpty) {
      return false;
    }
    candidates.sort((a, b) => b.compareTo(a));
    return candidates.first.isAfter(
      startedAt.subtract(const Duration(seconds: 3)),
    );
  }

  DateTime? _toDateTime(Object? value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    return null;
  }

  Future<bool> _showOrderDialog({
    required String orderId,
    required Map<String, dynamic> data,
  }) async {
    if (_isDialogOpen) {
      return false;
    }

    final navigatorState = Van3RiderApp.navigatorKey.currentState;
    final context =
        navigatorState?.overlay?.context ??
        Van3RiderApp.navigatorKey.currentContext;
    if (navigatorState == null || context == null) {
      return false;
    }

    _isDialogOpen = true;
    try {
      await navigatorState.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              IncomingOrderScreen(orderId: orderId, initialData: data),
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

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

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
            '/home': (context) => const HomeScreen(),
            '/welcome': (context) => const WelcomeScreen(),
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
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return authSnapshot.hasData
            ? const HomeScreen()
            : const WelcomeScreen();
      },
    );
  }
}
