import 'package:cloud_firestore/cloud_firestore.dart';

import '../l10n/l10n.dart';

class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.phoneNumber,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String? phoneNumber;
  final String? photoUrl;

  factory UserProfile.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    return UserProfile.fromMap(doc.id, doc.data());
  }

  factory UserProfile.fromMap(String uid, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    return UserProfile(
      uid: uid,
      displayName: (map['displayName'] ?? map['name'] ?? map['shopName'] ?? L10n.newUser).toString(),
      phoneNumber: (map['phoneNumber'] ?? map['phone']) as String?,
      photoUrl: (map['photoUrl'] ?? map['imageUrl'] ?? map['shopImageUrl']) as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'displayName': displayName,
      if (phoneNumber != null && phoneNumber!.isNotEmpty) 'phoneNumber': phoneNumber,
      if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
    };
  }
}
