import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/incident.dart';

abstract interface class IncidentRepository {
  /// Live list of public incidents that are ACTIVE or IN_PROGRESS, newest first,
  /// capped at [limit].
  Stream<List<Incident>> watchActivePublic({int limit = 150});

  /// The compressed photo of a report, or null when it is missing or unreadable.
  Future<Uint8List?> loadPhoto(String incidentId);
}

class FirestoreIncidentRepository implements IncidentRepository {
  FirestoreIncidentRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  static const String incidentsCollection = 'incidents';
  static const int defaultLimit = 150;

  final FirebaseFirestore _db;

  /// The visibility filter is required: rules only allow reads of public incidents,
  /// so a query without it would be denied. Needs a composite index on incidents:
  /// visibility ASC, status ASC, createdAt DESC. Firestore prints a link to create it.
  @override
  Stream<List<Incident>> watchActivePublic({int limit = defaultLimit}) =>
      Stream<List<Incident>>.multi((controller) {
        final sub = _db
            .collection(incidentsCollection)
            .where('visibility', isEqualTo: Incident.visibilityPublic)
            .where('status', whereIn: const [Incident.statusActive, Incident.statusInProgress])
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

  @override
  Future<Uint8List?> loadPhoto(String incidentId) async {
    final doc = await _db
        .collection(incidentsCollection)
        .doc(incidentId)
        .collection('photo')
        .doc('main')
        .get();
    final encoded = doc.data()?['imageBase64'];
    if (encoded is! String) return null;
    try {
      return base64Decode(encoded);
    } on FormatException {
      return null;
    }
  }
}
