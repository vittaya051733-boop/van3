import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'rider_chat_room_screen.dart';
import 'utils/contact_phone_resolver.dart';
import 'utils/order_call_launcher.dart';

class RiderJobsScreen extends StatelessWidget {
  const RiderJobsScreen({super.key});

  static const List<String> _registrationCollections = <String>[
    'market_registrations',
    'shop_registrations',
    'restaurant_registrations',
    'pharmacy_registrations',
    'other_registrations',
  ];

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('กรุณาเข้าสู่ระบบใหม่')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('รับงานใหม่')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('orders')
            .where('driverId', isEqualTo: user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
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

          final docs = (snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[])
              .where((doc) {
                final data = doc.data();
                final status = (data['status'] as String?) ?? '';
                final statusMatched = status == 'accepted';
                if (!statusMatched) {
                  return false;
                }

                final sourceApp = (data['sourceApp'] as String?)?.trim();
                if (sourceApp == 'van2_customer') {
                  final customerConfirmed = data['customerConfirmed'] == true;
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
                  final createdSource = (audit['createdSource'] as String?)?.trim();
                  return createdSource == 'cod_confirm_dialog';
                }
                return true;
              })
              .toList(growable: false);

          if (docs.isEmpty) {
            return const Center(
              child: Text('ยังไม่มีงานที่รับแล้วในตอนนี้'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final orderCode = (data['orderCode'] as String?)?.trim();
              final shopName = (data['shopName'] as String?)?.trim();
              final status = (data['status'] as String?)?.trim() ?? '-';
              final total = (data['grandTotal'] as num?) ?? (data['totalPrice'] as num?) ?? 0;
              final products = ((data['products'] as List?) ?? const <dynamic>[])
                  .whereType<Map>()
                  .cast<Map<dynamic, dynamic>>()
                  .toList(growable: false);

              final customerUid = _readCustomerUid(data);
              final shopOwnerUid = _readShopOwnerUid(data);

              return Container(
                padding: const EdgeInsets.all(12),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      orderCode?.isNotEmpty == true ? 'Order $orderCode' : 'Order ${doc.id}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text('ร้าน: ${shopName?.isNotEmpty == true ? shopName : '-'}'),
                    Text('สถานะ: $status'),
                    Text('ยอดรวม: THB ${total.toStringAsFixed(1)}'),
                    const SizedBox(height: 8),
                    const Text('รายการสินค้า', style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    for (final item in products)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          '- ${(item['name'] ?? '-').toString()} x${(item['quantity'] ?? 0).toString()} (THB ${(item['unitPrice'] ?? 0).toString()})',
                        ),
                      ),
                    const SizedBox(height: 10),
                    FutureBuilder<_ResolvedOrderPhones>(
                      future: _resolveOrderPhones(
                        data,
                        customerUid: customerUid,
                        shopOwnerUid: shopOwnerUid,
                      ),
                      builder: (context, phoneSnapshot) {
                        final customerPhone = phoneSnapshot.data?.customerPhone;
                        final shopPhone = phoneSnapshot.data?.shopPhone;

                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: null,
                                    icon: const Icon(Icons.check_circle_outline),
                                    label: const Text('รับงานแล้ว'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: customerUid == null || customerUid.isEmpty
                                        ? null
                                        : () async {
                                            await OrderCallLauncher.startVoiceCall(
                                              context: context,
                                              peerUid: customerUid,
                                              peerLabel: OrderCallLauncher.readCustomerLabel(data),
                                              orderData: data,
                                              phoneNumber: customerPhone,
                                              photoUrl: OrderCallLauncher.readCustomerPhotoUrl(data),
                                            );
                                          },
                                    icon: const Icon(Icons.phone),
                                    label: Text(
                                      customerUid == null || customerUid.isEmpty
                                          ? 'โทรลูกค้า (ไม่พบบัญชี)'
                                          : 'โทรลูกค้า',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: shopOwnerUid == null || shopOwnerUid.isEmpty
                                    ? null
                                    : () async {
                                        await OrderCallLauncher.startVoiceCall(
                                          context: context,
                                          peerUid: shopOwnerUid,
                                          peerLabel: OrderCallLauncher.readShopLabel(data),
                                          orderData: data,
                                          phoneNumber: shopPhone,
                                          photoUrl: OrderCallLauncher.readShopPhotoUrl(data),
                                        );
                                      },
                                icon: const Icon(Icons.support_agent_rounded),
                                label: Text(
                                  shopOwnerUid == null || shopOwnerUid.isEmpty
                                      ? 'โทรร้านค้า (ไม่พบบัญชี)'
                                      : 'โทรร้านค้า',
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _PeerChatButton(
                            peerUid: customerUid,
                            peerLabel: 'ลูกค้า',
                            label: 'แชตลูกค้า',
                            icon: Icons.chat_bubble_outline_rounded,
                            onPressed: customerUid == null || customerUid.isEmpty
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
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PeerChatButton(
                            peerUid: shopOwnerUid,
                            peerLabel: 'ร้านค้า',
                            label: 'แชตร้านค้า',
                            icon: Icons.storefront_outlined,
                            onPressed: shopOwnerUid == null || shopOwnerUid.isEmpty
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
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _acceptOrder(BuildContext context, String orderId) async {
    try {
      await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('รับงานสำเร็จ')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('รับงานไม่สำเร็จ: $e')),
        );
      }
    }
  }

  Future<_ResolvedOrderPhones> _resolveOrderPhones(
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

    return _ResolvedOrderPhones(
      customerPhone: customerPhone,
      shopPhone: shopPhone,
    );
  }

  Future<String?> _resolveShopPhone(Map<String, dynamic> data) async {
    final direct = (data['shopPhone'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final ownerUid = (data['shopOwnerId'] as String?)?.trim();
    if (ownerUid == null || ownerUid.isEmpty) {
      return null;
    }

    for (final collection in _registrationCollections) {
      try {
        final doc = await FirebaseFirestore.instance.collection(collection).doc(ownerUid).get();
        if (!doc.exists) continue;

        final map = doc.data();
        final phone = (map?['phone'] as String?)?.trim() ??
            (map?['phoneNumber'] as String?)?.trim() ??
            (map?['contactPhone'] as String?)?.trim();
        if (phone != null && phone.isNotEmpty) {
          return phone;
        }
      } catch (_) {
        // Ignore and try next collection.
      }
    }

    return null;
  }

  String? _readCustomerPhone(Map<String, dynamic> data) {
    final direct = (data['customerPhone'] as String?)?.trim();
    if (direct != null && direct.isNotEmpty) {
      return direct;
    }

    final alternatives = <String>[
      (data['customerPhoneNumber'] as String?)?.trim() ?? '',
      (data['phoneNumber'] as String?)?.trim() ?? '',
      (data['phone'] as String?)?.trim() ?? '',
      (data['buyerPhone'] as String?)?.trim() ?? '',
    ];
    for (final value in alternatives) {
      if (value.isNotEmpty) return value;
    }

    final snapshot = data['customerSnapshot'];
    if (snapshot is Map) {
      final fromSnapshot = <String>[
        (snapshot['phoneNumber'] as String?)?.trim() ?? '',
        (snapshot['phone'] as String?)?.trim() ?? '',
        (snapshot['contactPhone'] as String?)?.trim() ?? '',
      ];
      for (final value in fromSnapshot) {
        if (value.isNotEmpty) return value;
      }
    }

    return null;
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
    final canOpen = currentUid != null && resolvedPeerUid != null && resolvedPeerUid.isNotEmpty;

    if (!canOpen) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: Icon(icon),
        label: Text(label),
      );
    }

    final chatId = _chatIdFor(currentUid, resolvedPeerUid);
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('chats').doc(chatId).snapshots(),
      builder: (context, snapshot) {
        final unreadMap = snapshot.data?.data()?['unreadCounts'] as Map<String, dynamic>?;
        final unreadValue = unreadMap?[currentUid];
        final unreadCount = unreadValue is int
            ? unreadValue
            : unreadValue is num
                ? unreadValue.toInt()
                : 0;

        return OutlinedButton.icon(
          onPressed: onPressed,
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

class _ResolvedOrderPhones {
  const _ResolvedOrderPhones({
    required this.customerPhone,
    required this.shopPhone,
  });

  final String? customerPhone;
  final String? shopPhone;
}
