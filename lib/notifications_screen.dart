import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class RiderNotificationsScreen extends StatelessWidget {
  const RiderNotificationsScreen({super.key});

  static const String _targetApp = 'van3';
  static const String _announcementAction = 'admin_announcement';

  Stream<List<_RiderNotification>> _watchNotifications(String uid) {
    return FirebaseFirestore.instance
        .collection('app_notifications')
        .where('targetApp', isEqualTo: _targetApp)
        .where('recipientUid', isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          final items = snapshot.docs
              .map(_RiderNotification.fromSnapshot)
              .toList(growable: true)
            ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
          return items;
        });
  }

  Future<void> _markAsRead(_RiderNotification item) async {
    if (item.isRead) {
      return;
    }
    await item.reference.set(<String, dynamic>{
      'read': true,
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _markAllAsRead(List<_RiderNotification> items) async {
    final unread = items.where((item) => !item.isRead).toList(growable: false);
    if (unread.isEmpty) {
      return;
    }
    final batch = FirebaseFirestore.instance.batch();
    for (final item in unread.take(450)) {
      batch.set(item.reference, <String, dynamic>{
        'read': true,
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> _openNotification(
    BuildContext context,
    _RiderNotification item,
  ) async {
    await _markAsRead(item);
    if (!context.mounted) {
      return;
    }

    if (item.action == _announcementAction ||
        item.orderId == null ||
        item.orderId!.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(item.title),
          content: SingleChildScrollView(child: Text(item.body)),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('ปิด'),
            ),
          ],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('แจ้งเตือนนี้ไม่มีหน้าที่เชื่อมต่อ')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFFFFF8F1),
      appBar: AppBar(
        title: const Text('การแจ้งเตือน'),
        backgroundColor: const Color(0xFFFF8A00),
        foregroundColor: Colors.white,
      ),
      body: user == null
          ? const Center(child: Text('กรุณาเข้าสู่ระบบ'))
          : StreamBuilder<List<_RiderNotification>>(
              stream: _watchNotifications(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(
                    child: Text('โหลดแจ้งเตือนไม่สำเร็จ'),
                  );
                }

                final items = snapshot.data ?? const <_RiderNotification>[];
                if (items.isEmpty) {
                  return const Center(
                    child: Text(
                      'ยังไม่มีแจ้งเตือน',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                  );
                }

                final unreadCount = items.where((item) => !item.isRead).length;
                return Column(
                  children: <Widget>[
                    if (unreadCount > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'มีแจ้งเตือนใหม่ $unreadCount รายการ',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            TextButton(
                              onPressed: () => _markAllAsRead(items),
                              child: const Text('อ่านทั้งหมด'),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return _NotificationTile(
                            item: item,
                            onTap: () => _openNotification(context, item),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.onTap,
  });

  final _RiderNotification item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = item.isRead
        ? const Color(0xFF9CA3AF)
        : const Color(0xFFFF8A00);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: item.isRead
                  ? const Color(0xFFE5E7EB)
                  : const Color(0xFFFFD7A3),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                backgroundColor: item.isRead
                    ? const Color(0xFFF3F4F6)
                    : const Color(0xFFFFEDD5),
                child: Icon(
                  item.action == 'admin_announcement'
                      ? Icons.campaign_rounded
                      : Icons.notifications_none_rounded,
                  color: accent,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.body,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF4B5563),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RiderNotification {
  const _RiderNotification({
    required this.id,
    required this.reference,
    required this.title,
    required this.body,
    required this.action,
    required this.createdAt,
    required this.isRead,
    this.orderId,
  });

  final String id;
  final DocumentReference<Map<String, dynamic>> reference;
  final String title;
  final String body;
  final String action;
  final DateTime? createdAt;
  final bool isRead;
  final String? orderId;

  DateTime get sortTime =>
      createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);

  factory _RiderNotification.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return _RiderNotification(
      id: doc.id,
      reference: doc.reference,
      title: data['title']?.toString().trim().isNotEmpty == true
          ? data['title'].toString().trim()
          : 'แจ้งเตือนใหม่',
      body: data['body']?.toString().trim().isNotEmpty == true
          ? data['body'].toString().trim()
          : data['message']?.toString().trim() ?? '',
      action: data['action']?.toString().trim() ?? '',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
      isRead: data['read'] == true ||
          data['isRead'] == true ||
          data['readAt'] != null,
      orderId: data['orderId']?.toString().trim(),
    );
  }
}
