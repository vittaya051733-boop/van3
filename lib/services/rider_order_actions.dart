import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/l10n.dart';
import '../driver_scanner_screen.dart';
import '../utils/order_pay_at_destination.dart';
import '../utils/shop_location_resolver.dart';
import '../utils/guarded_functions.dart';
import '../utils/upload_image_compressor.dart';
import 'rider_location_pusher.dart';

class RiderOrderActions {
  RiderOrderActions._();

  static final RiderOrderActions instance = RiderOrderActions._();

  Future<void> openMap(double lat, double lng) async {
    final navUri = Uri.parse('google.navigation:q=$lat,$lng&mode=l');
    if (await launchUrl(navUri, mode: LaunchMode.externalApplication)) {
      return;
    }
    final dirUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=two-wheeler&dir_action=navigate',
    );
    if (await launchUrl(dirUri, mode: LaunchMode.externalApplication)) {
      return;
    }
    final searchUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
    );
    final ok = await launchUrl(searchUri, mode: LaunchMode.externalApplication);
    if (!ok) {
      debugPrint('Unable to open map for $lat,$lng');
    }
  }

  Future<void> openShopMap(Map<String, dynamic> orderData) async {
    final coords = await resolveShopCoordinates(orderData);
    if (coords == null) {
      return;
    }
    await openMap(coords['lat']!, coords['lng']!);
  }

  Future<void> openCustomerMap(Map<String, dynamic> orderData) async {
    final coords = readDestinationCoordinates(orderData);
    if (coords == null) {
      return;
    }
    await openMap(coords['lat']!, coords['lng']!);
  }

  Future<bool> openQrScanner(
    BuildContext context, {
    required String orderId,
    required Map<String, dynamic> orderData,
  }) async {
    final orderCode = (orderData['orderCode'] as String?)?.trim();
    final total = readOrderTotal(orderData);
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => DriverScannerScreen(
          orderId: orderId,
          orderCode: orderCode,
          orderTotal: total,
        ),
      ),
    );
    return result == true;
  }

  Future<bool> captureDeliveryProof(
    BuildContext context, {
    required String orderId,
    required Map<String, dynamic> orderData,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUid = currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.signInRequiredAgain)),
        );
      }
      return false;
    }

    final status = (orderData['status'] as String?)?.trim() ?? '';
    if (status != 'delivering') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.mustBeDeliveringForPhoto)),
        );
      }
      return false;
    }

    final picker = ImagePicker();
    final captured = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (captured == null) {
      return false;
    }

    try {
      final compressed = await UploadImageCompressor.compressForUpload(
        File(captured.path),
      );
      final file = compressed.file;
      if (!context.mounted) {
        return false;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(L10n.confirmDeliveryPhotoTitle),
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
                Text(L10n.confirmDeliveryPhotoBody),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(L10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(L10n.confirmDelivered),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        return false;
      }

      final storagePath =
          'riders/$currentUid/delivery_proofs/$orderId/${DateTime.now().millisecondsSinceEpoch}_${compressed.fileName}';
      final storageRef = FirebaseStorage.instance.ref().child(storagePath);
      await storageRef.putFile(
        file,
        SettableMetadata(contentType: compressed.contentType),
      );
      final proofUrl = await storageRef.getDownloadURL();
      final capturedByName = _readNonEmptyString(
        (currentUser?.displayName ?? '').trim(),
        (orderData['driverName'] as String?)?.trim(),
        (orderData['riderName'] as String?)?.trim(),
      );

      await GuardedFunctions.call(
        'completeRiderDelivery',
        parameters: <String, dynamic>{
          'orderId': orderId,
          'completedSource': 'photo_proof',
          'deliveryProofImageUrl': proofUrl,
          'deliveryProofStoragePath': storagePath,
          'deliveryProofCapturedByName': capturedByName,
        },
      );

      unawaited(
        RiderLocationPusher.pushOnce(
          uid: currentUid,
          source: 'order_delivered_proof',
        ),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPayAtDestinationOrder(orderData)
                  ? L10n.photoProofSavedPendingRelease
                  : L10n.photoProofSavedDelivered,
            ),
          ),
        );
      }
      return true;
    } catch (error) {
      if (context.mounted) {
        final message =
            error is FirebaseException &&
                error.plugin == 'firebase_storage' &&
                error.code == 'unauthorized'
            ? L10n.uploadBlockedRetry
            : L10n.saveDeliveryProofFailed(error);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
      return false;
    }
  }

  Future<bool> markTravelPickupArrived(
    BuildContext context, {
    required String orderId,
    required Map<String, dynamic> orderData,
  }) {
    return _updateTravelStatus(
      context,
      orderId: orderId,
      orderData: orderData,
      expectedStatus: 'accepted',
      nextStatus: 'ready',
      pickupArrived: true,
      locationSource: 'travel_pickup_arrived',
      successMessage: L10n.arrivedPickupStartTripHint,
    );
  }

  Future<bool> startTravelTrip(
    BuildContext context, {
    required String orderId,
    required Map<String, dynamic> orderData,
  }) {
    return _updateTravelStatus(
      context,
      orderId: orderId,
      orderData: orderData,
      expectedStatus: 'ready',
      nextStatus: 'delivering',
      startDelivery: true,
      locationSource: 'travel_trip_started',
      successMessage: L10n.tripStartedArriveHint,
    );
  }

  Future<bool> completeTravelAtDestination(
    BuildContext context, {
    required String orderId,
    required Map<String, dynamic> orderData,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final currentUid = currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.signInRequiredAgain)),
        );
      }
      return false;
    }

    final status = (orderData['status'] as String?)?.trim() ?? '';
    final driverId = (orderData['driverId'] as String?)?.trim();
    if (driverId != null && driverId.isNotEmpty && driverId != currentUid) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.orderNotYours)),
        );
      }
      return false;
    }

    if (status != 'delivering') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.cannotCompleteInStatus(status))),
        );
      }
      return false;
    }

    final confirmed = await _confirmTravelDestinationComplete(context, orderData);
    if (!confirmed) {
      return false;
    }

    try {
      await GuardedFunctions.call(
        'completeRiderDelivery',
        parameters: <String, dynamic>{
          'orderId': orderId,
          'completedSource': 'travel_destination',
        },
      );

      unawaited(
        RiderLocationPusher.pushOnce(
          uid: currentUid,
          source: 'travel_destination_complete',
        ),
      );

      if (context.mounted) {
        final isCod = isPayAtDestinationOrder(orderData);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCod
                  ? L10n.passengerArrivedPendingRelease
                  : L10n.passengerArrivedPendingPayout,
            ),
          ),
        );
      }
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.completeJobFailed(error))),
        );
      }
      return false;
    }
  }

  Future<bool> _updateTravelStatus(
    BuildContext context, {
    required String orderId,
    required Map<String, dynamic> orderData,
    required String expectedStatus,
    required String nextStatus,
    required String locationSource,
    required String successMessage,
    bool pickupArrived = false,
    bool startDelivery = false,
  }) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.signInRequiredAgain)),
        );
      }
      return false;
    }

    final status = (orderData['status'] as String?)?.trim() ?? '';
    final driverId = (orderData['driverId'] as String?)?.trim();
    if (driverId != null && driverId.isNotEmpty && driverId != currentUid) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.orderNotYours)),
        );
      }
      return false;
    }

    if (status != expectedStatus) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.cannotUpdateInStatus(status))),
        );
      }
      return false;
    }

    try {
      final update = <String, dynamic>{
        'status': nextStatus,
        'driverId': currentUid,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (pickupArrived) {
        update['pickupArrivedAt'] = FieldValue.serverTimestamp();
      }
      if (startDelivery) {
        update['deliveryStartTime'] = FieldValue.serverTimestamp();
      }

      await FirebaseFirestore.instance.collection('orders').doc(orderId).update(update);
      unawaited(
        RiderLocationPusher.pushOnce(uid: currentUid, source: locationSource),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
      return true;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(L10n.updateStatusFailedWithError(error))),
        );
      }
      return false;
    }
  }

  Future<bool> _confirmTravelDestinationComplete(
    BuildContext context,
    Map<String, dynamic> orderData,
  ) async {
    final isCod = isPayAtDestinationOrder(orderData);
    final fare = await resolveTravelFare(orderData);
    if (!context.mounted) {
      return false;
    }
    final fareLabel = fare > 0 ? fare.toStringAsFixed(1) : '-';

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(L10n.confirmDestinationArrivalTitle),
          content: Text(
            isCod
                ? L10n.confirmDestinationArrivalCod(fareLabel)
                : L10n.confirmDestinationArrival(fareLabel),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(L10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(L10n.confirmArrivedDestination),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<double> resolveTravelFare(Map<String, dynamic> data) async {
    final travelRequest = data['travelRequest'];
    if (travelRequest is Map) {
      final fare = _toDouble(travelRequest['fare']);
      if (fare != null && fare > 0) {
        return fare;
      }
    }

    final grandTotal = _toDouble(data['grandTotal']);
    if (grandTotal != null && grandTotal > 0) {
      return grandTotal;
    }

    return resolveShippingFee(data);
  }

  Future<Map<String, double>?> resolveShopCoordinates(
    Map<String, dynamic> data,
  ) {
    return ShopLocationResolver.resolveForOrder(
      data,
      shopOwnerUid: readShopOwnerUid(data),
    );
  }

  Map<String, double>? readDestinationCoordinates(Map<String, dynamic> data) {
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

  String? readShopOwnerUid(Map<String, dynamic> data) {
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
      if (value.isNotEmpty) {
        return value;
      }
    }

    final shopSnapshot = data['shopSnapshot'];
    if (shopSnapshot is Map) {
      final fromSnapshot = <String>[
        (shopSnapshot['ownerId'] as String?)?.trim() ?? '',
        (shopSnapshot['shopOwnerId'] as String?)?.trim() ?? '',
        (shopSnapshot['uid'] as String?)?.trim() ?? '',
      ];
      for (final value in fromSnapshot) {
        if (value.isNotEmpty) {
          return value;
        }
      }
    }

    return null;
  }

  double readOrderTotal(Map<String, dynamic> data) {
    return _toDouble(data['grandTotal']) ??
        _toDouble(data['totalAmount']) ??
        _toDouble(data['totalPrice']) ??
        _toDouble(data['subtotal']) ??
        0;
  }

  Future<double> resolveShippingFee(Map<String, dynamic> data) async {
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

    final shopCoords = await resolveShopCoordinates(data);
    final customerCoords = readDestinationCoordinates(data);
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

  String? _readNonEmptyString(String? first, String? second, String? third) {
    for (final value in <String?>[first, second, third]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        return trimmed;
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
