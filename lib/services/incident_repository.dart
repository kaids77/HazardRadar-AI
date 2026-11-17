import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/incident.dart';

abstract interface class IncidentRepository {
  /// Live list of active, public incidents, capped at [limit].
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

  /// The query includes both equality filters. Firestore rules only allow reads
  /// of public incidents, so a query without the visibility filter would be denied.
  @override
  Stream<List<Incident>> watchActivePublic({int limit = defaultLimit}) {
    return _db
        .collection(incidentsCollection)
        .where('status', isEqualTo: 'ACTIVE')
        .where('visibility', isEqualTo: 'PUBLIC')
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final incidents = <Incident>[];
          for (final doc in snapshot.docs) {
            final incident = Incident.tryFromFirestore(doc.id, doc.data());
            if (incident != null) incidents.add(incident);
          }
          return incidents;
        });
  }

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
