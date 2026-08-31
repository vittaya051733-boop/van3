import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import 'l10n/l10n.dart';
import 'rider_chat_room_screen.dart';
import 'services/chat_warmup_service.dart';
import 'wallet_screen.dart';
import 'services/rider_location_pusher.dart';
import 'services/rider_order_actions.dart';
import 'services/rider_app_image_prefetch.dart';
import 'utils/contact_phone_resolver.dart';
import 'utils/shop_image_resolver.dart';
import 'utils/shop_location_resolver.dart';
import 'utils/travel_vehicle_type.dart';
import 'widgets/cached_app_image.dart';
import 'widgets/travel_order_avatar.dart';
import 'utils/order_call_launcher.dart';
import 'utils/order_payment_label.dart';
import 'utils/order_pay_at_destination.dart';
import 'utils/guarded_functions.dart';

enum _InsufficientCreditAction { cancel, topUp, reject }

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
  bool _isPromptingAccept = false;

  Future<_IncomingOrderViewData> _buildViewData() {
    return _buildViewDataImpl().timeout(
      const Duration(seconds: 15),
      onTimeout: () => _IncomingOrderViewData.empty(widget.initialData),
    );
  }

  Future<double> _fetchCurrentCreditBalance(String uid) async {
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
    return total;
  }

  Future<bool> _confirmDeductCreditDialog({
    required double holdAmount,
    required double currentCredit,
    required String paymentLabel,
  }) async {
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(L10n.confirmCreditDeduct),
          content: Text(
            L10n.confirmCreditDeductBody(
              paymentLabel,
              holdAmount,
              currentCredit,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(L10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(L10n.confirmAcceptJob),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<_InsufficientCreditAction> _showInsufficientCreditDialog({
    required double holdAmount,
    required double currentCredit,
    required String paymentLabel,
  }) async {
    if (!mounted) return _InsufficientCreditAction.cancel;

    final action = await showDialog<_InsufficientCreditAction>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(L10n.insufficientCredit),
          content: Text(
            L10n.insufficientCreditBody(
              paymentLabel,
              holdAmount,
              currentCredit,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _InsufficientCreditAction.cancel,
              ),
              child: Text(L10n.close),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _InsufficientCreditAction.reject,
              ),
              child: Text(L10n.rejectJob),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                _InsufficientCreditAction.topUp,
              ),
              child: Text(L10n.topUpCredit),
            ),
          ],
        );
      },
    );

    return action ?? _InsufficientCreditAction.cancel;
  }

  @override
  Widget build(BuildContext context) {
    final orderCode = _readTrimmedString(widget.initialData['orderCode']);
    final shopName = _readTrimmedString(widget.initialData['shopName']);
    final isTravelOrder = _isTravelPassengerOrder(widget.initialData);
    final paymentLabel = resolveOrderPaymentLabel(widget.initialData);

    return Scaffold(
      backgroundColor: const Color(0x99000000),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 430,
                maxHeight: MediaQuery.sizeOf(context).height * 0.88,
              ),
              child: Material(
                color: const Color(0xFFFFF7F2),
                elevation: 18,
                borderRadius: BorderRadius.circular(26),
                clipBehavior: Clip.antiAlias,
                child: FutureBuilder<_IncomingOrderViewData>(
                  future: _viewDataFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 220,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    if (snapshot.hasError) {
                      return SizedBox(
                        height: 220,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              L10n.loadOrderDetailsFailedWithError(
                                snapshot.error!,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      );
                    }

          final viewData = snapshot.data ?? _IncomingOrderViewData.empty(widget.initialData);
          final products = viewData.products;
          final titleLabel = isTravelOrder
              ? (viewData.pickupLabel.isNotEmpty
                    ? viewData.pickupLabel
                    : L10n.pickupNotFound)
              : (shopName?.isNotEmpty == true ? shopName! : L10n.shopNameNotFound);
          final distanceLabel =
              isTravelOrder ? L10n.distanceToPickup : L10n.distanceToShop;
          final pickupMapLabel =
              isTravelOrder ? L10n.pickupMap : L10n.shopMap;
          final detailSectionTitle = isTravelOrder
              ? L10n.travelDetailsSection
              : L10n.productListSection;

          return Column(
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFF6B35),
                  ),
                  child: Text(
                    isTravelOrder
                        ? (orderCode?.isNotEmpty == true
                              ? L10n.newTravelJobWithCode(orderCode!)
                              : L10n.newTravelJob)
                        : (orderCode?.isNotEmpty == true
                              ? L10n.newOrderWithCode(orderCode!)
                              : L10n.newOrder),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
                    children: <Widget>[
                      _SectionCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _OrderAvatar(
                                  imageUrl: viewData.shopImageUrl,
                                  isTravelOrder: isTravelOrder,
                                  travelVehicleType: viewData.travelVehicleType,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        titleLabel,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        orderCode?.isNotEmpty == true
                                            ? L10n.orderIdAndCode(
                                                widget.orderId,
                                                orderCode!,
                                              )
                                            : L10n.orderIdWithValue(widget.orderId),
                                        style: const TextStyle(color: Color(0xFF6B7280)),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        L10n.paymentMethodWithLabel(paymentLabel),
                                        style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Wrap(
                              runSpacing: 10,
                              spacing: 10,
                              children: <Widget>[
                                _InfoChip(
                                  label: isTravelOrder ? L10n.fare : L10n.total,
                                  value: 'THB ${viewData.total.toStringAsFixed(1)}',
                                ),
                                if (!isTravelOrder)
                                  _InfoChip(
                                    label: L10n.shippingFee,
                                    value: 'THB ${viewData.shippingFee.toStringAsFixed(1)}',
                                  ),
                                _InfoChip(
                                  label: distanceLabel,
                                  value: viewData.riderToShopDistanceKm == null
                                      ? '-'
                                      : '${viewData.riderToShopDistanceKm!.toStringAsFixed(2)} km',
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (isTravelOrder) ...<Widget>[
                              Text(
                                L10n.pickupPoint(viewData.pickupLabel),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                L10n.dropoffPointWithLabel(viewData.destinationLabel),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (viewData.vehicleTypeLabel != null) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(
                                  L10n.vehicleTypeWithLabel(viewData.vehicleTypeLabel!),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                              if (viewData.scheduleLabel != null) ...<Widget>[
                                const SizedBox(height: 8),
                                Text(
                                  L10n.scheduleWithLabel(viewData.scheduleLabel!),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ] else ...<Widget>[
                              Text(
                                L10n.destinationWithLabel(viewData.destinationLabel),
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            if (!isTravelOrder) ...<Widget>[
                              const SizedBox(height: 8),
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
                                      label: Text(L10n.destinationMap),
                                    ),
                                  if (viewData.shopCoords != null)
                                    OutlinedButton.icon(
                                      onPressed: () async {
                                        await _openMap(
                                          viewData.shopCoords!['lat']!,
                                          viewData.shopCoords!['lng']!,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.store_mall_directory_outlined,
                                      ),
                                      label: Text(pickupMapLabel),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SectionCard(
                        title: L10n.contact,
                        child: isTravelOrder
                            ? Column(
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
                                                    peerLabel:
                                                        OrderCallLauncher.readCustomerLabel(
                                                          viewData.orderData,
                                                        ),
                                                    orderData: viewData.orderData,
                                                    phoneNumber: viewData.customerPhone,
                                                    photoUrl:
                                                        OrderCallLauncher.readCustomerPhotoUrl(
                                                          viewData.orderData,
                                                        ),
                                                  );
                                                },
                                          icon: const Icon(Icons.phone_in_talk_outlined),
                                          label: Text(L10n.callCustomer),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: viewData.shopCoords == null
                                              ? null
                                              : () async {
                                                  await RiderOrderActions.instance.openMap(
                                                    viewData.shopCoords!['lat']!,
                                                    viewData.shopCoords!['lng']!,
                                                  );
                                                },
                                          icon: const Icon(Icons.place_outlined),
                                          label: Text(L10n.pickupMap),
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
                                                  final myUid =
                                                      FirebaseAuth.instance.currentUser?.uid;
                                                  if (myUid != null) {
                                                    ChatWarmupService.prefetchRoom(
                                                      myUid: myUid,
                                                      peerUid: viewData.customerUid!,
                                                    );
                                                  }
                                                  await Navigator.of(context).push(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) => RiderChatRoomScreen(
                                                        peerUid: viewData.customerUid!,
                                                        peerLabel: L10n.customer,
                                                        orderId: widget.orderId,
                                                      ),
                                                    ),
                                                  );
                                                },
                                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                                          label: Text(L10n.chatCustomer),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: viewData.destinationCoords == null
                                              ? null
                                              : () async {
                                                  await RiderOrderActions.instance
                                                      .openCustomerMap(viewData.orderData);
                                                },
                                          icon: const Icon(Icons.map_outlined),
                                          label: Text(L10n.destinationMap),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              )
                            : Column(
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
                                                    peerLabel:
                                                        OrderCallLauncher.readCustomerLabel(
                                                          viewData.orderData,
                                                        ),
                                                    orderData: viewData.orderData,
                                                    phoneNumber: viewData.customerPhone,
                                                    photoUrl:
                                                        OrderCallLauncher.readCustomerPhotoUrl(
                                                          viewData.orderData,
                                                        ),
                                                  );
                                                },
                                          icon: const Icon(Icons.phone_in_talk_outlined),
                                          label: Text(L10n.callCustomer),
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
                                                    peerLabel:
                                                        OrderCallLauncher.readShopLabel(
                                                          viewData.orderData,
                                                        ),
                                                    orderData: viewData.orderData,
                                                    phoneNumber: viewData.shopPhone,
                                                    photoUrl:
                                                        OrderCallLauncher.readShopPhotoUrl(
                                                          viewData.orderData,
                                                        ),
                                                  );
                                                },
                                          icon: const Icon(Icons.support_agent_rounded),
                                          label: Text(L10n.callShop),
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
                                                  final myUid =
                                                      FirebaseAuth.instance.currentUser?.uid;
                                                  if (myUid != null) {
                                                    ChatWarmupService.prefetchRoom(
                                                      myUid: myUid,
                                                      peerUid: viewData.customerUid!,
                                                    );
                                                  }
                                                  await Navigator.of(context).push(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) => RiderChatRoomScreen(
                                                        peerUid: viewData.customerUid!,
                                                        peerLabel: L10n.customer,
                                                        orderId: widget.orderId,
                                                      ),
                                                    ),
                                                  );
                                                },
                                          icon: const Icon(Icons.chat_bubble_outline_rounded),
                                          label: Text(L10n.chatCustomer),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: viewData.shopOwnerUid == null
                                              ? null
                                              : () async {
                                                  final myUid =
                                                      FirebaseAuth.instance.currentUser?.uid;
                                                  if (myUid != null) {
                                                    ChatWarmupService.prefetchRoom(
                                                      myUid: myUid,
                                                      peerUid: viewData.shopOwnerUid!,
                                                    );
                                                  }
                                                  await Navigator.of(context).push(
                                                    MaterialPageRoute<void>(
                                                      builder: (_) => RiderChatRoomScreen(
                                                        peerUid: viewData.shopOwnerUid!,
                                                        peerLabel: L10n.shop,
                                                        orderId: widget.orderId,
                                                      ),
                                                    ),
                                                  );
                                                },
                                          icon: const Icon(Icons.storefront_outlined),
                                          label: Text(L10n.chatShop),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 10),
                      _SectionCard(
                        title: detailSectionTitle,
                        child: isTravelOrder
                            ? _TravelOrderSummary(viewData: viewData)
                            : Column(
                                children: products.isEmpty
                                    ? <Widget>[
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(L10n.noProductDetails),
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
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                          child: Text(L10n.declineJob),
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
                          label: Text(_isSubmitting ? L10n.savingJob : L10n.acceptJob),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<_IncomingOrderViewData> _buildViewDataImpl() async {
    final data = widget.initialData;
    final isTravelOrder = _isTravelPassengerOrder(data);
    final shippingFee = await _resolveShippingFee(data);
    final customerUid = _readCustomerUid(data);
    final shopOwnerUid = isTravelOrder ? null : _readShopOwnerUid(data);
    final customerPhone = await ContactPhoneResolver.resolveCustomerPhone(
      orderData: data,
      customerUid: customerUid,
    );
    final shopPhone = shopOwnerUid == null
        ? null
        : await ContactPhoneResolver.resolveShopPhone(
            orderData: data,
            ownerUid: shopOwnerUid,
            registrationCollections: _registrationCollections,
          );
    final riderToShopDistanceKm = await _resolveRiderToShopDistanceKm(
      data,
      requestLocationPermission: false,
    );
    final shopCoords = await _resolveShopCoordinates(data);
    final shopImageUrl = await ShopImageResolver.resolveForOrder(
      data,
      shopOwnerUid: shopOwnerUid,
    );
    RiderAppImagePrefetch.scheduleOrderCardImages(
      data,
      shopImageUrl: shopImageUrl,
    );
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
        pickupLabel: _readPickupLabel(data),
        vehicleTypeLabel: _readTravelVehicleLabel(data),
        travelVehicleType: readTravelVehicleTypeFromOrder(data),
        scheduleLabel: _readTravelScheduleLabel(data),
      shopCoords: shopCoords,
      shopImageUrl: shopImageUrl,
      products: _readProducts(
        data,
        fallbackShopImageUrl: shopImageUrl ?? ShopImageResolver.readFromOrder(data),
      ),
      total: (data['grandTotal'] as num?)?.toDouble() ??
          (data['totalPrice'] as num?)?.toDouble() ??
          0,
    );
  }

  Future<void> _acceptOrder() async {
    if (_isSubmitting || _isPromptingAccept) return;
    setState(() => _isPromptingAccept = true);
    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid == null || currentUid.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.signInRequiredAgain)),
        );
        return;
      }

      final orderRef = FirebaseFirestore.instance.collection('orders').doc(widget.orderId);
      final orderSnap = await orderRef.get();
      final data = orderSnap.data() ?? <String, dynamic>{};

      final isPayAtDestination = isPayAtDestinationOrder(data);
      final paymentLabel =
          resolveOrderPaymentLabel(data) ??
          (isPayAtDestination ? L10n.paymentPayAtDestination : '');

      if (isPayAtDestination) {
        final holdAmount = resolvePayAtDestinationHoldAmount(data);
        if (holdAmount > 0) {
          final currentCredit = await _fetchCurrentCreditBalance(currentUid);
          if (currentCredit < holdAmount) {
            final action = await _showInsufficientCreditDialog(
              holdAmount: holdAmount,
              currentCredit: currentCredit,
              paymentLabel: paymentLabel.isEmpty
                  ? L10n.paymentPayAtDestination
                  : paymentLabel,
            );

            if (action == _InsufficientCreditAction.topUp) {
              if (!mounted) return;
              await Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const WalletScreen()),
              );
              return;
            }

            if (action == _InsufficientCreditAction.reject) {
              await _rejectOrder();
              return;
            }

            return;
          }

          final confirmed = await _confirmDeductCreditDialog(
            holdAmount: holdAmount,
            currentCredit: currentCredit,
            paymentLabel: paymentLabel.isEmpty
                ? L10n.paymentPayAtDestination
                : paymentLabel,
          );
          if (!confirmed) {
            return;
          }
        }
      }

      if (!mounted) return;
      setState(() => _isSubmitting = true);

      await GuardedFunctions.call(
        'acceptRiderOrder',
        parameters: <String, dynamic>{'orderId': widget.orderId},
      );

      // Push พิกัดตอนรับงาน (action)
      unawaited(RiderLocationPusher.pushOnce(
        uid: currentUid,
        source: 'order_accepted',
      ));

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.jobAccepted)),
      );

      unawaited(_sendOrderAppNotification(
        targetApp: 'van1',
        recipientUid: _readTrimmedString(data['shopOwnerId']),
        orderId: widget.orderId,
        title: L10n.riderAcceptedJobTitle,
        body: L10n.riderAcceptedJobBody(_orderCodeSuffix(data)),
        action: 'order_accepted',
      ));
      return;
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? L10n.acceptJobFailed)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.acceptJobFailedWithError(error))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isPromptingAccept = false;
        });
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
      final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final driverId = _readTrimmedString(data['driverId']) ?? '';
      final status = _readTrimmedString(data['status']) ?? '';

      if (driverId.isNotEmpty &&
          currentUid.isNotEmpty &&
          driverId != currentUid) {
        if (!mounted) return;
        Navigator.of(context).pop(false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.orderTakenByOtherRider)),
        );
        return;
      }

      await GuardedFunctions.call(
        'rejectRiderOrder',
        parameters: <String, dynamic>{'orderId': widget.orderId},
      );

      if (!mounted) return;
      Navigator.of(context).pop(false);

      unawaited(_sendOrderAppNotification(
        targetApp: 'van2',
        recipientUid: _readTrimmedString(data['customerId']),
        orderId: widget.orderId,
        title: L10n.findingNewRiderTitle,
        body: L10n.findingNewRiderBody,
        action: 'order_rejected',
      ));

      unawaited(_sendOrderAppNotification(
        targetApp: 'van1',
        recipientUid: _readTrimmedString(data['shopOwnerId']),
        orderId: widget.orderId,
        title: L10n.riderDeclinedJobTitle,
        body: L10n.riderDeclinedJobBody(_orderCodeSuffix(data)),
        action: 'order_rejected',
      ));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'accepted'
                ? L10n.cancelAcceptFindingOther
                : L10n.declinedFindingOther,
          ),
        ),
      );
    } on FirebaseFunctionsException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message ?? L10n.updateStatusFailed)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.updateStatusFailedWithError(error))),
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
      'sourceApp': 'van3',
      'action': action,
    });
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
    final searchUri = Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng');
    final ok = await launchUrl(searchUri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.cannotOpenMap)),
      );
    }
  }

  String _readDestinationLabel(Map<String, dynamic> data) {
    final travelRequest = data['travelRequest'];
    if (travelRequest is Map<String, dynamic>) {
      final destination = travelRequest['destination'];
      if (destination is Map<String, dynamic>) {
        final label = _readTrimmedString(destination['title']);
        if (label != null && label.isNotEmpty) {
          return label;
        }
      }
    }

    final delivery = data['deliverySnapshot'];
    if (delivery is Map<String, dynamic>) {
      final label = _readTrimmedString(delivery['locationLabel']);
      if (label != null && label.isNotEmpty) {
        return label;
      }
    }

    final customer = data['customerLocation'];
    if (customer is Map<String, dynamic>) {
      final label = _readTrimmedString(customer['label']);
      if (label != null && label.isNotEmpty) {
        return label;
      }
    }

    return '-';
  }

  String _readPickupLabel(Map<String, dynamic> data) {
    final travelRequest = data['travelRequest'];
    if (travelRequest is Map<String, dynamic>) {
      final pickup = travelRequest['pickup'];
      if (pickup is Map<String, dynamic>) {
        final label = _readTrimmedString(pickup['title']);
        if (label != null && label.isNotEmpty) {
          return label;
        }
      }
    }

    return _readTrimmedString(data['shopName']) ?? '-';
  }

  String? _readTravelVehicleLabel(Map<String, dynamic> data) {
    final travelRequest = data['travelRequest'];
    if (travelRequest is Map<String, dynamic>) {
      return _readTrimmedString(travelRequest['vehicleTypeLabel']);
    }
    return null;
  }

  String? _readTravelScheduleLabel(Map<String, dynamic> data) {
    final travelRequest = data['travelRequest'];
    if (travelRequest is Map<String, dynamic>) {
      return _readTrimmedString(travelRequest['scheduleLabel']);
    }
    return null;
  }

  bool _isTravelPassengerOrder(Map<String, dynamic> data) {
    final orderType = _readTrimmedString(data['orderType']);
    final serviceType = _readTrimmedString(data['serviceType']);
    return orderType == 'travel_passenger' || serviceType == 'travel_passenger';
  }

  List<_IncomingOrderProduct> _readProducts(
    Map<String, dynamic> data, {
    String? fallbackShopImageUrl,
  }) {
    final rawProducts = ((data['products'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .cast<Map<dynamic, dynamic>>()
        .toList(growable: false);
    final shopImageFallback =
        fallbackShopImageUrl ?? ShopImageResolver.readFromOrder(data);

    return rawProducts.map((item) {
      return _IncomingOrderProduct(
        name: (item['name'] ?? item['productName'] ?? '-').toString(),
        quantity: int.tryParse((item['quantity'] ?? 0).toString()) ?? 0,
        unitPrice: double.tryParse((item['unitPrice'] ?? item['price'] ?? 0).toString()) ?? 0,
        imageUrl: ShopImageResolver.readProductImageUrl(
          item,
          fallbackShopImageUrl: shopImageFallback,
        ),
        note: (item['note'] ?? item['specialRequest'] ?? '').toString().trim(),
      );
    }).toList(growable: false);
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
      final travelRequest = data['travelRequest'];
      if (travelRequest is Map<String, dynamic>) {
        final destination = travelRequest['destination'];
        if (destination is Map<String, dynamic>) {
          lat = _toDouble(destination['latitude']) ?? _toDouble(destination['lat']);
          lng = _toDouble(destination['longitude']) ?? _toDouble(destination['lng']);
        }
      }
    }

    if (lat == null || lng == null) {
      return null;
    }

    return <String, double>{'lat': lat, 'lng': lng};
  }

  Future<double?> _resolveRiderToShopDistanceKm(
    Map<String, dynamic> data, {
    bool requestLocationPermission = true,
  }) async {
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

    final riderCoords = await _resolveRiderCoordinates(
      data,
      requestLocationPermission: requestLocationPermission,
    );
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
    Map<String, dynamic> data, {
    bool requestLocationPermission = true,
  }) async {
    final direct = _readCoordinatesFromAny(
      data,
      locationKey: 'riderLocation',
      latKey: 'riderLatitude',
      lngKey: 'riderLongitude',
    );
    if (direct != null) {
      return direct;
    }

    final livePosition = await _getFreshCurrentPosition(
      requestPermissionIfNeeded: requestLocationPermission,
    );
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
    if (_isTravelPassengerOrder(data)) {
      final travelRequest = data['travelRequest'];
      if (travelRequest is Map<String, dynamic>) {
        final pickup = travelRequest['pickup'];
        if (pickup is Map<String, dynamic>) {
          final lat = _toDouble(pickup['latitude']) ?? _toDouble(pickup['lat']);
          final lng = _toDouble(pickup['longitude']) ?? _toDouble(pickup['lng']);
          if (lat != null && lng != null) {
            return <String, double>{'lat': lat, 'lng': lng};
          }
        }
      }
    }

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

  Future<Position?> _getFreshCurrentPosition({
    bool requestPermissionIfNeeded = true,
  }) async {
    try {
      final current = await _getCurrentPosition(
        requestPermissionIfNeeded: requestPermissionIfNeeded,
      );
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

  Future<Position?> _getCurrentPosition({
    bool requestPermissionIfNeeded = true,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied && requestPermissionIfNeeded) {
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
    final direct = _readTrimmedString(data['customerId']);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final alternatives = <String>[
      _readTrimmedString(data['customerUid']) ?? '',
      _readTrimmedString(data['buyerId']) ?? '',
      _readTrimmedString(data['userId']) ?? '',
    ];
    for (final value in alternatives) {
      if (value.isNotEmpty) return value;
    }

    final snapshot = data['customerSnapshot'];
    if (snapshot is Map) {
      final fromSnapshot = <String>[
        _readTrimmedString(snapshot['uid']) ?? '',
        _readTrimmedString(snapshot['userId']) ?? '',
        _readTrimmedString(snapshot['customerId']) ?? '',
      ];
      for (final value in fromSnapshot) {
        if (value.isNotEmpty) return value;
      }
    }

    return null;
  }

  String? _readShopOwnerUid(Map<String, dynamic> data) {
    final direct = _readTrimmedString(data['shopOwnerId']);
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final alternatives = <String>[
      _readTrimmedString(data['shopId']) ?? '',
      _readTrimmedString(data['merchantId']) ?? '',
      _readTrimmedString(data['sellerId']) ?? '',
    ];
    for (final value in alternatives) {
      if (value.isNotEmpty) return value;
    }

    final shopSnapshot = data['shopSnapshot'];
    if (shopSnapshot is Map) {
      final fromSnapshot = <String>[
        _readTrimmedString(shopSnapshot['ownerId']) ?? '',
        _readTrimmedString(shopSnapshot['shopOwnerId']) ?? '',
        _readTrimmedString(shopSnapshot['uid']) ?? '',
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

  String? _readTrimmedString(Object? value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    return text;
  }

  String _orderCodeSuffix(Map<String, dynamic> data) {
    final code = _readTrimmedString(data['orderCode']);
    if (code == null) {
      return '';
    }
    return ' $code';
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
    required this.pickupLabel,
    required this.vehicleTypeLabel,
    required this.travelVehicleType,
    required this.scheduleLabel,
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
      pickupLabel: '-',
      vehicleTypeLabel: null,
      travelVehicleType: TravelVehicleType.motorcycle,
      scheduleLabel: null,
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
  final String pickupLabel;
  final String? vehicleTypeLabel;
  final TravelVehicleType travelVehicleType;
  final String? scheduleLabel;
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
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

class _TravelOrderSummary extends StatelessWidget {
  const _TravelOrderSummary({required this.viewData});

  final _IncomingOrderViewData viewData;

  @override
  Widget build(BuildContext context) {
    final travelRequest = viewData.orderData['travelRequest'];
    double? distanceKm;
    if (travelRequest is Map<String, dynamic>) {
      distanceKm = _toDoubleStatic(travelRequest['distanceKm']);
    }

    final note = viewData.products
        .map((product) => product.note.trim())
        .firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => '',
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.directions_bike_outlined, color: Color(0xFF2563EB)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${viewData.pickupLabel} → ${viewData.destinationLabel}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1D4ED8),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (distanceKm != null && distanceKm > 0) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            L10n.estimatedDistanceKm(distanceKm),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
        if (note.isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Text(
            note,
            style: const TextStyle(color: Color(0xFF4B5563)),
          ),
        ],
        const SizedBox(height: 10),
        Text(
          L10n.fareThb(viewData.total),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ],
    );
  }
}

double? _toDoubleStatic(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

class _OrderAvatar extends StatelessWidget {
  const _OrderAvatar({
    required this.imageUrl,
    required this.isTravelOrder,
    required this.travelVehicleType,
  });

  final String? imageUrl;
  final bool isTravelOrder;
  final TravelVehicleType travelVehicleType;

  @override
  Widget build(BuildContext context) {
    if (isTravelOrder) {
      return TravelOrderAvatar(
        vehicleType: travelVehicleType,
        size: 56,
        borderRadius: 16,
      );
    }

    return _ShopAvatar(imageUrl: imageUrl);
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
        child: const Icon(Icons.storefront_rounded, size: 28, color: Color(0xFFB45309)),
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
          child: const Icon(Icons.storefront_rounded, size: 28, color: Color(0xFFB45309)),
        ),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _ProductImage(imageUrl: product.imageUrl),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  product.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(L10n.quantityPieces(product.quantity)),
                Text(L10n.priceThb(product.unitPrice)),
                if (product.note.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    L10n.noteWithText(product.note),
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
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.fastfood_rounded, color: Color(0xFF6B7280)),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedAppImage(
        imageUrl: uri,
        width: 56,
        height: 56,
        fit: BoxFit.cover,
        lightweight: true,
        borderRadius: BorderRadius.circular(12),
        errorWidget: Container(
          width: 56,
          height: 56,
          color: const Color(0xFFE5E7EB),
          child: const Icon(Icons.fastfood_rounded, color: Color(0xFF6B7280)),
        ),
      ),
    );
  }
}