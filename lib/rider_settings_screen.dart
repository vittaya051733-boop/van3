import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'utils/app_colors.dart';
import 'admin_contact_screen.dart';
import 'admin_support_inbox_screen.dart';
import 'l10n/l10n.dart';
import 'privacy_security_screen.dart';
import 'rider_profile_edit_screen.dart';
import 'rider_reviews_screen.dart';
import 'services/admin_support_config.dart';
import 'services/biometric_auth_service.dart';
import 'services/locale_service.dart';
import 'services/rider_registration_service.dart';
import 'services/security_pin_service.dart';

class RiderSettingsScreen extends StatefulWidget {
  const RiderSettingsScreen({super.key});

  @override
  State<RiderSettingsScreen> createState() => _RiderSettingsScreenState();
}

class _RiderSettingsScreenState extends State<RiderSettingsScreen> {
  int _profileRefreshToken = 0;
  final _biometricAuthService = BiometricAuthService();
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _biometricLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBiometricSettings();
  }

  Future<void> _loadBiometricSettings() async {
    final available = await _biometricAuthService.canUseBiometrics();
    final enabled = await SecurityPinService.instance.isBiometricUnlockEnabled();
    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _biometricLoading = false;
    });
  }

  Future<void> _toggleBiometricUnlock(bool value) async {
    if (_biometricLoading) return;
    if (value && !_biometricAvailable) {
      _snack(context, L10n.biometricNotAvailable);
      return;
    }
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (value && uid != null) {
      final hasPin = await SecurityPinService.instance.hasPin(uid);
      if (!mounted) return;
      if (!hasPin) {
        _snack(context, L10n.setPinBeforeBiometric);
        return;
      }
    }
    setState(() => _biometricLoading = true);
    try {
      if (value) {
        final ok = await _biometricAuthService.authenticate(
          reason: L10n.biometricVerifyForUnlock,
        );
        if (!mounted) return;
        if (!ok) {
          _snack(context, L10n.biometricVerifyFailed);
          return;
        }
      }
      await SecurityPinService.instance.setBiometricUnlockEnabled(value);
      if (!mounted) return;
      setState(() => _biometricEnabled = value);
      _snack(
        context,
        value ? L10n.biometricUnlockEnabled : L10n.biometricUnlockDisabled,
      );
    } finally {
      if (mounted) {
        setState(() => _biometricLoading = false);
      }
    }
  }

  Future<void> _pickLanguage() async {
    final service = LocaleService.instance;
    final selected = await showModalBottomSheet<Locale>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  L10n.chooseLanguage,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              ListTile(
                title: Text(L10n.languageThai),
                trailing: service.locale == LocaleService.thai
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(LocaleService.thai),
              ),
              ListTile(
                title: Text(L10n.languageEnglish),
                trailing: service.locale == LocaleService.english
                    ? const Icon(Icons.check_rounded)
                    : null,
                onTap: () => Navigator.of(context).pop(LocaleService.english),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      await service.setLocale(selected);
      if (mounted) {
        setState(() {});
      }
    }
  }

  String _displayName(User? user) {
    final name = user?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = user?.email?.trim();
    if (email != null && email.isNotEmpty) return email;
    return L10n.defaultUser;
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
    final localeLabel = LocaleService.instance.labelFor(
      LocaleService.instance.locale,
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          L10n.settingsTitle,
          style: const TextStyle(fontWeight: FontWeight.w800),
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
          _sectionTitle(L10n.profileSection),
          FutureBuilder<RiderProfileData>(
            key: ValueKey<int>(_profileRefreshToken),
            future: user == null
                ? null
                : RiderRegistrationService.fetchProfile(user.uid),
            builder: (context, snapshot) {
              final complete = snapshot.data?.isCompleteForCustomerTravel == true;
              final promptPayReady = snapshot.data?.hasPromptPayForPayout == true;
              final needsAttention = !complete || !promptPayReady;
              return ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(L10n.editRiderProfile),
                subtitle: Text(
                  !promptPayReady
                      ? L10n.noPromptPayForWithdraw
                      : complete
                      ? L10n.profileCompleteHint
                      : L10n.profileIncompleteVan2HintShort,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (needsAttention &&
                        snapshot.connectionState == ConnectionState.done)
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
                        child: Text(
                          !promptPayReady
                              ? L10n.noPromptPayBadge
                              : L10n.incompleteBadge,
                          style: const TextStyle(
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
          _sectionTitle(L10n.reviewsSection),
          ListTile(
            leading: const Icon(Icons.star_rate_rounded),
            title: Text(L10n.customerReviews),
            subtitle: Text(L10n.customerReviewsHint),
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
          _sectionTitle(L10n.privacySection),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(L10n.privacyAndSecurity),
            subtitle: Text(L10n.privacyAndSecuritySubtitle),
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
          _sectionTitle(L10n.securitySection),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: Text(L10n.biometricUnlock),
            subtitle: Text(
              _biometricLoading
                  ? L10n.checkingBiometric
                  : _biometricAvailable
                  ? L10n.biometricUnlockHint
                  : L10n.biometricNotAvailable,
            ),
            value: _biometricAvailable && _biometricEnabled,
            onChanged: _biometricLoading ? null : _toggleBiometricUnlock,
          ),
          const Divider(height: 1),
          _sectionTitle(L10n.helpSection),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: Text(L10n.helpCenter),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _snack(context, L10n.helpCenterPreparing),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_rounded),
            title: Text(L10n.contactAdmin),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AdminContactScreen(
                    config: kVan3AdminSupportConfig,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.mark_chat_unread_outlined),
            title: Text(L10n.adminMessages),
            subtitle: Text(L10n.adminMessagesSubtitle),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AdminSupportInboxScreen(
                    config: kVan3AdminSupportConfig,
                    accentColor: Color(0xFF059669),
                  ),
                ),
              );
            },
          ),
          const Divider(height: 1),
          _sectionTitle(L10n.languageSection),
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: Text(L10n.language),
            subtitle: Text(localeLabel),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: _pickLanguage,
          ),
        ],
      ),
    );
  }
}
