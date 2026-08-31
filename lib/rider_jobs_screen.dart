import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n/l10n.dart';
import 'services/rider_app_image_prefetch.dart';
import 'services/rider_order_actions.dart';
import 'services/rider_orders_service.dart';

import 'driver_scanner_screen.dart';
import 'rider_chat_room_screen.dart';
import 'services/chat_warmup_service.dart';
import 'utils/contact_phone_resolver.dart';
import 'utils/shop_image_resolver.dart';
import 'utils/shop_location_resolver.dart';
import 'utils/travel_vehicle_type.dart';
import 'widgets/cached_app_image.dart';
import 'widgets/travel_order_avatar.dart';
import 'utils/order_payment_label.dart';
import 'utils/order_pay_at_destination.dart';
import 'utils/order_call_launcher.dart';
import 'utils/rider_incoming_order_filter.dart';

class RiderJobsScreen extends StatefulWidget {
  const RiderJobsScreen({super.key, this.showHistory = false});

  final bool showHistory;

  @override
  State<RiderJobsScreen> createState() => _RiderJobsScreenState();
}

class _RiderJobsScreenState extends State<RiderJobsScreen> {
  static const String _historyExpansionPrefsKey =
      'van3_rider_history_expanded_days';
  static const int _maxFreshPositionAgeSeconds = 45;
  final Set<String> _expandedHistoryDayKeys = <String>{};
  bool _historyExpansionLoaded = false;
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

  String _formatLoadError(Object? error) {
    final message = error?.toString() ?? 'unknown error';
    if (message.contains('permission-denied')) {
      return L10n.loadJobsFailedPermission;
    }
    return L10n.loadJobsFailedWithError(message);
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
      return Scaffold(body: Center(child: Text(L10n.signInRequiredAgain)));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.showHistory ? L10n.orderHistoryTitle : L10n.newJobsTitle),
      ),
      body: RefreshIndicator(
        onRefresh: RiderOrdersService.instance.refresh,
        child: StreamBuilder<RiderOrdersQuerySnapshot>(
        stream: RiderOrdersService.instance.ordersStream,
        initialData: RiderOrdersQuerySnapshot.empty,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData &&
              !snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 180),
                Center(child: CircularProgressIndicator()),
              ],
            );
          }
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  _formatLoadError(snapshot.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Center(
                  child: FilledButton(
                    onPressed: () => RiderOrdersService.instance.refresh(),
                    child: Text(L10n.reloadAgain),
                  ),
                ),
              ],
            );
          }

          final docs =
              (snapshot.data?.docs ?? const <RiderOrderDocument>[])
                  .where((doc) {
                    final data = doc.data();
                    if (widget.showHistory) {
                      return RiderIncomingOrderFilter.isDeliveredHistoryOrder(data);
                    }
                    return RiderIncomingOrderFilter.isActiveAcceptedOrder(data);
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
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(height: MediaQuery.sizeOf(context).height * 0.25),
                Center(
                  child: Text(
                    widget.showHistory
                        ? L10n.noDeliveredHistory
                        : L10n.noAcceptedJobsNow,
                  ),
                ),
              ],
            );
          }

          if (widget.showHistory) {
            if (!_historyExpansionLoaded) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }
            return _buildHistorySections(context, docs);
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
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
      ),
    );
  }

  Widget _buildHistorySections(
    BuildContext context,
    List<RiderOrderDocument> docs,
  ) {
    final groupedDocs = _groupDocsByHistoryDay(docs);
    final summaries = _buildHistoryDailySummaries(docs);
    final orderedKeys = groupedDocs.keys.toList(growable: false)
      ..sort((a, b) => b.compareTo(a));

    if (orderedKeys.isEmpty) {
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: docs.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          return _buildOrderCard(context, docs[index], showHistory: true);
        },
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: orderedKeys.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final dayKey = orderedKeys[index];
        final summary = summaries[dayKey];
        final dayDocs =
            groupedDocs[dayKey] ??
            const <RiderOrderDocument>[];
        final expanded = _expandedHistoryDayKeys.contains(dayKey);

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
            key: ValueKey<String>('history-$dayKey'),
            initiallyExpanded:
                expanded || (_expandedHistoryDayKeys.isEmpty && index == 0),
            onExpansionChanged: (isExpanded) {
              setState(() {
                if (isExpanded) {
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

  Map<String, List<RiderOrderDocument>>
  _groupDocsByHistoryDay(
    List<RiderOrderDocument> docs,
  ) {
    final grouped =
        <String, List<RiderOrderDocument>>{};
    for (final doc in docs) {
      final dayKey = _historyDayKey(doc.data()['deliveredAt']);
      if (dayKey == null) {
        continue;
      }
      grouped
          .putIfAbsent(
            dayKey,
            () => <RiderOrderDocument>[],
          )
          .add(doc);
    }
    return grouped;
  }

  Widget _buildOrderCard(
    BuildContext context,
    RiderOrderDocument doc, {
    required bool showHistory,
  }) {
    final data = doc.data();
    final orderCode = (data['orderCode'] as String?)?.trim();
    final shopName = (data['shopName'] as String?)?.trim();
    final status = (data['status'] as String?)?.trim() ?? '-';
    final total =
        (data['grandTotal'] as num?) ??
        (data['totalAmount'] as num?) ??
        (data['totalPrice'] as num?) ??
        (data['subtotal'] as num?) ??
        0;
    final products = ((data['products'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .toList(growable: false);
    final isTravelOrder = _isTravelPassengerOrder(data);
    final customerUid = _readCustomerUid(data);
    final shopOwnerUid = isTravelOrder ? null : _readShopOwnerUid(data);
    final destinationCoords = _readDestinationCoordinates(data);
        final paymentLabel = resolveOrderPaymentLabel(data);
        final isPayAtDestination = isPayAtDestinationOrder(data);
        final collectedAmount = isPayAtDestination
            ? resolvePayAtDestinationHoldAmount(data)
            : 0.0;

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
                  isTravelOrder
                      ? TravelOrderAvatar(
                          vehicleType: readTravelVehicleTypeFromOrder(data),
                        )
                      : _ShopAvatar(imageUrl: shopImageUrl),
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
                                    ? L10n.orderLabelWithCode(orderCode!)
                                    : L10n.orderLabel(doc.id),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            if (!showHistory && !isTravelOrder)
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
                                    tooltip: L10n.scanQr,
                                    icon: const Icon(
                                      Icons.qr_code_scanner_rounded,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () async {
                                      await RiderOrderActions.instance
                                          .captureDeliveryProof(
                                        context,
                                        orderId: doc.id,
                                        orderData: data,
                                      );
                                    },
                                    tooltip: L10n.captureDeliveryProof,
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
                          isTravelOrder
                              ? L10n.pickupLabel(_readTravelPickupLabel(data))
                              : L10n.shopLabel(
                                  shopName?.isNotEmpty == true ? shopName! : '-',
                                ),
                        ),
                        if (isTravelOrder) ...[
                          Text(
                            L10n.dropoffPointWithLabel(
                              _readTravelDestinationLabel(data),
                            ),
                          ),
                          if (_readTravelVehicleLabel(data) != null)
                            Text(
                              L10n.vehicleTypeWithLabel(
                                _readTravelVehicleLabel(data)!,
                              ),
                            ),
                        ],
                        Text(L10n.orderStatus(status)),
                        Text(L10n.paymentMethodWithLabel(paymentLabel)),
                        Text(L10n.shippingFeeThb(shippingFee)),
                        if (showHistory && isPayAtDestination) ...[
                          Text(
                            L10n.cashCollectedLabel(collectedAmount),
                          ),
                          Text(
                            L10n.riderNetIncomeLabel(riderNetIncome),
                          ),
                          Text(L10n.deliveredAtValue(deliveredAtText)),
                        ] else if (showHistory) ...[
                          Text(
                            L10n.riderNetIncomeLabel(riderNetIncome),
                          ),
                          Text(L10n.deliveredAtValue(deliveredAtText)),
                        ],
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            distanceKm == null
                                  ? (isTravelOrder
                                      ? L10n.distanceToPickupDash
                                      : L10n.distanceToShopDash)
                                  : (isTravelOrder
                                      ? L10n.distanceToPickupKm(distanceKm!)
                                      : L10n.distanceToShopKm(distanceKm!)),
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
              if (isTravelOrder) ...[
                Text(
                  L10n.travelDetailsSection,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  products.isNotEmpty
                      ? (products.first['note'] ??
                              products.first['name'] ??
                              L10n.passengerService)
                          .toString()
                      : L10n.passengerService,
                ),
              ] else ...[
                Text(
                  L10n.productListSection,
                  style: const TextStyle(fontWeight: FontWeight.w700),
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
              ],
              if (!showHistory) ...[
                const SizedBox(height: 10),
                if (isTravelOrder)
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
                                  await RiderOrderActions.instance.openMap(
                                    shopCoords['lat']!,
                                    shopCoords['lng']!,
                                  );
                                },
                                style: _orderActionButtonStyle(),
                                icon: const Icon(Icons.place_outlined),
                                label: Text(L10n.pickupMap),
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: null,
                                style: _orderActionButtonStyle(),
                                icon: const Icon(Icons.place_outlined),
                                label: Text(L10n.pickupMap),
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
                              label: Text(L10n.callCustomer),
                            ),
                            const SizedBox(height: 8),
                            _PeerChatButton(
                              peerUid: customerUid,
                              peerLabel: L10n.customer,
                              label: L10n.chatCustomer,
                              icon: Icons.chat_bubble_outline_rounded,
                              onPressed:
                                  customerUid == null || customerUid.isEmpty
                                  ? null
                                  : () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => RiderChatRoomScreen(
                                            peerUid: customerUid,
                                            peerLabel: L10n.customer,
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
                                  await RiderOrderActions.instance
                                      .openCustomerMap(data);
                                },
                                style: _orderActionButtonStyle(),
                                icon: const Icon(Icons.map_outlined),
                                label: Text(L10n.destinationMap),
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: null,
                                style: _orderActionButtonStyle(),
                                icon: const Icon(Icons.map_outlined),
                                label: Text(L10n.destinationMap),
                              ),
                            if (status == 'accepted') ...[
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: () async {
                                  await RiderOrderActions.instance
                                      .markTravelPickupArrived(
                                    context,
                                    orderId: doc.id,
                                    orderData: data,
                                  );
                                },
                                style: _orderActionButtonStyle(),
                                icon: const Icon(Icons.place_outlined),
                                label: Text(L10n.arrivedAtPickup),
                              ),
                            ],
                            if (status == 'ready') ...[
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: () async {
                                  await RiderOrderActions.instance.startTravelTrip(
                                    context,
                                    orderId: doc.id,
                                    orderData: data,
                                  );
                                },
                                style: _orderActionButtonStyle(),
                                icon: const Icon(Icons.directions_bike_outlined),
                                label: Text(L10n.startTrip),
                              ),
                            ],
                            if (status == 'delivering') ...[
                              const SizedBox(height: 8),
                              FilledButton.icon(
                                onPressed: () async {
                                  await RiderOrderActions.instance
                                      .completeTravelAtDestination(
                                    context,
                                    orderId: doc.id,
                                    orderData: data,
                                  );
                                },
                                style: _orderActionButtonStyle(),
                                icon: const Icon(Icons.flag_outlined),
                                label: Text(L10n.arrivedAtDestination),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  )
                else
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
                                label: Text(L10n.shopMap),
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: null,
                                style: _orderActionButtonStyle(),
                                icon: const Icon(
                                  Icons.store_mall_directory_outlined,
                                ),
                                label: Text(L10n.shopMap),
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
                              label: Text(L10n.callShop),
                            ),
                            const SizedBox(height: 8),
                            _PeerChatButton(
                              peerUid: shopOwnerUid,
                              peerLabel: L10n.shop,
                              label: L10n.chatShop,
                              icon: Icons.storefront_outlined,
                              onPressed:
                                  shopOwnerUid == null || shopOwnerUid.isEmpty
                                  ? null
                                  : () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => RiderChatRoomScreen(
                                            peerUid: shopOwnerUid,
                                            peerLabel: L10n.shop,
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
                                label: Text(L10n.customerMap),
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: null,
                                style: _orderActionButtonStyle(),
                                icon: const Icon(Icons.map_outlined),
                                label: Text(L10n.customerMap),
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
                              label: Text(L10n.callCustomer),
                            ),
                            const SizedBox(height: 8),
                            _PeerChatButton(
                              peerUid: customerUid,
                              peerLabel: L10n.customer,
                              label: L10n.chatCustomer,
                              icon: Icons.chat_bubble_outline_rounded,
                              onPressed:
                                  customerUid == null || customerUid.isEmpty
                                  ? null
                                  : () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute<void>(
                                          builder: (_) => RiderChatRoomScreen(
                                            peerUid: customerUid,
                                            peerLabel: L10n.customer,
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
                  L10n.totalThb(total.toDouble()),
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
    RiderAppImagePrefetch.scheduleOrderCardImages(
      data,
      shopImageUrl: shopImageUrl,
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

  Future<String?> _resolveShopImageUrl(
    Map<String, dynamic> data, {
    required String? ownerUid,
  }) {
    return ShopImageResolver.resolveForOrder(data, shopOwnerUid: ownerUid);
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
  ) {
    return ShopLocationResolver.resolveForOrder(
      data,
      shopOwnerUid: _readShopOwnerUid(data),
    );
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
    // เปิด Google Maps แบบ navigation มอเตอร์ไซค์ (two-wheeler) ทันที
    final navUri = Uri.parse('google.navigation:q=$lat,$lng&mode=l');
    if (await launchUrl(navUri, mode: LaunchMode.externalApplication)) {
      return;
    }
    // Fallback 1: Directions URL พร้อม travelmode=two-wheeler
    final dirUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=two-wheeler&dir_action=navigate',
    );
    if (await launchUrl(dirUri, mode: LaunchMode.externalApplication)) {
      return;
    }
    // Fallback 2: search
    final searchUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final ok = await launchUrl(searchUri, mode: LaunchMode.externalApplication);
    if (!ok) {
      debugPrint('Unable to open map for $lat,$lng');
    }
  }

  Map<String, double>? _readDestinationCoordinates(Map<String, dynamic> data) {
    final fromActions = RiderOrderActions.instance.readDestinationCoordinates(data);
    if (fromActions != null) {
      return fromActions;
    }

    final travelRequest = data['travelRequest'];
    if (travelRequest is Map<String, dynamic>) {
      final destination = travelRequest['destination'];
      if (destination is Map<String, dynamic>) {
        final lat =
            _toDouble(destination['latitude']) ?? _toDouble(destination['lat']);
        final lng =
            _toDouble(destination['longitude']) ?? _toDouble(destination['lng']);
        if (lat != null && lng != null) {
          return <String, double>{'lat': lat, 'lng': lng};
        }
      }
    }

    return null;
  }

  bool _isTravelPassengerOrder(Map<String, dynamic> data) {
    final orderType = (data['orderType'] as String?)?.trim();
    final serviceType = (data['serviceType'] as String?)?.trim();
    return orderType == 'travel_passenger' || serviceType == 'travel_passenger';
  }

  String _readTravelPickupLabel(Map<String, dynamic> data) {
    final travelRequest = data['travelRequest'];
    if (travelRequest is Map<String, dynamic>) {
      final pickup = travelRequest['pickup'];
      if (pickup is Map<String, dynamic>) {
        final title = (pickup['title'] as String?)?.trim();
        if (title != null && title.isNotEmpty) {
          return title;
        }
      }
    }
    return (data['shopName'] as String?)?.trim() ?? '-';
  }

  String _readTravelDestinationLabel(Map<String, dynamic> data) {
    final travelRequest = data['travelRequest'];
    if (travelRequest is Map<String, dynamic>) {
      final destination = travelRequest['destination'];
      if (destination is Map<String, dynamic>) {
        final title = (destination['title'] as String?)?.trim();
        if (title != null && title.isNotEmpty) {
          return title;
        }
      }
    }

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

  String? _readTravelVehicleLabel(Map<String, dynamic> data) {
    final travelRequest = data['travelRequest'];
    if (travelRequest is Map<String, dynamic>) {
      return (travelRequest['vehicleTypeLabel'] as String?)?.trim();
    }
    return null;
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

  Map<String, _HistoryDaySummary> _buildHistoryDailySummaries(
    List<RiderOrderDocument> docs,
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
    if (value is String) {
      return DateTime.tryParse(value);
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

  double _calculateRiderNetIncomeFromGross(double grossShippingFee) {
    if (grossShippingFee <= 0) {
      return 0;
    }
    return double.parse((grossShippingFee * 0.85).toStringAsFixed(1));
  }

  double? _readStoredGrossShippingFee(Map<String, dynamic> data) {
    return _toDouble(data['deliveryGrossShippingFee']) ??
        _toDouble(
          (data['deliveryFinancials']
              as Map<String, dynamic>?)?['grossShippingFee'],
        );
  }

  double? _readStoredRiderNetIncome(Map<String, dynamic> data) {
    return readRiderNetShippingIncome(data);
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
    return ShopImageResolver.readProductImageUrl(
      item,
      fallbackShopImageUrl: fallbackShopImageUrl,
    );
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
            L10n.deliveredCount(summary.deliveredCount),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF7C2D12),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            L10n.last7DaysNetIncome(summary.netIncomeTotal),
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
      child: CachedAppImage(
        imageUrl: uri,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        lightweight: true,
        borderRadius: BorderRadius.circular(16),
        errorWidget: Container(
          width: 56,
          height: 56,
          color: const Color(0xFFFFF1E8),
          child: const Icon(
            Icons.storefront_rounded,
            size: 28,
            color: Color(0xFFB45309),
          ),
        ),
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
                Text(L10n.quantityPieces(quantity)),
                Text(L10n.priceThb(unitPrice)),
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
      child: CachedAppImage(
        imageUrl: uri,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        lightweight: true,
        borderRadius: BorderRadius.circular(14),
        errorWidget: Container(
          width: 56,
          height: 56,
          color: const Color(0xFFE5E7EB),
          child: const Icon(
            Icons.inventory_2_rounded,
            color: Color(0xFF6B7280),
          ),
        ),
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
    ChatWarmupService.prefetchRoom(
      myUid: currentUid,
      peerUid: resolvedPeerUid,
    );
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
