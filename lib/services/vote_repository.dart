import 'package:cloud_firestore/cloud_firestore.dart';

class AlreadyVotedException implements Exception {
  const AlreadyVotedException();

  @override
  String toString() => 'You already voted on this report.';
}

abstract interface class VoteRepository {
  /// Records one vote of [value] (+/-1 or +/-2) and updates the report's net votes.
  /// Throws [AlreadyVotedException] if [uid] voted before.
  Future<void> cast({required String incidentId, required String uid, required int value});
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
  Future<void> cast({required String incidentId, required String uid, required int value}) {
    final incident = _db.collection('incidents').doc(incidentId);
    final vote = incident.collection('votes').doc(uid);

    return _db.runTransaction((transaction) async {
      if ((await transaction.get(vote)).exists) throw const AlreadyVotedException();

      final current = (await transaction.get(incident)).data()?['netVotes'];
      final next = (current is int ? current : 0) + value;

      transaction.set(vote, {'value': value, 'createdAt': FieldValue.serverTimestamp()});
      transaction.update(incident, {
        'netVotes': next,
        if (next <= quarantineAt) 'visibility': 'QUARANTINED',
      });
    });
  }
}
