import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'rider_chat_room_screen.dart';
import 'utils/contact_phone_resolver.dart';
import 'utils/order_call_launcher.dart';

class IncomingOrderScreen extends StatefulWidget {
  const IncomingOrderScreen({
    super.key,
    required this.orderId,
    required this.initialData,
  });

  final String orderId;
  final Map<String, dynamic> initialData;

  @override
  State<IncomingOrderScreen> createState() => _IncomingOrderScreenState();
}

class _IncomingOrderScreenState extends State<IncomingOrderScreen> {
  static const int _maxFreshPositionAgeSeconds = 45;
  static const List<String> _registrationCollections = <String>[
    'market_registrations',
    'shop_registrations',
    'restaurant_registrations',
    'pharmacy_registrations',
    'other_registrations',
  ];

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

  late final Future<_IncomingOrderViewData> _viewDataFuture = _buildViewData();
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final orderCode = (widget.initialData['orderCode'] as String?)?.trim();
    final shopName = (widget.initialData['shopName'] as String?)?.trim();

    return Scaffold(
      appBar: AppBar(
        title: Text(orderCode?.isNotEmpty == true ? 'Order $orderCode' : 'ออเดอร์ใหม่'),
      ),
      body: FutureBuilder<_IncomingOrderViewData>(
        future: _viewDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final viewData = snapshot.data ?? _IncomingOrderViewData.empty(widget.initialData);
          final products = viewData.products;

          return SafeArea(
            child: Column(
              children: <Widget>[
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    children: <Widget>[
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _ShopAvatar(imageUrl: viewData.shopImageUrl),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        shopName?.isNotEmpty == true ? shopName! : 'ไม่พบชื่อร้าน',
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        orderCode?.isNotEmpty == true
                                            ? 'Order ID: ${widget.orderId}\nเลขออเดอร์: $orderCode'
                                            : 'Order ID: ${widget.orderId}',
                                        style: const TextStyle(color: Color(0xFF6B7280)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              runSpacing: 10,
                              spacing: 10,
                              children: <Widget>[
                                _InfoChip(label: 'ยอดรวม', value: 'THB ${viewData.total.toStringAsFixed(1)}'),
                                _InfoChip(label: 'ค่าส่ง', value: 'THB ${viewData.shippingFee.toStringAsFixed(1)}'),
                                _InfoChip(
                                  label: 'ระยะถึงร้าน',
                                  value: viewData.riderToShopDistanceKm == null
                                      ? '-'
                                      : '${viewData.riderToShopDistanceKm!.toStringAsFixed(2)} km',
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'ปลายทาง: ${viewData.destinationLabel}',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: <Widget>[
                                if (viewData.destinationCoords != null)
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await _openMap(
                                        viewData.destinationCoords!['lat']!,
                                        viewData.destinationCoords!['lng']!,
                                      );
                                    },
                                    icon: const Icon(Icons.map_outlined),
                                    label: const Text('แผนที่ปลายทาง'),
                                  ),
                                if (viewData.shopCoords != null)
                                  OutlinedButton.icon(
                                    onPressed: () async {
                                      await _openMap(
                                        viewData.shopCoords!['lat']!,
                                        viewData.shopCoords!['lng']!,
                                      );
                                    },
                                    icon: const Icon(Icons.store_mall_directory_outlined),
                                    label: const Text('แผนที่ร้านค้า'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'ติดต่อ',
                        child: Column(
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: viewData.customerUid == null
                                        ? null
                                        : () async {
                                            await OrderCallLauncher.startVoiceCall(
                                              context: context,
                                              peerUid: viewData.customerUid!,
                                              peerLabel: OrderCallLauncher.readCustomerLabel(
                                                viewData.orderData,
                                              ),
                                              orderData: viewData.orderData,
                                              phoneNumber: viewData.customerPhone,
                                              photoUrl: OrderCallLauncher.readCustomerPhotoUrl(
                                                viewData.orderData,
                                              ),
                                            );
                                          },
                                    icon: const Icon(Icons.phone_in_talk_outlined),
                                    label: const Text('โทรลูกค้า'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: viewData.shopOwnerUid == null
                                        ? null
                                        : () async {
                                            await OrderCallLauncher.startVoiceCall(
                                              context: context,
                                              peerUid: viewData.shopOwnerUid!,
                                              peerLabel: OrderCallLauncher.readShopLabel(
                                                viewData.orderData,
                                              ),
                                              orderData: viewData.orderData,
                                              phoneNumber: viewData.shopPhone,
                                              photoUrl: OrderCallLauncher.readShopPhotoUrl(
                                                viewData.orderData,
                                              ),
                                            );
                                          },
                                    icon: const Icon(Icons.support_agent_rounded),
                                    label: const Text('โทรร้านค้า'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: viewData.customerUid == null
                                        ? null
                                        : () async {
                                            await Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => RiderChatRoomScreen(
                                                  peerUid: viewData.customerUid!,
                                                  peerLabel: 'ลูกค้า',
                                                  orderId: widget.orderId,
                                                ),
                                              ),
                                            );
                                          },
                                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                                    label: const Text('แชตลูกค้า'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: viewData.shopOwnerUid == null
                                        ? null
                                        : () async {
                                            await Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => RiderChatRoomScreen(
                                                  peerUid: viewData.shopOwnerUid!,
                                                  peerLabel: 'ร้านค้า',
                                                  orderId: widget.orderId,
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
                        ),
                      ),
                      const SizedBox(height: 14),
                      _SectionCard(
                        title: 'รายการสินค้า',
                        child: Column(
                          children: products.isEmpty
                              ? const <Widget>[
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text('ไม่พบรายละเอียดสินค้า'),
                                  ),
                                ]
                              : products
                                  .map((product) => _ProductTile(product: product))
                                  .toList(growable: false),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Color(0x11000000),
                        blurRadius: 18,
                        offset: Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSubmitting ? null : _rejectOrder,
                          child: const Text('ไม่รับงาน'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _isSubmitting ? null : _acceptOrder,
                          icon: _isSubmitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: Text(_isSubmitting ? 'กำลังบันทึก...' : 'รับงาน'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<_IncomingOrderViewData> _buildViewData() async {
    final data = widget.initialData;
    final shippingFee = await _resolveShippingFee(data);
    final customerUid = _readCustomerUid(data);
    final shopOwnerUid = _readShopOwnerUid(data);
    final customerPhone = await ContactPhoneResolver.resolveCustomerPhone(
      orderData: data,
      customerUid: customerUid,
    );
    final shopPhone = await ContactPhoneResolver.resolveShopPhone(
      orderData: data,
      ownerUid: shopOwnerUid,
      registrationCollections: _registrationCollections,
    );
    final riderToShopDistanceKm = await _resolveRiderToShopDistanceKm(data);
    final shopCoords = await _resolveShopCoordinates(data);
    return _IncomingOrderViewData(
      orderData: data,
      shippingFee: shippingFee,
      customerPhone: customerPhone,
      customerUid: customerUid,
      shopOwnerUid: shopOwnerUid,
      shopPhone: shopPhone,
      riderToShopDistanceKm: riderToShopDistanceKm,
      destinationCoords: _readDestinationCoordinates(data),
      destinationLabel: _readDestinationLabel(data),
      shopCoords: shopCoords,
      shopImageUrl: _readShopImageUrl(data),
      products: _readProducts(data),
      total: (data['grandTotal'] as num?)?.toDouble() ??
          (data['totalPrice'] as num?)?.toDouble() ??
          0,
    );
  }

  Future<void> _acceptOrder() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final orderRef = FirebaseFirestore.instance.collection('orders').doc(widget.orderId);
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
        orderId: widget.orderId,
        title: 'ไรเดอร์รับงานแล้ว',
        body: 'ออเดอร์${(data['orderCode'] as String?)?.trim().isNotEmpty == true ? ' ${(data['orderCode'] as String).trim()}' : ''} มีไรเดอร์รับงานแล้ว',
        action: 'order_accepted',
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('รับงานเรียบร้อย')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('รับงานไม่สำเร็จ: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _rejectOrder() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      final orderRef = FirebaseFirestore.instance.collection('orders').doc(widget.orderId);
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
        orderId: widget.orderId,
        title: 'กำลังหาไรเดอร์ใหม่',
        body: 'ไรเดอร์ปฏิเสธงาน ระบบกำลังค้นหาไรเดอร์ให้ใหม่',
        action: 'order_rejected',
      );

      await _sendOrderAppNotification(
        targetApp: 'van1',
        recipientUid: (data['shopOwnerId'] as String?)?.trim(),
        orderId: widget.orderId,
        title: 'ไรเดอร์ปฏิเสธงาน',
        body: 'ออเดอร์${(data['orderCode'] as String?)?.trim().isNotEmpty == true ? ' ${(data['orderCode'] as String).trim()}' : ''} ไรเดอร์ปฏิเสธงาน ระบบกำลังหาไรเดอร์ใหม่',
        action: 'order_rejected',
      );

      if (!mounted) return;
      Navigator.of(context).pop(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่รับงานแล้ว ระบบจะหาคนขับคนอื่นต่อ')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปเดตสถานะไม่สำเร็จ: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
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

  Future<void> _openMap(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถเปิดแผนที่ได้')),
      );
    }
  }

  String _readDestinationLabel(Map<String, dynamic> data) {
    final delivery = data['deliverySnapshot'];
    if (delivery is Map<String, dynamic>) {
      final label = (delivery['locationLabel'] as String?)?.trim();
      if (label != null && label.isNotEmpty) {
        return label;
      }
    }

    final customer = data['customerLocation'];
    if (customer is Map<String, dynamic>) {
      final label = (customer['label'] as String?)?.trim();
      if (label != null && label.isNotEmpty) {
        return label;
      }
    }

    return '-';
  }

  List<_IncomingOrderProduct> _readProducts(Map<String, dynamic> data) {
    final rawProducts = ((data['products'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .toList(growable: false);
    final fallbackShopImageUrl = _readShopImageUrl(data);

    return rawProducts.map((item) {
      final imageUrl = (item['imageUrl'] ?? item['photoUrl'] ?? item['image'] ?? item['productImage'])
          ?.toString()
          .trim();
      return _IncomingOrderProduct(
        name: (item['name'] ?? item['productName'] ?? '-').toString(),
        quantity: int.tryParse((item['quantity'] ?? 0).toString()) ?? 0,
        unitPrice: double.tryParse((item['unitPrice'] ?? item['price'] ?? 0).toString()) ?? 0,
        imageUrl: imageUrl == null || imageUrl.isEmpty ? fallbackShopImageUrl : imageUrl,
        note: (item['note'] ?? item['specialRequest'] ?? '').toString().trim(),
      );
    }).toList(growable: false);
  }

  String? _readShopImageUrl(Map<String, dynamic> data) {
    final direct = (data['shopImageUrl'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final snapshot = data['shopSnapshot'];
    if (snapshot is Map) {
      final imageUrl = (snapshot['shopImageUrl'] ?? snapshot['photoUrl'] ?? snapshot['imageUrl'])
          ?.toString()
          .trim();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        return imageUrl;
      }
    }
    return null;
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

    final riderCoords = await _resolveRiderCoordinates(data);
    if (riderCoords == null) {
      return null;
    }

    final meters = Geolocator.distanceBetween(
      riderCoords['lat']!,
      riderCoords['lng']!,
      shopCoords['lat']!,
      shopCoords['lng']!,
    );
    return meters.isFinite ? meters / 1000 : null;
  }

  Future<Map<String, double>?> _resolveRiderCoordinates(Map<String, dynamic> data) async {
    final direct = _readCoordinatesFromAny(
      data,
      locationKey: 'riderLocation',
      latKey: 'riderLatitude',
      lngKey: 'riderLongitude',
    );
    if (direct != null) {
      return direct;
    }

    final livePosition = await _getFreshCurrentPosition();
    if (livePosition != null) {
      return <String, double>{
        'lat': livePosition.latitude,
        'lng': livePosition.longitude,
      };
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      return null;
    }

    try {
      final riderDoc = await FirebaseFirestore.instance.collection('riders').doc(currentUid).get();
      final riderData = riderDoc.data();
      if (riderData == null) {
        return null;
      }

      return _readCoordinatesFromAny(
        riderData,
        locationKey: 'currentLocation',
        latKey: 'latitude',
        lngKey: 'longitude',
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, double>?> _resolveShopCoordinates(Map<String, dynamic> data) async {
    final direct = _readCoordinatesFromAny(
      data,
      locationKey: 'shopLocation',
      latKey: 'shopLatitude',
      lngKey: 'shopLongitude',
    );
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
        // Try next collection.
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
    return double.parse(fee.toStringAsFixed(1));
  }

  Map<String, double>? _readCustomerCoordinates(Map<String, dynamic> data) {
    final customer = data['customerLocation'];
    if (customer is Map<String, dynamic>) {
      final lat = _toDouble(customer['latitude']) ?? _toDouble(customer['lat']);
      final lng = _toDouble(customer['longitude']) ?? _toDouble(customer['lng']);
      if (lat != null && lng != null) {
        return <String, double>{'lat': lat, 'lng': lng};
      }
    }

    final delivery = data['deliverySnapshot'];
    if (delivery is Map<String, dynamic>) {
      final lat = _toDouble(delivery['latitude']) ?? _toDouble(delivery['lat']);
      final lng = _toDouble(delivery['longitude']) ?? _toDouble(delivery['lng']);
      if (lat != null && lng != null) {
        return <String, double>{'lat': lat, 'lng': lng};
      }
    }

    return null;
  }

  Future<Position?> _getFreshCurrentPosition() async {
    try {
      final current = await _getCurrentPosition();
      if (current != null) {
        return current;
      }
    } catch (_) {
      // Ignore and try last known fallback.
    }

    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final capturedAt = lastKnown.timestamp;
        final age = DateTime.now().difference(capturedAt).inSeconds;
        if (age <= _maxFreshPositionAgeSeconds) {
          return lastKnown;
        }
      }
    } catch (_) {
      // Ignore final fallback failure.
    }

    return null;
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

  double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }
}

class _IncomingOrderViewData {
  const _IncomingOrderViewData({
    required this.orderData,
    required this.shippingFee,
    required this.customerPhone,
    required this.customerUid,
    required this.shopOwnerUid,
    required this.shopPhone,
    required this.riderToShopDistanceKm,
    required this.destinationCoords,
    required this.destinationLabel,
    required this.shopCoords,
    required this.shopImageUrl,
    required this.products,
    required this.total,
  });

  factory _IncomingOrderViewData.empty(Map<String, dynamic> orderData) {
    return _IncomingOrderViewData(
      orderData: orderData,
      shippingFee: 0,
      customerPhone: null,
      customerUid: null,
      shopOwnerUid: null,
      shopPhone: null,
      riderToShopDistanceKm: null,
      destinationCoords: null,
      destinationLabel: '-',
      shopCoords: null,
      shopImageUrl: null,
      products: const <_IncomingOrderProduct>[],
      total: 0,
    );
  }

  final Map<String, dynamic> orderData;
  final double shippingFee;
  final String? customerPhone;
  final String? customerUid;
  final String? shopOwnerUid;
  final String? shopPhone;
  final double? riderToShopDistanceKm;
  final Map<String, double>? destinationCoords;
  final String destinationLabel;
  final Map<String, double>? shopCoords;
  final String? shopImageUrl;
  final List<_IncomingOrderProduct> products;
  final double total;
}

class _IncomingOrderProduct {
  const _IncomingOrderProduct({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.imageUrl,
    required this.note,
  });

  final String name;
  final int quantity;
  final double unitPrice;
  final String? imageUrl;
  final String note;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.title});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Text(
              title!,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ShopAvatar extends StatelessWidget {
  const _ShopAvatar({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final uri = imageUrl?.trim();
    if (uri == null || uri.isEmpty) {
      return Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1E8),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(Icons.storefront_rounded, size: 34, color: Color(0xFFB45309)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Image.network(
        uri,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 72,
            height: 72,
            color: const Color(0xFFFFF1E8),
            child: const Icon(Icons.storefront_rounded, size: 34, color: Color(0xFFB45309)),
          );
        },
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product});

  final _IncomingOrderProduct product;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ProductImage(imageUrl: product.imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  product.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text('จำนวน ${product.quantity} ชิ้น'),
                Text('ราคา THB ${product.unitPrice.toStringAsFixed(1)}'),
                if (product.note.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    'หมายเหตุ: ${product.note}',
                    style: const TextStyle(color: Color(0xFF6B7280)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final uri = imageUrl?.trim();
    if (uri == null || uri.isEmpty) {
      return Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.fastfood_rounded, color: Color(0xFF6B7280)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        uri,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 72,
            height: 72,
            color: const Color(0xFFE5E7EB),
            child: const Icon(Icons.fastfood_rounded, color: Color(0xFF6B7280)),
          );
        },
      ),
    );
  }
}