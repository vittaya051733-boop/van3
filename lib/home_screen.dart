import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'rider_jobs_screen.dart';
import 'rider_location_permission_screen.dart';
import 'rider_settings_screen.dart';
import 'wallet_screen.dart';

bool _isVerifiedSlipOkFunctionCredit(Map<String, dynamic> data) {
  final status = data['status']?.toString().trim().toLowerCase();
  final provider = data['provider']?.toString().trim().toLowerCase();
  final slipFeedbackId = data['slipFeedbackId']?.toString().trim();
  return status == 'verified' &&
      provider == 'slipok' &&
      data['creditedByCloudFunction'] == true &&
      slipFeedbackId != null &&
      slipFeedbackId.isNotEmpty;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _maxFreshPositionAgeSeconds = 45;
  static const double _minimumReadyCredit = 500.0;
  static const double _lowCreditWarningCredit = 600.0;
  static const double _healthyCreditTarget = 3000.0;
  static const String _seenOrderIdsPrefsKey = 'van3_seen_pending_order_ids';
  static const int _maxPersistedSeenOrderIds = 200;
  static const Set<String> _eligibleVan2OrderSources = <String>{
    'cod_confirm_dialog',
    'travel_cod_confirm_dialog',
    'promptpay_slip_dialog',
    'travel_promptpay_slip_dialog',
  };

  bool _isSettingOnline = false;
  bool _isSettingPassengerReady = false;
  bool _isOnlineReady = false;
  bool _isPassengerReady = false;
  bool _isPromptingLocation = false;
  bool _hasShownLowCreditWarning = false;
  double? _currentCreditBalance;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _locationHeartbeatTimer;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _riderDocSubscription;

  bool get _hasAnyReadyMode => _isOnlineReady || _isPassengerReady;

    bool get _hasLoadedCreditBalance => _currentCreditBalance != null;

    bool get _hasEnoughCreditToOpenReady =>
      _currentCreditBalance != null &&
      _currentCreditBalance! >= _minimumReadyCredit;

  LocationSettings _buildLocationSettings({
    LocationAccuracy accuracy = LocationAccuracy.high,
    int distanceFilter = 0,
  }) {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        forceLocationManager: true,
      );
    }

    return LocationSettings(accuracy: accuracy, distanceFilter: distanceFilter);
  }

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _newJobSubscription;
  final Set<String> _seenPendingOrderIds = <String>{};
  bool _hasPrimedPendingSnapshot = false;
  DateTime? _newJobListenerStartedAt;

  static const List<_DashboardAction> _actions = [
    _DashboardAction(
      title: 'ออเดอร์ใหม่',
      subtitle: 'ดูงานที่รอรับ',
      icon: Icons.assignment_turned_in_rounded,
      color: Color(0xFFFF8A00),
    ),
    _DashboardAction(
      title: 'ประวัติ ออเดอร์',
      subtitle: 'กำลังจัดส่ง',
      icon: Icons.receipt_long_rounded,
      color: Color(0xFFFF6B00),
    ),
    _DashboardAction(
      title: 'กระเป๋าเงิน',
      subtitle: 'ยอดคงเหลือ',
      icon: Icons.account_balance_wallet_rounded,
      color: Color(0xFFFFA940),
    ),
    _DashboardAction(
      title: 'รายได้วันนี้',
      subtitle: 'สรุปรายวัน',
      icon: Icons.query_stats_rounded,
      color: Color(0xFFE66A00),
    ),
    _DashboardAction(
      title: 'การแจ้งเตือน',
      subtitle: 'อัปเดตงานล่าสุด',
      icon: Icons.notifications_active_rounded,
      color: Color(0xFFFF7F11),
    ),
    _DashboardAction(
      title: 'ตั้งค่า',
      subtitle: 'โปรไฟล์และระบบ',
      icon: Icons.settings_rounded,
      color: Color(0xFFFF9340),
    ),
  ];

  static const Set<String> _bottomBarActionTitles = <String>{
    'กระเป๋าเงิน',
    'รายได้วันนี้',
    'การแจ้งเตือน',
    'ตั้งค่า',
  };

  static final List<_DashboardAction> _dashboardActions = _actions
      .where((action) => !_bottomBarActionTitles.contains(action.title))
      .toList(growable: false);

  static final List<_DashboardAction> _bottomBarActions = _actions
      .where((action) => _bottomBarActionTitles.contains(action.title))
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _ensureLocationReadyOnEntry();
    _loadReadyStatuses();
    unawaited(_initializeNewJobListener());
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _locationHeartbeatTimer?.cancel();
    _newJobSubscription?.cancel();
    _riderDocSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeNewJobListener() async {
    await _restoreSeenPendingOrderIds();
    _startNewJobListener();
  }

  Future<void> _restoreSeenPendingOrderIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedIds =
          prefs.getStringList(_seenOrderIdsPrefsKey) ?? const <String>[];
      _seenPendingOrderIds
        ..clear()
        ..addAll(storedIds.where((id) => id.trim().isNotEmpty));
    } catch (_) {
      // Keep listener functional even if local persistence is unavailable.
    }
  }

  Future<void> _persistSeenPendingOrderIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final values = _seenPendingOrderIds.toList(growable: false);
      final trimmed = values.length <= _maxPersistedSeenOrderIds
          ? values
          : values.sublist(values.length - _maxPersistedSeenOrderIds);
      await prefs.setStringList(_seenOrderIdsPrefsKey, trimmed);
    } catch (_) {
      // Ignore persistence failures.
    }
  }

  void _startNewJobListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    _newJobSubscription?.cancel();
    _hasPrimedPendingSnapshot = false;
    _newJobListenerStartedAt = DateTime.now();
    _newJobSubscription = FirebaseFirestore.instance
        .collection('orders')
        .where('driverId', isEqualTo: user.uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .handleError((Object error) {
          debugPrint('[van3:new-job] stream error: $error');
        })
        .listen((snapshot) {
          if (!_hasPrimedPendingSnapshot) {
            for (final doc in snapshot.docs) {
              final data = doc.data();
              if (_shouldShowOrderToRider(data)) {
                _seenPendingOrderIds.add(doc.id);
              }
            }
            unawaited(_persistSeenPendingOrderIds());
            _hasPrimedPendingSnapshot = true;
            return;
          }

          for (final change in snapshot.docChanges) {
            if (change.type != DocumentChangeType.added) {
              continue;
            }

            final doc = change.doc;
            final data = doc.data();
            if (data == null || !_shouldShowOrderToRider(data)) {
              continue;
            }
            if (!_isFreshNewOrder(data)) {
              debugPrint(
                '[van3:new-job] ignore stale order id=${doc.id} code=${data['orderCode']}',
              );
              _seenPendingOrderIds.add(doc.id);
              unawaited(_persistSeenPendingOrderIds());
              continue;
            }

            if (_seenPendingOrderIds.add(doc.id)) {
              unawaited(_persistSeenPendingOrderIds());
              debugPrint(
                '[van3:new-job] notify order id=${doc.id} code=${data['orderCode']}',
              );
            }
          }
        });
  }

  bool _shouldShowOrderToRider(Map<String, dynamic> data) {
    final sourceApp = (data['sourceApp'] as String?)?.trim();
    if (sourceApp != 'van2_customer') {
      return false;
    }

    // Block notifications entirely when rider has turned ready toggles off.
    final orderType = (data['orderType'] as String?)?.trim();
    final serviceType = (data['serviceType'] as String?)?.trim();
    final isTravel =
        orderType == 'travel_passenger' || serviceType == 'travel_passenger';
    if (isTravel) {
      if (!_isPassengerReady) return false;
    } else {
      if (!_isOnlineReady) return false;
    }

    final customerConfirmed = data['customerConfirmed'] == true;
    if (!customerConfirmed) {
      return false;
    }

    final riderNotifyReady = data['riderNotifyReady'] == true;
    if (!riderNotifyReady) {
      return false;
    }

    final confirmedAt = _toDateTime(data['customerConfirmedAt']);
    if (confirmedAt == null) {
      return false;
    }

    final audit = data['audit'];
    if (audit is Map<String, dynamic>) {
      final createdSource = (audit['createdSource'] as String?)?.trim();
      if (!_eligibleVan2OrderSources.contains(createdSource)) {
        return false;
      }
    } else {
      return false;
    }

    final status = (data['status'] as String?)?.trim();
    return status == 'pending' || status == 'awaiting_rider';
  }

  bool _isFreshNewOrder(Map<String, dynamic> data) {
    final startedAt = _newJobListenerStartedAt;
    if (startedAt == null) {
      return true;
    }

    final orderTime = _latestOrderTime(data);
    if (orderTime == null) {
      return false;
    }

    // Allow a tiny clock skew window between client and server timestamps.
    return orderTime.isAfter(startedAt.subtract(const Duration(seconds: 3)));
  }

  DateTime? _latestOrderTime(Map<String, dynamic> data) {
    final candidates = <DateTime?>[
      _toDateTime(data['assignedRiderAt']),
      _toDateTime(data['createdAt']),
      _toDateTime(data['timestamp']),
    ].whereType<DateTime>().toList(growable: false);

    if (candidates.isEmpty) {
      return null;
    }

    candidates.sort((a, b) => b.compareTo(a));
    return candidates.first;
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

  double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  Map<String, dynamic>? _readStringKeyedMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
    }
    return null;
  }

  double _calculateRiderNetShippingIncome(Map<String, dynamic> data) {
    final persisted = _readPersistedRiderNetIncome(data);
    if (persisted != null && persisted > 0) {
      return persisted;
    }

    final shippingFee = _readShippingFeeAmount(data);
    if (shippingFee <= 0) {
      return 0;
    }
    return double.parse((shippingFee * 0.85).toStringAsFixed(1));
  }

  double? _readPersistedRiderNetIncome(Map<String, dynamic> data) {
    final financials = _readStringKeyedMap(data['deliveryFinancials']);
    return _toDouble(data['deliveryRiderNetIncome']) ??
        _toDouble(financials?['riderNetIncome']);
  }

  bool _isDeliveredToday(Map<String, dynamic> data) {
    final financials = _readStringKeyedMap(data['deliveryFinancials']);
    final deliveredAt =
        _toDateTime(data['deliveredAt']) ??
        _toDateTime(financials?['completedAt']);
    if (deliveredAt == null) {
      return false;
    }

    final now = DateTime.now();
    return deliveredAt.year == now.year &&
        deliveredAt.month == now.month &&
        deliveredAt.day == now.day;
  }

  List<_IncomeDaySummary> _buildLast7DayIncomeSummaries(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final summaries = <String, _IncomeDaySummary>{};

    for (final doc in docs) {
      final data = doc.data();
      final status = (data['status'] as String?)?.trim() ?? '';
      if (status != 'delivered') {
        continue;
      }

      final financials = _readStringKeyedMap(data['deliveryFinancials']);
      final deliveredAt =
          _toDateTime(data['deliveredAt']) ??
          _toDateTime(financials?['completedAt']);
      if (deliveredAt == null) {
        continue;
      }

      final dayKey = _dayKey(deliveredAt);
      final netIncome = _calculateRiderNetShippingIncome(data);
      final existing = summaries[dayKey];
      if (existing == null) {
        summaries[dayKey] = _IncomeDaySummary(
          dayKey: dayKey,
          label: _formatDayLabel(deliveredAt),
          deliveredCount: 1,
          netIncomeTotal: netIncome,
        );
      } else {
        summaries[dayKey] = _IncomeDaySummary(
          dayKey: existing.dayKey,
          label: existing.label,
          deliveredCount: existing.deliveredCount + 1,
          netIncomeTotal: existing.netIncomeTotal + netIncome,
        );
      }
    }

    final ordered = summaries.values.toList(growable: false)
      ..sort((a, b) => b.dayKey.compareTo(a.dayKey));
    return ordered.take(7).toList(growable: false);
  }

  String _dayKey(DateTime dateTime) {
    final year = dateTime.year.toString();
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatDayLabel(DateTime dateTime) {
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    return '$day/$month/$year';
  }

  double _readShippingFeeAmount(Map<String, dynamic> data) {
    final direct =
        _toDouble(data['shippingFee']) ??
        _toDouble(data['deliveryFee']) ??
        _toDouble(data['deliveryCharge']) ??
        _toDouble(data['shipping']) ??
        0;
    if (direct > 0) {
      return direct;
    }

    final subtotal =
        _toDouble(data['subtotal']) ?? _toDouble(data['totalPrice']) ?? 0;
    final grandTotal = _toDouble(data['grandTotal']) ?? subtotal;
    final delta = grandTotal - subtotal;
    if (delta > 0) {
      return delta;
    }

    return 0;
  }

  Future<void> _loadReadyStatuses() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Subscribe to riders/{uid} so the toggle UI always mirrors Firestore.
    // If anything else (admin tool, another device, Cloud Function) writes to
    // this doc, the home screen will reflect the change immediately.
    await _riderDocSubscription?.cancel();
    _riderDocSubscription = FirebaseFirestore.instance
        .collection('riders')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snap) {
            if (!mounted) return;
            final data = snap.data();
            final newOnline = (data?['onlineReady'] as bool?) ?? false;
            final newPassenger = (data?['passengerReady'] as bool?) ?? false;
            if (newOnline == _isOnlineReady &&
                newPassenger == _isPassengerReady) {
              return;
            }
            debugPrint(
              '[van3:ready-stream] uid=${user.uid} online=$newOnline '
              'passenger=$newPassenger',
            );
            setState(() {
              _isOnlineReady = newOnline;
              _isPassengerReady = newPassenger;
            });

            if (_hasAnyReadyMode) {
              unawaited(_startRealtimeLocationUpdates(user.uid));
            } else {
              unawaited(_stopRealtimeLocationUpdates());
            }
          },
          onError: (Object error) {
            debugPrint('[van3:ready-stream] error: $error');
          },
        );
  }

  Future<void> _ensureLocationReadyOnEntry() async {
    if (_isPromptingLocation || !mounted) return;
    _isPromptingLocation = true;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      var permission = await Geolocator.checkPermission();

      final hasPermission =
          permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;

      if (serviceEnabled && hasPermission) {
        return;
      }

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (!mounted) return;

      final permissionStillBlocked =
          permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever;
      final serviceStillOff = !await Geolocator.isLocationServiceEnabled();

      if (permissionStillBlocked || serviceStillOff) {
        await _showLocationEnableDialog(
          needService: serviceStillOff,
          deniedForever: permission == LocationPermission.deniedForever,
        );
      }
    } finally {
      _isPromptingLocation = false;
    }
  }

  Future<void> _showLocationEnableDialog({
    required bool needService,
    required bool deniedForever,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('เปิดการใช้งานตำแหน่ง'),
          content: Text(
            deniedForever
                ? 'กรุณาเปิดสิทธิ์ตำแหน่งในตั้งค่าแอป เพื่อให้ระบบอัปเดตพิกัดไรเดอร์ได้'
                : (needService
                      ? 'กรุณาเปิด GPS/Location ของเครื่อง เพื่อให้ระบบดึงพิกัดได้'
                      : 'กรุณาอนุญาตสิทธิ์ตำแหน่ง เพื่อให้ระบบดึงพิกัดได้'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ภายหลัง'),
            ),
            FilledButton(
              onPressed: () async {
                if (deniedForever) {
                  await Geolocator.openAppSettings();
                } else if (needService) {
                  await Geolocator.openLocationSettings();
                } else {
                  await Geolocator.requestPermission();
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('เปิดตอนนี้'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _setOnlineReady(bool value) async {
    await _setReadyMode(
      value: value,
      isPassengerMode: false,
      enabledMessage: 'เปิดรับงานส่งของแล้ว',
      disabledMessage: _isPassengerReady
          ? 'ปิดรับงานส่งของแล้ว แต่ยังเปิดรับผู้โดยสารอยู่'
          : 'ปิดรับงานส่งของแล้ว',
    );
  }

  Future<void> _setPassengerReady(bool value) async {
    await _setReadyMode(
      value: value,
      isPassengerMode: true,
      enabledMessage: 'เปิดรับงานผู้โดยสารแล้ว',
      disabledMessage: _isOnlineReady
          ? 'ปิดรับงานผู้โดยสารแล้ว แต่ยังเปิดรับส่งของอยู่'
          : 'ปิดรับงานผู้โดยสารแล้ว',
    );
  }

  Future<void> _setReadyMode({
    required bool value,
    required bool isPassengerMode,
    required String enabledMessage,
    required String disabledMessage,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('ไม่พบผู้ใช้ กรุณาเข้าสู่ระบบใหม่');
      return;
    }

    setState(() {
      if (isPassengerMode) {
        _isSettingPassengerReady = true;
      } else {
        _isSettingOnline = true;
      }
    });
    try {
      // ----- Turning ON: enforce GPS first ---------------------------------
      if (value) {
        final ok = await _ensureGpsReadyForToggle();
        if (!ok) {
          _showSnack('กรุณาเปิด GPS และอนุญาตสิทธิ์ตำแหน่งก่อนเปิดรับงาน');
          return;
        }
      }

      final targetOnlineReady = isPassengerMode ? _isOnlineReady : value;
      final targetPassengerReady = isPassengerMode ? value : _isPassengerReady;
      final targetHasAnyReadyMode = targetOnlineReady || targetPassengerReady;

      // ----- Build the Firestore payload -----------------------------------
      // The key fields (onlineReady / passengerReady) are ALWAYS written so
      // turning the toggle off reliably reaches the database, even if any
      // optional step (GPS read, location stream, etc.) later throws.
      final payload = <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'onlineReady': targetOnlineReady,
        'passengerReady': targetPassengerReady,
        'locationStreaming': targetHasAnyReadyMode,
        'readyUpdatedAt': FieldValue.serverTimestamp(),
        'readyUpdateSource': isPassengerMode
            ? 'passenger_ready_toggle'
            : 'ready_toggle',
        'locationCapturedAt': FieldValue.delete(),
        'updatedAt': FieldValue.delete(),
      };

      if (value) {
        Position? position = await _getFreshCurrentPosition(
          maxAgeSeconds: _maxFreshPositionAgeSeconds,
        ).catchError((_) => null);
        position ??= await Geolocator.getLastKnownPosition().catchError(
          (_) => null,
        );

        if (position != null) {
          payload.addAll(_positionPayload(position));
          payload['locationUpdatedAt'] = FieldValue.serverTimestamp();
          payload['locationStatus'] = 'streaming';
        } else {
          payload['locationStatus'] = 'waiting_for_fix';
        }
        payload['locationSource'] = isPassengerMode
            ? 'passenger_ready_toggle'
            : 'ready_toggle';
      } else if (targetHasAnyReadyMode) {
        payload['locationStatus'] = 'streaming';
      } else {
        payload['locationStatus'] = 'offline';
      }

      // ----- Write to Firestore (this is the SINGLE source of truth) -------
      debugPrint(
        '[van3:ready-toggle] uid=${user.uid} onlineReady=$targetOnlineReady '
        'passengerReady=$targetPassengerReady (was online=$_isOnlineReady, '
        'passenger=$_isPassengerReady)',
      );
      try {
        await FirebaseFirestore.instance
            .collection('riders')
            .doc(user.uid)
            .set(payload, SetOptions(merge: true));
        debugPrint(
          '[van3:ready-toggle] WRITE OK riders/${user.uid} onlineReady=$targetOnlineReady',
        );
      } catch (e, st) {
        debugPrint('[van3:ready-toggle] WRITE FAILED: $e\n$st');
        _showSnack('บันทึกสถานะลง Firestore ไม่สำเร็จ: $e');
        return; // Do NOT update local UI state if the write failed.
      }

      if (!mounted) return;
      setState(() {
        _isOnlineReady = targetOnlineReady;
        _isPassengerReady = targetPassengerReady;
      });
      if (value) {
        _showSnack('$enabledMessage และบันทึกพิกัดลงระบบแล้ว');
      } else {
        _showSnack(disabledMessage);
        // Best-effort release of pending orders the rider can no longer take.
        unawaited(
          _releasePendingOrdersForMode(
            uid: user.uid,
            isPassengerMode: isPassengerMode,
          ),
        );
      }

      if (targetHasAnyReadyMode) {
        try {
          await _startRealtimeLocationUpdates(user.uid);
        } catch (_) {
          if (mounted) {
            _showSnack(
              'เปิดสถานะรับงานแล้ว แต่เริ่มอัปเดตพิกัดเรียลไทม์ไม่สำเร็จ',
            );
          }
        }
      } else {
        await _stopRealtimeLocationUpdates();
      }
    } catch (e) {
      _showSnack('ไม่สามารถตั้งค่าออนไลน์ได้: $e');
    } finally {
      if (mounted) {
        setState(() {
          if (isPassengerMode) {
            _isSettingPassengerReady = false;
          } else {
            _isSettingOnline = false;
          }
        });
      }
    }
  }

  Future<void> _startRealtimeLocationUpdates(String uid) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return;
    }

    await _positionSubscription?.cancel();
    _locationHeartbeatTimer?.cancel();
    _positionSubscription = null;
    _locationHeartbeatTimer = null;

    // ลดการอัพเดทพิกัดให้เหลือแค่ตอนจำเป็น:
    //   - ครั้งแรกตอน toggle online (ที่นี่)
    //   - ตอน action ของออเดอร์ (accept/pickup/start delivering/deliver)
    // ไม่มี position stream / heartbeat แบบเดิมอีกต่อไป
    await _pushCurrentLocationTick(uid, source: 'initial');
  }

  Future<void> _stopRealtimeLocationUpdates() async {
    await _positionSubscription?.cancel();
    _locationHeartbeatTimer?.cancel();
    _positionSubscription = null;
    _locationHeartbeatTimer = null;
  }

  /// Ensures GPS service + permission are granted before toggling ready on.
  /// Prompts the user to open Location settings or grant permission. Returns
  /// true only when both service and permission are ready.
  Future<bool> _ensureGpsReadyForToggle() async {
    var serviceEnabled = await Geolocator.isLocationServiceEnabled();
    var permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!mounted) return false;

    final permissionBlocked =
        permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever;

    if (!serviceEnabled || permissionBlocked) {
      await _showLocationEnableDialog(
        needService: !serviceEnabled,
        deniedForever: permission == LocationPermission.deniedForever,
      );
      // Re-check after the user returns from settings.
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      permission = await Geolocator.checkPermission();
    }

    final hasPermission =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
    return serviceEnabled && hasPermission;
  }

  /// Release pending orders the rider was assigned to but is no longer ready
  /// for. Clears `driverId` and flags `needsReassign=true` so the customer
  /// app or a Cloud Function can hand the job to another rider.
  Future<void> _releasePendingOrdersForMode({
    required String uid,
    required bool isPassengerMode,
  }) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('orders')
          .where('driverId', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .get();
      if (snapshot.docs.isEmpty) return;

      final batch = FirebaseFirestore.instance.batch();
      var releasedCount = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final orderType = (data['orderType'] as String?)?.trim();
        final serviceType = (data['serviceType'] as String?)?.trim();
        final isTravel = orderType == 'travel_passenger' ||
            serviceType == 'travel_passenger';
        // Only release orders that match the mode we just closed.
        if (isTravel != isPassengerMode) continue;

        batch.update(doc.reference, <String, dynamic>{
          'driverId': null,
          'previousDriverId': uid,
          'needsReassign': true,
          'reassignReason': 'rider_closed_ready',
          'status': 'awaiting_rider',
          'riderNotifyReady': false,
          'reassignRequestedAt': FieldValue.serverTimestamp(),
        });
        releasedCount++;
      }
      if (releasedCount > 0) {
        await batch.commit();
        debugPrint(
          '[van3:release] released $releasedCount pending order(s) on close',
        );
      }
    } catch (e) {
      debugPrint('[van3:release] error releasing pending orders: $e');
    }
  }

  Map<String, dynamic> _positionPayload(Position position) {
    return {
      'currentLocation': GeoPoint(position.latitude, position.longitude),
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'speed': position.speed,
      'heading': position.heading,
    };
  }

  Future<void> _pushCurrentLocationTick(
    String uid, {
    required String source,
  }) async {
    try {
      final position = await _getFreshCurrentPosition(
        maxAgeSeconds: _maxFreshPositionAgeSeconds,
      );
      if (position == null) return;

      // Use the CURRENT ready flags — never force them on. Otherwise this
      // heartbeat-style write would clobber the user's "close" toggle.
      await _writeRiderLocationSnapshot(
        uid: uid,
        position: position,
        source: source,
      );
    } catch (_) {
      // Ignore heartbeat failures, next tick will retry.
    }
  }

  Future<void> _writeRiderLocationSnapshot({
    required String uid,
    required Position position,
    required String source,
    bool? forceOnlineReady,
    bool? forcePassengerReady,
  }) async {
    final capturedAt = _positionTimestamp(position);
    final ageSeconds = DateTime.now().toUtc().difference(capturedAt).inSeconds;
    final onlineReady = forceOnlineReady ?? _isOnlineReady;
    final passengerReady = forcePassengerReady ?? _isPassengerReady;
    final hasAnyReadyMode = onlineReady || passengerReady;

    await FirebaseFirestore.instance.collection('riders').doc(uid).set({
      'uid': uid,
      ..._positionPayload(position),
      'onlineReady': onlineReady,
      'passengerReady': passengerReady,
      'locationStreaming': hasAnyReadyMode,
      'locationStatus': hasAnyReadyMode ? 'streaming' : 'offline',
      'locationSource': source,
      'locationCapturedAt': FieldValue.delete(),
      'updatedAt': FieldValue.delete(),
      'locationAgeSeconds': ageSeconds < 0 ? 0 : ageSeconds,
      'locationUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Position?> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: _buildLocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 10));
  }

  Future<Position?> _getFreshCurrentPosition({
    required int maxAgeSeconds,
  }) async {
    try {
      final current = await _getCurrentPosition();
      if (current != null &&
          _isFreshPosition(current, maxAgeSeconds: maxAgeSeconds)) {
        return current;
      }
    } catch (_) {
      // Ignore and try stream/last known fallback.
    }

    try {
      final streamed = await Geolocator.getPositionStream(
        locationSettings: _buildLocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 0,
        ),
      ).first.timeout(const Duration(seconds: 8));
      if (_isFreshPosition(streamed, maxAgeSeconds: maxAgeSeconds)) {
        return streamed;
      }
    } catch (_) {
      // Ignore and try last known location.
    }

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null &&
          _isFreshPosition(lastKnown, maxAgeSeconds: maxAgeSeconds)) {
        return lastKnown;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  DateTime _positionTimestamp(Position position) {
    return position.timestamp.toUtc();
  }

  bool _isFreshPosition(Position position, {required int maxAgeSeconds}) {
    final ts = _positionTimestamp(position);
    final age = DateTime.now().toUtc().difference(ts).inSeconds;
    if (age < 0) {
      return true;
    }
    return age <= maxAgeSeconds;
  }

  Future<void> _toggleOnlineReady() async {
    if (_isOnlineReady) {
      await _setOnlineReady(false);
      return;
    }

    if (!_hasLoadedCreditBalance) {
      final ok = await _refreshCreditBalanceOnce();
      if (!ok || !_hasLoadedCreditBalance) {
        _showSnack('ยังโหลดเครดิตไม่ได้ (ตรวจอินเทอร์เน็ต/Firestore)');
        return;
      }
    }

    if (!_hasEnoughCreditToOpenReady) {
      _showCreditRequiredMessage();
      return;
    }

    // _setReadyMode เป็นคนตรวจ GPS + permission + เขียนพิกัด/onlineReady
    // ลงใน Firestore แบบครบในที่เดียว ไม่ต้องทำซ้ำที่นี่
    debugPrint('[van3:ready-toggle] tap OPEN delivery');
    await _setOnlineReady(true);
  }

  Future<void> _togglePassengerReady() async {
    if (_isPassengerReady) {
      await _setPassengerReady(false);
      return;
    }

    if (!_hasLoadedCreditBalance) {
      final ok = await _refreshCreditBalanceOnce();
      if (!ok || !_hasLoadedCreditBalance) {
        _showSnack('ยังโหลดเครดิตไม่ได้ (ตรวจอินเทอร์เน็ต/Firestore)');
        return;
      }
    }

    if (!_hasEnoughCreditToOpenReady) {
      _showCreditRequiredMessage();
      return;
    }

    debugPrint('[van3:ready-toggle] tap OPEN passenger');
    await _setPassengerReady(true);
  }

  void _onActionTap(BuildContext context, _DashboardAction action) {
    if (action.title == 'ออเดอร์ใหม่') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const RiderJobsScreen()));
      return;
    }

    if (action.title == 'ประวัติ ออเดอร์') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const RiderJobsScreen(showHistory: true),
        ),
      );
      return;
    }

    if (action.title == 'รายได้วันนี้') {
      _showTodayIncomeSummarySheet(context);
      return;
    }

    if (action.title == 'กระเป๋าเงิน') {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const WalletScreen()));
      return;
    }

    if (action.title == 'ตั้งค่า') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RiderSettingsScreen()),
      );
      return;
    }

    if (action.title == 'พร้อมรับงาน') {
      _toggleOnlineReady();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('เมนู "${action.title}" พร้อมแล้ว รอเชื่อมต่อระบบถัดไป'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  void _showCreditRequiredMessage() {
    _showSnack(
      'เครดิตต้องไม่ต่ำกว่า 500 บาท จึงจะเปิดรับงานได้ เพื่อป้องกันการส่งของให้ถึงมือลูกค้า',
    );
  }

  void _syncCreditBalance(double creditTotal) {
    if ((_currentCreditBalance ?? -1) == creditTotal) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _currentCreditBalance = creditTotal);

      if (creditTotal > _lowCreditWarningCredit) {
        _hasShownLowCreditWarning = false;
        return;
      }

      if (creditTotal >= _minimumReadyCredit && !_hasShownLowCreditWarning) {
        _hasShownLowCreditWarning = true;
        _showLowCreditWarningDialog();
      }
    });
  }

  Future<bool> _refreshCreditBalanceOnce() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return false;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('credits')
          .where('uid', isEqualTo: uid)
          .get();

      var total = 0.0;
      for (final doc in snapshot.docs) {
        final amount = doc.data()['amount'];
        if (amount is num) {
          total += amount.toDouble();
        }
      }

      if (!mounted) return false;
      setState(() => _currentCreditBalance = total);
      debugPrint('[van3:credit] refreshed creditTotal=$total');
      return true;
    } catch (e) {
      debugPrint('[van3:credit] refresh failed: $e');
      return false;
    }
  }

  Future<void> _showLowCreditWarningDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('เครดิตใกล้ถึงขั้นต่ำ'),
          content: const Text(
            'เครดิตของคุณใกล้ต่ำกว่า 500 บาท หากต่ำกว่า 500 บาท จะไม่สามารถเปิดรับงานได้ เพื่อป้องกันการส่งของให้ถึงมือลูกค้า',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('ปิด'),
            ),
          ],
        );
      },
    );
  }

  Color _creditProgressColor(double creditTotal) {
    if (creditTotal >= _healthyCreditTarget) {
      return const Color(0xFF22C55E);
    }
    if (creditTotal <= 1000) {
      return const Color(0xFFEF4444);
    }
    return const Color(0xFFF59E0B);
  }

  String _creditLevelLabel(double creditTotal) {
    if (creditTotal >= _healthyCreditTarget) {
      return 'ระดับ 4 พร้อมรับงาน';
    }
    if (creditTotal >= 2000) {
      return 'ระดับ 3';
    }
    if (creditTotal > 1000) {
      return 'ระดับ 2';
    }
    if (creditTotal >= _minimumReadyCredit) {
      return 'ระดับ 1 ใกล้ขั้นต่ำ';
    }
    return 'ต่ำกว่าขั้นต่ำ';
  }

  Future<void> _showTodayIncomeSummarySheet(BuildContext context) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      _showSnack('ไม่พบบัญชีที่ล็อกอิน');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .where('driverId', isEqualTo: currentUid)
                  .snapshots(),
              builder: (context, snapshot) {
                final docs =
                    snapshot.data?.docs ??
                    const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                var deliveredTodayCount = 0;
                var netIncomeToday = 0.0;
                final last7Days = _buildLast7DayIncomeSummaries(docs);

                for (final doc in docs) {
                  final data = doc.data();
                  final status = (data['status'] as String?)?.trim() ?? '';
                  if (status != 'delivered' || !_isDeliveredToday(data)) {
                    continue;
                  }
                  deliveredTodayCount += 1;
                  netIncomeToday += _calculateRiderNetShippingIncome(data);
                }

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'รายได้วันนี้',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'สรุปจากงานที่ส่งสำเร็จวันนี้และใช้ข้อมูลที่บันทึกตอนปิดงาน',
                      style: TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'รายได้สุทธิรวมวันนี้',
                            style: TextStyle(
                              color: Color(0xFF9A3412),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'THB ${netIncomeToday.toStringAsFixed(1)}',
                            style: const TextStyle(
                              color: Color(0xFF7C2D12),
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.fact_check_rounded,
                            color: Color(0xFF0F172A),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'ส่งสำเร็จวันนี้ $deliveredTodayCount งาน',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'สรุป 7 วันล่าสุด',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (last7Days.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Text(
                          'ยังไม่มีข้อมูลรายได้ย้อนหลัง 7 วันล่าสุด',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                          ),
                        ),
                      )
                    else
                      ...last7Days.map(
                        (summary) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        summary.label,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF111827),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'ส่งสำเร็จ ${summary.deliveredCount} งาน',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF6B7280),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  'THB ${summary.netIncomeTotal.toStringAsFixed(1)}',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF9A3412),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '-';
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final dashboardActions = _dashboardActions;
    final bottomBarActions = _bottomBarActions;
    return Scaffold(
      bottomNavigationBar: _buildBottomActionBar(context, bottomBarActions),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF9F1C), Color(0xFFFF6B00), Color(0xFFFF5A00)],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.30),
                          ),
                        ),
                        child: const Icon(
                          Icons.delivery_dining_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Van3 Rider Dashboard',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'พร้อมลุยงานจัดส่งวันนี้',
                              style: TextStyle(
                                color: Color(0xFFFFF0DF),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _RiderProfileAvatarButton(
                        uid: currentUid,
                        fallbackEmail: email,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const RiderSettingsScreen(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      color: Colors.white.withValues(alpha: 0.14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.verified_user_rounded,
                              color: Colors.white,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'บัญชีที่ล็อกอิน',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          email,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: currentUid == null
                              ? null
                              : FirebaseFirestore.instance
                                    .collection('orders')
                                    .where('driverId', isEqualTo: currentUid)
                                    .snapshots(),
                          builder: (context, snapshot) {
                            final docs =
                                snapshot.data?.docs ??
                                const <
                                  QueryDocumentSnapshot<Map<String, dynamic>>
                                >[];
                            var acceptedCount = 0;
                            var deliveringCount = 0;
                            var deliveredCount = 0;
                            var riderNetIncome = 0.0;

                            for (final doc in docs) {
                              final data = doc.data();
                              final status =
                                  (data['status'] as String?)?.trim() ?? '';
                              if (status == 'accepted' || status == 'ready') {
                                acceptedCount += 1;
                              } else if (status == 'delivering') {
                                deliveringCount += 1;
                              } else if (status == 'delivered') {
                                deliveredCount += 1;
                                if (_isDeliveredToday(data)) {
                                  riderNetIncome +=
                                      _calculateRiderNetShippingIncome(data);
                                }
                              }
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.20,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'รายได้ค่าส่งสุทธิของไรเดอร์วันนี้',
                                        style: TextStyle(
                                          color: Color(0xFFFFF0DF),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'THB ${riderNetIncome.toStringAsFixed(1)}',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      const Text(
                                        'ใช้ข้อมูลที่บันทึกตอนส่งสำเร็จ หัก 15%',
                                        style: TextStyle(
                                          color: Color(0xFFFFF0DF),
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                StreamBuilder<
                                  QuerySnapshot<Map<String, dynamic>>
                                >(
                                  stream: currentUid == null
                                      ? null
                                      : FirebaseFirestore.instance
                                            .collection('credits')
                                            .where('uid', isEqualTo: currentUid)
                                            .snapshots(),
                                  builder: (context, creditSnapshot) {
                                    final creditDocs =
                                        creditSnapshot.data?.docs ??
                                        const <
                                          QueryDocumentSnapshot<
                                            Map<String, dynamic>
                                          >
                                        >[];
                                    var creditTotal = 0.0;
                                    for (final creditDoc in creditDocs) {
                                      final data = creditDoc.data();
                                      final amount = data['amount'];
                                      if (amount is num) {
                                        creditTotal += amount.toDouble();
                                      }
                                    }
                                    _syncCreditBalance(creditTotal);
                                    final creditColor = _creditProgressColor(
                                      creditTotal,
                                    );
                                    final creditProgress =
                                        (creditTotal / _healthyCreditTarget)
                                            .clamp(0.0, 1.0)
                                            .toDouble();

                                    return Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.14,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.20,
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const Text(
                                                      'เครดิตไรเดอร์คงเหลือ',
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFFFFF0DF,
                                                        ),
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'THB ${creditTotal.toStringAsFixed(2)}',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 20,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              FilledButton.icon(
                                                onPressed: () =>
                                                    Navigator.of(context).push(
                                                      MaterialPageRoute<void>(
                                                        builder: (_) =>
                                                            const WalletScreen(),
                                                      ),
                                                    ),
                                                style: FilledButton.styleFrom(
                                                  backgroundColor: Colors.white,
                                                  foregroundColor: const Color(
                                                    0xFFE86D00,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 10,
                                                      ),
                                                ),
                                                icon: const Icon(
                                                  Icons.add_card_rounded,
                                                  size: 18,
                                                ),
                                                label: const Text(
                                                  'เติมเครดิต',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            child: LinearProgressIndicator(
                                              value: creditProgress,
                                              minHeight: 9,
                                              backgroundColor: Colors.white
                                                  .withValues(alpha: 0.38),
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                    creditColor,
                                                  ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              const Text(
                                                '0',
                                                style: TextStyle(
                                                  color: Color(0xFFFFF0DF),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  _creditLevelLabel(
                                                    creditTotal,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: creditColor,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                                ),
                                              ),
                                              const Text(
                                                '3000',
                                                style: TextStyle(
                                                  color: Color(0xFFFFF0DF),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (creditTotal <
                                              _minimumReadyCredit) ...[
                                            const SizedBox(height: 6),
                                            const Text(
                                              'เครดิตต่ำกว่า 500 บาท ปุ่มรับงานจะเปิดไม่ได้',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    _miniStat(
                                      'งานที่รับแล้ว',
                                      '$acceptedCount',
                                    ),
                                    const SizedBox(width: 10),
                                    _miniStat('กำลังส่ง', '$deliveringCount'),
                                    const SizedBox(width: 10),
                                    _miniStat('ส่งสำเร็จ', '$deliveredCount'),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed:
                                    _isSettingOnline ||
                                        (!_isOnlineReady &&
                                      _hasLoadedCreditBalance &&
                                      !_hasEnoughCreditToOpenReady)
                                    ? null
                                    : _toggleOnlineReady,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isOnlineReady
                                      ? const Color(0xFF2ECC71)
                                      : Colors.white,
                                  foregroundColor: _isOnlineReady
                                      ? Colors.white
                                      : const Color(0xFFE86D00),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                                icon: _isSettingOnline
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _isOnlineReady
                                              ? Colors.white
                                              : const Color(0xFFE86D00),
                                        ),
                                      )
                                    : Icon(
                                        _isOnlineReady
                                            ? Icons.local_shipping_rounded
                                            : Icons.inventory_2_outlined,
                                      ),
                                label: Text(
                                  _isOnlineReady ? 'รับส่งของ' : 'ปิดส่งของ',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed:
                                    _isSettingPassengerReady ||
                                        (!_isPassengerReady &&
                                      _hasLoadedCreditBalance &&
                                      !_hasEnoughCreditToOpenReady)
                                    ? null
                                    : _togglePassengerReady,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _isPassengerReady
                                      ? const Color(0xFF3B82F6)
                                      : Colors.white,
                                  foregroundColor: _isPassengerReady
                                      ? Colors.white
                                      : const Color(0xFF1D4ED8),
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                                icon: _isSettingPassengerReady
                                    ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: _isPassengerReady
                                              ? Colors.white
                                              : const Color(0xFF1D4ED8),
                                        ),
                                      )
                                    : Icon(
                                        _isPassengerReady
                                            ? Icons
                                                  .directions_car_filled_rounded
                                            : Icons.person_pin_circle_outlined,
                                      ),
                                label: Text(
                                  _isPassengerReady
                                      ? 'รับผู้โดยสาร'
                                      : 'ปิดรับผู้โดยสาร',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _hasAnyReadyMode
                              ? 'พิกัดไรเดอร์กำลังอัปเดตแบบเรียลไทม์สำหรับงานที่เปิดรับอยู่'
                              : 'พิกัดจะเริ่มอัปเดตเมื่อกดเปิดรับส่งของหรือรับผู้โดยสาร',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          !_hasLoadedCreditBalance
                              ? 'กำลังโหลดเครดิต...'
                              : !_hasEnoughCreditToOpenReady
                              ? 'เครดิตต่ำกว่า 500 บาท ไม่สามารถเปิดรับงานได้'
                              : 'ส่งของ: ${_isOnlineReady ? 'เปิดรับ' : 'ปิดรับ'} | ผู้โดยสาร: ${_isPassengerReady ? 'เปิดรับ' : 'ปิดรับ'}',
                          style: const TextStyle(
                            color: Color(0xFFFFF0DF),
                            fontWeight: FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.1,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final action = dashboardActions[index];
                    final isHighContrastAction =
                        action.title == 'ออเดอร์ใหม่' ||
                        action.title == 'ประวัติ ออเดอร์';
                    final hideSubtitle = isHighContrastAction;
                    final iconColor = isHighContrastAction
                        ? Colors.black
                        : action.color;
                    return InkWell(
                      onTap: () => _onActionTap(context, action),
                      borderRadius: BorderRadius.circular(20),
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: action.color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Center(
                                      child: Icon(
                                        action.icon,
                                        color: iconColor,
                                        size: 25,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                action.title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF2D2D2D),
                                ),
                              ),
                              if (!hideSubtitle) ...[
                                const SizedBox(height: 2),
                                Text(
                                  action.subtitle,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF7A7A7A),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  }, childCount: dashboardActions.length),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(
    BuildContext context,
    List<_DashboardAction> actions,
  ) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, -4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
        child: Row(
          children: [
            for (final action in actions)
              Expanded(
                child: InkWell(
                  onTap: () => _onActionTap(context, action),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: action.color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Center(
                            child: Icon(
                              action.icon,
                              color: action.color,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          action.title,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2D2D2D),
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.18),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFFFFF0DF)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DashboardAction {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _DashboardAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class _RiderProfileAvatarButton extends StatelessWidget {
  const _RiderProfileAvatarButton({
    required this.uid,
    required this.fallbackEmail,
    required this.onTap,
  });

  final String? uid;
  final String fallbackEmail;
  final VoidCallback onTap;

  String? _readTrimmedString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  String? _photoUrlFromData(Map<String, dynamic>? data) {
    return _readTrimmedString(
      data?['photoUrl'] ??
          data?['imageUrl'] ??
          data?['profileImageUrl'] ??
          data?['riderImageUrl'] ??
          data?['avatarUrl'],
    );
  }

  String _initialFromText(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return 'R';
    }
    return trimmed.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (uid == null || uid!.isEmpty) {
      return _AvatarButtonShell(
        photoUrl: _readTrimmedString(
          FirebaseAuth.instance.currentUser?.photoURL,
        ),
        initial: _initialFromText(fallbackEmail),
        onTap: onTap,
      );
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('riders')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        final user = FirebaseAuth.instance.currentUser;
        final data = snapshot.data?.data();
        final name =
            _readTrimmedString(data?['displayName']) ??
            _readTrimmedString(data?['name']) ??
            _readTrimmedString(data?['riderName']) ??
            _readTrimmedString(user?.displayName) ??
            fallbackEmail;

        return _AvatarButtonShell(
          photoUrl:
              _photoUrlFromData(data) ?? _readTrimmedString(user?.photoURL),
          initial: _initialFromText(name),
          onTap: onTap,
        );
      },
    );
  }
}

class _AvatarButtonShell extends StatelessWidget {
  const _AvatarButtonShell({
    required this.photoUrl,
    required this.initial,
    required this.onTap,
  });

  final String? photoUrl;
  final String initial;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'ตั้งค่า',
      child: Material(
        color: Colors.white.withValues(alpha: 0.18),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.82),
                width: 2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: photoUrl == null
                ? _AvatarInitial(initial: initial)
                : Image.network(
                    photoUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _AvatarInitial(initial: initial);
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _AvatarInitial extends StatelessWidget {
  const _AvatarInitial({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Color(0xFFFF6B00),
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _IncomeDaySummary {
  const _IncomeDaySummary({
    required this.dayKey,
    required this.label,
    required this.deliveredCount,
    required this.netIncomeTotal,
  });

  final String dayKey;
  final String label;
  final int deliveredCount;
  final double netIncomeTotal;
}
