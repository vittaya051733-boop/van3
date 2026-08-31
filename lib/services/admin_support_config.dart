import '../l10n/l10n.dart';

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

AdminSupportConfig get kVan3AdminSupportConfig => AdminSupportConfig(
  sourceApp: 'van3',
  sourceLabel: L10n.adminSupportSourceRider,
  topics: <AdminSupportTopic>[
    AdminSupportTopic(
      key: 'job_assignment',
      label: L10n.adminTopicJobAssignment,
    ),
    AdminSupportTopic(
      key: 'wallet_credit',
      label: L10n.adminTopicWalletCredit,
    ),
    AdminSupportTopic(
      key: 'location_gps',
      label: L10n.adminTopicGps,
    ),
    AdminSupportTopic(
      key: 'delivery_issue',
      label: L10n.adminTopicDeliveryIssue,
    ),
    AdminSupportTopic(
      key: 'account_verification',
      label: L10n.adminTopicAccountVerification,
    ),
    AdminSupportTopic(
      key: 'app_bug',
      label: L10n.adminTopicAppBug,
    ),
    AdminSupportTopic(
      key: AdminSupportTopic.customKey,
      label: L10n.adminTopicCustom,
    ),
  ],
);
