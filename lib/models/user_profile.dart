/// A commuter's profile as stored in `users/{uid}`.
///
/// Field names and values must match `firestore.rules`. Changing them
/// without updating the rules makes profile creation fail.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.role,
    required this.tier,
    required this.accountStatus,
  });

  static const String roleCitizen = 'CITIZEN';
  static const String accountActive = 'ACTIVE';
  static const int tierCommuterObserver = 1;
  static const int tierCivicScout = 2;

  final String uid;
  final String role;
  final int tier;
  final String accountStatus;

  String get tierTitle => switch (tier) {
        1 => 'Commuter Observer',
        2 => 'Civic Scout',
        3 => 'Neighborhood Sentinel',
        4 => 'Municipal Dispatcher',
        5 => 'System Administrator',
        _ => 'Unknown tier',
      };

  /// Fields for a new Level 1 profile, without the server timestamp.
  static Map<String, Object> newCitizenFields() => {
        'role': roleCitizen,
        'tier': tierCommuterObserver,
        'accountStatus': accountActive,
      };

  factory UserProfile.fromFirestore(String uid, Map<String, Object?> data) {
    final tier = data['tier'];
    return UserProfile(
      uid: uid,
      role: data['role'] as String? ?? roleCitizen,
      tier: tier is int ? tier : tierCommuterObserver,
      accountStatus: data['accountStatus'] as String? ?? accountActive,
    );
  }
}
