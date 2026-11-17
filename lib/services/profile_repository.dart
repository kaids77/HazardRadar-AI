import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';

abstract interface class ProfileRepository {
  /// Returns the profile for [uid], creating the Level 1 profile if it does not exist.
  Future<UserProfile> getOrCreateProfile(String uid);
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
}
