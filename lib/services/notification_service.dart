import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import '../utils/app_check_guard.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n/l10n.dart';
import '../call_screen.dart';
import '../main.dart';
import '../models/user_profile.dart';
import '../rider_chat_room_screen.dart';

class NotificationService {
  NotificationService._internal();

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  static const MethodChannel _callIntentChannel = MethodChannel('van.rider/call_intents');
  static const MethodChannel _appStateChannel = MethodChannel('van.rider/app_state');
  static const String _methodDrainPending = 'drain_pending_intents';

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _incomingCallVisible = false;
  bool _callIntentBridgeAttached = false;
  String? _activeIncomingChannelId;
  final Set<String> _cancelledChannelIds = <String>{};
  String? _backgroundReturnChannelId;
  bool _shouldReturnAppToBackground = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );
    await _ensureAndroidNotificationChannel();

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      _handleNotificationTap(initial);
    }

    _setupCallIntentBridge();
    _initialized = true;
  }

  Future<bool> enablePushNotifications() async {
    if (!_initialized) {
      await initialize();
    }

    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!authorized) {
      return false;
    }

    if (Platform.isAndroid) {
      try {
        final status = await Permission.notification.request();
        if (!status.isGranted && !status.isLimited) {
          return false;
        }
      } catch (_) {
        return false;
      }
    }

    return true;
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final data = message.data;

    if (data['type'] == 'call_cancel') {
      _handleCallCancelFromNative(data['channelId'] as String?);
      return;
    }

    if (data['type'] == 'call') {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final callerId = data['callerId'] ?? data['caller_id'];
      if (currentUid != null && callerId != null && currentUid == callerId) {
        return;
      }

      _navigateToIncomingCall(
        channelId: data['channelId'] ?? '',
        appId: data['appId'],
        token: data['token'],
        callerId: data['callerId'] ?? data['caller_id'] ?? '',
        callerName: data['callerName'] ?? L10n.caller,
        callerPhotoUrl: data['callerPhotoUrl'],
        isVideo: _resolveIsVideoFlag(data),
      );
      return;
    }

    if (data['type'] == 'chat') {
      final senderName = (data['senderName'] ?? data['title'] ?? L10n.newMessage).toString();
      final messageText = (data['message'] ?? data['body'] ?? '').toString();
      await _showLocalNotification(
        title: senderName,
        body: messageText,
        payload: jsonEncode(<String, dynamic>{
          'type': 'chat',
          'chatId': data['chatId'],
          'senderId': data['senderId'] ?? data['sender_id'],
          'senderName': senderName,
        }),
      );
      return;
    }
  }

  Future<void> _ensureAndroidNotificationChannel() async {
    if (!Platform.isAndroid) {
      return;
    }
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) {
      return;
    }

    final channel = AndroidNotificationChannel(
      'chat_channel_van3',
      L10n.chatNotificationChannelName,
      description: L10n.chatNotificationChannelDesc,
      importance: Importance.high,
      playSound: true,
    );
    await androidPlugin.createNotificationChannel(channel);
  }

  Future<void> _showLocalNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'chat_channel_van3',
      L10n.chatNotificationChannelName,
      channelDescription: L10n.chatNotificationChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      playSound: true,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      payload: payload,
    );
  }

  void _onNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        final data = <String, dynamic>{
          for (final entry in decoded.entries) entry.key.toString(): entry.value,
        };
        if (data['type'] == 'chat') {
          _openChatFromNotificationData(data);
        }
      }
    } catch (error) {
      debugPrint('Failed to parse local notification payload: $error');
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    if (message.data['type'] == 'call') {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      final callerId = message.data['callerId'] ?? message.data['caller_id'];
      if (currentUid != null && callerId != null && currentUid == callerId) {
        return;
      }

      _navigateToIncomingCall(
        channelId: message.data['channelId'] ?? '',
        appId: message.data['appId'],
        token: message.data['token'],
        callerId: message.data['callerId'] ?? message.data['caller_id'] ?? '',
        callerName: message.data['callerName'] ?? L10n.caller,
        callerPhotoUrl: message.data['callerPhotoUrl'],
        isVideo: _resolveIsVideoFlag(message.data),
      );
      return;
    }

    if (message.data['type'] == 'call_cancel') {
      _handleCallCancelFromNative(message.data['channelId'] as String?);
      return;
    }

    if (message.data['type'] == 'chat') {
      _openChatFromNotificationData(message.data);
    }
  }

  void _setupCallIntentBridge() {
    if ((!Platform.isAndroid && !Platform.isIOS) || _callIntentBridgeAttached) {
      return;
    }
    _callIntentBridgeAttached = true;
    _callIntentChannel.setMethodCallHandler((call) async {
      if (call.method != 'incoming_call_intent') {
        return;
      }
      _handleIncomingCallPayload(call.arguments);
    });
    _drainPendingPlatformIntents();
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

  Future<void> _drainPendingPlatformIntents() async {
    try {
      final List<dynamic>? pending =
          await _callIntentChannel.invokeListMethod<dynamic>(_methodDrainPending);
      if (pending == null) return;
      for (final dynamic rawPayload in pending) {
        _handleIncomingCallPayload(rawPayload);
      }
    } catch (error) {
      debugPrint('Unable to drain call intents: $error');
    }
  }

  void _handleIncomingCallPayload(dynamic payloadData) {
    final payload = _normalizePlatformPayload(payloadData);
    if (payload == null) {
      return;
    }

    if (payload['cancelOnly'] == true) {
      _handleCallCancelFromNative(payload['channelId'] as String?);
      return;
    }

    if (payload['type'] == 'chat') {
      unawaited(_openChatFromNotificationData(payload));
      return;
    }

    final bool minimizeOnEnd = payload['appWasForeground'] == false;
    _navigateToIncomingCall(
      channelId: payload['channelId'] as String? ?? '',
      appId: payload['appId'] as String?,
      token: payload['token'] as String?,
      callerId: payload['callerId'] as String? ?? '',
      callerName: payload['callerName'] as String? ?? L10n.caller,
      callerPhotoUrl: payload['callerPhotoUrl'] as String?,
      isVideo: payload['isVideo'] == true,
      minimizeOnEnd: minimizeOnEnd,
    );
  }

  void _handleCallCancelFromNative(String? channelId) {
    if (channelId != null) {
      _cancelledChannelIds.add(channelId);
    }
    _dismissIncomingCallUI(channelId: channelId);
  }

  void _dismissIncomingCallUI({String? channelId}) {
    if (!_incomingCallVisible) {
      return;
    }
    if (_activeIncomingChannelId != null && channelId != null && _activeIncomingChannelId != channelId) {
      return;
    }

    final navigatorState = Van3RiderApp.navigatorKey.currentState;
    if (navigatorState != null) {
      navigatorState.maybePop();
    }

    _incomingCallVisible = false;
    _activeIncomingChannelId = null;
    _maybeReturnAppToBackground(channelId: channelId);
  }

  void _navigateToIncomingCall({
    required String channelId,
    required String? appId,
    required String? token,
    required String callerId,
    required String callerName,
    String? callerPhotoUrl,
    required bool isVideo,
    int retryCount = 30,
    bool minimizeOnEnd = false,
  }) {
    if (channelId.isEmpty || token == null || token.isEmpty) {
      debugPrint('Incoming call payload missing channel/token, skip UI presentation');
      return;
    }

    if (_cancelledChannelIds.contains(channelId)) {
      return;
    }

    if (_incomingCallVisible) {
      return;
    }

    final navigatorState = Van3RiderApp.navigatorKey.currentState;
    if (navigatorState == null) {
      if (retryCount <= 0) {
        debugPrint('Navigator not ready, cannot open CallScreen');
        return;
      }
      Future.delayed(const Duration(milliseconds: 300), () {
        _navigateToIncomingCall(
          channelId: channelId,
          appId: appId,
          token: token,
          callerId: callerId,
          callerName: callerName,
          callerPhotoUrl: callerPhotoUrl,
          isVideo: isVideo,
          retryCount: retryCount - 1,
          minimizeOnEnd: minimizeOnEnd,
        );
      });
      return;
    }

    _incomingCallVisible = true;
    _activeIncomingChannelId = channelId;
    if (minimizeOnEnd) {
      _backgroundReturnChannelId = channelId;
      _shouldReturnAppToBackground = true;
    }

    navigatorState.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CallScreen(
          channelName: channelId,
          targetProfile: UserProfile.fromMap(
            callerId,
            {
              'displayName': callerName,
              'photoUrl': callerPhotoUrl,
            },
          ),
          isVideo: isVideo,
          isIncoming: true,
          appIdOverride: appId,
          tokenOverride: token,
        ),
      ),
    ).whenComplete(() {
      _incomingCallVisible = false;
      if (_activeIncomingChannelId == channelId) {
        _activeIncomingChannelId = null;
      }
      _cancelledChannelIds.remove(channelId);
      _maybeReturnAppToBackground(channelId: channelId);
    });
  }

  bool _resolveIsVideoFlag(Map<String, dynamic> data) {
    final raw = data['callType'] ?? data['isVideo'];
    if (raw is bool) return raw;
    if (raw is String) {
      final lower = raw.toLowerCase();
      return lower == 'video' || lower == 'true';
    }
    return false;
  }

  Future<void> _maybeReturnAppToBackground({String? channelId}) async {
    if (!_shouldReturnAppToBackground) {
      return;
    }
    if (_backgroundReturnChannelId != null && channelId != null && _backgroundReturnChannelId != channelId) {
      return;
    }

    _shouldReturnAppToBackground = false;
    _backgroundReturnChannelId = null;
    if (!Platform.isAndroid) {
      return;
    }

    try {
      await _appStateChannel.invokeMethod('move_task_to_back');
    } catch (error) {
      debugPrint('Unable to return app to background: $error');
    }
  }

  Future<void> _openChatFromNotificationData(
    Map<String, dynamic> data, {
    int retryCount = 6,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return;
    }

    final navigatorState = Van3RiderApp.navigatorKey.currentState;
    if (navigatorState == null) {
      if (retryCount <= 0) {
        return;
      }
      Future.delayed(const Duration(milliseconds: 250), () {
        _openChatFromNotificationData(data, retryCount: retryCount - 1);
      });
      return;
    }

    final senderIdRaw = data['senderId'] ?? data['sender_id'];
    final senderId = senderIdRaw?.toString();
    if (senderId == null || senderId.isEmpty) {
      return;
    }

    final senderName = (data['senderName'] ?? data['title'] ?? L10n.chatPartner).toString();
    final orderId = data['orderId']?.toString().trim();
    navigatorState.push(
      MaterialPageRoute<void>(
        builder: (_) => RiderChatRoomScreen(
          peerUid: senderId,
          peerLabel: senderName,
          orderId: orderId != null && orderId.isNotEmpty ? orderId : null,
        ),
      ),
    );
  }

  Future<void> cancelCallInvite({
    required String channelId,
    required String calleeId,
  }) async {
    try {
      await AppCheckGuard.ensureCallableReady();
      final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('cancelCallInvite');
      await callable.call({
        'channelId': channelId,
        'calleeId': calleeId,
        'callerId': FirebaseAuth.instance.currentUser?.uid,
      });
    } catch (error) {
      debugPrint('Failed to cancel call invite: $error');
    }
  }

  Future<Map<String, dynamic>> initiateCall({
    required UserProfile caller,
    required UserProfile callee,
    required bool isVideo,
  }) async {
    await AppCheckGuard.ensureCallableReady();
    const List<String> preferredRegions = <String>['asia-southeast1', 'us-central1'];
    FirebaseFunctionsException? lastError;

    for (final region in preferredRegions) {
      try {
        final callable =
            FirebaseFunctions.instanceFor(region: region).httpsCallable('initiateCall');
        final result = await callable.call(<String, dynamic>{
          'calleeId': callee.uid,
          'callerId': caller.uid,
          'callerName': caller.displayName,
          'callerPhotoUrl': caller.photoUrl,
          'isVideo': isVideo,
          'callType': isVideo ? 'video' : 'voice',
          'callerData': caller.toFirestore()..['uid'] = caller.uid,
        });
        return Map<String, dynamic>.from(result.data);
      } on FirebaseFunctionsException catch (e) {
        lastError = e;
        if (e.code != 'not-found') {
          rethrow;
        }
      }
    }

    if (lastError != null) {
      throw lastError;
    }

    throw FirebaseFunctionsException(code: 'unknown', message: 'Unknown error initiating call');
  }

  String buildCallPayload({
    required String channelId,
    required String callerId,
    required String callerName,
    String? callerPhotoUrl,
    required bool isVideo,
    required String appId,
    required String token,
  }) {
    return jsonEncode({
      'type': 'call',
      'channelId': channelId,
      'callerId': callerId,
      'callerName': callerName,
      'callerPhotoUrl': callerPhotoUrl,
      'isVideo': isVideo,
      'appId': appId,
      'token': token,
    });
  }
}
