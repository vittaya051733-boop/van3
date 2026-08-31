import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/l10n.dart';
import '../main.dart';
import '../widgets/rider_order_workflow_dialog.dart';
import 'rider_order_actions.dart';
import 'rider_orders_service.dart';

enum RiderOrderWorkflowStep {
  shopReady,
  scanAtShop,
  goToCustomer,
  photoProof,
}

enum RiderOrderWorkflowAction {
  later,
  goToShopNow,
  openShopMap,
  scanQr,
  openCustomerMap,
  capturePhoto,
}

class RiderOrderWorkflowService {
  RiderOrderWorkflowService._();

  static final RiderOrderWorkflowService instance = RiderOrderWorkflowService._();

  static const String _deferredKeyPrefix = 'workflow_deferred_';
  static const String _shopReadyAction = 'shop_ready_for_pickup';

  final ValueNotifier<int> deferredRevision = ValueNotifier<int>(0);
  final Set<String> _shownWorkflowKeys = <String>{};
  final Map<String, String> _lastKnownStatus = <String, String>{};

  bool _initialized = false;
  bool _isDialogOpen = false;
  StreamSubscription<RiderOrdersQuerySnapshot>? _ordersSubscription;
  final fln.FlutterLocalNotificationsPlugin _localNotifications =
      fln.FlutterLocalNotificationsPlugin();

  static final fln.AndroidNotificationChannel _shopReadyChannel =
      fln.AndroidNotificationChannel(
        'rider_shop_ready',
        L10n.shopReadyChannelName,
        description: L10n.shopReadyChannelDesc,
        importance: fln.Importance.high,
      );

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          fln.AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_shopReadyChannel);
    _ordersSubscription = RiderOrdersService.instance.ordersStream.listen(
      _handleOrdersSnapshot,
      onError: (_) {},
    );
    _initialized = true;
  }

  void dispose() {
    unawaited(_ordersSubscription?.cancel());
    _ordersSubscription = null;
  }

  Future<bool> isDeferred(String orderId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_deferredKeyPrefix$orderId') ?? false;
  }

  Future<void> setDeferred(String orderId, bool deferred) async {
    final prefs = await SharedPreferences.getInstance();
    if (deferred) {
      await prefs.setBool('$_deferredKeyPrefix$orderId', true);
    } else {
      await prefs.remove('$_deferredKeyPrefix$orderId');
    }
    deferredRevision.value++;
  }

  Future<void> clearDeferred(String orderId) async {
    await setDeferred(orderId, false);
  }

  RiderOrderWorkflowStep resolveStep(Map<String, dynamic> orderData) {
    final status = (orderData['status'] as String?)?.trim() ?? '';
    switch (status) {
      case 'ready':
        return RiderOrderWorkflowStep.shopReady;
      case 'accepted':
        return RiderOrderWorkflowStep.scanAtShop;
      case 'delivering':
        return RiderOrderWorkflowStep.goToCustomer;
      default:
        return RiderOrderWorkflowStep.shopReady;
    }
  }

  Future<void> handleShopReadyAlert(RemoteMessage message) async {
    final orderId = _extractOrderId(message.data);
    if (orderId == null || orderId.isEmpty) {
      return;
    }

    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        L10n.shopPreparedTitle;
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        L10n.shopReadyForPickupBody;

    await _showShopReadyTrayNotification(
      orderId: orderId,
      title: title,
      body: body,
    );

    await resume(
      orderId,
      showTrayNotification: false,
      forceStep: RiderOrderWorkflowStep.shopReady,
    );
  }

  Future<void> handleShopReadyBackgroundNotification(RemoteMessage message) async {
    final orderId = _extractOrderId(message.data);
    if (orderId == null || orderId.isEmpty) {
      return;
    }

    final title = message.notification?.title ??
        message.data['title']?.toString() ??
        L10n.shopPreparedTitle;
    final body = message.notification?.body ??
        message.data['body']?.toString() ??
        L10n.shopReadyForPickupBody;

    await _showShopReadyTrayNotification(
      orderId: orderId,
      title: title,
      body: body,
    );
  }

  Future<void> resume(
    String orderId, {
    bool showTrayNotification = false,
    RiderOrderWorkflowStep? forceStep,
  }) async {
    final orderDoc =
        await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
    final orderData = orderDoc.data();
    if (orderData == null) {
      return;
    }

    final status = (orderData['status'] as String?)?.trim() ?? '';
    if (!_isActiveWorkflowStatus(status)) {
      await clearDeferred(orderId);
      return;
    }

    if (showTrayNotification) {
      await _showShopReadyTrayNotification(
        orderId: orderId,
        title: L10n.shopPreparedTitle,
        body: L10n.shopReadyForPickupBody,
      );
    }

    final step = forceStep ?? resolveStep(orderData);
    await _showWorkflowDialog(
      orderId: orderId,
      orderData: orderData,
      step: step,
    );
  }

  Future<void> continueWorkflow(
    BuildContext context, {
    required String orderId,
    required Map<String, dynamic> orderData,
  }) async {
    await clearDeferred(orderId);
    final step = resolveStep(orderData);
    await _showWorkflowDialog(
      orderId: orderId,
      orderData: orderData,
      step: step,
      hostContext: context,
    );
  }

  Future<void> showPhotoProofStep(
    BuildContext context, {
    required String orderId,
    required Map<String, dynamic> orderData,
  }) async {
    await _showWorkflowDialog(
      orderId: orderId,
      orderData: orderData,
      step: RiderOrderWorkflowStep.photoProof,
      hostContext: context,
    );
  }

  Future<void> _showWorkflowDialog({
    required String orderId,
    required Map<String, dynamic> orderData,
    required RiderOrderWorkflowStep step,
    BuildContext? hostContext,
  }) async {
    if (_isDialogOpen) {
      return;
    }

    final dedupeKey = '$orderId:${step.name}';
    if (!_shownWorkflowKeys.add(dedupeKey)) {
      return;
    }

    final context = hostContext ??
        Van3RiderApp.navigatorKey.currentState?.overlay?.context ??
        Van3RiderApp.navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      _shownWorkflowKeys.remove(dedupeKey);
      return;
    }

    final orderCode = (orderData['orderCode'] as String?)?.trim();
    final orderCodeLabel = orderCode?.isNotEmpty == true
        ? L10n.orderHashLabel(orderCode!)
        : L10n.orderHashLabel(orderId.substring(0, orderId.length.clamp(0, 8)));
    final shopName = (orderData['shopName'] as String?)?.trim() ?? '';

    _isDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: step != RiderOrderWorkflowStep.shopReady,
        builder: (dialogContext) {
          return RiderOrderWorkflowDialog(
            step: step,
            orderCodeLabel: orderCodeLabel,
            shopName: shopName.isNotEmpty ? L10n.shopLabel(shopName) : '',
            onAction: (action) {
              unawaited(
                _handleWorkflowAction(
                  dialogContext,
                  action: action,
                  orderId: orderId,
                  orderData: orderData,
                  step: step,
                ),
              );
            },
          );
        },
      );
    } finally {
      _isDialogOpen = false;
      Future<void>.delayed(const Duration(seconds: 8), () {
        _shownWorkflowKeys.remove(dedupeKey);
      });
    }
  }

  Future<void> _handleWorkflowAction(
    BuildContext dialogContext, {
    required RiderOrderWorkflowAction action,
    required String orderId,
    required Map<String, dynamic> orderData,
    required RiderOrderWorkflowStep step,
  }) async {
    switch (action) {
      case RiderOrderWorkflowAction.later:
        await setDeferred(orderId, true);
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        return;
      case RiderOrderWorkflowAction.goToShopNow:
        await clearDeferred(orderId);
        await RiderOrderActions.instance.openShopMap(orderData);
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        await _showWorkflowDialog(
          orderId: orderId,
          orderData: orderData,
          step: RiderOrderWorkflowStep.scanAtShop,
        );
        return;
      case RiderOrderWorkflowAction.openShopMap:
        await RiderOrderActions.instance.openShopMap(orderData);
        return;
      case RiderOrderWorkflowAction.scanQr:
        await clearDeferred(orderId);
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        final hostContext = Van3RiderApp.navigatorKey.currentContext;
        if (hostContext == null || !hostContext.mounted) {
          return;
        }
        final scanned = await RiderOrderActions.instance.openQrScanner(
          hostContext,
          orderId: orderId,
          orderData: orderData,
        );
        if (!scanned) {
          return;
        }
        final refreshed = await FirebaseFirestore.instance
            .collection('orders')
            .doc(orderId)
            .get();
        final refreshedData = refreshed.data();
        if (refreshedData == null) {
          return;
        }
        await _showWorkflowDialog(
          orderId: orderId,
          orderData: refreshedData,
          step: RiderOrderWorkflowStep.goToCustomer,
        );
        return;
      case RiderOrderWorkflowAction.openCustomerMap:
        await RiderOrderActions.instance.openCustomerMap(orderData);
        return;
      case RiderOrderWorkflowAction.capturePhoto:
        if (dialogContext.mounted) {
          Navigator.of(dialogContext).pop();
        }
        final hostContext = Van3RiderApp.navigatorKey.currentContext;
        if (hostContext == null || !hostContext.mounted) {
          return;
        }
        await RiderOrderActions.instance.captureDeliveryProof(
          hostContext,
          orderId: orderId,
          orderData: orderData,
        );
        await clearDeferred(orderId);
        return;
    }
  }

  void _handleOrdersSnapshot(RiderOrdersQuerySnapshot snapshot) {
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final orderId = doc.id;
      final status = (data['status'] as String?)?.trim() ?? '';
      final previous = _lastKnownStatus[orderId];
      _lastKnownStatus[orderId] = status;

      if (previous == null) {
        continue;
      }
      if (previous == status) {
        continue;
      }

      if (previous != 'ready' && status == 'ready') {
        unawaited(
          resume(
            orderId,
            forceStep: RiderOrderWorkflowStep.shopReady,
          ),
        );
      } else if (
          (previous == 'ready' || previous == 'accepted') &&
          status == 'delivering') {
        unawaited(
          _showWorkflowDialog(
            orderId: orderId,
            orderData: data,
            step: RiderOrderWorkflowStep.goToCustomer,
          ),
        );
      } else if (previous == 'delivering' && status == 'delivered') {
        unawaited(clearDeferred(orderId));
      }
    }
  }

  Future<void> _showShopReadyTrayNotification({
    required String orderId,
    required String title,
    required String body,
  }) async {
    try {
      final id = orderId.hashCode & 0x7fffffff;
      await _localNotifications.show(
        id,
        title,
        body.isNotEmpty ? body : title,
        fln.NotificationDetails(
          android: fln.AndroidNotificationDetails(
            _shopReadyChannel.id,
            _shopReadyChannel.name,
            channelDescription: _shopReadyChannel.description,
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
        payload: 'shop_ready_for_pickup:$orderId',
      );
    } catch (error) {
      debugPrint('Shop-ready tray notification failed: $error');
    }
  }

  bool _isActiveWorkflowStatus(String status) {
    return status == 'ready' || status == 'accepted' || status == 'delivering';
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

  static bool isShopReadyAction(Map<String, dynamic> data) {
    return data['action']?.toString().trim() == _shopReadyAction;
  }
}
