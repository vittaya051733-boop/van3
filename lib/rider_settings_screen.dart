import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'utils/app_colors.dart';
import 'admin_contact_screen.dart';
import 'admin_support_inbox_screen.dart';
import 'privacy_security_screen.dart';
import 'rider_profile_edit_screen.dart';
import 'rider_reviews_screen.dart';
import 'services/admin_support_config.dart';
import 'services/rider_registration_service.dart';

class RiderSettingsScreen extends StatefulWidget {
  const RiderSettingsScreen({super.key});

  @override
  State<RiderSettingsScreen> createState() => _RiderSettingsScreenState();
}

class _RiderSettingsScreenState extends State<RiderSettingsScreen> {
  int _profileRefreshToken = 0;

  String _displayName(User? user) {
    final name = user?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    return 'ผู้ใช้';
  }

  String? _secondaryText(User? user) {
    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    return null;
  }

  Widget _buildAvatar(User? user) {
    final photoUrl = user?.photoURL?.trim();
    if (photoUrl != null && photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundColor: Colors.white,
        backgroundImage: NetworkImage(photoUrl),
      );
    }

    final name = user?.displayName?.trim();
    final letter = (name != null && name.isNotEmpty)
        ? name.characters.first.toUpperCase()
        : null;

    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.white,
      child: letter != null
          ? Text(
              letter,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.accentDark,
              ),
            )
          : const Icon(
              Icons.person_rounded,
              color: AppColors.accentDark,
            ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
        ),
      ),
    );
  }

  void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final name = _displayName(user);
    final secondary = _secondaryText(user);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'ตั้งค่า',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(74),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: Row(
              children: [
                _buildAvatar(user),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (secondary != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          secondary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        children: [
          _sectionTitle('โปรไฟล์'),
          FutureBuilder<RiderProfileData>(
            key: ValueKey<int>(_profileRefreshToken),
            future: user == null
                ? null
                : RiderRegistrationService.fetchProfile(user.uid),
            builder: (context, snapshot) {
              final complete = snapshot.data?.isCompleteForCustomerTravel == true;
              return ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('แก้ไขโปรไฟล์ไรเดอร์'),
                subtitle: Text(
                  complete
                      ? 'รูป ข้อมูลรถ เอกสาร และบัญชีธนาคาร'
                      : 'ยังขาดข้อมูลที่ van2 ใช้ในหน้าเดินทาง — แตะเพื่อเติม',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (!complete && snapshot.connectionState == ConnectionState.done)
                      Container(
                        margin: const EdgeInsets.only(right: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: const Text(
                          'ไม่ครบ',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFEA580C),
                          ),
                        ),
                      ),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                onTap: () async {
                  final saved = await Navigator.of(context).push<bool>(
                    MaterialPageRoute<bool>(
                      builder: (_) => const RiderProfileEditScreen(),
                    ),
                  );
                  if (saved == true && mounted) {
                    setState(() => _profileRefreshToken++);
                  }
                },
              );
            },
          ),
          const Divider(height: 1),
          _sectionTitle('รีวิว'),
          ListTile(
            leading: const Icon(Icons.star_rate_rounded),
            title: const Text('รีวิวจากลูกค้า'),
            subtitle: const Text(
              'อ่านอย่างเดียว — ลูกค้าเป็นผู้ให้คะแนนและแก้ไขรีวิวเอง',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const RiderReviewsScreen(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          _sectionTitle('ความเป็นส่วนตัว'),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('ความเป็นส่วนตัวและความปลอดภัย'),
            subtitle: const Text('ความยินยอม สิทธิข้อมูล และการแจ้งเตือน'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PrivacySecurityScreen(),
                ),
              );
            },
          ),
          const Divider(height: 1),
          _sectionTitle('ช่วยเหลือ'),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text('ศูนย์ช่วยเหลือ'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _snack(context, 'ศูนย์ช่วยเหลือ (กำลังเตรียม)'),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_rounded),
            title: const Text('ติดต่อแอดมิน'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminContactScreen(
                    config: kVan3AdminSupportConfig,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.mark_chat_unread_outlined),
            title: const Text('ข้อความถึงแอดมิน'),
            subtitle: const Text('ดูคำตอบจากแอดมินและตอบกลับ'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AdminSupportInboxScreen(
                    config: kVan3AdminSupportConfig,
                    accentColor: Color(0xFF059669),
                  ),
                ),
              );
            },
          ),
          const Divider(height: 1),
          _sectionTitle('ความปลอดภัย'),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('ความเป็นส่วนตัวและความปลอดภัย'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () =>
                _snack(context, 'ความปลอดภัย (กำลังเตรียม)'),
          ),
          const Divider(height: 1),
          _sectionTitle('ตั้งค่าภาษา'),
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: const Text('ภาษา'),
            subtitle: const Text('ไทย'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _snack(context, 'ตั้งค่าภาษา (กำลังเตรียม)'),
          ),
        ],
      ),
    );
  }
}
