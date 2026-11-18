import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/triage_result.dart';
import 'triage_service.dart';

/// A report of the current user that was triaged offline and still needs the AI.
class PendingReport {
  const PendingReport({required this.id, required this.note});

  final String id;
  final String note;
}

abstract interface class PendingReportRepository {
  /// The user's own reports with aiProcessed == false, at most [limit].
  Future<List<PendingReport>> pendingFor(String uid, {int limit = 5});

  /// Writes the AI result. firestore.rules allow this once per report, by its owner.
  Future<void> applyAi(String incidentId, TriageResult result);
}

class FirestorePendingReportRepository implements PendingReportRepository {
  FirestorePendingReportRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  @override
  Future<List<PendingReport>> pendingFor(String uid, {int limit = 5}) async {
    final snapshot = await _db
        .collection('incidents')
        .where('reporterUid', isEqualTo: uid)
        .where('aiProcessed', isEqualTo: false)
        .limit(limit)
        .get();
    return [
      for (final doc in snapshot.docs)
        if (doc.data()['note'] is String) PendingReport(id: doc.id, note: doc.data()['note'] as String),
    ];
  }

  @override
  Future<void> applyAi(String incidentId, TriageResult result) {
    return _db.collection('incidents').doc(incidentId).update({
      'category': result.category,
      'riskLevel': result.riskLevel,
      'aiSummary': result.aiSummary,
      'recommendedAction': result.recommendedAction,
      'aiProcessed': true,
    });
  }
}

/// Sends offline-triaged reports to the AI once the proxy is reachable again.
/// Best effort: any failure leaves the report pending for the next launch.
class ReportEnricher {
  const ReportEnricher({required this.repository, required this.proxy});

  final PendingReportRepository repository;
  final ProxyTriageService proxy;

  /// Returns how many reports were updated.
  Future<int> enrichPending(String uid) async {
    var updated = 0;
    try {
      final pending = await repository.pendingFor(uid);
      for (final report in pending) {
        if (report.note.trim().isEmpty) continue;
        final result = await proxy.tryClassify(report.note);
        // Stop at the first proxy failure; the connection is probably still down.
        if (result == null) break;
        await repository.applyAi(report.id, result);
        updated++;
      }
    } on Object {
      // Leave remaining reports pending.
    }
    return updated;
  }
}
