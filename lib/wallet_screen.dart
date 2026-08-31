import 'package:cloud_firestore/cloud_firestore.dart';
import 'utils/guarded_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'l10n/l10n.dart';
import 'wallet_top_up_dialog.dart';
import 'wallet_withdraw_dialog.dart';
import 'widgets/security_pin_verify_dialog.dart';
import 'services/app_unlock_session.dart';
import 'services/rider_orders_service.dart';
import 'services/security_pin_service.dart';
import 'utils/order_pay_at_destination.dart';
import 'utils/settlement_payout_support.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  double _currentCredit = 0.0;
  double _withdrawableBalance = 0.0;
  String? _uid;
  bool _withdrawFlowBusy = false;

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
      return Text(L10n.signInRequiredForHistory);
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
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(L10n.loadHistoryFailed),
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
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(L10n.loadDeliveryHistoryFailed),
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
              String title = isTopUp ? L10n.creditTopUp : L10n.creditDeduct;
              if (creditType == 'order_pay_at_destination_hold') {
                title = L10n.creditDeductPayAtDestination;
              } else if (creditType == 'order_pay_at_destination_release') {
                title = L10n.creditReleasePayAtDestination;
              } else if (creditType == 'order_cod_rider_credit_release') {
                title = L10n.riderIncomeAfterGp;
              } else if (provider == 'slipok' && status == 'verified') {
                title = L10n.creditTopUpSlipVerified;
              } else if (provider != null && provider.isNotEmpty) {
                title = L10n.creditTitleWithProvider(title, provider);
              }

              final subtitleParts = <String>[];
              if (orderId != null && orderId.isNotEmpty) {
                subtitleParts.add(L10n.orderLabelWithCode(orderId));
              }
              if (paymentGroupId != null && paymentGroupId.isNotEmpty) {
                subtitleParts.add(L10n.codeLabel(paymentGroupId));
              }
              if (slipFeedbackId != null && slipFeedbackId.isNotEmpty) {
                subtitleParts.add(L10n.slipOkLabel(slipFeedbackId));
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
              final creditRelease = readRiderCreditReleaseInfo(data);
              if (creditRelease != null && !creditRelease.isReleased) {
                items.add(
                  _WalletHistoryItem(
                    title: L10n.pendingCreditReleaseCod(isCod),
                    subtitle: orderCode == null || orderCode.isEmpty
                        ? creditRelease.displayStatus
                        : '${L10n.orderLabelWithCode(orderCode)} • ${creditRelease.displayStatus}',
                    amount: netIncome,
                    happenedAt: deliveredAt,
                    icon: Icons.hourglass_top_rounded,
                    color: Colors.orange,
                  ),
                );
                continue;
              }
              if (isCod) {
                final collected = resolvePayAtDestinationHoldAmount(data);
                items.add(
                  _WalletHistoryItem(
                    title: L10n.netDeliveryIncomePayAtDestination,
                    subtitle: orderCode == null || orderCode.isEmpty
                        ? L10n.cashCollectedThb(collected)
                        : L10n.orderCashCollected(orderCode, collected),
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
                  title: L10n.netDeliveryIncome,
                  subtitle: orderCode == null || orderCode.isEmpty
                      ? L10n.jobDeliveredSuccess
                      : L10n.orderLabelWithCode(orderCode),
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
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(L10n.noItemsYet),
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
                        L10n.amountBaht(item.amount),
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
          if (isPayAtDestinationOrder(data) && !isRiderCreditReleased(data)) {
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
                    Text(
                      L10n.todayNetIncome,
                      style: const TextStyle(color: _dashboardCream, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      L10n.amountBaht(netIncomeToday),
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      L10n.deliveredTodayCount(deliveredTodayCount),
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

  Future<void> _fetchCurrentCredit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    if (mounted) {
      setState(() => _uid = user.uid);
    }

    try {
      final result = await GuardedFunctions.call(
        'getWithdrawableBalance',
        parameters: <String, dynamic>{'actorType': 'rider'},
      );
      final data = result.data is Map
          ? Map<String, dynamic>.from(result.data as Map)
          : const <String, dynamic>{};
      final withdrawable = (data['availableBalance'] as num?)?.toDouble() ?? 0;
      final creditTotal = (data['creditTotal'] as num?)?.toDouble() ?? withdrawable;

      if (!mounted) {
        return;
      }
      setState(() {
        _withdrawableBalance = withdrawable;
        _currentCredit = creditTotal;
      });
    } catch (_) {
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
      setState(() {
        _currentCredit = total;
        _withdrawableBalance = total;
      });
    }
  }

  Future<bool> _ensureWithdrawAuthorized() async {
    // Already verified PIN/biometric at AppUnlockGate this session.
    if (AppUnlockSession.isUnlocked) {
      return true;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return false;
    }

    final hasPin = await SecurityPinService.instance.hasPin(user.uid);
    if (!hasPin) {
      _showSnack(L10n.noPinOnDeviceForWithdraw);
      return false;
    }

    if (!mounted) {
      return false;
    }

    return verifySecurityPinForSensitiveAction(
      context,
      title: L10n.confirmBeforeWithdraw,
    );
  }

  Future<void> _requestWithdraw() async {
    if (_withdrawFlowBusy) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack(L10n.signInRequiredFirst);
      return;
    }

    setState(() => _withdrawFlowBusy = true);
    try {
      final authorized = await _ensureWithdrawAuthorized();
      if (!authorized || !mounted) {
        return;
      }

      final result = await showDialog<double>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) =>
            const WalletWithdrawDialog(actorType: 'rider'),
      );

      if (!mounted || result == null) {
        return;
      }

      await _fetchCurrentCredit();
      _showSnack(L10n.withdrawRequestSubmitted(result));
    } catch (error, stack) {
      if (kDebugMode) {
        debugPrint('wallet withdraw flow failed: $error\n$stack');
      }
      _showSnack(L10n.openWithdrawFailed);
    } finally {
      if (mounted) {
        setState(() => _withdrawFlowBusy = false);
      }
    }
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
        title: Text(L10n.walletTitle),
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
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _withdrawFlowBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.money_off),
                    label: Text(_withdrawFlowBusy ? L10n.opening : L10n.withdrawMoney),
                    style: _walletActionButtonStyle(),
                    onPressed: _withdrawFlowBusy ? null : _requestWithdraw,
                  ),
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
                                Expanded(
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.account_balance_wallet,
                                        color: Colors.white,
                                        size: 32,
                                      ),
                                      const SizedBox(width: 12),
                                      Flexible(
                                        child: Text(
                                          L10n.creditBalanceRemaining,
                                          style: const TextStyle(fontSize: 18, color: Colors.white),
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
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(L10n.topUpCredit),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              L10n.amountBaht(_currentCredit),
                              style: const TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if ((_withdrawableBalance - _currentCredit).abs() > 0.01) ...[
                              const SizedBox(height: 4),
                              Text(
                                L10n.withdrawableBalance(_withdrawableBalance),
                                style: const TextStyle(color: _dashboardCream, fontSize: 13),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Text(
                                  L10n.uidPrefix,
                                  style: const TextStyle(color: Colors.white70),
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
                                  tooltip: L10n.copyFullUid,
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: uid));
                                    _showSnack(L10n.uidCopied);
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildTodayNetIncomeCard(uid),
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
                              Text(
                                L10n.creditAndDeliveryHistory,
                                style: const TextStyle(
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