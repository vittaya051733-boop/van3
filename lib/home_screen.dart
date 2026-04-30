import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'rider_jobs_screen.dart';
import 'rider_chat_room_screen.dart';
import 'rider_location_permission_screen.dart';
import 'services/fcm_token_sync_service.dart';
import 'utils/contact_phone_resolver.dart';
import 'utils/order_call_launcher.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _maxFreshPositionAgeSeconds = 45;
  static const String _seenOrderIdsPrefsKey = 'van3_seen_pending_order_ids';
  static const int _maxPersistedSeenOrderIds = 200;
  static const List<String> _registrationCollections = <String>[
    'market_registrations',
    'shop_registrations',
    'restaurant_registrations',
    'pharmacy_registrations',
    'other_registrations',
  ];

  bool _isSettingOnline = false;
  bool _isOnlineReady = false;
  bool _isPromptingLocation = false;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _locationHeartbeatTimer;

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

    return LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
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
    _loadOnlineReadyStatus();
    unawaited(_initializeNewJobListener());
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _locationHeartbeatTimer?.cancel();
    _newJobSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeNewJobListener() async {
    await _restoreSeenPendingOrderIds();
    _startNewJobListener();
  }

  Future<void> _restoreSeenPendingOrderIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storedIds = prefs.getStringList(_seenOrderIdsPrefsKey) ?? const <String>[];
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
          debugPrint('[van3:new-job] ignore stale order id=${doc.id} code=${data['orderCode']}');
          _seenPendingOrderIds.add(doc.id);
          unawaited(_persistSeenPendingOrderIds());
          continue;
        }

        if (_seenPendingOrderIds.add(doc.id)) {
          unawaited(_persistSeenPendingOrderIds());
          debugPrint('[van3:new-job] notify order id=${doc.id} code=${data['orderCode']}');
        }
      }
    });
  }

  bool _shouldShowOrderToRider(Map<String, dynamic> data) {
    final sourceApp = (data['sourceApp'] as String?)?.trim();
    if (sourceApp != 'van2_customer') {
      return false;
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
      if (createdSource != 'cod_confirm_dialog') {
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

  Future<void> _showIncomingOrderDialog({
    required String orderId,
    required Map<String, dynamic> data,
  }) async {
    if (!mounted) return;

    final orderCode = (data['orderCode'] as String?)?.trim();
    final shopName = (data['shopName'] as String?)?.trim();
    final total = (data['grandTotal'] as num?) ?? (data['totalPrice'] as num?) ?? 0;
    final shippingFee = await _resolveShippingFee(data);
    final customerUid = _readCustomerUid(data);
    final shopOwnerUid = _readShopOwnerUid(data);
    final customerPhone = await ContactPhoneResolver.resolveCustomerPhone(
      orderData: data,
      customerUid: customerUid,
    );
    final riderToShopDistanceKm = await _resolveRiderToShopDistanceKm(data);
    final destinationCoords = _readDestinationCoordinates(data);
    final shopPhone = await ContactPhoneResolver.resolveShopPhone(
      orderData: data,
      ownerUid: shopOwnerUid,
      registrationCollections: _registrationCollections,
    );
    if (!mounted) return;

    String destination = '-';
    final delivery = data['deliverySnapshot'];
    if (delivery is Map<String, dynamic>) {
      final label = (delivery['locationLabel'] as String?)?.trim();
      if (label != null && label.isNotEmpty) {
        destination = label;
      }
    }

    if (destination == '-') {
      final customer = data['customerLocation'];
      if (customer is Map<String, dynamic>) {
        final label = (customer['label'] as String?)?.trim();
        if (label != null && label.isNotEmpty) {
          destination = label;
        }
      }
    }

    final action = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('มีคำสั่งซื้อใหม่'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(orderCode?.isNotEmpty == true ? 'Order: $orderCode' : 'Order: $orderId'),
              const SizedBox(height: 4),
              Text('ร้าน: ${shopName?.isNotEmpty == true ? shopName : '-'}'),
              const SizedBox(height: 4),
              Text(
                riderToShopDistanceKm == null
                    ? 'ระยะทางถึงร้าน: -'
                    : 'ระยะทางถึงร้าน: ${_formatDistanceFromKm(riderToShopDistanceKm)}',
              ),
              const SizedBox(height: 4),
              Text('ปลายทาง: $destination'),
              if (destinationCoords != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await _openDestinationMap(
                      destinationCoords['lat']!,
                      destinationCoords['lng']!,
                    );
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('เปิดแผนที่ปลายทาง'),
                ),
              ],
              const SizedBox(height: 4),
              Text('ค่าส่ง: THB ${shippingFee.toStringAsFixed(1)}'),
              if (customerPhone != null || shopPhone != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: customerUid == null
                            ? null
                            : () async {
                                await OrderCallLauncher.startVoiceCall(
                                  context: dialogContext,
                                  peerUid: customerUid,
                                  peerLabel: OrderCallLauncher.readCustomerLabel(data),
                                  orderData: data,
                                  phoneNumber: customerPhone,
                                  photoUrl: OrderCallLauncher.readCustomerPhotoUrl(data),
                                );
                              },
                        icon: const Icon(Icons.phone_in_talk_outlined),
                        label: const Text('โทรลูกค้า'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: shopOwnerUid == null
                            ? null
                            : () async {
                                await OrderCallLauncher.startVoiceCall(
                                  context: dialogContext,
                                  peerUid: shopOwnerUid,
                                  peerLabel: OrderCallLauncher.readShopLabel(data),
                                  orderData: data,
                                  phoneNumber: shopPhone,
                                  photoUrl: OrderCallLauncher.readShopPhotoUrl(data),
                                );
                              },
                        icon: const Icon(Icons.support_agent_rounded),
                        label: const Text('โทรร้านค้า'),
                      ),
                    ),
                  ],
                ),
              ],
              if (customerUid != null || shopOwnerUid != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: customerUid == null
                            ? null
                            : () async {
                                await Navigator.of(dialogContext).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => RiderChatRoomScreen(
                                      peerUid: customerUid,
                                      peerLabel: 'ลูกค้า',
                                      orderId: orderId,
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: const Text('แชตลูกค้า'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: shopOwnerUid == null
                            ? null
                            : () async {
                                await Navigator.of(dialogContext).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => RiderChatRoomScreen(
                                      peerUid: shopOwnerUid,
                                      peerLabel: 'ร้านค้า',
                                      orderId: orderId,
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.storefront_outlined),
                        label: const Text('แชตร้านค้า'),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Text('ยอดรวม: THB ${total.toStringAsFixed(1)}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('reject'),
              child: const Text('ไม่รับงาน'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop('accept'),
              child: const Text('รับงาน'),
            ),
          ],
        );
      },
    );

    if (!mounted || action == null) return;

    if (action == 'accept') {
      await _acceptIncomingOrder(orderId);
      return;
    }
    await _rejectIncomingOrder(orderId);
  }

  Future<void> _acceptIncomingOrder(String orderId) async {
    try {
      final orderRef = FirebaseFirestore.instance.collection('orders').doc(orderId);
      final orderSnap = await orderRef.get();
      final data = orderSnap.data() ?? <String, dynamic>{};

      await orderRef.update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _sendOrderAppNotification(
        targetApp: 'van1',
        recipientUid: (data['shopOwnerId'] as String?)?.trim(),
        orderId: orderId,
        title: 'ไรเดอร์รับงานแล้ว',
        body: 'ออเดอร์${(data['orderCode'] as String?)?.trim().isNotEmpty == true ? ' ${(data['orderCode'] as String).trim()}' : ''} มีไรเดอร์รับงานแล้ว',
        action: 'order_accepted',
      );

      _showSnack('รับงานเรียบร้อย');
    } catch (e) {
      _showSnack('รับงานไม่สำเร็จ: $e');
    }
  }

  Future<void> _rejectIncomingOrder(String orderId) async {
    try {
      final orderRef = FirebaseFirestore.instance.collection('orders').doc(orderId);
      final orderSnap = await orderRef.get();
      final data = orderSnap.data() ?? <String, dynamic>{};

      await orderRef.update({
        'status': 'awaiting_rider',
        'statusLabel': 'awaiting_nearest_rider',
        'driverId': null,
        'assignedRiderAt': null,
        'rejectedByDriverAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _sendOrderAppNotification(
        targetApp: 'van2',
        recipientUid: (data['customerId'] as String?)?.trim(),
        orderId: orderId,
        title: 'กำลังหาไรเดอร์ใหม่',
        body: 'ไรเดอร์ปฏิเสธงาน ระบบกำลังค้นหาไรเดอร์ให้ใหม่',
        action: 'order_rejected',
      );

      await _sendOrderAppNotification(
        targetApp: 'van1',
        recipientUid: (data['shopOwnerId'] as String?)?.trim(),
        orderId: orderId,
        title: 'ไรเดอร์ปฏิเสธงาน',
        body: 'ออเดอร์${(data['orderCode'] as String?)?.trim().isNotEmpty == true ? ' ${(data['orderCode'] as String).trim()}' : ''} ไรเดอร์ปฏิเสธงาน ระบบกำลังหาไรเดอร์ใหม่',
        action: 'order_rejected',
      );

      _showSnack('ไม่รับงานแล้ว ระบบจะหาคนขับคนอื่นต่อ');
    } catch (e) {
      _showSnack('อัปเดตสถานะไม่สำเร็จ: $e');
    }
  }

  Map<String, double>? _readDestinationCoordinates(Map<String, dynamic> data) {
    double? lat;
    double? lng;

    final delivery = data['deliverySnapshot'];
    if (delivery is Map<String, dynamic>) {
      lat = _toDouble(delivery['latitude']);
      lng = _toDouble(delivery['longitude']);
    }

    if (lat == null || lng == null) {
      final customer = data['customerLocation'];
      if (customer is Map<String, dynamic>) {
        lat = _toDouble(customer['latitude']);
        lng = _toDouble(customer['longitude']);
      }
    }

    if (lat == null || lng == null) {
      return null;
    }

    return <String, double>{'lat': lat, 'lng': lng};
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

  Future<void> _openDestinationMap(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      _showSnack('ไม่สามารถเปิดแผนที่ได้');
    }
  }

  Future<void> _sendOrderAppNotification({
    required String targetApp,
    required String? recipientUid,
    required String orderId,
    required String title,
    required String body,
    required String action,
  }) async {
    if (recipientUid == null || recipientUid.isEmpty) {
      return;
    }

    await FirebaseFirestore.instance.collection('app_notifications').add({
      'targetApp': targetApp,
      'recipientUid': recipientUid,
      'orderId': orderId,
      'title': title,
      'body': body,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      'source': 'van3_rider',
      'action': action,
    });
  }

  Future<String?> _resolveShopPhone(Map<String, dynamic> data) async {
    final direct = (data['shopPhone'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final ownerUid = (data['shopOwnerId'] as String?)?.trim();
    if (ownerUid == null || ownerUid.isEmpty) {
      return null;
    }

    for (final collection in _registrationCollections) {
      try {
        final doc = await FirebaseFirestore.instance.collection(collection).doc(ownerUid).get();
        if (!doc.exists) continue;

        final map = doc.data();
        final phone = (map?['phone'] as String?)?.trim() ??
            (map?['phoneNumber'] as String?)?.trim() ??
            (map?['contactPhone'] as String?)?.trim();
        if (phone != null && phone.isNotEmpty) {
          return phone;
        }
      } catch (_) {
        // Try next collection.
      }
    }

    return null;
  }

  Future<double?> _resolveRiderToShopDistanceKm(Map<String, dynamic> data) async {
    final riderSearch = data['riderSearch'];
    if (riderSearch is Map<String, dynamic>) {
      final matchedDistanceKm = _toDouble(riderSearch['matchedDistanceKm']);
      if (matchedDistanceKm != null && matchedDistanceKm > 0) {
        return matchedDistanceKm;
      }
    }

    final shopCoords = await _resolveShopCoordinates(data);
    if (shopCoords == null) {
      return null;
    }

    final riderPosition = await _getFreshCurrentPosition(
      maxAgeSeconds: _maxFreshPositionAgeSeconds,
    );
    if (riderPosition == null) {
      return null;
    }

    final meters = Geolocator.distanceBetween(
      riderPosition.latitude,
      riderPosition.longitude,
      shopCoords['lat']!,
      shopCoords['lng']!,
    );

    return meters.isFinite ? meters / 1000 : null;
  }

  Future<Map<String, double>?> _resolveShopCoordinates(Map<String, dynamic> data) async {
    final direct = _readCoordinatesFromAny(data, locationKey: 'shopLocation', latKey: 'shopLatitude', lngKey: 'shopLongitude');
    if (direct != null) {
      return direct;
    }

    final ownerUid = _readShopOwnerUid(data);
    if (ownerUid == null || ownerUid.isEmpty) {
      return null;
    }

    for (final collection in _registrationCollections) {
      try {
        final doc = await FirebaseFirestore.instance.collection(collection).doc(ownerUid).get();
        if (!doc.exists) continue;
        final map = doc.data();
        if (map == null) continue;

        final resolved = _readCoordinatesFromAny(
          map,
          locationKey: 'shopLocation',
          latKey: 'shopLatitude',
          lngKey: 'shopLongitude',
        );
        if (resolved != null) {
          return resolved;
        }
      } catch (_) {
        // Try next collection for resilient coordinate lookup.
      }
    }

    return null;
  }

  Map<String, double>? _readCoordinatesFromAny(
    Map<String, dynamic> data, {
    required String locationKey,
    required String latKey,
    required String lngKey,
  }) {
    final directLat = _toDouble(data[latKey]) ?? _toDouble(data['latitude']) ?? _toDouble(data['lat']);
    final directLng = _toDouble(data[lngKey]) ??
        _toDouble(data['longitude']) ??
        _toDouble(data['lng']) ??
        _toDouble(data['lon']) ??
        _toDouble(data['long']);
    if (directLat != null && directLng != null) {
      return <String, double>{'lat': directLat, 'lng': directLng};
    }

    final location = data[locationKey] ?? data['location'] ?? data['geoPoint'] ?? data['coordinates'];
    if (location is GeoPoint) {
      return <String, double>{'lat': location.latitude, 'lng': location.longitude};
    }
    if (location is Map) {
      final lat = _toDouble(location['latitude']) ?? _toDouble(location['lat']);
      final lng = _toDouble(location['longitude']) ??
          _toDouble(location['lng']) ??
          _toDouble(location['lon']) ??
          _toDouble(location['long']);
      if (lat != null && lng != null) {
        return <String, double>{'lat': lat, 'lng': lng};
      }
    }

    return null;
  }

  Future<double> _resolveShippingFee(Map<String, dynamic> data) async {
    final direct = _toDouble(data['shippingFee']) ??
        _toDouble(data['deliveryFee']) ??
        _toDouble(data['deliveryCharge']) ??
        _toDouble(data['shipping']) ??
        0;
    if (direct > 0) {
      return direct;
    }

    final subtotal = _toDouble(data['subtotal']) ?? _toDouble(data['totalPrice']) ?? 0;
    final grandTotal = _toDouble(data['grandTotal']) ?? subtotal;
    final delta = grandTotal - subtotal;
    if (delta > 0) {
      return delta;
    }

    final shopCoords = await _resolveShopCoordinates(data);
    final customerCoords = _readCustomerCoordinates(data);
    if (shopCoords == null || customerCoords == null) {
      return 0;
    }

    final meters = Geolocator.distanceBetween(
      shopCoords['lat']!,
      shopCoords['lng']!,
      customerCoords['lat']!,
      customerCoords['lng']!,
    );

    final km = meters <= 0 ? 0.0 : meters / 1000.0;
    final billableKm = km < 1 ? 1.0 : km;
    final fee = 25 + ((billableKm - 1) * 12.5);
    return double.parse(fee.toStringAsFixed(2));
  }

  Map<String, double>? _readCustomerCoordinates(Map<String, dynamic> data) {
    final delivery = data['deliverySnapshot'];
    if (delivery is Map<String, dynamic>) {
      final lat = _toDouble(delivery['latitude']) ?? _toDouble(delivery['lat']);
      final lng = _toDouble(delivery['longitude']) ?? _toDouble(delivery['lng']);
      if (lat != null && lng != null) {
        return <String, double>{'lat': lat, 'lng': lng};
      }
    }

    final customer = data['customerLocation'];
    if (customer is Map<String, dynamic>) {
      final lat = _toDouble(customer['latitude']) ?? _toDouble(customer['lat']);
      final lng = _toDouble(customer['longitude']) ?? _toDouble(customer['lng']);
      if (lat != null && lng != null) {
        return <String, double>{'lat': lat, 'lng': lng};
      }
    }

    return null;
  }

  String _formatDistanceFromKm(double km) {
    if (km < 1) {
      return '${(km * 1000).round()} เมตร';
    }
    return '${km.toStringAsFixed(2)} กม.';
  }

  String? _readCustomerPhone(Map<String, dynamic> data) {
    final direct = (data['customerPhone'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final alternatives = <String>[
      (data['customerPhoneNumber'] as String?)?.trim() ?? '',
      (data['phoneNumber'] as String?)?.trim() ?? '',
      (data['phone'] as String?)?.trim() ?? '',
      (data['buyerPhone'] as String?)?.trim() ?? '',
    ];
    for (final value in alternatives) {
      if (value.isNotEmpty) return value;
    }

    final snapshot = data['customerSnapshot'];
    if (snapshot is Map) {
      final fromSnapshot = <String>[
        (snapshot['phoneNumber'] as String?)?.trim() ?? '',
        (snapshot['phone'] as String?)?.trim() ?? '',
        (snapshot['contactPhone'] as String?)?.trim() ?? '',
      ];
      for (final value in fromSnapshot) {
        if (value.isNotEmpty) return value;
      }
    }

    return null;
  }

  String? _readCustomerUid(Map<String, dynamic> data) {
    final direct = (data['customerId'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final alternatives = <String>[
      (data['customerUid'] as String?)?.trim() ?? '',
      (data['buyerId'] as String?)?.trim() ?? '',
      (data['userId'] as String?)?.trim() ?? '',
    ];
    for (final value in alternatives) {
      if (value.isNotEmpty) return value;
    }

    final snapshot = data['customerSnapshot'];
    if (snapshot is Map) {
      final fromSnapshot = <String>[
        (snapshot['uid'] as String?)?.trim() ?? '',
        (snapshot['userId'] as String?)?.trim() ?? '',
        (snapshot['customerId'] as String?)?.trim() ?? '',
      ];
      for (final value in fromSnapshot) {
        if (value.isNotEmpty) return value;
      }
    }

    return null;
  }

  String? _readShopOwnerUid(Map<String, dynamic> data) {
    final direct = (data['shopOwnerId'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final alternatives = <String>[
      (data['shopId'] as String?)?.trim() ?? '',
      (data['merchantId'] as String?)?.trim() ?? '',
      (data['sellerId'] as String?)?.trim() ?? '',
    ];
    for (final value in alternatives) {
      if (value.isNotEmpty) return value;
    }

    final shopSnapshot = data['shopSnapshot'];
    if (shopSnapshot is Map) {
      final fromSnapshot = <String>[
        (shopSnapshot['ownerId'] as String?)?.trim() ?? '',
        (shopSnapshot['shopOwnerId'] as String?)?.trim() ?? '',
        (shopSnapshot['uid'] as String?)?.trim() ?? '',
      ];
      for (final value in fromSnapshot) {
        if (value.isNotEmpty) return value;
      }
    }

    return null;
  }

  Future<void> _loadOnlineReadyStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('riders')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      setState(() {
        _isOnlineReady = (doc.data()?['onlineReady'] as bool?) ?? false;
      });

      if (_isOnlineReady) {
        try {
          await _startRealtimeLocationUpdates(user.uid);
        } catch (_) {
          // Keep app usable even if location stream cannot start at launch.
        }
      } else {
        await _stopRealtimeLocationUpdates();
      }
    } catch (_) {
      // Keep default false if the profile is not available yet.
    }
  }

  Future<void> _ensureLocationReadyOnEntry() async {
    if (_isPromptingLocation || !mounted) return;
    _isPromptingLocation = true;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      var permission = await Geolocator.checkPermission();

      final hasPermission = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;

      if (serviceEnabled && hasPermission) {
        return;
      }

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (!mounted) return;

      final permissionStillBlocked = permission == LocationPermission.denied ||
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('ไม่พบผู้ใช้ กรุณาเข้าสู่ระบบใหม่');
      return;
    }

    setState(() => _isSettingOnline = true);
    try {
      final payload = <String, dynamic>{
        'uid': user.uid,
        'email': user.email,
        'onlineReady': value,
        'locationStreaming': value,
        'locationCapturedAt': FieldValue.delete(),
        'updatedAt': FieldValue.delete(),
      };

      var hasLocation = false;
      String? locationWarning;

      if (value) {
        final position = await _getFreshCurrentPosition(
          maxAgeSeconds: _maxFreshPositionAgeSeconds,
        );
        if (position == null) {
          throw Exception('ไม่พบพิกัดปัจจุบันของไรเดอร์');
        }

        payload.addAll(_positionPayload(position));
        payload['locationUpdatedAt'] = FieldValue.serverTimestamp();
        payload['locationStatus'] = 'streaming';
        payload['locationSource'] = 'ready_toggle';
        hasLocation = true;
      } else {
        payload['locationStatus'] = 'offline';
      }

      await FirebaseFirestore.instance
          .collection('riders')
          .doc(user.uid)
          .set(payload, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _isOnlineReady = value);
      if (value) {
        if (hasLocation) {
          _showSnack('ออนไลน์พร้อมรับงานแล้ว และบันทึกพิกัดลงระบบแล้ว');
        } else {
          _showSnack(locationWarning ?? 'ออนไลน์พร้อมรับงานแล้ว');
        }
      } else {
        _showSnack('ปิดรับงานแล้ว');
      }

      if (value) {
        try {
          await _startRealtimeLocationUpdates(user.uid);
        } catch (_) {
          if (mounted) {
            _showSnack('เปิดรับงานแล้ว แต่เริ่มอัปเดตพิกัดเรียลไทม์ไม่สำเร็จ');
          }
        }
      } else {
        await _stopRealtimeLocationUpdates();
      }
    } catch (e) {
      _showSnack('ไม่สามารถตั้งค่าออนไลน์ได้: $e');
    } finally {
      if (mounted) {
        setState(() => _isSettingOnline = false);
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

    // Push immediately so Firestore gets location fields without waiting for stream tick.
    await _pushCurrentLocationTick(uid, source: 'initial');

    // Heartbeat keeps location fresh even when movement is minimal (common on emulator).
    _locationHeartbeatTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _pushCurrentLocationTick(uid, source: 'heartbeat');
    });

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _buildLocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 0,
      ),
    ).listen((position) async {
      try {
        if (!_isFreshPosition(position, maxAgeSeconds: _maxFreshPositionAgeSeconds)) {
          return;
        }

        await _writeRiderLocationSnapshot(
          uid: uid,
          position: position,
          source: 'stream',
          forceOnlineReady: true,
        );
      } catch (_) {
        // Ignore transient stream write errors, next location tick will retry.
      }
    });
  }

  Future<void> _stopRealtimeLocationUpdates() async {
    await _positionSubscription?.cancel();
    _locationHeartbeatTimer?.cancel();
    _positionSubscription = null;
    _locationHeartbeatTimer = null;
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

  Future<void> _pushCurrentLocationTick(String uid, {required String source}) async {
    try {
      final position = await _getFreshCurrentPosition(
        maxAgeSeconds: _maxFreshPositionAgeSeconds,
      );
      if (position == null) return;

      await _writeRiderLocationSnapshot(
        uid: uid,
        position: position,
        source: source,
        forceOnlineReady: true,
      );
    } catch (_) {
      // Ignore heartbeat failures, next tick will retry.
    }
  }

  Future<void> _writeRiderLocationSnapshot({
    required String uid,
    required Position position,
    required String source,
    bool forceOnlineReady = false,
  }) async {
    final capturedAt = _positionTimestamp(position);
    final ageSeconds = DateTime.now().toUtc().difference(capturedAt).inSeconds;

    await FirebaseFirestore.instance.collection('riders').doc(uid).set({
      'uid': uid,
      ..._positionPayload(position),
      'onlineReady': forceOnlineReady ? true : _isOnlineReady,
      'locationStreaming': true,
      'locationStatus': 'streaming',
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
      locationSettings: _buildLocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    ).timeout(const Duration(seconds: 10));
  }

  Future<Position?> _getFreshCurrentPosition({
    required int maxAgeSeconds,
  }) async {
    try {
      final current = await _getCurrentPosition();
      if (current != null && _isFreshPosition(current, maxAgeSeconds: maxAgeSeconds)) {
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
      if (lastKnown != null && _isFreshPosition(lastKnown, maxAgeSeconds: maxAgeSeconds)) {
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

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('ไม่พบผู้ใช้ กรุณาเข้าสู่ระบบใหม่');
      return;
    }

    final allowed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const RiderLocationPermissionScreen(),
      ),
    );

    if (!mounted || allowed != true) {
      _showSnack('ยังไม่สามารถเปิดพร้อมรับงานได้ เนื่องจากยังไม่ได้สิทธิ์พิกัด');
      return;
    }

    final position = await _getFreshCurrentPosition(
      maxAgeSeconds: _maxFreshPositionAgeSeconds,
    );
    if (position == null) {
      _showSnack('ยังไม่พบพิกัดปัจจุบันของไรเดอร์ กรุณาลองใหม่อีกครั้ง');
      return;
    }

    // Force-write a fresh location snapshot to riders/{uid} before going online.
    try {
      await _writeRiderLocationSnapshot(
        uid: user.uid,
        position: position,
        source: 'permission_gate',
        forceOnlineReady: true,
      );
    } catch (e) {
      _showSnack('บันทึกพิกัดลงระบบไม่สำเร็จ: $e');
      return;
    }

    await _setOnlineReady(true);
  }

  Future<void> _logout(BuildContext context) async {
    await FcmTokenSyncService.instance.clearTokenBeforeLogout();
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
  }

  void _onActionTap(BuildContext context, _DashboardAction action) {
    if (action.title == 'ออเดอร์ใหม่') {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const RiderJobsScreen()),
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
                      IconButton(
                        onPressed: () => _logout(context),
                        icon: const Icon(Icons.logout_rounded, color: Colors.white),
                        tooltip: 'ออกจากระบบ',
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
                      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.verified_user_rounded, color: Colors.white),
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
                            final docs = snapshot.data?.docs ??
                                const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                            var acceptedCount = 0;
                            var deliveringCount = 0;
                            var deliveredCount = 0;

                            for (final doc in docs) {
                              final data = doc.data();
                              final status = (data['status'] as String?)?.trim() ?? '';
                              if (status == 'accepted' || status == 'ready') {
                                acceptedCount += 1;
                              } else if (status == 'delivering') {
                                deliveringCount += 1;
                              } else if (status == 'delivered') {
                                deliveredCount += 1;
                              }
                            }

                            return Row(
                              children: [
                                _miniStat('งานที่รับแล้ว', '$acceptedCount'),
                                const SizedBox(width: 10),
                                _miniStat('กำลังส่ง', '$deliveringCount'),
                                const SizedBox(width: 10),
                                _miniStat('ส่งสำเร็จ', '$deliveredCount'),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isSettingOnline ? null : _toggleOnlineReady,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isOnlineReady
                                  ? const Color(0xFF2ECC71)
                                  : Colors.white,
                              foregroundColor: _isOnlineReady
                                  ? Colors.white
                                  : const Color(0xFFE86D00),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 13),
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
                                        ? Icons.check_circle_rounded
                                        : Icons.power_settings_new_rounded,
                                  ),
                            label: Text(
                              _isOnlineReady
                                  ? 'พร้อมรับงาน'
                                  : 'ปิดรับงาน',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isOnlineReady
                              ? 'พิกัดไรเดอร์กำลังอัปเดตแบบเรียลไทม์'
                              : 'พิกัดจะเริ่มอัปเดตเมื่อกดพร้อมรับงาน',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
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
                        action.title == 'ออเดอร์ใหม่' || action.title == 'ประวัติ ออเดอร์';
                    final hideSubtitle = isHighContrastAction;
                    final iconColor = isHighContrastAction ? Colors.black : action.color;
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
                                      child: Icon(action.icon, color: iconColor, size: 25),
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

  Widget _buildBottomActionBar(BuildContext context, List<_DashboardAction> actions) {
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
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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
                            child: Icon(action.icon, color: action.color, size: 24),
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
