import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import 'l10n/l10n.dart';
import 'services/promptpay_qr_payload.dart';
import 'services/rider_registration_service.dart';
import 'utils/app_colors.dart';

class RiderProfileEditScreen extends StatefulWidget {
  const RiderProfileEditScreen({super.key});

  @override
  State<RiderProfileEditScreen> createState() => _RiderProfileEditScreenState();
}

class _RiderProfileEditScreenState extends State<RiderProfileEditScreen> {
  List<MapEntry<String, String>> get _vehicleTypes => <MapEntry<String, String>>[
    MapEntry('motorcycle', L10n.paymentVehicleMotorcycle),
    MapEntry('sedan', L10n.paymentVehicleSedan),
    MapEntry('pickup', L10n.paymentVehiclePickup),
  ];

  List<String> get _bankOptions {
    final banks = L10n.thaiBanks;
    final bank = _selectedBank?.trim();
    if (bank != null && bank.isNotEmpty && !banks.contains(bank)) {
      return <String>[bank, ...banks];
    }
    return banks;
  }

  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _accountOwnerController = TextEditingController();
  final _promptPayPhoneController = TextEditingController();
  final _promptPayNationalIdController = TextEditingController();
  final _licensePlateController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _vehicleBrandModelController = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _loading = true;
  bool _saving = false;
  bool _pickingImage = false;
  bool _isElectricVehicle = false;
  bool _pushOptIn = false;
  String? _selectedBank;
  String? _vehicleType;
  String? _existingProfilePhotoUrl;
  String? _existingLicenseUrl;
  String? _existingMotorcycleUrl;
  String? _existingBookBankUrl;
  File? _profilePhotoImage;
  File? _licenseImage;
  File? _motorcycleImage;
  File? _bookBankImage;
  RiderProfileData? _loadedProfile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _nameController.dispose();
    _accountNumberController.dispose();
    _accountOwnerController.dispose();
    _promptPayPhoneController.dispose();
    _promptPayNationalIdController.dispose();
    _licensePlateController.dispose();
    _vehicleColorController.dispose();
    _vehicleBrandModelController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }

    try {
      final profile = await RiderRegistrationService.fetchProfile(user.uid);
      if (!mounted) {
        return;
      }
      setState(() {
        _loadedProfile = profile;
        _nameController.text = profile.displayName ?? user.displayName ?? '';
        _phoneController.text = profile.phoneNumber ?? '';
        _accountNumberController.text = profile.accountNumber ?? '';
        _accountOwnerController.text = profile.accountOwner ?? '';
        _promptPayPhoneController.text = profile.promptPayPhoneNumber ?? '';
        _promptPayNationalIdController.text = profile.promptPayNationalId ?? '';
        _licensePlateController.text = profile.licensePlate ?? '';
        _vehicleColorController.text = profile.vehicleColor ?? '';
        _vehicleBrandModelController.text = profile.vehicleBrandModel ?? '';
        _selectedBank = profile.bankName;
        _vehicleType = profile.vehicleType;
        _isElectricVehicle = profile.isElectricVehicle;
        _pushOptIn = profile.pushOptIn;
        _existingProfilePhotoUrl = profile.profilePhotoUrl;
        _existingLicenseUrl = profile.driverLicenseImageUrl;
        _existingMotorcycleUrl = profile.motorcycleImageUrl;
        _existingBookBankUrl = profile.bookBankImageUrl;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      _showSnack(L10n.loadProfileFailed(error));
    }
  }

  Future<void> _pickImage(void Function(File file) assign) async {
    if (_pickingImage) {
      return;
    }
    setState(() => _pickingImage = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (picked == null || !mounted) {
        return;
      }
      setState(() => assign(File(picked.path)));
    } on PlatformException catch (error) {
      if (!mounted) {
        return;
      }
      if (error.code == 'already_active') {
        _showSnack(L10n.waitForImagePickerClose);
      } else {
        _showSnack(L10n.pickImageFailed(error.message ?? error.code));
      }
    } finally {
      if (mounted) {
        setState(() => _pickingImage = false);
      }
    }
  }

  Future<String> _uploadImage(File file, String label) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError(L10n.signInBeforeUpload);
    }
    final compressed = await FlutterImageCompress.compressWithFile(
      file.absolute.path,
      quality: 82,
    );
    final bytes = compressed ?? await file.readAsBytes();
    final path =
        'rider_registrations/${user.uid}/${label}_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = FirebaseStorage.instance.ref().child(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  Future<String?> _resolveImageUrl({
    required File? picked,
    required String? existing,
    required String label,
  }) async {
    if (picked != null) {
      return _uploadImage(picked, label);
    }
    return existing?.trim().isNotEmpty == true ? existing!.trim() : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final promptPayError = PromptPayQrPayload.validatePayoutProfile(
      phone: _promptPayPhoneController.text,
      nationalId: _promptPayNationalIdController.text,
    );
    if (promptPayError != null) {
      _showSnack('PromptPay: $promptPayError');
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack(L10n.signInRequiredFirst);
      return;
    }

    setState(() => _saving = true);
    try {
      final profilePhotoUrl = await _resolveImageUrl(
        picked: _profilePhotoImage,
        existing: _existingProfilePhotoUrl,
        label: 'profile',
      );
      final licenseUrl = await _resolveImageUrl(
        picked: _licenseImage,
        existing: _existingLicenseUrl,
        label: 'license',
      );
      final motorcycleUrl = await _resolveImageUrl(
        picked: _motorcycleImage,
        existing: _existingMotorcycleUrl,
        label: 'motorcycle',
      );
      final bookBankUrl = await _resolveImageUrl(
        picked: _bookBankImage,
        existing: _existingBookBankUrl,
        label: 'book_bank',
      );

      await RiderRegistrationService.updateProfile(
        uid: user.uid,
        displayName: _nameController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        bankName: _selectedBank,
        accountNumber: _accountNumberController.text.trim(),
        accountOwner: _accountOwnerController.text.trim(),
        promptPayPhoneNumber: _promptPayPhoneController.text.trim(),
        promptPayNationalId: _promptPayNationalIdController.text.trim(),
        driverLicenseImageUrl: licenseUrl,
        motorcycleImageUrl: motorcycleUrl,
        bookBankImageUrl: bookBankUrl,
        profilePhotoUrl: profilePhotoUrl,
        vehicleType: _vehicleType,
        licensePlate: _licensePlateController.text.trim(),
        vehicleColor: _vehicleColorController.text.trim(),
        vehicleBrandModel: _vehicleBrandModelController.text.trim(),
        isElectricVehicle: _isElectricVehicle,
        pushOptIn: _pushOptIn,
      );

      final displayName = _nameController.text.trim();
      if (displayName.isNotEmpty && displayName != user.displayName) {
        await user.updateDisplayName(displayName);
      }
      if (profilePhotoUrl != null && profilePhotoUrl != user.photoURL) {
        await user.updatePhotoURL(profilePhotoUrl);
      }

      if (!mounted) {
        return;
      }

      final updated = RiderProfileData.fromMap(<String, dynamic>{
        'displayName': displayName,
        'phoneNumber': _phoneController.text.trim(),
        'bankName': _selectedBank,
        'accountNumber': _accountNumberController.text.trim(),
        'accountOwner': _accountOwnerController.text.trim(),
        'promptPayPhoneNumber': _promptPayPhoneController.text.trim(),
        'promptPayNationalId': _promptPayNationalIdController.text.trim(),
        'driverLicenseImageUrl': licenseUrl,
        'motorcycleImageUrl': motorcycleUrl,
        'bookBankImageUrl': bookBankUrl,
        'profilePhotoUrl': profilePhotoUrl,
        'photoUrl': profilePhotoUrl,
        'vehicleType': _vehicleType,
        'licensePlate': _licensePlateController.text.trim(),
        'vehicleColor': _vehicleColorController.text.trim(),
        'vehicleBrandModel': _vehicleBrandModelController.text.trim(),
        'isElectricVehicle': _isElectricVehicle,
      });

      if (updated.isCompleteForCustomerTravel) {
        _showSnack(L10n.profileSavedVan2Visible);
      } else {
        _showSnack(L10n.profileSavedIncomplete);
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      _showSnack(L10n.saveFailedWithError(error));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: Colors.black54)),
          ],
        ],
      ),
    );
  }

  Widget _imageTile({
    required String title,
    File? file,
    String? existingUrl,
    required VoidCallback onPick,
  }) {
    Widget? leading;
    if (file != null) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(file, width: 48, height: 48, fit: BoxFit.cover),
      );
    } else if (existingUrl != null && existingUrl.isNotEmpty) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          existingUrl,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
        ),
      );
    } else {
      leading = const Icon(Icons.add_a_photo_outlined);
    }

    final hasImage = file != null || (existingUrl?.isNotEmpty == true);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: leading,
        title: Text(title),
        subtitle: Text(
          _pickingImage
              ? L10n.openingGallery
              : hasImage
              ? L10n.tapToChange
              : L10n.notSelected,
        ),
        trailing: _pickingImage
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: _pickingImage ? null : onPick,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final travelReady = _loadedProfile?.isCompleteForCustomerTravel == true;
    final promptPayReady = _loadedProfile?.hasPromptPayForPayout == true ||
        PromptPayQrPayload.hasValidPayoutProfile(
          phone: _promptPayPhoneController.text,
          nationalId: _promptPayNationalIdController.text,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(L10n.editRiderProfile),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: <Widget>[
                  if (!promptPayReady)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDBA74)),
                      ),
                      child: Text(
                        PromptPayQrPayload.payoutLinkedBankNotice,
                        style: const TextStyle(
                          color: Color(0xFF9A3412),
                          height: 1.4,
                        ),
                      ),
                    ),
                  if (!travelReady)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFDBA74)),
                      ),
                      child: Text(
                        L10n.profileIncompleteVan2Hint,
                        style: const TextStyle(
                          color: Color(0xFF9A3412),
                          height: 1.4,
                        ),
                      ),
                    ),
                  _sectionHeader(
                    L10n.personalInfoSection,
                    subtitle: L10n.personalInfoCustomerHint,
                  ),
                  TextFormField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: L10n.fullName,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        value?.trim().isEmpty == true ? L10n.pleaseEnterName : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: L10n.phone,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) =>
                        value?.trim().isEmpty == true ? L10n.pleaseEnterPhone : null,
                  ),
                  if (user?.email?.trim().isNotEmpty == true) ...<Widget>[
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: user!.email,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: L10n.emailReadOnly,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionHeader(
                    L10n.profilePhotoVehicleSection,
                    subtitle: L10n.profileVan2TravelHint,
                  ),
                  _imageTile(
                    title: L10n.profilePhotoTitle,
                    file: _profilePhotoImage,
                    existingUrl: _existingProfilePhotoUrl,
                    onPick: () => _pickImage(
                      (file) => setState(() => _profilePhotoImage = file),
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    value: _vehicleType,
                    items: _vehicleTypes
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        )
                        .toList(),
                    decoration: InputDecoration(
                      labelText: L10n.vehicleType,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _vehicleType = value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _licensePlateController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: L10n.licensePlate,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _vehicleColorController,
                    decoration: InputDecoration(
                      labelText: L10n.vehicleColorHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _vehicleBrandModelController,
                    decoration: InputDecoration(
                      labelText: L10n.vehicleBrandHint,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _isElectricVehicle,
                    onChanged: (value) =>
                        setState(() => _isElectricVehicle = value),
                    title: Text(L10n.electricVehicle),
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    L10n.identityDocumentsSection,
                    subtitle: L10n.identityDocumentsEditableHint,
                  ),
                  _imageTile(
                    title: L10n.driverLicense,
                    file: _licenseImage,
                    existingUrl: _existingLicenseUrl,
                    onPick: () => _pickImage(
                      (file) => setState(() => _licenseImage = file),
                    ),
                  ),
                  _imageTile(
                    title: L10n.vehiclePhoto,
                    file: _motorcycleImage,
                    existingUrl: _existingMotorcycleUrl,
                    onPick: () => _pickImage(
                      (file) => setState(() => _motorcycleImage = file),
                    ),
                  ),
                  _imageTile(
                    title: L10n.bankBookPage,
                    file: _bookBankImage,
                    existingUrl: _existingBookBankUrl,
                    onPick: () => _pickImage(
                      (file) => setState(() => _bookBankImage = file),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader(L10n.payoutAccountSection),
                  DropdownButtonFormField<String>(
                    value: _selectedBank,
                    items: _bankOptions
                        .map(
                          (bank) => DropdownMenuItem<String>(
                            value: bank,
                            child: Text(bank),
                          ),
                        )
                        .toList(),
                    decoration: InputDecoration(
                      labelText: L10n.bank,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => _selectedBank = value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _accountNumberController,
                    decoration: InputDecoration(
                      labelText: L10n.accountNumber,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _accountOwnerController,
                    decoration: InputDecoration(
                      labelText: L10n.accountName,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader(
                    L10n.promptPayWithdrawRequired.replaceAll(' *', ''),
                    subtitle: PromptPayQrPayload.payoutLinkedBankNotice,
                  ),
                  TextFormField(
                    controller: _promptPayPhoneController,
                    decoration: InputDecoration(
                      labelText: L10n.promptPayPhoneRequired,
                      hintText: L10n.promptPayPhoneHint,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      return PromptPayQrPayload.validatePayoutProfile(
                        phone: value,
                        nationalId: _promptPayNationalIdController.text,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _promptPayNationalIdController,
                    decoration: InputDecoration(
                      labelText: L10n.promptPayNationalIdOptional,
                      hintText: L10n.promptPayNationalIdHint,
                      border: const OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => _formKey.currentState?.validate(),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return null;
                      }
                      final digits = value.replaceAll(RegExp(r'\D'), '');
                      if (digits.length != 13) {
                        return L10n.promptPayNationalIdLengthError;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _pushOptIn,
                    onChanged: (value) => setState(() => _pushOptIn = value),
                    title: Text(L10n.privacyJobNotificationsToggle),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: Text(
                      _saving ? L10n.saving : L10n.saveProfile,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
