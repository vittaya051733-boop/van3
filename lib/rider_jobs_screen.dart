import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'driver_scanner_screen.dart';
import 'rider_chat_room_screen.dart';
import 'utils/contact_phone_resolver.dart';
import 'utils/order_call_launcher.dart';

class RiderJobsScreen extends StatefulWidget {
  const RiderJobsScreen({super.key, this.showHistory = false});

  final bool showHistory;

  @override
  State<RiderJobsScreen> createState() => _RiderJobsScreenState();
}

class _RiderJobsScreenState extends State<RiderJobsScreen> {
  static const String _historyExpansionPrefsKey =
      'van3_rider_history_expanded_days';
  static const Set<String> _eligibleVan2OrderSources = <String>{
    'cod_confirm_dialog',
    'travel_cod_confirm_dialog',
    'promptpay_slip_dialog',
    'travel_promptpay_slip_dialog',
  };
  final Set<String> _expandedHistoryDayKeys = <String>{};
  bool _historyExpansionLoaded = false;

  static const int _maxFreshPositionAgeSeconds = 45;
  static const List<String> _registrationCollections = <String>[
    'market_registrations',
    'shop_registrations',
    'restaurant_registrations',
    'pharmacy_registrations',
    'other_registrations',
  ];

  @override
  void initState() {
    super.initState();
    _restoreExpandedHistoryDayKeys();
  }

  Future<void> _restoreExpandedHistoryDayKeys() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      if (mounted) {
        setState(() => _historyExpansionLoaded = true);
      }
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final storedKeys =
          prefs.getStringList('$_historyExpansionPrefsKey:$currentUid') ??
          const <String>[];
      if (!mounted) {
        return;
      }
      setState(() {
        _expandedHistoryDayKeys
          ..clear()
          ..addAll(storedKeys.where((value) => value.trim().isNotEmpty));
        _historyExpansionLoaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _historyExpansionLoaded = true);
      }
    }
  }

  Future<void> _persistExpandedHistoryDayKeys() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        '$_historyExpansionPrefsKey:$currentUid',
        _expandedHistoryDayKeys.toList(growable: false),
      );
    } catch (_) {
      // Ignore preference persistence failures.
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('กรุณาเข้าสู่ระบบใหม่')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.showHistory ? 'ประวัติ ออเดอร์' : 'รับงานใหม่'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('driverId', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text('โหลดงานไม่สำเร็จ: ${snapshot.error}'),
              ),
            );
          }

          final docs =
              (snapshot.data?.docs ??
                      const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                  .where((doc) {
                    final data = doc.data();
                    final status = (data['status'] as String?)?.trim() ?? '';
                    final statusMatched = widget.showHistory
                        ? status == 'delivered'
                        : status == 'accepted' ||
                              status == 'ready' ||
                              status == 'delivering';
                    if (!statusMatched) {
                      return false;
                    }

                    final sourceApp = (data['sourceApp'] as String?)?.trim();
                    if (sourceApp == 'van2_customer') {
                      final customerConfirmed =
                          data['customerConfirmed'] == true;
                      if (!customerConfirmed) {
                        return false;
                      }

                      final riderNotifyReady = data['riderNotifyReady'] == true;
                      if (!riderNotifyReady) {
                        return false;
                      }

                      final customerConfirmedAt = data['customerConfirmedAt'];
                      if (customerConfirmedAt is! Timestamp) {
                        return false;
                      }

                      final audit = data['audit'];
                      if (audit is! Map<String, dynamic>) {
                        return false;
                      }
                      final createdSource = (audit['createdSource'] as String?)
                          ?.trim();
                      return _eligibleVan2OrderSources.contains(createdSource);
                    }
                    return true;
                  })
                  .toList();

          if (widget.showHistory) {
            docs.sort(
              (a, b) => _compareDateDesc(
                a.data()['deliveredAt'],
                b.data()['deliveredAt'],
              ),
            );
          }

          if (docs.isEmpty) {
            return Center(
              child: Text(
                widget.showHistory
                    ? 'ยังไม่มีประวัติออเดอร์ที่ส่งสำเร็จ'
                    : 'ยังไม่มีงานที่รับแล้วในตอนนี้',
              ),
            );
          }

          if (widget.showHistory) {
            return _buildHistorySections(context, docs);
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              return _buildOrderCard(context, doc, showHistory: false);
            },
          );
        },
      ),
    );
  }

  Widget _buildHistorySections(
    BuildContext context,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final groupedDocs = _groupDocsByHistoryDay(docs);
    final summaries = _buildHistoryDailySummaries(docs);
    final orderedKeys = groupedDocs.keys.toList(growable: false)
      ..sort((a, b) => b.compareTo(a));

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: orderedKeys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final dayKey = orderedKeys[index];
        final summary = summaries[dayKey];
        final dayDocs =
            groupedDocs[dayKey] ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x11000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: ExpansionTile(
            key: PageStorageKey<String>('history-$dayKey'),
            initiallyExpanded:
                _expandedHistoryDayKeys.contains(dayKey) ||
                (!_historyExpansionLoaded && index == 0),
            onExpansionChanged: (expanded) {
              setState(() {
                if (expanded) {
                  _expandedHistoryDayKeys.add(dayKey);
                } else {
                  _expandedHistoryDayKeys.remove(dayKey);
                }
              });
              _persistExpandedHistoryDayKeys();
            },
            tilePadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 4,
            ),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            shape: const Border(),
            collapsedShape: const Border(),
            title: summary == null
                ? Text(dayKey)
                : _HistoryDaySummaryCard(summary: summary),
            children: [
              for (var docIndex = 0; docIndex < dayDocs.length; docIndex++) ...[
                if (docIndex > 0) const SizedBox(height: 10),
                _buildOrderCard(context, dayDocs[docIndex], showHistory: true),
              ],
            ],
          ),
        );
      },
    );
  }

  Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _groupDocsByHistoryDay(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final grouped =
        <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in docs) {
      final dayKey = _historyDayKey(doc.data()['deliveredAt']);
      if (dayKey == null) {
        continue;
      }
      grouped
          .putIfAbsent(
            dayKey,
            () => <QueryDocumentSnapshot<Map<String, dynamic>>>[],
          )
          .add(doc);
    }
    return grouped;
  }

  Widget _buildOrderCard(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool showHistory,
  }) {
    final data = doc.data();
    final orderCode = (data['orderCode'] as String?)?.trim();
    final shopName = (data['shopName'] as String?)?.trim();
    final status = (data['status'] as String?)?.trim() ?? '-';
    final total =
        (data['grandTotal'] as num?) ?? (data['totalPrice'] as num?) ?? 0;
    final products = ((data['products'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .toList(growable: false);
    final customerUid = _readCustomerUid(data);
    final shopOwnerUid = _readShopOwnerUid(data);
    final destinationCoords = _readDestinationCoordinates(data);

    return FutureBuilder<_ResolvedOrderCardData>(
      future: _resolveOrderCardData(
        data,
        customerUid: customerUid,
        shopOwnerUid: shopOwnerUid,
      ),
      builder: (context, orderSnapshot) {
        final orderCard = orderSnapshot.data;
        final shopImageUrl = orderCard?.shopImageUrl;
        final distanceKm = orderCard?.riderToShopDistanceKm;
        final shippingFee =
            _readStoredGrossShippingFee(data) ?? orderCard?.shippingFee ?? 0;
        final riderNetIncome =
            _readStoredRiderNetIncome(data) ??
            _calculateRiderNetIncomeFromGross(shippingFee);
        final shopCoords = orderCard?.shopCoords;
        final customerPhone = orderCard?.customerPhone;
        final shopPhone = orderCard?.shopPhone;
        final deliveredAtText = _formatDateTime(data['deliveredAt']);

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: showHistory ? const Color(0xFFF9FAFB) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: showHistory
                ? Border.all(color: const Color(0xFFE5E7EB))
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShopAvatar(imageUrl: shopImageUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                orderCode?.isNotEmpty == true
                                    ? 'Order $orderCode'
                                    : 'Order ${doc.id}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (!showHistory)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    onPressed: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => DriverScannerScreen(
                                            orderId: doc.id,
                                            orderCode: orderCode,
                                            orderTotal: total.toDouble(),
                                          ),
                                        ),
                                      );
                                    },
                                    tooltip: 'สแกนคิวอาร์',
                                    icon: const Icon(
                                      Icons.qr_code_scanner_rounded,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () async {
                                      await _captureDeliveryProof(
                                        context,
                                        orderId: doc.id,
                                        orderData: data,
                                      );
                                    },
                                    tooltip: 'ถ่ายรูปยืนยันส่งถึงมือลูกค้า',
                                    icon: const Icon(Icons.camera_alt_rounded),
                                  ),
                                ],
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          'Order ID: ${doc.id}',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ร้าน: ${shopName?.isNotEmpty == true ? shopName : '-'}',
                        ),
                        Text('สถานะ: $status'),
                        Text('ค่าส่ง: THB ${shippingFee.toStringAsFixed(1)}'),
                        if (showHistory) ...[
                          Text(
                            'รายได้สุทธิไรเดอร์: THB ${riderNetIncome.toStringAsFixed(1)}',
                          ),
                          Text('ส่งสำเร็จเมื่อ: ${deliveredAtText ?? '-'}'),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            distanceKm == null
                                ? 'ระยะทางไรเดอร์ถึงร้าน: -'
                                : 'ระยะทางไรเดอร์ถึงร้าน: ${distanceKm.toStringAsFixed(2)} km',
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'รายการสินค้า',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              for (final item in products)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _OrderProductTile(
                    name: (item['name'] ?? item['productName'] ?? '-')
                        .toString(),
                    quantity:
                        int.tryParse((item['quantity'] ?? 0).toString()) ?? 0,
                    unitPrice:
                        double.tryParse(
                          (item['unitPrice'] ?? item['price'] ?? 0).toString(),
                        ) ??
                        0,
                    imageUrl: _readProductImageUrl(
                      item,
                      fallbackShopImageUrl: shopImageUrl,
                    ),
                  ),
                ),
              if (!showHistory) ...[
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (shopCoords != null)
                            OutlinedButton.icon(
                              onPressed: () async {
                                await _openMap(
                                  shopCoords['lat']!,
                                  shopCoords['lng']!,
                                );
                              },
                              style: _orderActionButtonStyle(),
                              icon: const Icon(
                                Icons.store_mall_directory_outlined,
                              ),
                              label: const Text('แผนที่ร้าน'),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: null,
                              style: _orderActionButtonStyle(),
                              icon: const Icon(
                                Icons.store_mall_directory_outlined,
                              ),
                              label: const Text('แผนที่ร้าน'),
                            ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed:
                                shopOwnerUid == null || shopOwnerUid.isEmpty
                                ? null
                                : () async {
                                    await OrderCallLauncher.startVoiceCall(
                                      context: context,
                                      peerUid: shopOwnerUid,
                                      peerLabel:
                                          OrderCallLauncher.readShopLabel(data),
                                      orderData: data,
                                      phoneNumber: shopPhone,
                                      photoUrl:
                                          OrderCallLauncher.readShopPhotoUrl(
                                            data,
                                          ),
                                    );
                                  },
                            style: _orderActionButtonStyle(),
                            icon: const Icon(Icons.support_agent_rounded),
                            label: const Text('โทรร้านค้า'),
                          ),
                          const SizedBox(height: 8),
                          _PeerChatButton(
                            peerUid: shopOwnerUid,
                            peerLabel: 'ร้านค้า',
                            label: 'แชตร้านค้า',
                            icon: Icons.storefront_outlined,
                            onPressed:
                                shopOwnerUid == null || shopOwnerUid.isEmpty
                                ? null
                                : () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => RiderChatRoomScreen(
                                          peerUid: shopOwnerUid,
                                          peerLabel: 'ร้านค้า',
                                          orderId: doc.id,
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (destinationCoords != null)
                            OutlinedButton.icon(
                              onPressed: () async {
                                await _openMap(
                                  destinationCoords['lat']!,
                                  destinationCoords['lng']!,
                                );
                              },
                              style: _orderActionButtonStyle(),
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('แผนที่ลูกค้า'),
                            )
                          else
                            OutlinedButton.icon(
                              onPressed: null,
                              style: _orderActionButtonStyle(),
                              icon: const Icon(Icons.map_outlined),
                              label: const Text('แผนที่ลูกค้า'),
                            ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed:
                                customerUid == null || customerUid.isEmpty
                                ? null
                                : () async {
                                    await OrderCallLauncher.startVoiceCall(
                                      context: context,
                                      peerUid: customerUid,
                                      peerLabel:
                                          OrderCallLauncher.readCustomerLabel(
                                            data,
                                          ),
                                      orderData: data,
                                      phoneNumber: customerPhone,
                                      photoUrl:
                                          OrderCallLauncher.readCustomerPhotoUrl(
                                            data,
                                          ),
                                    );
                                  },
                            style: _orderActionButtonStyle(),
                            icon: const Icon(Icons.phone),
                            label: const Text('โทรลูกค้า'),
                          ),
                          const SizedBox(height: 8),
                          _PeerChatButton(
                            peerUid: customerUid,
                            peerLabel: 'ลูกค้า',
                            label: 'แชตลูกค้า',
                            icon: Icons.chat_bubble_outline_rounded,
                            onPressed:
                                customerUid == null || customerUid.isEmpty
                                ? null
                                : () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => RiderChatRoomScreen(
                                          peerUid: customerUid,
                                          peerLabel: 'ลูกค้า',
                                          orderId: doc.id,
                                        ),
                                      ),
                                    );
                                  },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: Text(
                  'ยอดรวม: THB ${total.toStringAsFixed(1)}',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<_ResolvedOrderCardData> _resolveOrderCardData(
    Map<String, dynamic> data, {
    required String? customerUid,
    required String? shopOwnerUid,
  }) async {
    final customerPhone = await ContactPhoneResolver.resolveCustomerPhone(
      orderData: data,
      customerUid: customerUid,
    );
    final shopPhone = await ContactPhoneResolver.resolveShopPhone(
      orderData: data,
      ownerUid: shopOwnerUid,
      registrationCollections: _registrationCollections,
    );
    final shippingFee = await _resolveShippingFee(data);
    final shopCoords = await _resolveShopCoordinates(data);
    final riderToShopDistanceKm = await _resolveRiderToShopDistanceKm(data);
    final shopImageUrl = await _resolveShopImageUrl(
      data,
      ownerUid: shopOwnerUid,
    );

    return _ResolvedOrderCardData(
      customerPhone: customerPhone,
      shopPhone: shopPhone,
      shopCoords: shopCoords,
      riderToShopDistanceKm: riderToShopDistanceKm,
      shippingFee: shippingFee,
      shopImageUrl: shopImageUrl,
    );
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

  String? _readShopImageUrl(Map<String, dynamic> data) {
    final direct = (data['shopImageUrl'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final shopSnapshot = data['shopSnapshot'];
    if (shopSnapshot is Map) {
      final imageUrl =
          (shopSnapshot['shopImageUrl'] ??
                  shopSnapshot['photoUrl'] ??
                  shopSnapshot['imageUrl'])
              ?.toString()
              .trim();
      if (imageUrl != null && imageUrl.isNotEmpty) {
        return imageUrl;
      }
    }

    return null;
  }

  Future<String?> _resolveShopImageUrl(
    Map<String, dynamic> data, {
    required String? ownerUid,
  }) async {
    final direct = _readShopImageUrl(data);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final productImage = _readShopImageFromProducts(data);
    if (productImage != null && productImage.isNotEmpty) {
      return productImage;
    }

    if (ownerUid == null || ownerUid.isEmpty) {
      return null;
    }

    for (final collection in _registrationCollections) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection(collection)
            .doc(ownerUid)
            .get();
        if (!doc.exists) continue;
        final map = doc.data();
        if (map == null) continue;
        final resolved =
            (map['shopImageUrl'] ??
                    map['photoUrl'] ??
                    map['imageUrl'] ??
                    map['storeImageUrl'] ??
                    map['logoUrl'])
                ?.toString()
                .trim();
        if (resolved != null && resolved.isNotEmpty) {
          return resolved;
        }
      } catch (_) {
        // Try next collection.
      }
    }

    return null;
  }

  String? _readShopImageFromProducts(Map<String, dynamic> data) {
    final rawProducts = (data['products'] as List?) ?? const <dynamic>[];
    for (final item in rawProducts.whereType<Map>()) {
      final resolved =
          (item['shopImageUrl'] ??
                  item['storeImageUrl'] ??
                  item['shopPhotoUrl'] ??
                  item['merchantImageUrl'] ??
                  item['businessImageUrl'])
              ?.toString()
              .trim();
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }
    return null;
  }

  Future<double?> _resolveRiderToShopDistanceKm(
    Map<String, dynamic> data,
  ) async {
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

  Future<Map<String, double>?> _resolveRiderCoordinates(
    Map<String, dynamic> data,
  ) async {
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
      final riderDoc = await FirebaseFirestore.instance
          .collection('riders')
          .doc(currentUid)
          .get();
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

  Future<Map<String, double>?> _resolveShopCoordinates(
    Map<String, dynamic> data,
  ) async {
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
        final doc = await FirebaseFirestore.instance
            .collection(collection)
            .doc(ownerUid)
            .get();
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
    final directLat =
        _toDouble(data[latKey]) ??
        _toDouble(data['latitude']) ??
        _toDouble(data['lat']);
    final directLng =
        _toDouble(data[lngKey]) ??
        _toDouble(data['longitude']) ??
        _toDouble(data['lng']) ??
        _toDouble(data['lon']) ??
        _toDouble(data['long']);
    if (directLat != null && directLng != null) {
      return <String, double>{'lat': directLat, 'lng': directLng};
    }

    final location =
        data[locationKey] ??
        data['location'] ??
        data['geoPoint'] ??
        data['coordinates'];
    if (location is GeoPoint) {
      return <String, double>{
        'lat': location.latitude,
        'lng': location.longitude,
      };
    }
    if (location is Map) {
      final lat = _toDouble(location['latitude']) ?? _toDouble(location['lat']);
      final lng =
          _toDouble(location['longitude']) ??
          _toDouble(location['lng']) ??
          _toDouble(location['lon']) ??
          _toDouble(location['long']);
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
        final age = DateTime.now().difference(lastKnown.timestamp).inSeconds;
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
      locationSettings: _buildLocationSettings(accuracy: LocationAccuracy.high),
    ).timeout(const Duration(seconds: 10));
  }

  Future<void> _openMap(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      debugPrint('Unable to open map for $lat,$lng');
    }
  }

  Map<String, double>? _readDestinationCoordinates(Map<String, dynamic> data) {
    double? lat;
    double? lng;

    final delivery = data['deliverySnapshot'];
    if (delivery is Map<String, dynamic>) {
      lat = _toDouble(delivery['latitude']) ?? _toDouble(delivery['lat']);
      lng = _toDouble(delivery['longitude']) ?? _toDouble(delivery['lng']);
    }

    if (lat == null || lng == null) {
      final customer = data['customerLocation'];
      if (customer is Map<String, dynamic>) {
        lat = _toDouble(customer['latitude']) ?? _toDouble(customer['lat']);
        lng = _toDouble(customer['longitude']) ?? _toDouble(customer['lng']);
      }
    }

    if (lat == null || lng == null) {
      return null;
    }

    return <String, double>{'lat': lat, 'lng': lng};
  }

  Future<double> _resolveShippingFee(Map<String, dynamic> data) async {
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

    final shopCoords = await _resolveShopCoordinates(data);
    final customerCoords = _readDestinationCoordinates(data);
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

  Future<void> _captureDeliveryProof(
    BuildContext context, {
    required String orderId,
    required Map<String, dynamic> orderData,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUid = currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('กรุณาเข้าสู่ระบบใหม่')));
      }
      return;
    }

    final status = (orderData['status'] as String?)?.trim() ?? '';
    if (status != 'delivering') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'ต้องเป็นสถานะกำลังส่งก่อน จึงจะถ่ายรูปยืนยันการส่งได้',
            ),
          ),
        );
      }
      return;
    }

    final picker = ImagePicker();
    final captured = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (captured == null) {
      return;
    }

    try {
      final file = File(captured.path);
      if (!context.mounted) {
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('ยืนยันรูปส่งสำเร็จ'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    file,
                    height: 260,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'ตรวจสอบรูปก่อนยืนยัน ระบบจะอัปเดตออเดอร์เป็นส่งสำเร็จทันที',
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('ยืนยันส่งสำเร็จ'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        return;
      }

      final now = Timestamp.now();
      final grossShippingFee = await _resolveShippingFee(orderData);
      final deliverySnapshot = _buildDeliveryFinancialSnapshot(
        grossShippingFee: grossShippingFee,
        completedAt: now,
        completedSource: 'photo_proof',
      );
      final storagePath =
          'delivery_proofs/$orderId/${DateTime.now().millisecondsSinceEpoch}_${captured.name}';
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);
      await storageRef.putFile(file);
      final proofUrl = await storageRef.getDownloadURL();
      final capturedByName = _readNonEmptyString(
        (currentUser?.displayName ?? '').trim(),
        (orderData['driverName'] as String?)?.trim(),
        (orderData['riderName'] as String?)?.trim(),
      );

      await FirebaseFirestore.instance
          .collection('orders')
          .doc(orderId)
          .update({
            'status': 'delivered',
            'deliveredAt': now,
            'updatedAt': now,
            ...deliverySnapshot,
            'deliveryProofImageUrl': proofUrl,
            'deliveryProofStoragePath': storagePath,
            'deliveryProofCapturedAt': now,
            'deliveryProofCapturedById': currentUid,
            'deliveryProofCapturedByName': capturedByName,
          });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกรูปยืนยันและอัปเดตสถานะส่งสำเร็จแล้ว'),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกรูปยืนยันไม่สำเร็จ: $error')),
        );
      }
    }
  }

  String? _readNonEmptyString(String? first, String? second, String? third) {
    final values = <String?>[first, second, third];
    for (final value in values) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }

  Map<String, _HistoryDaySummary> _buildHistoryDailySummaries(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final summaries = <String, _HistoryDaySummary>{};
    for (final doc in docs) {
      final data = doc.data();
      final dayKey = _historyDayKey(data['deliveredAt']);
      if (dayKey == null) {
        continue;
      }

      final deliveredAt = _readDateTime(data['deliveredAt']);
      final netIncome =
          _readStoredRiderNetIncome(data) ??
          _calculateRiderNetIncomeFromGross(
            _readStoredGrossShippingFee(data) ?? 0,
          );

      final existing = summaries[dayKey];
      if (existing == null) {
        summaries[dayKey] = _HistoryDaySummary(
          dayKey: dayKey,
          label: _formatDateLabel(deliveredAt),
          deliveredCount: 1,
          netIncomeTotal: netIncome,
        );
      } else {
        summaries[dayKey] = _HistoryDaySummary(
          dayKey: existing.dayKey,
          label: existing.label,
          deliveredCount: existing.deliveredCount + 1,
          netIncomeTotal: existing.netIncomeTotal + netIncome,
        );
      }
    }
    return summaries;
  }

  String? _historyDayKey(dynamic value) {
    final dateTime = _readDateTime(value);
    if (dateTime == null) {
      return null;
    }
    final year = dateTime.year.toString();
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatDateLabel(DateTime? value) {
    if (value == null) {
      return '-';
    }
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString();
    return '$day/$month/$year';
  }

  int _compareDateDesc(dynamic left, dynamic right) {
    final leftTime = _readDateTime(left);
    final rightTime = _readDateTime(right);
    if (leftTime == null && rightTime == null) {
      return 0;
    }
    if (leftTime == null) {
      return 1;
    }
    if (rightTime == null) {
      return -1;
    }
    return rightTime.compareTo(leftTime);
  }

  DateTime? _readDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is DateTime) {
      return value;
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    return null;
  }

  String? _formatDateTime(dynamic value) {
    final dateTime = _readDateTime(value);
    if (dateTime == null) {
      return null;
    }
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  Map<String, dynamic> _buildDeliveryFinancialSnapshot({
    required double grossShippingFee,
    required Timestamp completedAt,
    required String completedSource,
  }) {
    final safeGross = double.parse(grossShippingFee.toStringAsFixed(1));
    final platformFee = double.parse((safeGross * 0.15).toStringAsFixed(1));
    final riderNetIncome = double.parse(
      (safeGross - platformFee).toStringAsFixed(1),
    );

    return <String, dynamic>{
      'deliveryGrossShippingFee': safeGross,
      'deliveryPlatformFee': platformFee,
      'deliveryRiderNetIncome': riderNetIncome,
      'deliveryCompletedSource': completedSource,
      'deliveryFinancials': <String, dynamic>{
        'grossShippingFee': safeGross,
        'platformFee': platformFee,
        'riderNetIncome': riderNetIncome,
        'deductionRate': 0.15,
        'currency': 'THB',
        'completedAt': completedAt,
        'completedSource': completedSource,
      },
    };
  }

  double? _readStoredGrossShippingFee(Map<String, dynamic> data) {
    return _toDouble(data['deliveryGrossShippingFee']) ??
        _toDouble(
          (data['deliveryFinancials']
              as Map<String, dynamic>?)?['grossShippingFee'],
        );
  }

  double? _readStoredRiderNetIncome(Map<String, dynamic> data) {
    return _toDouble(data['deliveryRiderNetIncome']) ??
        _toDouble(
          (data['deliveryFinancials']
              as Map<String, dynamic>?)?['riderNetIncome'],
        );
  }

  double _calculateRiderNetIncomeFromGross(double grossShippingFee) {
    if (grossShippingFee <= 0) {
      return 0;
    }
    return double.parse((grossShippingFee * 0.85).toStringAsFixed(1));
  }

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

  double? _toDouble(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  String? _readProductImageUrl(
    Map<dynamic, dynamic> item, {
    String? fallbackShopImageUrl,
  }) {
    final direct =
        (item['imageUrl'] ??
                item['photoUrl'] ??
                item['image'] ??
                item['productImage'])
            ?.toString()
            .trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    final fallback = fallbackShopImageUrl?.trim();
    return fallback == null || fallback.isEmpty ? null : fallback;
  }
}

class _HistoryDaySummary {
  const _HistoryDaySummary({
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

class _HistoryDaySummaryCard extends StatelessWidget {
  const _HistoryDaySummaryCard({required this.summary});

  final _HistoryDaySummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            summary.label,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: Color(0xFF9A3412),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ส่งสำเร็จ ${summary.deliveredCount} งาน',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF7C2D12),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'รายได้สุทธิรวม THB ${summary.netIncomeTotal.toStringAsFixed(1)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF7C2D12),
            ),
          ),
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
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1E8),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.storefront_rounded,
          size: 28,
          color: Color(0xFFB45309),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        uri,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 56,
            height: 56,
            color: const Color(0xFFFFF1E8),
            child: const Icon(
              Icons.storefront_rounded,
              size: 28,
              color: Color(0xFFB45309),
            ),
          );
        },
      ),
    );
  }
}

class _OrderProductTile extends StatelessWidget {
  const _OrderProductTile({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.imageUrl,
  });

  final String name;
  final int quantity;
  final double unitPrice;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _OrderProductImage(imageUrl: imageUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('จำนวน $quantity ชิ้น'),
                Text('ราคา THB ${unitPrice.toStringAsFixed(1)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderProductImage extends StatelessWidget {
  const _OrderProductImage({required this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final uri = imageUrl?.trim();
    if (uri == null || uri.isEmpty) {
      return Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.inventory_2_rounded, color: Color(0xFF6B7280)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.network(
        uri,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 56,
            height: 56,
            color: const Color(0xFFE5E7EB),
            child: const Icon(
              Icons.inventory_2_rounded,
              color: Color(0xFF6B7280),
            ),
          );
        },
      ),
    );
  }
}

ButtonStyle _orderActionButtonStyle() {
  return OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(44),
    alignment: Alignment.center,
  );
}

class _PeerChatButton extends StatelessWidget {
  const _PeerChatButton({
    required this.peerUid,
    required this.peerLabel,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String? peerUid;
  final String peerLabel;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final resolvedPeerUid = peerUid?.trim();
    final canOpen =
        currentUid != null &&
        resolvedPeerUid != null &&
        resolvedPeerUid.isNotEmpty;

    if (!canOpen) {
      return OutlinedButton.icon(
        onPressed: null,
        style: _orderActionButtonStyle(),
        icon: Icon(icon),
        label: Text(label),
      );
    }

    final chatId = _chatIdFor(currentUid, resolvedPeerUid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadMap =
            snapshot.data?.data()?['unreadCounts'] as Map<String, dynamic>?;
        final unreadValue = unreadMap?[currentUid];
        final unreadCount = unreadValue is int
            ? unreadValue
            : unreadValue is num
            ? unreadValue.toInt()
            : 0;

        return OutlinedButton.icon(
          onPressed: onPressed,
          style: _orderActionButtonStyle(),
          icon: Icon(icon),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (unreadCount > 0) ...[
                const SizedBox(width: 6),
                _UnreadPill(count: unreadCount),
              ],
            ],
          ),
        );
      },
    );
  }

  String _chatIdFor(String uidA, String uidB) {
    final sorted = <String>[uidA, uidB]..sort();
    return 'chat_${sorted.join('_')}';
  }
}

class _UnreadPill extends StatelessWidget {
  const _UnreadPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(999),
      ),
      constraints: const BoxConstraints(minWidth: 18),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

class _ResolvedOrderCardData {
  const _ResolvedOrderCardData({
    required this.customerPhone,
    required this.shopPhone,
    required this.shopCoords,
    required this.riderToShopDistanceKm,
    required this.shippingFee,
    required this.shopImageUrl,
  });

  final String? customerPhone;
  final String? shopPhone;
  final Map<String, double>? shopCoords;
  final double? riderToShopDistanceKm;
  final double shippingFee;
  final String? shopImageUrl;
}
