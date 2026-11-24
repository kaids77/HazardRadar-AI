import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/transparency_entry.dart';

class AlreadyVotedException implements Exception {
  const AlreadyVotedException();

  @override
  String toString() => 'You already voted on this report.';
}

abstract interface class VoteRepository {
  /// Records one vote of [value] (+/-1 or +/-2) and updates the report's net votes.
  /// Returns the new net vote total, so the app can say right away whether the
  /// report became verified or quarantined.
  /// Throws [AlreadyVotedException] if [uid] voted before.
  Future<int> cast({required String incidentId, required String uid, required int value});

  /// A Neighborhood Sentinel sends a public report straight to quarantine as spam or a duplicate.
  Future<void> flag({required String incidentId, required String uid});
}

class FirestoreVoteRepository implements VoteRepository {
  FirestoreVoteRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// A report at or below this many net votes is hidden from the public map.
  static const int quarantineAt = -3;

  final FirebaseFirestore _db;

  /// A transaction keeps the vote document and the new total consistent.
  /// The rules require both writes together and check the total moves by `value`.
  @override
  Future<int> cast({required String incidentId, required String uid, required int value}) {
    final incident = _db.collection('incidents').doc(incidentId);
    final vote = incident.collection('votes').doc(uid);

    return _db.runTransaction<int>((transaction) async {
      if ((await transaction.get(vote)).exists) throw const AlreadyVotedException();

      final data = (await transaction.get(incident)).data();
      final current = data?['netVotes'];
      final next = (current is int ? current : 0) + value;
      final quarantines = next <= quarantineAt;

      transaction.set(vote, {'value': value, 'createdAt': FieldValue.serverTimestamp()});
      transaction.update(incident, {
        'netVotes': next,
        if (quarantines) 'visibility': 'QUARANTINED',
      });
      // The public transparency log records the quarantine in the same transaction.
      final log = quarantines ? _logEntry(data, TransparencyEntry.reasonCommunityVotes) : null;
      if (log != null) transaction.set(_db.collection(TransparencyEntry.collection).doc(incidentId), log);
      return next;
    });
  }

  @override
  Future<void> flag({required String incidentId, required String uid}) {
    final incident = _db.collection('incidents').doc(incidentId);
    return _db.runTransaction((transaction) async {
      final data = (await transaction.get(incident)).data();
      transaction.update(incident, {'visibility': 'QUARANTINED', 'flaggedBy': uid});
      final log = _logEntry(data, TransparencyEntry.reasonSentinelFlag);
      if (log != null) transaction.set(_db.collection(TransparencyEntry.collection).doc(incidentId), log);
    });
  }

  /// A QUARANTINED log entry copied from the report, or null when the report lacks the fields.
  static Map<String, Object>? _logEntry(Map<String, dynamic>? data, String reason) {
    final category = data?['category'];
    final riskLevel = data?['riskLevel'];
    if (category is! String || riskLevel is! String) return null;
    return {
      ...TransparencyEntry.fields(
        category: category,
        riskLevel: riskLevel,
        kind: TransparencyEntry.kindQuarantined,
        reason: reason,
      ),
      'at': FieldValue.serverTimestamp(),
    };
  }
}
