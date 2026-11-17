import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/report.dart';

abstract interface class ReportRepository {
  /// Stores the report and its photo together. Returns the new incident id.
  /// Either both documents are written or neither is.
  Future<String> create(NewReport report);
}

class FirestoreReportRepository implements ReportRepository {
  FirestoreReportRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Future<String> create(NewReport report) async {
    final incident = _db.collection('incidents').doc();
    final photo = incident.collection('photo').doc('main');

    // One batch, so the photo rule can check ownership with getAfter.
    final batch = _db.batch()
      ..set(incident, {...report.incidentFields(), 'createdAt': FieldValue.serverTimestamp()})
      ..set(photo, {...report.photoFields(), 'createdAt': FieldValue.serverTimestamp()});
    await batch.commit();
    return incident.id;
  }
}
