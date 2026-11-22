import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/incident.dart';
import '../models/transparency_entry.dart';
import 'dispatch_repository.dart';

/// Reads the public report transparency log. Every signed-in user may read it.
abstract interface class TransparencyRepository {
  /// The newest entries first.
  Stream<List<TransparencyEntry>> watchRecent({int limit = 30});

  /// Totals for the log: resolved, and quarantined (only reports still in quarantine).
  Future<({int resolved, int quarantined})> counts();
}

class FirestoreTransparencyRepository implements TransparencyRepository {
  FirestoreTransparencyRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _log => _db.collection(TransparencyEntry.collection);

  /// One orderBy on a single field, so the automatic index is enough.
  @override
  Stream<List<TransparencyEntry>> watchRecent({int limit = 30}) => _log
      .orderBy('at', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final doc in s.docs) ?TransparencyEntry.tryFromFirestore(doc.id, doc.data())]);

  @override
  Future<({int resolved, int quarantined})> counts() async {
    final resolved = await _log.where('kind', isEqualTo: TransparencyEntry.kindResolved).count().get();
    final quarantined = await _log.where('kind', isEqualTo: TransparencyEntry.kindQuarantined).count().get();
    return (resolved: resolved.count ?? 0, quarantined: quarantined.count ?? 0);
  }
}

/// Staff-only: adds log entries for reports resolved or quarantined before the log existed.
/// Each batch is small, because every entry's rule reads its report.
class TransparencySync {
  TransparencySync({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  static const int batchSize = 5;

  final FirebaseFirestore _db;

  /// Returns how many entries were added.
  Future<int> syncMissing() async {
    try {
      final existing = {for (final doc in (await _db.collection(TransparencyEntry.collection).get()).docs) doc.id};
      final incidents = _db.collection('incidents');
      final resolved = await incidents.where('status', isEqualTo: Incident.statusResolved).get();
      final quarantined = await incidents.where('visibility', isEqualTo: Incident.visibilityQuarantined).get();

      final writes = <(DocumentReference<Map<String, dynamic>>, Map<String, Object>)>[];
      for (final doc in resolved.docs) {
        final data = doc.data();
        final resolvedAt = data['resolvedAt'];
        if (existing.contains(doc.id) || resolvedAt is! Timestamp || data['visibility'] != Incident.visibilityPublic) continue;
        final entry = _entry(data, TransparencyEntry.kindResolved,
            crew: _string(data['assignedCrew']), note: _string(data['resolutionNote']));
        if (entry != null) writes.add((_db.collection(TransparencyEntry.collection).doc(doc.id), {...entry, 'at': resolvedAt}));
      }
      for (final doc in quarantined.docs) {
        final data = doc.data();
        if (existing.contains(doc.id)) continue;
        final flagged = _string(data['flaggedBy']).isNotEmpty;
        final votes = data['netVotes'];
        if (!flagged && !(votes is int && votes <= -3)) continue;
        final entry = _entry(data, TransparencyEntry.kindQuarantined,
            reason: flagged ? TransparencyEntry.reasonSentinelFlag : TransparencyEntry.reasonCommunityVotes);
        if (entry != null) {
          writes.add((_db.collection(TransparencyEntry.collection).doc(doc.id), {...entry, 'at': FieldValue.serverTimestamp()}));
        }
      }

      for (var start = 0; start < writes.length; start += batchSize) {
        final batch = _db.batch();
        for (final (ref, fields) in writes.skip(start).take(batchSize)) {
          batch.set(ref, fields);
        }
        await batch.commit();
      }
      return writes.length;
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') throw const DispatchFailed('Only staff can sync the transparency log.');
      rethrow;
    }
  }

  static Map<String, Object>? _entry(
    Map<String, dynamic> data,
    String kind, {
    String reason = '',
    String crew = '',
    String note = '',
  }) {
    final category = data['category'];
    final riskLevel = data['riskLevel'];
    if (category is! String || riskLevel is! String) return null;
    return TransparencyEntry.fields(
      category: category,
      riskLevel: riskLevel,
      kind: kind,
      reason: reason,
      crew: crew,
      resolutionNote: note,
    );
  }

  static String _string(Object? value) => value is String ? value : '';
}
