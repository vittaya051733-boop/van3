import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_gallery_saver2_fixed/image_gallery_saver2_fixed.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';

class WalletTopUpDialog extends StatefulWidget {
  const WalletTopUpDialog({super.key});

  @override
  State<WalletTopUpDialog> createState() => _WalletTopUpDialogState();
}

class _WalletTopUpDialogState extends State<WalletTopUpDialog> {
  static const List<double> _presets = <double>[500, 1000, 2000, 3000];

  static const String _appLogoAsset = 'assets/app_logo.png';

  static const String _promptPayPurposeNote = 'เติม เครดิตไรเดอร์';

  final TextEditingController _customAmountController = TextEditingController();
  final GlobalKey _qrBoundaryKey = GlobalKey();

  bool _loadingConfig = true;
  bool _isBusy = false;

  String? _promptPayNationalId;
  double? _selectedAmount;
  XFile? _selectedSlipImage;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPaymentConfig());
  }

  @override
  void dispose() {
    _customAmountController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentConfig() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('payment_config')
          .doc('collection')
          .get()
          .timeout(const Duration(seconds: 5));
      final data = snapshot.data() ?? const <String, dynamic>{};
      final value = data['promptPayNationalIdOrTaxId']?.toString().trim();
      if (value != null && value.isNotEmpty) {
        _promptPayNationalId = value;
      } else {
        _promptPayNationalId = '1410400168710';
      }
    } catch (_) {
      _promptPayNationalId = '1410400168710';
    } finally {
      if (mounted) {
        setState(() => _loadingConfig = false);
      }
    }
  }

  void _selectPreset(double amount) {
    setState(() {
      _selectedAmount = amount;
      _customAmountController.text = '';
    });
  }

  void _onCustomAmountChanged(String value) {
    final parsed = double.tryParse(value);
    setState(() {
      _selectedAmount = (parsed != null && parsed > 0) ? parsed : null;
    });
  }

  double? get _amount => _selectedAmount;

  bool get _canGeneratePromptPayQr {
    final amount = _amount;
    final nationalId = _promptPayNationalId;
    return amount != null && amount > 0 && nationalId != null && nationalId.isNotEmpty;
  }

  Future<void> _saveQrToGallery() async {
    if (kIsWeb) {
      _showSnack('บันทึก QR บน Web ยังไม่รองรับ');
      return;
    }

    if (!_canGeneratePromptPayQr) {
      _showSnack('ยังไม่มี QR สำหรับบันทึก');
      return;
    }

    setState(() => _isBusy = true);
    try {
      final double pixelRatio = View.of(context).devicePixelRatio;

      final permission = await Permission.photos.request();
      if (!permission.isGranted) {
        final storagePermission = await Permission.storage.request();
        if (!storagePermission.isGranted) {
          _showSnack('ไม่ได้รับสิทธิ์เข้าถึงรูปภาพ/พื้นที่จัดเก็บ');
          return;
        }
      }

      if (!mounted) {
        return;
      }

      final boundary = _qrBoundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _showSnack('บันทึก QR ไม่สำเร็จ');
        return;
      }
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _showSnack('บันทึก QR ไม่สำเร็จ');
        return;
      }

      final bytes = byteData.buffer.asUint8List();
      final result = await ImageGallerySaver.saveImage(
        bytes,
        quality: 100,
        name: 'promptpay_topup_${DateTime.now().millisecondsSinceEpoch}',
      );

      final success = result['isSuccess'] == true;
      _showSnack(success ? 'บันทึก QR ลงเครื่องเรียบร้อย' : 'บันทึก QR ไม่สำเร็จ');
    } catch (error) {
      _showSnack('บันทึก QR ไม่สำเร็จ: $error');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<void> _pickSlipImage() async {
    if (kIsWeb) {
      _showSnack('แนบสลิปบน Web ยังไม่รองรับ');
      return;
    }

    if (!_canGeneratePromptPayQr) {
      _showSnack('กรุณาเลือกจำนวนเงินก่อน');
      return;
    }

    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 92);
      if (image == null || !mounted) {
        return;
      }

      setState(() => _selectedSlipImage = image);
    } catch (error) {
      _showSnack('เลือกสลิปไม่สำเร็จ: $error');
    }
  }

  Future<void> _verifySelectedSlip() async {
    if (kIsWeb) {
      _showSnack('แนบสลิปบน Web ยังไม่รองรับ');
      return;
    }

    final image = _selectedSlipImage;
    if (image == null) {
      _showSnack('กรุณาเลือกรูปสลิปก่อน');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('กรุณาเข้าสู่ระบบก่อน');
      return;
    }

    final amount = _amount;
    if (amount == null || amount <= 0) {
      _showSnack('กรุณาเลือกจำนวนเงินก่อน');
      return;
    }

    setState(() => _isBusy = true);
    try {
      const source = ImageSource.gallery;
      final paymentGroupId = _newPaymentGroupId(user.uid);
      final fileName = image.name.isNotEmpty ? image.name : 'slip.jpg';
      final contentType = _guessContentType(fileName);
      final objectPath = 'riders/${user.uid}/topups/$paymentGroupId/$fileName';

      await _ensureTopUpSlipDocExists(
        uid: user.uid,
        paymentGroupId: paymentGroupId,
        expectedAmount: amount,
        storagePath: objectPath,
        fileName: fileName,
        contentType: contentType,
        source: source,
      );

      final ref = FirebaseStorage.instance.ref().child(objectPath);
      await ref.putFile(
        File(image.path),
        SettableMetadata(contentType: contentType),
      );

      // Also store a WebP copy for smaller size / consistent format.
      final webpBytes = await _tryEncodeToWebpBytes(image.path);
      if (webpBytes != null && webpBytes.isNotEmpty) {
        final webpPath = 'riders/${user.uid}/topups/$paymentGroupId/slip.webp';
        final webpRef = FirebaseStorage.instance.ref().child(webpPath);
        await webpRef.putData(
          webpBytes,
          SettableMetadata(contentType: 'image/webp'),
        );

        await _patchTopUpSlipDoc(
          uid: user.uid,
          paymentGroupId: paymentGroupId,
          patch: <String, dynamic>{
            'webpPath': webpPath,
            'webpContentType': 'image/webp',
            'webpBytes': webpBytes.length,
          },
        );
      }

      await _patchTopUpSlipDoc(
        uid: user.uid,
        paymentGroupId: paymentGroupId,
        patch: <String, dynamic>{
          'status': 'uploaded',
          'uploadedAt': FieldValue.serverTimestamp(),
        },
      );

      final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('verifyTopUpSlip');

      final response = await callable.call(<String, dynamic>{
        'uid': user.uid,
        'expectedAmount': amount,
        'storagePath': objectPath,
        'bucket': Firebase.app().options.storageBucket,
        'paymentGroupId': paymentGroupId,
        'fileName': fileName,
        'contentType': contentType,
      });

      final data = (response.data is Map)
          ? Map<String, dynamic>.from(response.data as Map)
          : const <String, dynamic>{};

      final success = data['success'] == true;
      final message = data['message']?.toString().trim();
      final verifiedAmount = (data['verifiedAmount'] is num)
          ? (data['verifiedAmount'] as num).toDouble()
          : null;
      final remainingAmount = (data['remainingAmount'] is num)
          ? (data['remainingAmount'] as num).toDouble()
          : null;
      final overpaidAmount = (data['overpaidAmount'] is num)
          ? (data['overpaidAmount'] as num).toDouble()
          : null;

      await _patchTopUpSlipDoc(
        uid: user.uid,
        paymentGroupId: paymentGroupId,
        patch: <String, dynamic>{
          'status': success ? 'verified' : 'failed',
          'verifiedAt': FieldValue.serverTimestamp(),
          'success': success,
          if (message != null && message.isNotEmpty) 'message': message,
          if (verifiedAmount != null) 'verifiedAmount': verifiedAmount,
          if (remainingAmount != null) 'remainingAmount': remainingAmount,
          if (overpaidAmount != null) 'overpaidAmount': overpaidAmount,
          'rawResponse': data,
        },
      );

      if (!mounted) {
        return;
      }

      if (success) {
        final details = <String>[];
        if (verifiedAmount != null) {
          details.add('เติมเครดิต ${verifiedAmount.toStringAsFixed(2)} บาท');
        }
        if (remainingAmount != null && remainingAmount > 0) {
          details.add('คงเหลือต้องจ่ายอีก ${remainingAmount.toStringAsFixed(2)} บาท');
        }
        if (overpaidAmount != null && overpaidAmount > 0) {
          details.add('จ่ายเกิน ${overpaidAmount.toStringAsFixed(2)} บาท (ระบบเติมตามยอดที่จ่าย)');
        }

        final shouldContinueForRemaining = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ผลตรวจสลิป'),
            content: Text(
              [
                if (message != null && message.isNotEmpty) message,
                if (details.isNotEmpty) details.join('\n'),
              ].where((line) => line.trim().isNotEmpty).join('\n\n'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('ปิด'),
              ),
              if (remainingAmount != null && remainingAmount > 0)
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('สร้าง QR ยอดคงเหลือ'),
                )
              else
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('ตกลง'),
                ),
            ],
          ),
        );

        if (!mounted) {
          return;
        }

        if (remainingAmount != null && remainingAmount > 0 && shouldContinueForRemaining == true) {
          setState(() {
            _selectedAmount = remainingAmount;
            _customAmountController.text = remainingAmount.toStringAsFixed(2);
          });
          _showSnack('สร้าง QR สำหรับยอดคงเหลือเรียบร้อย');
          return;
        }

        Navigator.of(context).pop(true);
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ผลตรวจสลิป'),
            content: Text(message?.isNotEmpty == true ? message! : 'ตรวจสลิปไม่สำเร็จ'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('ตกลง'),
              ),
            ],
          ),
        );
      }
    } on FirebaseFunctionsException catch (error) {
      _showSnack(error.message ?? 'ตรวจสลิปไม่สำเร็จ');
    } catch (error) {
      _showSnack('ตรวจสลิปไม่สำเร็จ: $error');
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  DocumentReference<Map<String, dynamic>> _topUpSlipDocRef({
    required String uid,
    required String paymentGroupId,
  }) {
    return FirebaseFirestore.instance
        .collection('riders')
        .doc(uid)
        .collection('topup_slips')
        .doc(paymentGroupId);
  }

  Future<void> _ensureTopUpSlipDocExists({
    required String uid,
    required String paymentGroupId,
    required double expectedAmount,
    required String storagePath,
    required String fileName,
    required String contentType,
    required ImageSource source,
  }) async {
    try {
      final ref = _topUpSlipDocRef(uid: uid, paymentGroupId: paymentGroupId);
      final snap = await ref.get();
      if (snap.exists) {
        return;
      }

      await ref.set(<String, dynamic>{
        'uid': uid,
        'paymentGroupId': paymentGroupId,
        'expectedAmount': expectedAmount,
        'storagePath': storagePath,
        'fileName': fileName,
        'contentType': contentType,
        'source': source.name,
        'status': 'picked',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Best-effort logging: rules/network may block this; slip verify can still proceed.
    }
  }

  Future<void> _patchTopUpSlipDoc({
    required String uid,
    required String paymentGroupId,
    required Map<String, dynamic> patch,
  }) async {
    try {
      final ref = _topUpSlipDocRef(uid: uid, paymentGroupId: paymentGroupId);
      await ref.set(
        <String, dynamic>{
          ...patch,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Best-effort logging.
    }
  }

  String _newPaymentGroupId(String uid) {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(999999).toString().padLeft(6, '0');
    return 'topup_${uid}_$stamp$rand';
  }

  String _guessContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<Uint8List?> _tryEncodeToWebpBytes(String inputPath) async {
    try {
      final result = await FlutterImageCompress.compressWithFile(
        inputPath,
        format: CompressFormat.webp,
        quality: 92,
      );
      return result;
    } catch (_) {
      return null;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildSlipPickerPanel() {
    final enabled = !_isBusy && _canGeneratePromptPayQr;
    final selectedSlipImage = _selectedSlipImage;

    return Container(
      width: 240,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.receipt_long_outlined, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'แนบสลิป',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: selectedSlipImage == null ? 'เลือกจากแกลเลอรี' : 'เปลี่ยนรูปสลิป',
                visualDensity: VisualDensity.compact,
                onPressed: enabled ? () => unawaited(_pickSlipImage()) : null,
                icon: const Icon(Icons.photo_library_outlined),
              ),
            ],
          ),
          if (selectedSlipImage != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: double.infinity,
                height: 140,
                child: Image.file(
                  File(selectedSlipImage.path),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: enabled ? _verifySelectedSlip : null,
                child: _isBusy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text('ส่งสลิปเพื่อตรวจสอบ'),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _twoDigitLength(int length) => length < 10 ? '0$length' : '$length';

  static int _crc16CcittFalse(String data) {
    int crc = 0xFFFF;
    final bytes = utf8.encode(data);
    for (final b in bytes) {
      int x = ((crc >> 8) ^ b) & 0xFF;
      x ^= x >> 4;
      crc = ((crc << 8) ^ (x << 12) ^ (x << 5) ^ x) & 0xFFFF;
    }
    return crc;
  }

  static String _generatePromptPayPayload({
    required String promptPayId,
    required double amount,
    String? purposeNote,
  }) {
    if (promptPayId.length != 10 && promptPayId.length != 13) {
      return '';
    }

    const String start = '000201';
    const String acceptRecycle = '010211';
    const String merchantInfo = '0016A000000677010111';

    final String merchantInfoType = promptPayId.length == 10
        ? '2937$merchantInfo' '01130066${promptPayId.substring(1)}'
        : '2937$merchantInfo' '0213$promptPayId';

    const String country = '5802TH';
    const String currencyISO = '5303764';

    String dataAmount = '';
    if (amount > 0) {
      final String amountText = amount.toStringAsFixed(2);
      dataAmount = '54${_twoDigitLength(amountText.length)}$amountText';
    }

    String additionalData = '';
    final note = purposeNote?.trim();
    if (note != null && note.isNotEmpty) {
      // EMVCo Additional Data Field Template (62), use sub-tag 08 (Purpose of Transaction).
      final int noteByteLen = utf8.encode(note).length;
      final String subField = '08${_twoDigitLength(noteByteLen)}$note';
      final int subFieldByteLen = utf8.encode(subField).length;
      additionalData = '62${_twoDigitLength(subFieldByteLen)}$subField';
    }

    const String checkSumTag = '6304';
    final String payloadBeforeCrc =
        '$start$acceptRecycle$merchantInfoType$country$dataAmount$currencyISO$additionalData$checkSumTag';

    final String crc = _crc16CcittFalse(payloadBeforeCrc)
        .toRadixString(16)
        .toUpperCase()
        .padLeft(4, '0');
    return '$payloadBeforeCrc$crc';
  }

  @override
  Widget build(BuildContext context) {
    final canGenerateQr = _canGeneratePromptPayQr;
    final amount = _amount;
    final nationalId = _promptPayNationalId;

    final amountLabel = (amount ?? 0).toStringAsFixed(2);

    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: const Text('เติมเครดิต'),
      content: SizedBox(
        width: 420,
        child: _loadingConfig
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('เลือกจำนวนเงิน'),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final preset in _presets)
                            ChoiceChip(
                              label: Text(preset.toStringAsFixed(0)),
                              selected: amount == preset,
                              onSelected: _isBusy ? null : (_) => _selectPreset(preset),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _customAmountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        enabled: !_isBusy,
                        decoration: const InputDecoration(
                          labelText: 'กำหนดเอง',
                          hintText: 'เช่น 1500',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: _onCustomAmountChanged,
                      ),
                      const SizedBox(height: 14),
                      if (!canGenerateQr)
                        const Text('กรุณาเลือกจำนวนเงินเพื่อสร้าง QR')
                      else
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(
                              child: RepaintBoundary(
                                key: _qrBoundaryKey,
                                child: Container(
                                  width: 240,
                                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        height: 28,
                                        width: double.infinity,
                                        color: const Color(0xFF0E55AA),
                                        alignment: Alignment.center,
                                        child: Image.asset(
                                          'assets/images/thai_qr_payment.png',
                                          package: 'promptpay_qrcode_generate',
                                          height: 22,
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Image.asset(
                                        'assets/images/prompt_pay_logo.png',
                                        package: 'promptpay_qrcode_generate',
                                        height: 28,
                                        fit: BoxFit.contain,
                                      ),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        width: 150,
                                        height: 150,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            Builder(
                                              builder: (context) {
                                                final data = _generatePromptPayPayload(
                                                  promptPayId: nationalId!,
                                                  amount: amount!,
                                                  purposeNote: _promptPayPurposeNote,
                                                );

                                                if (data.isEmpty) {
                                                  return const Center(
                                                    child: Text('PromptPay ID ไม่ถูกต้อง'),
                                                  );
                                                }

                                                return QrImageView(
                                                  data: data,
                                                  errorCorrectionLevel: QrErrorCorrectLevel.Q,
                                                  backgroundColor: Colors.white,
                                                );
                                              },
                                            ),
                                            Positioned.fill(
                                              child: IgnorePointer(
                                                child: Align(
                                                  // Shift logo up ~3% of the QR area height.
                                                  alignment: Alignment(0, -0.06),
                                                  child: _TrimmedAssetImage(
                                                    assetName: _appLogoAsset,
                                                    size: 16,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Account ($nationalId)',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Amount $amountLabel Baht',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _buildSlipPickerPanel(),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _isBusy ? null : () => Navigator.of(context).pop(false),
          child: const Text('ปิด'),
        ),
        FilledButton(
          onPressed: (_isBusy || !canGenerateQr) ? null : _saveQrToGallery,
          child: _isBusy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('บันทึก QR ลงเครื่อง'),
                ),
        ),
      ],
    );
  }
}

class _TrimInfo {
  const _TrimInfo({required this.image, required this.srcRect});

  final ui.Image image;
  final Rect srcRect;
}

class _TrimmedAssetImage extends StatefulWidget {
  const _TrimmedAssetImage({required this.assetName, required this.size});

  final String assetName;
  final double size;

  @override
  State<_TrimmedAssetImage> createState() => _TrimmedAssetImageState();
}

class _TrimmedAssetImageState extends State<_TrimmedAssetImage> {
  static final Map<String, Future<_TrimInfo>> _cache = <String, Future<_TrimInfo>>{};

  late final Future<_TrimInfo> _future =
      _cache[widget.assetName] ??= _loadAndTrim(widget.assetName);

  static Future<_TrimInfo> _loadAndTrim(String assetName) async {
    final byteData = await rootBundle.load(assetName);
    final bytes = byteData.buffer.asUint8List();
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    final image = await completer.future;

    final raw = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (raw == null) {
      return _TrimInfo(
        image: image,
        srcRect: Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      );
    }

    final Uint8List data = raw.buffer.asUint8List();
    final int width = image.width;
    final int height = image.height;

    int minX = width;
    int minY = height;
    int maxX = -1;
    int maxY = -1;

    const int alphaThreshold = 12;
    for (int y = 0; y < height; y++) {
      final int rowStart = y * width * 4;
      for (int x = 0; x < width; x++) {
        final int a = data[rowStart + (x * 4) + 3];
        if (a > alphaThreshold) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (maxX < minX || maxY < minY) {
      return _TrimInfo(
        image: image,
        srcRect: Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      );
    }

    // Add a tiny safety margin (1px) to avoid cropping anti-aliased edges.
    minX = max(0, minX - 1);
    minY = max(0, minY - 1);
    maxX = min(width - 1, maxX + 1);
    maxY = min(height - 1, maxY + 1);

    final srcRect = Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );

    return _TrimInfo(image: image, srcRect: srcRect);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_TrimInfo>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return SizedBox(width: widget.size, height: widget.size);
        }

        final info = snapshot.data!;
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _TrimmedImagePainter(image: info.image, srcRect: info.srcRect),
        );
      },
    );
  }
}

class _TrimmedImagePainter extends CustomPainter {
  const _TrimmedImagePainter({required this.image, required this.srcRect});

  final ui.Image image;
  final Rect srcRect;

  @override
  void paint(Canvas canvas, Size size) {
    final dstRect = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawImageRect(image, srcRect, dstRect, paint);
  }

  @override
  bool shouldRepaint(covariant _TrimmedImagePainter oldDelegate) {
    return oldDelegate.image != image || oldDelegate.srcRect != srcRect;
  }
}
