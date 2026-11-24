import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/incident.dart';

abstract interface class MyReportsRepository {
  /// The user's own reports, newest first, including quarantined ones.
  Stream<List<Incident>> watchMine(String uid, {int limit = 50});
}

class FirestoreMyReportsRepository implements MyReportsRepository {
  FirestoreMyReportsRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Needs a composite index on incidents: reporterUid ascending, createdAt descending.
  /// Firestore prints a link to create it the first time this query runs.
  @override
  Stream<List<Incident>> watchMine(String uid, {int limit = 50}) =>
      Stream<List<Incident>>.multi((controller) {
        final sub = _db
            .collection('incidents')
            .where('reporterUid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(limit)
            .snapshots()
            .map((snapshot) => [
                  for (final doc in snapshot.docs) ?Incident.tryFromFirestore(doc.id, doc.data()),
                ])
            .listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
        controller.onCancel = sub.cancel;
      });
}
