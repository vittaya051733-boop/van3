class AdminSupportTopic {
  const AdminSupportTopic({
    required this.key,
    required this.label,
  });

  final String key;
  final String label;

  static const String customKey = 'custom';
}

class AdminSupportConfig {
  const AdminSupportConfig({
    required this.sourceApp,
    required this.sourceLabel,
    required this.topics,
  });

  final String sourceApp;
  final String sourceLabel;
  final List<AdminSupportTopic> topics;
}

/// UID แอดมินสำหรับโทรในแอป (fallback ถ้า ticket ยังไม่มี assignedAdminUid)
const String kAdminSupportCalleeUid = '';

const AdminSupportConfig kVan3AdminSupportConfig = AdminSupportConfig(
  sourceApp: 'van3',
  sourceLabel: 'ไรเดอร์',
  topics: <AdminSupportTopic>[
    AdminSupportTopic(
      key: 'job_assignment',
      label: 'ปัญหารับงาน / มอบหมายออเดอร์',
    ),
    AdminSupportTopic(
      key: 'wallet_credit',
      label: 'กระเป๋าเงิน / เครดิต / รายได้',
    ),
    AdminSupportTopic(
      key: 'location_gps',
      label: 'GPS / พิกัด / แผนที่',
    ),
    AdminSupportTopic(
      key: 'delivery_issue',
      label: 'ปัญหาลูกค้า / ร้านขณะส่งของ',
    ),
    AdminSupportTopic(
      key: 'account_verification',
      label: 'บัญชีไรเดอร์ / เอกสารยืนยัน',
    ),
    AdminSupportTopic(
      key: 'app_bug',
      label: 'แจ้งข้อผิดพลาดแอป',
    ),
    AdminSupportTopic(
      key: AdminSupportTopic.customKey,
      label: 'อื่นๆ (พิมพ์หัวข้อเอง)',
    ),
  ],
);
