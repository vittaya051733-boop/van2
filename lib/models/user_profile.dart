import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/shop_profile_resolver.dart';

/// Minimal profile information stored in the top-level `users` collection
/// so other services (chat/friends) can reference a shop quickly.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.displayName,
    this.phoneNumber,
    this.photoUrl,
    this.serviceType,
    this.isOfficial = false,
    this.profileCompleted = false,
  });

  final String uid;
  final String displayName;
  final String? phoneNumber;
  final String? photoUrl;
  final String? serviceType;
  final bool isOfficial;
  final bool profileCompleted;

  factory UserProfile.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    return UserProfile.fromMap(doc.id, doc.data());
  }

  factory UserProfile.fromMap(String uid, Map<String, dynamic>? data) {
    final map = data ?? const <String, dynamic>{};
    final resolvedName = ShopProfileResolver.resolveName(map);
    final resolvedImageUrl = ShopProfileResolver.resolveImageUrl(map);
    return UserProfile(
      uid: uid,
      displayName:
          (resolvedName ?? map['displayName'] ?? map['name'] ?? 'ผู้ใช้ใหม่').toString(),
      phoneNumber: (map['phoneNumber'] ?? map['phone']) as String?,
      photoUrl: (resolvedImageUrl ?? map['photoUrl'] ?? map['imageUrl'] ?? map['shopImageUrl'])
          as String?,
      serviceType: (map['serviceType'] ?? map['type']) as String?,
      isOfficial: (map['isOfficial'] as bool?) ?? false,
      profileCompleted: (map['profileCompleted'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'displayName': displayName,
      if (phoneNumber != null && phoneNumber!.isNotEmpty) 'phoneNumber': phoneNumber,
      if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
      if (serviceType != null && serviceType!.isNotEmpty) 'serviceType': serviceType,
      'isOfficial': isOfficial,
      'profileCompleted': profileCompleted,
    };
  }

  UserProfile copyWith({
    String? displayName,
    String? phoneNumber,
    String? photoUrl,
    String? serviceType,
    bool? isOfficial,
    bool? profileCompleted,
  }) {
    return UserProfile(
      uid: uid,
      displayName: displayName ?? this.displayName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      photoUrl: photoUrl ?? this.photoUrl,
      serviceType: serviceType ?? this.serviceType,
      isOfficial: isOfficial ?? this.isOfficial,
      profileCompleted: profileCompleted ?? this.profileCompleted,
    );
  }
}
