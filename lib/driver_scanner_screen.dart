import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'l10n/l10n.dart';
import 'services/rider_location_pusher.dart';
import 'utils/guarded_functions.dart';

class DriverScannerScreen extends StatefulWidget {
  const DriverScannerScreen({
    super.key,
    required this.orderId,
    this.orderCode,
    required this.orderTotal,
  });

  final String orderId;
  final String? orderCode;
  final double orderTotal;

  @override
  State<DriverScannerScreen> createState() => _DriverScannerScreenState();
}

class _DriverScannerScreenState extends State<DriverScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;
  String? _lastScannedCode;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.orderCode?.trim().isNotEmpty == true
              ? L10n.scanQrForOrder(widget.orderCode!.trim())
              : L10n.scanQrOrder,
        ),
        actions: [
          IconButton(
            onPressed: () => _scannerController.toggleTorch(),
            icon: const Icon(Icons.flash_on),
          ),
          IconButton(
            onPressed: () => _scannerController.switchCamera(),
            icon: const Icon(Icons.flip_camera_ios),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleBarcode,
          ),
          CustomPaint(painter: _ScannerOverlayPainter(), child: Container()),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.qr_code_scanner, color: Colors.white, size: 48),
                  SizedBox(height: 16),
                  Text(
                    L10n.alignCameraWithQr,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    L10n.scanQrInstructions,
                    style: TextStyle(color: Colors.white70, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(L10n.processing),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_isProcessing) return;
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final code = barcodes.first.rawValue?.trim();
    if (code == null || code.isEmpty) return;
    if (code == _lastScannedCode) return;

    _lastScannedCode = code;
    setState(() => _isProcessing = true);
    _processQrCode(code);
  }

  Future<void> _processQrCode(String qrCode) async {
    try {
      final payload = _parseQrPayload(qrCode);
      if (payload == null) {
        _showError(L10n.invalidQrCode);
      } else if (payload.type == _QrPayloadType.universal) {
        await _handleUniversalQr(payload);
      } else if (payload.type == _QrPayloadType.order) {
        await _handleOrderQr(payload);
      } else {
        await _handleLocationQr(payload);
      }
    } catch (error) {
      _showError(L10n.errorOccurred(error));
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      Future.delayed(const Duration(seconds: 2), () {
        _lastScannedCode = null;
      });
    }
  }

  Future<void> _handleUniversalQr(_ScannedQrPayload payload) async {
    final orderDoc = await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .get();
    if (!orderDoc.exists) {
      _showError(L10n.orderNotFound);
      return;
    }

    final data = orderDoc.data() ?? <String, dynamic>{};
    final status = (data['status'] as String?)?.trim() ?? '';
    if (status == 'accepted' || status == 'ready') {
      await _handleOrderQr(payload);
      return;
    }
    if (status == 'delivering') {
      await _handleLocationQr(payload);
      return;
    }

    _showError(L10n.orderQrNotAvailableForStatus(status));
  }

  Future<void> _handleOrderQr(_ScannedQrPayload payload) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError(L10n.signInRequired);
      return;
    }

    final orderRef = FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      _showError(L10n.orderNotFound);
      return;
    }

    final data = orderDoc.data() ?? <String, dynamic>{};
    final mismatches = _buildQrMismatchMessages(payload, data);
    if (mismatches.isNotEmpty) {
      _showMismatchAlert(mismatches);
      return;
    }

    final status = (data['status'] as String?)?.trim() ?? '';
    final driverId = (data['driverId'] as String?)?.trim();
    if (driverId != null && driverId.isNotEmpty && driverId != user.uid) {
      _showError(L10n.orderNotAssignedToYou);
      return;
    }
    if (status != 'accepted' && status != 'ready') {
      _showError(L10n.orderNotReadyToDeliver(status));
      return;
    }

    await orderRef.update({
      'status': 'delivering',
      'deliveryStartTime': Timestamp.now(),
      'driverId': user.uid,
      'scannedByDriverId': user.uid,
      'scannedAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });

    // Push พิกัดตอนเริ่มจัดส่ง (action)
    unawaited(
      RiderLocationPusher.pushOnce(uid: user.uid, source: 'order_pickup_scan'),
    );

    if (!mounted) return;
    _scannerController.stop();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.local_shipping_rounded, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text(L10n.deliveryStarted),
          ],
        ),
        content: Text(L10n.scanAgainToComplete),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _scannerController.start();
            },
            child: Text(L10n.ok),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLocationQr(_ScannedQrPayload payload) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError(L10n.signInRequired);
      return;
    }

    final orderRef = FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId);
    final orderDoc = await orderRef.get();
    if (!orderDoc.exists) {
      _showError(L10n.orderNotFound);
      return;
    }

    final data = orderDoc.data() ?? <String, dynamic>{};
    final mismatches = _buildQrMismatchMessages(payload, data);
    if (mismatches.isNotEmpty) {
      _showMismatchAlert(mismatches);
      return;
    }

    final status = (data['status'] as String?)?.trim() ?? '';
    final driverId = (data['driverId'] as String?)?.trim();
    if (driverId != user.uid) {
      _showError(L10n.orderNotAssignedToYou);
      return;
    }
    if (status != 'delivering') {
      _showError(L10n.orderNotDelivering(status));
      return;
    }

    await GuardedFunctions.call(
      'completeRiderDelivery',
      parameters: <String, dynamic>{
        'orderId': widget.orderId,
        'completedSource': 'location_qr',
      },
    );

    // Push พิกัดตอนส่งสำเร็จ (action)
    unawaited(
      RiderLocationPusher.pushOnce(
        uid: user.uid,
        source: 'order_delivered_scan',
      ),
    );

    if (!mounted) return;
    _scannerController.stop();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.celebration, color: Colors.green, size: 28),
            SizedBox(width: 12),
            Text(L10n.deliveryCompleted),
          ],
        ),
        content: Text(L10n.deliveryJobClosed),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(this.context).pop(true);
            },
            child: Text(L10n.done),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  _ScannedQrPayload? _parseQrPayload(String qrCode) {
    final separator = qrCode.indexOf(':');
    if (separator <= 0) {
      return null;
    }

    final rawType = qrCode.substring(0, separator).trim().toUpperCase();
    final rawBody = qrCode.substring(separator + 1).trim();
    if (rawBody.isEmpty) {
      return null;
    }

    final parts = rawBody
        .split('|')
        .map((part) => part.trim())
        .toList(growable: false);
    final orderId = parts.isNotEmpty ? parts.first : '';
    if (orderId.isEmpty) {
      return null;
    }

    final orderCode = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
    final total = parts.length > 2 ? double.tryParse(parts[2]) : null;
    switch (rawType) {
      case 'ORDER':
        return _ScannedQrPayload(
          type: _QrPayloadType.order,
          orderId: orderId,
          orderCode: orderCode,
          orderTotal: total,
        );
      case 'LOCATION':
        return _ScannedQrPayload(
          type: _QrPayloadType.location,
          orderId: orderId,
          orderCode: orderCode,
          orderTotal: total,
        );
      case 'VAN_ORDER':
      case 'ORDER_FLOW':
        return _ScannedQrPayload(
          type: _QrPayloadType.universal,
          orderId: orderId,
          orderCode: orderCode,
          orderTotal: total,
        );
      default:
        return null;
    }
  }

  List<String> _buildQrMismatchMessages(
    _ScannedQrPayload payload,
    Map<String, dynamic> orderData,
  ) {
    final mismatches = <String>[];

    if (payload.orderId != widget.orderId) {
      mismatches.add(L10n.qrOrderIdMismatch);
    }

    final expectedOrderCode =
        (widget.orderCode ?? _readOrderCode(orderData) ?? '').trim();
    final actualOrderCode =
        (payload.orderCode ?? _readOrderCode(orderData) ?? '').trim();
    if (expectedOrderCode.isEmpty ||
        actualOrderCode.isEmpty ||
        expectedOrderCode != actualOrderCode) {
      mismatches.add(L10n.qrOrderCodeMismatch);
    }

    final actualTotal = payload.orderTotal ?? _readOrderTotal(orderData);
    if (_totalsDiffer(widget.orderTotal, actualTotal)) {
      mismatches.add(L10n.qrTotalMismatch);
    }

    return mismatches;
  }

  String? _readOrderCode(Map<String, dynamic> data) {
    final direct = (data['orderCode'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }
    return (data['orderNumber'] as String?)?.trim();
  }

  double _readOrderTotal(Map<String, dynamic> data) {
    return _toDouble(data['grandTotal']) ??
        _toDouble(data['totalAmount']) ??
        _toDouble(data['totalPrice']) ??
        _toDouble(data['subtotal']) ??
        0;
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
      return double.parse(delta.toStringAsFixed(1));
    }

    return 0;
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

  bool _totalsDiffer(double expected, double actual) {
    return (expected - actual).abs() > 0.05;
  }

  Future<void> _showMismatchAlert(List<String> mismatches) async {
    if (!mounted) return;
    _scannerController.stop();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.qrMismatchTitle),
        content: Text(mismatches.join('\n')),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              _scannerController.start();
            },
            child: Text(L10n.ok),
          ),
        ],
      ),
    );
  }
}

enum _QrPayloadType { order, location, universal }

class _ScannedQrPayload {
  const _ScannedQrPayload({
    required this.type,
    required this.orderId,
    required this.orderCode,
    required this.orderTotal,
  });

  final _QrPayloadType type;
  final String orderId;
  final String? orderCode;
  final double? orderTotal;
}

class _ScannerOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final scanAreaSize = size.width * 0.7;
    final left = (size.width - scanAreaSize) / 2;
    final top = (size.height - scanAreaSize) / 2;
    final scanArea = Rect.fromLTWH(left, top, scanAreaSize, scanAreaSize);

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(
          RRect.fromRectAndRadius(scanArea, const Radius.circular(16)),
        ),
      ),
      paint,
    );

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(scanArea, const Radius.circular(16)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
