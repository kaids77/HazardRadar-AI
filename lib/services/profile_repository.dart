import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';
import 'level_policy.dart';

abstract interface class ProfileRepository {
  /// Returns the profile for [uid], creating the Level 1 profile if it does not exist.
  Future<UserProfile> getOrCreateProfile(String uid);

  /// Raises a Level 1 profile to Level 2 (Civic Scout). Profiles already at
  /// Level 2 or above are returned unchanged.
  Future<UserProfile> upgradeToCivicScout(String uid);

  /// Applies a level the user has earned with points (see LevelPolicy.dueUpgrade)
  /// and returns the current profile. Does nothing when no level is due.
  Future<UserProfile> applyEarnedLevel(String uid);

  /// Saves a Neighborhood Sentinel's focus badge (one of LevelPolicy.focusBadges).
  Future<void> setFocusBadge(String uid, String badge);

  /// Saves the user's own display name (1 to 40 characters).
  Future<void> setDisplayName(String uid, String name);

  /// Turns the public "Reported by" credit on the user's resolved reports on or off.
  Future<void> setCreditName(String uid, bool value);
}

class FirestoreProfileRepository implements ProfileRepository {
  FirestoreProfileRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  static const String usersCollection = 'users';

  final FirebaseFirestore _db;

  /// Reads and creates inside one transaction. An existing profile is never
  /// overwritten, even if two launches race.
  @override
  Future<UserProfile> getOrCreateProfile(String uid) {
    final ref = _db.collection(usersCollection).doc(uid);

    return _db.runTransaction<UserProfile>((transaction) async {
      final snapshot = await transaction.get(ref);
      final existing = snapshot.data();
      if (snapshot.exists && existing != null) {
        return UserProfile.fromFirestore(uid, existing);
      }

      final fields = UserProfile.newCitizenFields();
      transaction.set(ref, {
        ...fields,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return UserProfile.fromFirestore(uid, fields);
    });
  }

  @override
  Future<UserProfile> upgradeToCivicScout(String uid) {
    final ref = _db.collection(usersCollection).doc(uid);

    return _db.runTransaction<UserProfile>((transaction) async {
      final data = (await transaction.get(ref)).data();
      if (data == null) throw StateError('Profile does not exist');
      final profile = UserProfile.fromFirestore(uid, data);
      if (profile.tier != UserProfile.tierCommuterObserver) return profile;

      transaction.update(ref, {'tier': UserProfile.tierCivicScout});
      return UserProfile.fromFirestore(uid, {
        ...data,
        'tier': UserProfile.tierCivicScout,
      });
    });
  }

  @override
  Future<UserProfile> applyEarnedLevel(String uid) {
    final ref = _db.collection(usersCollection).doc(uid);

    return _db.runTransaction<UserProfile>((transaction) async {
      final data = (await transaction.get(ref)).data();
      if (data == null) throw StateError('Profile does not exist');
      final due = LevelPolicy.dueUpgrade(UserProfile.fromFirestore(uid, data));
      if (due == null) return UserProfile.fromFirestore(uid, data);

      final changes = <String, Object>{'tier': due.tier};
      if (due.role != data['role']) changes['role'] = due.role;
      transaction.update(ref, changes);
      return UserProfile.fromFirestore(uid, {...data, ...changes});
    });
  }

  @override
  Future<void> setFocusBadge(String uid, String badge) {
    if (!LevelPolicy.focusBadges.contains(badge)) throw ArgumentError.value(badge, 'badge');
    return _db.collection(usersCollection).doc(uid).update({'focusBadge': badge});
  }

  @override
  Future<void> setDisplayName(String uid, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 40) throw ArgumentError.value(name, 'name');
    return _db.collection(usersCollection).doc(uid).update({'displayName': trimmed});
  }

  @override
  Future<void> setCreditName(String uid, bool value) =>
      _db.collection(usersCollection).doc(uid).update({'creditName': value});
}
