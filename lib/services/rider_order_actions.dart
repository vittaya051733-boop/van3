import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../driver_scanner_screen.dart';
import '../utils/order_pay_at_destination.dart';
import '../utils/settlement_payout_support.dart';
import '../utils/shop_location_resolver.dart';
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
          const SnackBar(content: Text('กรุณาเข้าสู่ระบบใหม่')),
        );
      }
      return false;
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
        return false;
      }

      final now = Timestamp.now();
      final grossShippingFee = await resolveShippingFee(orderData);
      final deliverySnapshot = buildDeliveryFinancialSnapshot(
        orderData: orderData,
        grossShippingFee: grossShippingFee,
        completedAt: now,
        completedSource: 'photo_proof',
      );
      final deliveredOrderData = <String, dynamic>{
        ...orderData,
        ...deliverySnapshot,
        'status': 'delivered',
      };
      final riderNetAmount = resolveRiderPayoutAmount(deliveredOrderData);
      final shopNetAmount = resolveShopPayoutAmount(orderData);
      final settlementPatch = buildPendingSettlementPatch(
        orderData: orderData,
        riderNetAmount: riderNetAmount,
        shopNetAmount: shopNetAmount,
        now: now,
      );
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

      final orderRef = FirebaseFirestore.instance.collection('orders').doc(orderId);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        releasePayAtDestinationHold(
          transaction: transaction,
          orderId: orderId,
          riderUid: currentUid,
          releaseAmount: isPayAtDestinationOrder(orderData)
              ? resolvePayAtDestinationCreditReleaseAmount(
                  orderData,
                  grossShippingFee: grossShippingFee,
                )
              : 0,
          completedSource: 'photo_proof',
        );

        transaction.update(orderRef, {
          'status': 'delivered',
          'deliveredAt': now,
          'updatedAt': now,
          ...deliverySnapshot,
          ...settlementPatch,
          'deliveryProofImageUrl': proofUrl,
          'deliveryProofStoragePath': storagePath,
          'deliveryProofCapturedAt': now,
          'deliveryProofCapturedById': currentUid,
          'deliveryProofCapturedByName': capturedByName,
        });
      });

      if (riderNetAmount > 0 || shopNetAmount > 0) {
        unawaited(
          enqueuePayoutPendingNotifications(
            orderId: orderId,
            orderData: orderData,
            riderNetAmount: riderNetAmount,
            shopNetAmount: shopNetAmount,
          ),
        );
      }

      unawaited(
        RiderLocationPusher.pushOnce(
          uid: currentUid,
          source: 'order_delivered_proof',
        ),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกรูปยืนยันและอัปเดตสถานะส่งสำเร็จแล้ว'),
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
            ? 'Firebase บล็อกการอัปโหลดรูป กรุณาลองใหม่อีกครั้ง'
            : 'บันทึกรูปยืนยันไม่สำเร็จ: $error';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
      return false;
    }
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
