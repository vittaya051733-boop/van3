import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'qr_scanner_screen.dart';
import 'wallet_action_dialogs.dart';
import 'wallet_top_up_dialog.dart';
import 'services/rider_orders_service.dart';
import 'utils/order_pay_at_destination.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  double _currentCredit = 0.0;
  String? _uid;

  static const Color _dashboardOrangeTop = Color(0xFFFF9F1C);
  static const Color _dashboardOrangeMid = Color(0xFFFF6B00);
  static const Color _dashboardOrangeBottom = Color(0xFFFF5A00);
  static const Color _dashboardCream = Color(0xFFFFF0DF);
  static const Color _dashboardText = Color(0xFF2D2D2D);

  DateTime? _toDateTime(Object? value) {
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

  double? _toDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  Map<String, dynamic>? _readStringKeyedMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries) entry.key.toString(): entry.value,
      };
    }
    return null;
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

    final subtotal = _toDouble(data['subtotal']) ?? _toDouble(data['totalPrice']) ?? 0;
    final grandTotal = _toDouble(data['grandTotal']) ?? subtotal;
    final delta = grandTotal - subtotal;
    if (delta > 0) {
      return delta;
    }

    return 0;
  }

  double? _readPersistedRiderNetIncome(Map<String, dynamic> data) {
    final financials = _readStringKeyedMap(data['deliveryFinancials']);
    return _toDouble(data['deliveryRiderNetIncome']) ?? _toDouble(financials?['riderNetIncome']);
  }

  double _calculateRiderNetShippingIncome(Map<String, dynamic> data) {
    return readRiderNetShippingIncome(data) ?? 0;
  }

  DateTime? _orderDeliveredAt(Map<String, dynamic> data) {
    final financials = _readStringKeyedMap(data['deliveryFinancials']);
    return _toDateTime(data['deliveredAt']) ??
        _toDateTime(financials?['completedAt']) ??
        _toDateTime(data['timestamp']) ??
        _toDateTime(data['createdAt']);
  }

  bool _isDeliveredToday(Map<String, dynamic> data) {
    final deliveredAt = _orderDeliveredAt(data);
    if (deliveredAt == null) {
      return false;
    }

    final now = DateTime.now();
    return deliveredAt.year == now.year &&
        deliveredAt.month == now.month &&
        deliveredAt.day == now.day;
  }

  String _formatTimestamp(dynamic value) {
    DateTime? dt;
    dt = _toDateTime(value);

    if (dt == null) {
      return '';
    }

    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final yyyy = dt.year.toString();
    final hh = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }

  Widget _buildCreditsHistory(String uid) {
    if (uid.isEmpty) {
      return const Text('กรุณาเข้าสู่ระบบเพื่อดูประวัติ');
    }

    final creditStream = FirebaseFirestore.instance
        .collection('credits')
        .where('uid', isEqualTo: uid)
        .snapshots();
    final orderStream = RiderOrdersService.instance.ordersStream;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: creditStream,
      builder: (context, creditSnapshot) {
        if (creditSnapshot.connectionState == ConnectionState.waiting && !creditSnapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (creditSnapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('โหลดประวัติไม่สำเร็จ'),
          );
        }

        return StreamBuilder<RiderOrdersQuerySnapshot>(
          stream: orderStream,
          builder: (context, orderSnapshot) {
            if (orderSnapshot.connectionState == ConnectionState.waiting && !orderSnapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (orderSnapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('โหลดประวัติค่าส่งไม่สำเร็จ'),
              );
            }

            final items = <_WalletHistoryItem>[];

            final creditDocs = creditSnapshot.data?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (final doc in creditDocs) {
              final data = doc.data();
              final amount = _toDouble(data['amount']) ?? 0.0;
              final provider = data['provider']?.toString().trim().toLowerCase();
              final status = data['status']?.toString().trim().toLowerCase();
              final paymentGroupId = data['paymentGroupId']?.toString().trim();
              final slipFeedbackId = data['slipFeedbackId']?.toString().trim();
              final isTopUp = amount >= 0;

              final creditType = data['type']?.toString().trim();
              final orderId = data['orderId']?.toString().trim();
              String title = isTopUp ? 'เติมเครดิต' : 'หักเครดิต';
              if (creditType == 'order_pay_at_destination_hold') {
                title = 'หักเครดิต (รับงานจ่ายปลายทาง)';
              } else if (creditType == 'order_pay_at_destination_release') {
                title = 'คืนเครดิต (ค่าส่งสุทธิ • รับปลายทาง)';
              } else if (provider == 'slipok' && status == 'verified') {
                title = 'เติมเครดิต (ตรวจสลิป)';
              } else if (provider != null && provider.isNotEmpty) {
                title = '$title ($provider)';
              }

              final subtitleParts = <String>[];
              if (orderId != null && orderId.isNotEmpty) {
                subtitleParts.add('ออเดอร์: $orderId');
              }
              if (paymentGroupId != null && paymentGroupId.isNotEmpty) {
                subtitleParts.add('รหัส: $paymentGroupId');
              }
              if (slipFeedbackId != null && slipFeedbackId.isNotEmpty) {
                subtitleParts.add('SlipOK: $slipFeedbackId');
              }

              items.add(
                _WalletHistoryItem(
                  title: title,
                  subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' • '),
                  amount: amount,
                  happenedAt: _toDateTime(data['timestamp']),
                  icon: isTopUp ? Icons.add_circle_outline : Icons.remove_circle_outline,
                  color: isTopUp ? Colors.green : Colors.redAccent,
                ),
              );
            }

            final orderDocs = orderSnapshot.data?.docs ??
                const <RiderOrderDocument>[];
            for (final doc in orderDocs) {
              final data = doc.data();
              final status = data['status']?.toString().trim();
              if (status != 'delivered') {
                continue;
              }
              final netIncome = _calculateRiderNetShippingIncome(data);
              if (netIncome <= 0) {
                continue;
              }

              final orderCode = data['orderCode']?.toString().trim();
              final deliveredAt = _orderDeliveredAt(data);
              final isCod = isPayAtDestinationOrder(data);
              if (isCod) {
                final collected = resolvePayAtDestinationHoldAmount(data);
                items.add(
                  _WalletHistoryItem(
                    title: 'รายได้ค่าส่งสุทธิ (รับปลายทาง)',
                    subtitle: orderCode == null || orderCode.isEmpty
                        ? 'เก็บเงินสด THB ${collected.toStringAsFixed(1)}'
                        : 'ออเดอร์: $orderCode • เก็บเงินสด THB ${collected.toStringAsFixed(1)}',
                    amount: netIncome,
                    happenedAt: deliveredAt,
                    icon: Icons.payments_outlined,
                    color: _dashboardOrangeMid,
                  ),
                );
                continue;
              }

              items.add(
                _WalletHistoryItem(
                  title: 'รายได้ค่าส่งสุทธิ',
                  subtitle: orderCode == null || orderCode.isEmpty ? 'งานส่งสำเร็จ' : 'ออเดอร์: $orderCode',
                  amount: netIncome,
                  happenedAt: deliveredAt,
                  icon: Icons.local_shipping_outlined,
                  color: _dashboardOrangeMid,
                ),
              );
            }

            items.sort((a, b) {
              final at = a.happenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              final bt = b.happenedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
              return bt.compareTo(at);
            });

            final visibleItems = items.take(50).toList();
            if (visibleItems.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('ยังไม่มีรายการ'),
              );
            }

            return ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleItems.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = visibleItems[index];
                final isPositive = item.amount >= 0;

                return ListTile(
                  leading: Icon(item.icon, color: item.color),
                  title: Text(item.title),
                  subtitle: item.subtitle == null ? null : Text(item.subtitle!),
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${item.amount.toStringAsFixed(2)} บาท',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isPositive ? Colors.green : Colors.redAccent,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTimestamp(item.happenedAt),
                        style: const TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildTodayNetIncomeCard(String uid) {
    if (uid.isEmpty) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<RiderOrdersQuerySnapshot>(
      stream: RiderOrdersService.instance.ordersStream,
      builder: (context, snapshot) {
        var deliveredTodayCount = 0;
        var netIncomeToday = 0.0;

        final docs = snapshot.data?.docs ?? const <RiderOrderDocument>[];
        for (final doc in docs) {
          final data = doc.data();
          final status = data['status']?.toString().trim();
          if (status != 'delivered' || !_isDeliveredToday(data)) {
            continue;
          }
          deliveredTodayCount += 1;
          netIncomeToday += _calculateRiderNetShippingIncome(data);
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            color: Colors.white.withValues(alpha: 0.14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.query_stats_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'รายได้สุทธิของวัน',
                      style: TextStyle(color: _dashboardCream, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${netIncomeToday.toStringAsFixed(2)} บาท',
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'ส่งสำเร็จวันนี้ $deliveredTodayCount งาน',
                      style: const TextStyle(color: _dashboardCream, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _fetchCurrentCredit();
  }

  @override
  void dispose() {
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

  Future<void> _promptTopUpAmount() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const WalletTopUpDialog(),
    );

    if (!mounted) {
      return;
    }
    if (result == true) {
      await _fetchCurrentCredit();
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
      backgroundColor: _dashboardOrangeMid,
      appBar: AppBar(
        title: const Text('กระเป๋าเงิน'),
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_dashboardOrangeTop, _dashboardOrangeMid],
            ),
          ),
        ),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_dashboardOrangeTop, _dashboardOrangeMid, _dashboardOrangeBottom],
          ),
        ),
        child: Column(
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
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          color: Colors.white.withValues(alpha: 0.14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
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
                                      Flexible(
                                        child: Text(
                                          'ยอดเครดิตคงเหลือ',
                                          style: TextStyle(fontSize: 18, color: Colors.white),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  height: 36,
                                  child: FilledButton(
                                    onPressed: _promptTopUpAmount,
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: _dashboardOrangeMid,
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      minimumSize: const Size(0, 36),
                                    ),
                                    child: const FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text('เติมเครดิต'),
                                    ),
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
                      const SizedBox(height: 12),
                      _buildTodayNetIncomeCard(uid),
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
                                      BoxShadow(color: Color(0x24000000), blurRadius: 10),
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
                              const Text('QR รับเงิน', style: TextStyle(fontSize: 14, color: _dashboardCream)),
                            ],
                          ),
                          Column(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: const [
                                    BoxShadow(color: Color(0x24000000), blurRadius: 10),
                                  ],
                                ),
                                child: IconButton(
                                  icon: const Icon(
                                    Icons.qr_code_scanner,
                                    size: 48,
                                    color: _dashboardOrangeMid,
                                  ),
                                  onPressed: _openQRScanner,
                                  tooltip: 'สแกน QR',
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'สแกนจ่าย/รับเงิน',
                                style: TextStyle(fontSize: 14, color: _dashboardCream),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 0,
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'ประวัติเติมเครดิตและค่าส่ง',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: _dashboardText,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildCreditsHistory(uid),
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
      ),
    );
  }

  ButtonStyle _walletActionButtonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: Colors.white.withValues(alpha: 0.18),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      elevation: 0,
      side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
    );
  }
}

class _WalletHistoryItem {
  const _WalletHistoryItem({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
    this.subtitle,
    this.happenedAt,
  });

  final String title;
  final String? subtitle;
  final double amount;
  final DateTime? happenedAt;
  final IconData icon;
  final Color color;
}