import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../l10n/l10n.dart';
import 'promptpay_qr_payload.dart';

enum RiderAccessStatus {
  approved,
  pending,
  rejected,
  needsRegistration,
}

class RiderProfileData {
  const RiderProfileData({
    this.displayName,
    this.phoneNumber,
    this.contactEmail,
    this.bankName,
    this.accountNumber,
    this.accountOwner,
    this.driverLicenseImageUrl,
    this.motorcycleImageUrl,
    this.bookBankImageUrl,
    this.profilePhotoUrl,
    this.vehicleType,
    this.licensePlate,
    this.vehicleColor,
    this.vehicleBrandModel,
    this.isElectricVehicle = false,
    this.pushOptIn = false,
    this.registrationStatus,
    this.promptPayPhoneNumber,
    this.promptPayNationalId,
  });

  final String? displayName;
  final String? phoneNumber;
  final String? contactEmail;
  final String? bankName;
  final String? accountNumber;
  final String? accountOwner;
  final String? driverLicenseImageUrl;
  final String? motorcycleImageUrl;
  final String? bookBankImageUrl;
  final String? profilePhotoUrl;
  final String? vehicleType;
  final String? licensePlate;
  final String? vehicleColor;
  final String? vehicleBrandModel;
  final bool isElectricVehicle;
  final bool pushOptIn;
  final String? registrationStatus;
  final String? promptPayPhoneNumber;
  final String? promptPayNationalId;

  /// Fields van2 travel page reads from `riders/{uid}`.
  bool get isCompleteForCustomerTravel {
    return _nonEmpty(profilePhotoUrl) &&
        _nonEmpty(vehicleType) &&
        _nonEmpty(licensePlate) &&
        _nonEmpty(vehicleColor) &&
        _nonEmpty(vehicleBrandModel);
  }

  bool get hasPromptPayForPayout {
    return PromptPayQrPayload.hasValidPayoutProfile(
      phone: promptPayPhoneNumber,
      nationalId: promptPayNationalId,
    );
  }

  static bool _nonEmpty(String? value) => value?.trim().isNotEmpty == true;

  static RiderProfileData fromMap(Map<String, dynamic>? map) {
    final data = map ?? const <String, dynamic>{};
    return RiderProfileData(
      displayName: data['displayName']?.toString().trim(),
      phoneNumber: (data['phoneNumber'] ?? data['phone'])?.toString().trim(),
      contactEmail: (data['contactEmail'] ?? data['email'])?.toString().trim(),
      bankName: data['bankName']?.toString().trim(),
      accountNumber: data['accountNumber']?.toString().trim(),
      accountOwner: (data['accountOwner'] ?? data['accountName'])
          ?.toString()
          .trim(),
      driverLicenseImageUrl: data['driverLicenseImageUrl']?.toString().trim(),
      motorcycleImageUrl: data['motorcycleImageUrl']?.toString().trim(),
      bookBankImageUrl: data['bookBankImageUrl']?.toString().trim(),
      profilePhotoUrl: _readPhotoUrl(data),
      vehicleType: data['vehicleType']?.toString().trim(),
      licensePlate: data['licensePlate']?.toString().trim(),
      vehicleColor: data['vehicleColor']?.toString().trim(),
      vehicleBrandModel: data['vehicleBrandModel']?.toString().trim(),
      isElectricVehicle: data['isElectricVehicle'] == true,
      pushOptIn: data['pushOptIn'] == true,
      registrationStatus: data['registrationStatus']?.toString(),
      promptPayPhoneNumber: data['promptPayPhoneNumber']?.toString().trim(),
      promptPayNationalId: (data['promptPayNationalId'] ??
              data['promptPayNationalIdOrTaxId'])
          ?.toString()
          .trim(),
    );
  }

  static String? _readPhotoUrl(Map<String, dynamic> map) {
    for (final key in <String>['profilePhotoUrl', 'photoUrl', 'imageUrl']) {
      final value = map[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  static Map<String, dynamic> mergeMaps(
    Map<String, dynamic>? primary,
    Map<String, dynamic>? secondary,
  ) {
    final merged = <String, dynamic>{};
    if (secondary != null) {
      merged.addAll(secondary);
    }
    if (primary != null) {
      merged.addAll(primary);
    }
    return merged;
  }
}

class RiderRegistrationService {
  RiderRegistrationService._();

  static const String collection = 'rider_registrations';
  static const String privacyPolicyVersion = '2026-06-01';

  static Future<RiderAccessStatus> resolveAccessStatus(String uid) async {
    DocumentSnapshot<Map<String, dynamic>>? registration;
    try {
      registration = await FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .get();
    } catch (_) {
      // Missing Firestore rules or transient read errors — fall back to riders doc.
      registration = null;
    }

    DocumentSnapshot<Map<String, dynamic>>? rider;
    try {
      rider = await FirebaseFirestore.instance.collection('riders').doc(uid).get();
    } catch (_) {
      rider = null;
    }

    return statusFromSnapshots(
      registration: registration,
      rider: rider,
    );
  }

  static RiderAccessStatus statusFromSnapshots({
    DocumentSnapshot<Map<String, dynamic>>? registration,
    DocumentSnapshot<Map<String, dynamic>>? rider,
  }) {
    if (registration != null && registration.exists) {
      final status =
          registration.data()?['registrationStatus']?.toString() ?? 'pending';
      return switch (status) {
        'approved' => RiderAccessStatus.approved,
        'rejected' => RiderAccessStatus.rejected,
        _ => RiderAccessStatus.pending,
      };
    }

    final riderData = rider?.data();
    final riderStatus = riderData?['registrationStatus']?.toString();
    if (riderStatus == 'approved') {
      return RiderAccessStatus.approved;
    }
    if (riderStatus == 'pending') {
      return RiderAccessStatus.pending;
    }
    if (riderStatus == 'rejected') {
      return RiderAccessStatus.rejected;
    }

    final hasBank = _hasBankProfile(riderData);
    if (rider != null && rider.exists && hasBank && riderStatus == null) {
      return RiderAccessStatus.pending;
    }
    return RiderAccessStatus.needsRegistration;
  }

  static Stream<RiderAccessStatus> watchAccessStatus(String uid) {
    DocumentSnapshot<Map<String, dynamic>>? registration;
    DocumentSnapshot<Map<String, dynamic>>? rider;
    late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
        registrationSub;
    late final StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>
        riderSub;

    late final StreamController<RiderAccessStatus> controller;
    controller = StreamController<RiderAccessStatus>(
      onListen: () {
        void emit() {
          if (!controller.isClosed) {
            controller.add(
              statusFromSnapshots(registration: registration, rider: rider),
            );
          }
        }

        registrationSub = FirebaseFirestore.instance
            .collection(collection)
            .doc(uid)
            .snapshots()
            .listen(
              (snapshot) {
                registration = snapshot;
                emit();
              },
              onError: (_) {
                registration = null;
                emit();
              },
            );

        riderSub = FirebaseFirestore.instance
            .collection('riders')
            .doc(uid)
            .snapshots()
            .listen(
              (snapshot) {
                rider = snapshot;
                emit();
              },
              onError: (_) {
                rider = null;
                emit();
              },
            );
      },
      onCancel: () async {
        await registrationSub.cancel();
        await riderSub.cancel();
      },
    );

    return controller.stream;
  }

  static bool _hasBankProfile(Map<String, dynamic>? data) {
    if (data == null) {
      return false;
    }
    return data['bankName']?.toString().trim().isNotEmpty == true &&
        data['accountNumber']?.toString().trim().isNotEmpty == true &&
        (data['accountOwner']?.toString().trim().isNotEmpty == true ||
            data['accountName']?.toString().trim().isNotEmpty == true);
  }

  static Future<void> submitRegistration({
    required User user,
    required String phoneNumber,
    required String displayName,
    required String bankName,
    required String accountNumber,
    required String accountOwner,
    String? promptPayPhoneNumber,
    String? promptPayNationalId,
    required String contactEmail,
    required String driverLicenseImageUrl,
    required String motorcycleImageUrl,
    required String bookBankImageUrl,
    required String profilePhotoUrl,
    required String vehicleType,
    required String licensePlate,
    required String vehicleColor,
    required String vehicleBrandModel,
    required bool isElectricVehicle,
    required bool acceptedPrivacy,
    bool marketingOptIn = false,
    bool pushOptIn = false,
  }) async {
    if (!acceptedPrivacy) {
      throw StateError(L10n.privacyPolicyRequired);
    }

    final now = FieldValue.serverTimestamp();
    final normalizedContactEmail = contactEmail.trim();
    final resolvedEmail = normalizedContactEmail.isNotEmpty
        ? normalizedContactEmail
        : (user.email?.trim() ?? '');
    final payload = <String, dynamic>{
      'uid': user.uid,
      'email': resolvedEmail,
      if (normalizedContactEmail.isNotEmpty) 'contactEmail': normalizedContactEmail,
      'phoneNumber': phoneNumber,
      'displayName': displayName,
      'bankName': bankName,
      'accountNumber': accountNumber,
      'accountOwner': accountOwner,
      'accountName': accountOwner,
      if (promptPayPhoneNumber?.trim().isNotEmpty == true)
        'promptPayPhoneNumber':
            promptPayPhoneNumber!.replaceAll(RegExp(r'\D'), ''),
      if (promptPayNationalId?.trim().isNotEmpty == true)
        'promptPayNationalId':
            promptPayNationalId!.replaceAll(RegExp(r'\D'), ''),
      'driverLicenseImageUrl': driverLicenseImageUrl,
      'motorcycleImageUrl': motorcycleImageUrl,
      'bookBankImageUrl': bookBankImageUrl,
      'profilePhotoUrl': profilePhotoUrl,
      'photoUrl': profilePhotoUrl,
      'vehicleType': vehicleType,
      'licensePlate': licensePlate,
      'vehicleColor': vehicleColor,
      'vehicleBrandModel': vehicleBrandModel,
      'isElectricVehicle': isElectricVehicle,
      'rating': 5.0,
      'registrationStatus': 'pending',
      'privacyPolicyVersion': privacyPolicyVersion,
      'privacyAcceptedAt': now,
      'marketingOptIn': marketingOptIn,
      'pushOptIn': pushOptIn,
      'role': 'rider',
      'userType': 'rider',
      'updatedAt': now,
      'createdAt': now,
      'submittedAt': now,
    };

    final batch = FirebaseFirestore.instance.batch();
    final registrationRef =
        FirebaseFirestore.instance.collection(collection).doc(user.uid);
    final riderRef = FirebaseFirestore.instance.collection('riders').doc(user.uid);
    batch.set(registrationRef, payload, SetOptions(merge: true));
    batch.set(riderRef, payload, SetOptions(merge: true));
    await batch.commit();
  }

  static Future<RiderProfileData> fetchProfile(String uid) async {
    DocumentSnapshot<Map<String, dynamic>>? registration;
    DocumentSnapshot<Map<String, dynamic>>? rider;

    try {
      registration = await FirebaseFirestore.instance
          .collection(collection)
          .doc(uid)
          .get();
    } catch (_) {
      registration = null;
    }

    try {
      rider = await FirebaseFirestore.instance.collection('riders').doc(uid).get();
    } catch (_) {
      rider = null;
    }

    final merged = RiderProfileData.mergeMaps(
      rider?.data(),
      registration?.data(),
    );
    return RiderProfileData.fromMap(merged);
  }

  static Future<void> updateProfile({
    required String uid,
    required String displayName,
    required String phoneNumber,
    String? bankName,
    String? accountNumber,
    String? accountOwner,
    String? driverLicenseImageUrl,
    String? motorcycleImageUrl,
    String? bookBankImageUrl,
    String? profilePhotoUrl,
    String? vehicleType,
    String? licensePlate,
    String? vehicleColor,
    String? vehicleBrandModel,
    bool? isElectricVehicle,
    bool? pushOptIn,
    String? promptPayPhoneNumber,
    String? promptPayNationalId,
    String? registrationStatus,
  }) async {
    final payload = <String, dynamic>{
      'uid': uid,
      'displayName': displayName.trim(),
      'phoneNumber': phoneNumber.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    void putIfNonEmpty(String key, String? value) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) {
        payload[key] = trimmed;
      }
    }

    putIfNonEmpty('bankName', bankName);
    putIfNonEmpty('accountNumber', accountNumber);
    putIfNonEmpty('accountOwner', accountOwner);
    if (accountOwner?.trim().isNotEmpty == true) {
      payload['accountName'] = accountOwner!.trim();
    }
    putIfNonEmpty('driverLicenseImageUrl', driverLicenseImageUrl);
    putIfNonEmpty('motorcycleImageUrl', motorcycleImageUrl);
    putIfNonEmpty('bookBankImageUrl', bookBankImageUrl);
    putIfNonEmpty('profilePhotoUrl', profilePhotoUrl);
    if (profilePhotoUrl?.trim().isNotEmpty == true) {
      payload['photoUrl'] = profilePhotoUrl!.trim();
    }
    putIfNonEmpty('vehicleType', vehicleType);
    putIfNonEmpty('licensePlate', licensePlate);
    putIfNonEmpty('vehicleColor', vehicleColor);
    putIfNonEmpty('vehicleBrandModel', vehicleBrandModel);
    if (isElectricVehicle != null) {
      payload['isElectricVehicle'] = isElectricVehicle;
    }
    if (pushOptIn != null) {
      payload['pushOptIn'] = pushOptIn;
    }
    final ppPhone = promptPayPhoneNumber?.replaceAll(RegExp(r'\D'), '');
    if (ppPhone != null && ppPhone.isNotEmpty) {
      payload['promptPayPhoneNumber'] = ppPhone;
    }
    final ppNational = promptPayNationalId?.replaceAll(RegExp(r'\D'), '');
    if (ppNational != null && ppNational.isNotEmpty) {
      payload['promptPayNationalId'] = ppNational;
    }
    // registrationStatus is admin-controlled and blocked by Firestore rules on update.

    final batch = FirebaseFirestore.instance.batch();
    final registrationRef =
        FirebaseFirestore.instance.collection(collection).doc(uid);
    final riderRef = FirebaseFirestore.instance.collection('riders').doc(uid);
    batch.set(registrationRef, payload, SetOptions(merge: true));
    batch.set(riderRef, payload, SetOptions(merge: true));
    await batch.commit();
  }
}
