import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'call_screen.dart';
import 'models/user_profile.dart';
import 'services/notification_service.dart';
import 'utils/contact_phone_resolver.dart';

class RiderChatRoomScreen extends StatefulWidget {
  const RiderChatRoomScreen({
    super.key,
    required this.peerUid,
    required this.peerLabel,
    this.orderId,
  });

  final String peerUid;
  final String peerLabel;
  final String? orderId;

  @override
  State<RiderChatRoomScreen> createState() => _RiderChatRoomScreenState();
}

class _RiderChatRoomScreenState extends State<RiderChatRoomScreen> {
  static const List<String> _registrationCollections = <String>[
    'market_registrations',
    'shop_registrations',
    'restaurant_registrations',
    'pharmacy_registrations',
    'other_registrations',
  ];

  final TextEditingController _messageController = TextEditingController();
  bool _sending = false;
  bool _startingCall = false;
  bool _initializingChat = true;
  bool _markingAsRead = false;
  String? _initError;
  bool _resolvingPeerPhone = false;
  String? _peerPhone;

  String? get _myUid => FirebaseAuth.instance.currentUser?.uid;

  String get _chatId {
    final myUid = _myUid ?? '';
    final sorted = [myUid, widget.peerUid]..sort();
    return 'chat_${sorted.join('_')}';
  }

  @override
  void initState() {
    super.initState();
    _prepareChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _prepareChat() async {
    if (!mounted) return;
    setState(() {
      _initializingChat = true;
      _initError = null;
    });

    try {
      final myUid = _myUid;
      if (myUid == null || myUid.trim().isEmpty) {
        throw Exception('ไม่พบผู้ใช้ปัจจุบัน');
      }
      if (myUid == widget.peerUid) {
        throw Exception('ไม่สามารถเริ่มแชทกับบัญชีตัวเองได้');
      }

      await _ensureChatDoc();
      await _markChatAsRead();
      _peerPhone = await _resolvePeerPhone();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initError = 'ไม่สามารถเริ่มห้องแชทได้: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _initializingChat = false;
        });
      }
    }
  }

  Future<String?> _resolvePeerPhone() async {
    if (_resolvingPeerPhone) {
      return _peerPhone;
    }

    _resolvingPeerPhone = true;
    try {
      final fromCustomerUsers = await _readPhoneFromDoc(
        collection: 'customer_users',
        docId: widget.peerUid,
      );
      if (fromCustomerUsers != null) {
        return fromCustomerUsers;
      }

      final fromRiders = await _readPhoneFromDoc(
        collection: 'riders',
        docId: widget.peerUid,
      );
      if (fromRiders != null) {
        return fromRiders;
      }

      final fromUsers = await _readPhoneFromDoc(
        collection: 'users',
        docId: widget.peerUid,
      );
      if (fromUsers != null) {
        return fromUsers;
      }

      for (final collection in _registrationCollections) {
        final phone = await _readPhoneFromDoc(
          collection: collection,
          docId: widget.peerUid,
        );
        if (phone != null) {
          return phone;
        }
      }

      return null;
    } finally {
      _resolvingPeerPhone = false;
    }
  }

  Future<String?> _readPhoneFromDoc({
    required String collection,
    required String docId,
  }) async {
    try {
      final doc = await FirebaseFirestore.instance.collection(collection).doc(docId).get();
      if (!doc.exists) {
        return null;
      }

      final data = doc.data();
      if (data == null) {
        return null;
      }

      return ContactPhoneResolver.readPhoneFromMap(data);
    } catch (_) {
      return null;
    }
  }

  Future<void> _callPeerPhone() async {
    final phone = _peerPhone;
    if (phone == null || phone.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบเบอร์โทรของคู่แชท')),
        );
      }
      return;
    }

    final uri = Uri(
      scheme: 'tel',
      path: ContactPhoneResolver.normalizeDialable(phone),
    );
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่สามารถโทรออกได้')),
      );
    }
  }

  PreferredSizeWidget _buildAppBar() {
    final orderId = widget.orderId?.trim();
    final orderSuffix = orderId != null && orderId.isNotEmpty
        ? ' • Order ${orderId.length > 8 ? orderId.substring(0, 8) : orderId}'
        : '';
    return AppBar(
      title: Text('แชตกับ ${widget.peerLabel}$orderSuffix'),
      actions: [
        IconButton(
          tooltip: 'โทรด้วยเสียง',
          onPressed: _startingCall ? null : () => _startCall(isVideo: false),
          icon: const Icon(Icons.call_outlined),
        ),
        IconButton(
          tooltip: 'วิดีโอคอล',
          onPressed: _startingCall ? null : () => _startCall(isVideo: true),
          icon: const Icon(Icons.videocam_outlined),
        ),
        IconButton(
          tooltip: _peerPhone == null ? 'ไม่พบเบอร์โทร' : 'โทรปกติ',
          onPressed: _peerPhone == null ? null : _callPeerPhone,
          icon: const Icon(Icons.phone_in_talk_rounded),
        ),
      ],
    );
  }

  Future<UserProfile> _buildCurrentUserProfile() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('ไม่พบผู้ใช้ปัจจุบัน');
    }

    try {
      final riderDoc = await FirebaseFirestore.instance
          .collection('riders')
          .doc(currentUser.uid)
          .get();
      if (riderDoc.exists) {
        return UserProfile.fromMap(currentUser.uid, riderDoc.data());
      }
    } catch (_) {
      // Fallback to auth profile when Firestore lookup fails.
    }

    return UserProfile(
      uid: currentUser.uid,
      displayName: (currentUser.displayName?.trim().isNotEmpty ?? false)
          ? currentUser.displayName!.trim()
          : 'ไรเดอร์',
      phoneNumber: currentUser.phoneNumber,
      photoUrl: currentUser.photoURL,
    );
  }

  UserProfile _buildPeerProfile() {
    return UserProfile(
      uid: widget.peerUid,
      displayName: widget.peerLabel,
      phoneNumber: _peerPhone,
    );
  }

  Future<void> _startCall({required bool isVideo}) async {
    if (_startingCall) return;

    setState(() => _startingCall = true);
    try {
      final caller = await _buildCurrentUserProfile();
      final callee = _buildPeerProfile();

      final callData = await NotificationService().initiateCall(
        caller: caller,
        callee: callee,
        isVideo: isVideo,
      );

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CallScreen(
            channelName: (callData['channelId'] as String?) ?? _chatId,
            isVideo: isVideo,
            targetProfile: callee,
            appIdOverride: callData['appId'] as String?,
            tokenOverride: callData['token'] as String?,
            isIncoming: false,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เริ่มการโทรไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _startingCall = false);
      }
    }
  }

  Future<void> _ensureChatDoc() async {
    final myUid = _myUid;
    if (myUid == null) {
      throw Exception('ไม่พบผู้ใช้');
    }

    final caller = await _buildCurrentUserProfile();
    final callee = _buildPeerProfile();

    final ref = FirebaseFirestore.instance.collection('chats').doc(_chatId);
    await ref.set({
      'participants': [myUid, widget.peerUid],
      'participantProfiles': {
        myUid: caller.toFirestore(),
        widget.peerUid: callee.toFirestore(),
      },
      'participantNames': {
        myUid: caller.displayName,
        widget.peerUid: widget.peerLabel,
      },
      'lastMessage': '',
      'lastMessageType': 'text',
      'lastSenderId': myUid,
      'lastMessageSender': myUid,
      'lastMessageAt': FieldValue.serverTimestamp(),
      if (widget.orderId?.trim().isNotEmpty ?? false) 'orderId': widget.orderId!.trim(),
      'unreadCounts': {
        myUid: 0,
        widget.peerUid: 0,
      },
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _markChatAsRead() async {
    final myUid = _myUid;
    if (myUid == null || _markingAsRead) {
      return;
    }

    _markingAsRead = true;
    try {
      await FirebaseFirestore.instance.collection('chats').doc(_chatId).set({
        'unreadCounts.$myUid': 0,
        'lastReadAt.$myUid': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } finally {
      _markingAsRead = false;
    }
  }

  Future<void> _sendText() async {
    final myUid = _myUid;
    if (myUid == null) return;

    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    try {
      await _ensureChatDoc();
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(_chatId);
      await chatRef.collection('messages').add({
        'senderId': myUid,
        'receiverId': widget.peerUid,
        'type': 'text',
        'text': text,
        if (widget.orderId?.trim().isNotEmpty ?? false) 'orderId': widget.orderId!.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      await chatRef.set({
        'lastMessage': text,
        'lastMessageType': 'text',
        'lastSenderId': myUid,
        'lastMessageSender': myUid,
        'lastMessageAt': FieldValue.serverTimestamp(),
        if (widget.orderId?.trim().isNotEmpty ?? false) 'orderId': widget.orderId!.trim(),
        'unreadCounts.$myUid': 0,
        'unreadCounts.${widget.peerUid}': FieldValue.increment(1),
        'lastReadAt.$myUid': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ส่งข้อความไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = _myUid;
    if (myUid == null) {
      return const Scaffold(
        body: Center(child: Text('กรุณาเข้าสู่ระบบใหม่')),
      );
    }

    if (_initializingChat) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_initError != null) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _initError!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _prepareChat,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองอีกครั้ง'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .snapshots();

    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('โหลดแชตไม่สำเร็จ: ${snapshot.error}'));
                }

                final docs = snapshot.data?.docs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                if (docs.isNotEmpty) {
                  _markChatAsRead();
                }
                if (docs.isEmpty) {
                  return const Center(child: Text('เริ่มสนทนาได้เลย'));
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();
                    final text = (data['text'] as String?)?.trim() ?? '';
                    final senderId = (data['senderId'] as String?) ?? '';
                    final mine = senderId == myUid;

                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: mine ? const Color(0xFFFF8A00) : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: mine ? Colors.white : const Color(0xFF111827),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: const InputDecoration(
                        hintText: 'พิมพ์ข้อความ...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _sendText,
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
