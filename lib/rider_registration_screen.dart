import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

import 'l10n/l10n.dart';
import 'data/legal_content.dart';
import 'legal_document_screen.dart';
import 'services/rider_auth_sign_out.dart';
import 'services/rider_registration_service.dart';
import 'services/promptpay_qr_payload.dart';
import 'services/security_pin_service.dart';
import 'services/app_unlock_session.dart';
import 'widgets/security_pin_field.dart';
import 'utils/app_colors.dart';

class RiderRegistrationScreen extends StatefulWidget {
  const RiderRegistrationScreen({super.key, this.rejectedReason});

  final String? rejectedReason;

  @override
  State<RiderRegistrationScreen> createState() =>
      _RiderRegistrationScreenState();
}

class _RiderRegistrationScreenState extends State<RiderRegistrationScreen> {
  List<MapEntry<String, String>> get _vehicleTypes => <MapEntry<String, String>>[
    MapEntry('motorcycle', L10n.paymentVehicleMotorcycle),
    MapEntry('sedan', L10n.paymentVehicleSedan),
    MapEntry('pickup', L10n.paymentVehiclePickup),
  ];

  final _pageController = PageController();
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _accountNumberController = TextEditingController();
  final _accountOwnerController = TextEditingController();
  final _promptPayPhoneController = TextEditingController();
  final _promptPayNationalIdController = TextEditingController();
  final _imagePicker = ImagePicker();

  int _step = 0;
  bool _submitting = false;
  bool _pickingImage = false;
  bool _acceptedPrivacy = false;
  bool _pushOptIn = false;
  String? _selectedBank;
  File? _licenseImage;
  File? _motorcycleImage;
  File? _bookBankImage;
  File? _profilePhotoImage;
  String? _vehicleType;
  final _licensePlateController = TextEditingController();
  final _vehicleColorController = TextEditingController();
  final _vehicleBrandModelController = TextEditingController();
  bool _isElectricVehicle = false;

  @override
  void dispose() {
    _pageController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!_acceptedPrivacy) {
      _showSnack(L10n.pleaseAcceptPrivacyPolicy);
      return;
    }
    if (_licenseImage == null ||
        _motorcycleImage == null ||
        _bookBankImage == null ||
        _profilePhotoImage == null) {
      _showSnack(L10n.pleaseUploadAllDocuments);
      return;
    }
    if (_vehicleType == null || _vehicleType!.isEmpty) {
      _showSnack(L10n.pleaseSelectVehicleType);
      return;
    }
    if (_licensePlateController.text.trim().isEmpty ||
        _vehicleColorController.text.trim().isEmpty ||
        _vehicleBrandModelController.text.trim().isEmpty) {
      _showSnack(L10n.pleaseCompleteVehicleInfo);
      return;
    }
    if (_selectedBank == null || _selectedBank!.isEmpty) {
      _showSnack(L10n.pleaseSelectBank);
      return;
    }

    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    if (!SecurityPinService.instance.isValidPinFormat(pin)) {
      _showSnack(L10n.pleaseSetPinSixDigits);
      return;
    }
    if (pin != confirmPin) {
      _showSnack(L10n.pinMismatch);
      return;
    }

    setState(() => _submitting = true);
    try {
      User? user = FirebaseAuth.instance.currentUser;
      user ??= (await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      )).user;

      if (user == null) {
        throw StateError(L10n.accountCreationFailed);
      }

      final licenseUrl = await _uploadImage(_licenseImage!, 'license');
      final bikeUrl = await _uploadImage(_motorcycleImage!, 'motorcycle');
      final bankUrl = await _uploadImage(_bookBankImage!, 'book_bank');
      final profileUrl = await _uploadImage(_profilePhotoImage!, 'profile');

      await RiderRegistrationService.submitRegistration(
        user: user,
        contactEmail: _emailController.text.trim(),
        phoneNumber: _phoneController.text.trim(),
        displayName: _nameController.text.trim(),
        bankName: _selectedBank!,
        accountNumber: _accountNumberController.text.trim(),
        accountOwner: _accountOwnerController.text.trim(),
        promptPayPhoneNumber: _promptPayPhoneController.text.trim(),
        promptPayNationalId: _promptPayNationalIdController.text.trim(),
        driverLicenseImageUrl: licenseUrl,
        motorcycleImageUrl: bikeUrl,
        bookBankImageUrl: bankUrl,
        profilePhotoUrl: profileUrl,
        vehicleType: _vehicleType!,
        licensePlate: _licensePlateController.text.trim(),
        vehicleColor: _vehicleColorController.text.trim(),
        vehicleBrandModel: _vehicleBrandModelController.text.trim(),
        isElectricVehicle: _isElectricVehicle,
        acceptedPrivacy: _acceptedPrivacy,
        pushOptIn: _pushOptIn,
      );

      await SecurityPinService.instance.setPin(user.uid, pin);
      AppUnlockSession.unlock();

      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacementNamed('/registration-pending');
    } on FirebaseAuthException catch (error) {
      _showSnack(error.message ?? L10n.registrationFailed);
    } catch (error) {
      _showSnack(L10n.registrationFailedWithError(error));
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openDocument(LegalDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(document: document),
      ),
    );
  }

  Widget _imageTile({
    required String title,
    required File? file,
    required VoidCallback onPick,
  }) {
    return Card(
      child: ListTile(
        leading: file == null
            ? const Icon(Icons.add_a_photo_outlined)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(file, width: 48, height: 48, fit: BoxFit.cover),
              ),
        title: Text(title),
        subtitle: Text(
          _pickingImage
              ? L10n.openingGallery
              : file == null
              ? L10n.notSelected
              : L10n.selected,
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
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(L10n.registerRiderTitle),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: <Widget>[
            if (widget.rejectedReason != null)
              Container(
                width: double.infinity,
                color: const Color(0xFFFEF2F2),
                padding: const EdgeInsets.all(12),
                child: Text(
                  L10n.registrationRejected(widget.rejectedReason!),
                  style: const TextStyle(color: Color(0xFFB91C1C)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: List<Widget>.generate(4, (index) {
                  final active = index <= _step;
                  return Expanded(
                    child: Container(
                      margin: EdgeInsets.only(right: index == 3 ? 0 : 6),
                      height: 4,
                      decoration: BoxDecoration(
                        color: active ? AppColors.accent : const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (value) => setState(() => _step = value),
                children: <Widget>[
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      Text(
                        L10n.accountInfoSection,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      if (!loggedIn) ...<Widget>[
                        TextFormField(
                          controller: _emailController,
                          decoration: InputDecoration(
                            labelText: L10n.email,
                            border: const OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) =>
                              value?.trim().isEmpty == true ? L10n.pleaseEnterEmail : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: L10n.passwordMinSix,
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              (value ?? '').length < 6 ? L10n.passwordTooShort : null,
                        ),
                        const SizedBox(height: 12),
                        SecurityPinField(
                          controller: _pinController,
                          label: L10n.pinSixDigits,
                        ),
                        const SizedBox(height: 12),
                        SecurityPinField(
                          controller: _confirmPinController,
                          label: L10n.confirmPinSixDigits,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            L10n.pinUsageHint,
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
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
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      Text(
                        L10n.profileAndVehicleSection,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        L10n.profileVehicleCustomerHint,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      _imageTile(
                        title: L10n.profilePhotoTitle,
                        file: _profilePhotoImage,
                        onPick: () => _pickImage(
                          (file) => setState(() => _profilePhotoImage = file),
                        ),
                      ),
                      const SizedBox(height: 12),
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
                        onChanged: (value) =>
                            setState(() => _vehicleType = value),
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
                      const SizedBox(height: 16),
                      Text(
                        L10n.identityDocumentsSection,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        L10n.identityDocumentsHint,
                        style: const TextStyle(color: Colors.black54),
                      ),
                      const SizedBox(height: 12),
                      _imageTile(
                        title: L10n.driverLicense,
                        file: _licenseImage,
                        onPick: () => _pickImage(
                          (file) => setState(() => _licenseImage = file),
                        ),
                      ),
                      _imageTile(
                        title: L10n.motorcyclePhoto,
                        file: _motorcycleImage,
                        onPick: () => _pickImage(
                          (file) => setState(() => _motorcycleImage = file),
                        ),
                      ),
                      _imageTile(
                        title: L10n.bankBookPage,
                        file: _bookBankImage,
                        onPick: () => _pickImage(
                          (file) => setState(() => _bookBankImage = file),
                        ),
                      ),
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      Text(
                        L10n.payoutAccountSection,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _selectedBank,
                        items: L10n.thaiBanks
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
                        validator: (value) =>
                            value == null || value.isEmpty ? L10n.selectBank : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _accountNumberController,
                        decoration: InputDecoration(
                          labelText: L10n.accountNumber,
                          border: const OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        validator: (value) =>
                            value?.trim().isEmpty == true ? L10n.pleaseEnterAccountNumber : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _accountOwnerController,
                        decoration: InputDecoration(
                          labelText: L10n.accountName,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) =>
                            value?.trim().isEmpty == true ? L10n.pleaseEnterAccountName : null,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        L10n.promptPayWithdrawRequired,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        PromptPayQrPayload.payoutLinkedBankNotice,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB45309),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
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
                    ],
                  ),
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      Text(
                        L10n.privacyPdpaSection,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      _LinkCard(
                        title: L10n.privacyPolicyTitle,
                        onTap: () => _openDocument(LegalContent.privacyPolicy),
                      ),
                      const SizedBox(height: 8),
                      _LinkCard(
                        title: L10n.termsTitle,
                        onTap: () => _openDocument(LegalContent.termsOfService),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _acceptedPrivacy,
                        onChanged: (value) =>
                            setState(() => _acceptedPrivacy = value == true),
                        title: Text(
                          L10n.acceptPrivacyRequired,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _pushOptIn,
                        onChanged: (value) => setState(() => _pushOptIn = value),
                        title: Text(L10n.jobNotificationsOptional),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: _submitting
                          ? null
                          : () {
                              final next = _step - 1;
                              _pageController.animateToPage(
                                next,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                              );
                              setState(() => _step = next);
                            },
                      child: Text(L10n.back),
                    ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting
                          ? null
                          : () async {
                              if (_step < 3) {
                                if (!_formKey.currentState!.validate()) {
                                  return;
                                }
                                if (_step == 1 &&
                                    (_licenseImage == null ||
                                        _motorcycleImage == null ||
                                        _bookBankImage == null ||
                                        _profilePhotoImage == null ||
                                        _vehicleType == null ||
                                        _licensePlateController.text
                                            .trim()
                                            .isEmpty ||
                                        _vehicleColorController.text
                                            .trim()
                                            .isEmpty ||
                                        _vehicleBrandModelController.text
                                            .trim()
                                            .isEmpty)) {
                                  _showSnack(
                                    L10n.pleaseCompleteVehicleAndPhotos,
                                  );
                                  return;
                                }
                                final next = _step + 1;
                                await _pageController.animateToPage(
                                  next,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                );
                                setState(() => _step = next);
                                return;
                              }
                              await _submit();
                            },
                      child: Text(
                        _submitting
                            ? L10n.submitting
                            : _step < 3
                            ? L10n.next
                            : L10n.submitRegistration,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RiderRegistrationPendingScreen extends StatefulWidget {
  const RiderRegistrationPendingScreen({super.key});

  @override
  State<RiderRegistrationPendingScreen> createState() =>
      _RiderRegistrationPendingScreenState();
}

class _RiderRegistrationPendingScreenState
    extends State<RiderRegistrationPendingScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: Text(L10n.pendingApprovalTitle)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.hourglass_top_rounded, size: 72, color: AppColors.accent),
            const SizedBox(height: 16),
            Text(
              L10n.registrationSubmitted,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              L10n.registrationPendingBody,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.5, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () async {
                await RiderAuthSignOut.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (_) => false);
                }
              },
              child: Text(L10n.signOut),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
