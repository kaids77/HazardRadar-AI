import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/incident.dart';
import '../models/transparency_entry.dart';
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
  Future<UserProfile> getOrCreateProfile(String uid) async {
    final ref = _db.collection(usersCollection).doc(uid);

    final profile = await _db.runTransaction<UserProfile>((transaction) async {
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
    if (profile.tier >= UserProfile.tierCivicScout) {
      unawaited(_syncResolvedCredit(uid));
    }
    return profile;
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
  Future<void> setDisplayName(String uid, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed.length > 40) throw ArgumentError.value(name, 'name');
    await _db.collection(usersCollection).doc(uid).update({'displayName': trimmed});
    await _syncResolvedCredit(uid);
  }

  @override
  Future<void> setCreditName(String uid, bool value) async {
    await _db.collection(usersCollection).doc(uid).update({'creditName': value});
    await _syncResolvedCredit(uid);
  }

  static const int _creditBatchSize = 5;

  /// Updates the public transparency entries of [uid]'s own resolved reports so their
  /// "Reported by" credit matches their current [UserProfile.creditName] and [UserProfile.displayName].
  Future<void> _syncResolvedCredit(String uid) async {
    try {
      final userSnap = await _db.collection(usersCollection).doc(uid).get();
      final credit = TransparencyEntry.creditFor(userSnap.data());
      final own = await _db.collection('incidents').where('reporterUid', isEqualTo: uid).get();
      final resolved = [
        for (final doc in own.docs)
          if (doc.data()['status'] == Incident.statusResolved &&
              doc.data()['visibility'] != Incident.visibilityQuarantined &&
              doc.data()['resolvedAt'] is Timestamp &&
              doc.data()['category'] is String &&
              doc.data()['riskLevel'] is String)
            doc,
      ];
      if (resolved.isEmpty) return;

      final log = _db.collection(TransparencyEntry.collection);
      final existing = await Future.wait([for (final doc in resolved) log.doc(doc.id).get()]);
      final writes = <(DocumentReference<Map<String, dynamic>>, Map<String, Object>)>[];
      for (var i = 0; i < resolved.length; i++) {
        final doc = resolved[i];
        final data = doc.data();
        final current = existing[i].data();
        final currentCredit = current?['reporterName'] is String ? current!['reporterName'] as String : null;
        if (current != null &&
            current['kind'] == TransparencyEntry.kindResolved &&
            currentCredit == credit) {
          continue;
        }
        writes.add((
          log.doc(doc.id),
          {
            ...TransparencyEntry.fields(
              category: data['category'] as String,
              riskLevel: data['riskLevel'] as String,
              kind: TransparencyEntry.kindResolved,
              crew: data['assignedCrew'] is String ? data['assignedCrew'] as String : '',
              resolutionNote: data['resolutionNote'] is String ? data['resolutionNote'] as String : '',
              reporterName: credit,
            ),
            'at': data['resolvedAt'] as Timestamp,
          },
        ));
      }
      for (var start = 0; start < writes.length; start += _creditBatchSize) {
        final batch = _db.batch();
        for (final (ref, fields) in writes.skip(start).take(_creditBatchSize)) {
          batch.set(ref, fields);
        }
        await batch.commit();
      }
    } catch (_) {
      // Best-effort sync; saving the profile preference itself already succeeded.
    }
  }
}
