import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'qr_scanner_screen.dart';
import 'utils/app_colors.dart';
import 'wallet_action_dialogs.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final TextEditingController _creditController = TextEditingController();

  bool _isLoading = false;
  double _currentCredit = 0.0;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _fetchCurrentCredit();
  }

  @override
  void dispose() {
    _creditController.dispose();
    super.dispose();
  }

  Future<void> _openQRScanner() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (context) => const QRScannerScreen(),
      ),
    );
    if (!mounted || result == null || result.isEmpty) {
      return;
    }
    _handleScannedQRCode(result);
  }

  void _handleScannedQRCode(String data) {
    if (data.startsWith('pay:')) {
      final amount = double.tryParse(data.substring(4));
      if (amount != null && amount > 0) {
        setState(() => _currentCredit -= amount);
        _showSnack('จ่ายเงิน $amount บาท สำเร็จ');
        return;
      }
    } else if (data.startsWith('receive:')) {
      final amount = double.tryParse(data.substring(8));
      if (amount != null && amount > 0) {
        setState(() => _currentCredit += amount);
        _showSnack('รับเงิน $amount บาท สำเร็จ');
        return;
      }
    }

    _showSnack('QR ไม่ถูกต้อง: $data');
  }

  Future<void> _fetchCurrentCredit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    if (mounted) {
      setState(() => _uid = user.uid);
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('credits')
        .where('uid', isEqualTo: user.uid)
        .get();

    var total = 0.0;
    for (final doc in snapshot.docs) {
      final amount = doc.data()['amount'];
      if (amount is num) {
        total += amount.toDouble();
      }
    }

    if (!mounted) {
      return;
    }
    setState(() => _currentCredit = total);
  }

  Future<void> _requestWithdraw() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('กรุณาเข้าสู่ระบบก่อน');
      return;
    }

    await _fetchCurrentCredit();
    if (!mounted) {
      return;
    }
    if (_currentCredit <= 0) {
      _showSnack('คุณไม่มีเครดิตสำหรับถอนเงิน');
      return;
    }

    await FirebaseFirestore.instance.collection('withdraw_requests').add({
      'uid': user.uid,
      'amount': _currentCredit,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'pending',
      'companyBankAccount': null,
    });
    _showSnack('ส่งคำขอถอนเงินเรียบร้อย (รอบริษัทอนุมัติ)');
  }

  Future<void> _submitCredit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack('กรุณาเข้าสู่ระบบก่อน');
      return;
    }

    final credit = double.tryParse(_creditController.text);
    if (credit == null || credit <= 0) {
      _showSnack('กรุณากรอกจำนวนเครดิตที่ถูกต้อง');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('credits').add({
        'uid': user.uid,
        'amount': credit,
        'timestamp': FieldValue.serverTimestamp(),
      });
      _creditController.clear();
      await _fetchCurrentCredit();
      _showSnack('บันทึกเครดิตเรียบร้อยแล้ว');
    } catch (error) {
      _showSnack('เกิดข้อผิดพลาด: $error');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _promptTopUpAmount() async {
    _creditController.clear();

    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('เติมเงิน'),
          content: TextField(
            controller: _creditController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'กรอกจำนวนเงิน',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('เติมเงิน'),
            ),
          ],
        );
      },
    );

    if (shouldSubmit == true) {
      await _submitCredit();
    }
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? _uid ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F7),
      appBar: AppBar(
        title: const Text('กระเป๋าเงิน'),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
      ),
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.arrow_downward),
                      label: const Text('รับเงิน'),
                      style: _walletActionButtonStyle(),
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) => ReceiveMoneyDialog(uid: uid),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.arrow_upward),
                      label: const Text('จ่ายเงิน'),
                      style: _walletActionButtonStyle(),
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) => PayMoneyDialog(uid: uid),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.compare_arrows),
                      label: const Text('โอนเงิน'),
                      style: _walletActionButtonStyle(),
                      onPressed: () {
                        showDialog<void>(
                          context: context,
                          builder: (context) => TransferMoneyDialog(uid: uid),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.money_off),
                      label: const Text('ถอนเงิน'),
                      style: _walletActionButtonStyle(),
                      onPressed: _requestWithdraw,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      elevation: 4,
                      color: AppColors.accent,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Expanded(
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                      SizedBox(width: 12),
                                      Text(
                                        'ยอดเงินคงเหลือ',
                                        style: TextStyle(fontSize: 18, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 170,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      SizedBox(
                                        height: 36,
                                        child: FilledButton(
                                          onPressed: _isLoading ? null : _promptTopUpAmount,
                                          style: FilledButton.styleFrom(
                                            backgroundColor: Colors.white,
                                            foregroundColor: AppColors.accent,
                                            padding: const EdgeInsets.symmetric(horizontal: 14),
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(
                                                  height: 16,
                                                  width: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                )
                                              : const Text('เติมเงิน'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '${_currentCredit.toStringAsFixed(2)} บาท',
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text(
                                  'UID: ',
                                  style: TextStyle(color: Colors.white70),
                                ),
                                Expanded(
                                  child: SelectableText(
                                    uid.length > 10
                                        ? '${uid.substring(0, 6)}...${uid.substring(uid.length - 4)}'
                                        : uid,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.copy, color: Colors.white),
                                  tooltip: 'คัดลอก UID เต็ม',
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: uid));
                                    _showSnack('คัดลอก UID เรียบร้อย');
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            GestureDetector(
                              onTap: () {
                                showDialog<void>(
                                  context: context,
                                  barrierDismissible: true,
                                  builder: (context) => GestureDetector(
                                    onTap: () => Navigator.of(context).pop(),
                                    child: Dialog(
                                      backgroundColor: Colors.transparent,
                                      child: Center(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(24),
                                            boxShadow: const [
                                              BoxShadow(color: Colors.black26, blurRadius: 12),
                                            ],
                                          ),
                                          padding: const EdgeInsets.all(32),
                                          child: QrImageView(
                                            data: uid,
                                            size: 280,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: const [
                                    BoxShadow(color: Colors.black12, blurRadius: 4),
                                  ],
                                ),
                                padding: const EdgeInsets.all(12),
                                child: QrImageView(
                                  data: uid,
                                  size: 100,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text('QR รับเงิน', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                        Column(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: const [
                                  BoxShadow(color: Colors.black12, blurRadius: 4),
                                ],
                              ),
                              child: IconButton(
                                icon: const Icon(
                                  Icons.qr_code_scanner,
                                  size: 48,
                                  color: AppColors.accent,
                                ),
                                onPressed: _openQRScanner,
                                tooltip: 'สแกน QR',
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text('สแกนจ่าย/รับเงิน', style: TextStyle(fontSize: 14)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 2,
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'ประวัติธุรกรรม',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            SizedBox(height: 12),
                            ListTile(
                              leading: Icon(Icons.arrow_downward, color: Colors.green),
                              title: Text('รับเงินจาก UID: userA'),
                              subtitle: Text('500 บาท'),
                              trailing: Text('10/11/2025'),
                            ),
                            ListTile(
                              leading: Icon(Icons.arrow_upward, color: Colors.redAccent),
                              title: Text('จ่ายเงินให้ UID: userB'),
                              subtitle: Text('200 บาท'),
                              trailing: Text('09/11/2025'),
                            ),
                            ListTile(
                              leading: Icon(Icons.compare_arrows, color: AppColors.accent),
                              title: Text('โอนเงินไป UID: userC'),
                              subtitle: Text('100 บาท'),
                              trailing: Text('08/11/2025'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _walletActionButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.accent,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      elevation: 0,
    );
  }
}