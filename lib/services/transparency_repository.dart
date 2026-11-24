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
  /// Multi-subscription stream so remounted widgets and multiple listeners can
  /// listen without stream-already-listened-to errors.
  @override
  Stream<List<TransparencyEntry>> watchRecent({int limit = 30}) =>
      Stream<List<TransparencyEntry>>.multi((controller) {
        final sub = _log
            .orderBy('at', descending: true)
            .limit(limit)
            .snapshots()
            .map((s) => [for (final doc in s.docs) ?TransparencyEntry.tryFromFirestore(doc.id, doc.data())])
            .listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
        controller.onCancel = sub.cancel;
      });

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
      final existing = {
        for (final doc in (await _db.collection(TransparencyEntry.collection).get()).docs) doc.id: doc.data(),
      };
      final incidents = _db.collection('incidents');
      final resolved = await incidents.where('status', isEqualTo: Incident.statusResolved).get();
      final quarantined = await incidents.where('visibility', isEqualTo: Incident.visibilityQuarantined).get();

      final writes = <(DocumentReference<Map<String, dynamic>>, Map<String, Object>)>[];
      final toResolve = [
        for (final doc in resolved.docs)
          if (doc.data()['resolvedAt'] is Timestamp &&
              doc.data()['visibility'] != Incident.visibilityQuarantined)
            doc,
      ];
      final credits = await _credits({for (final doc in toResolve) _string(doc.data()['reporterUid'])});
      for (final doc in toResolve) {
        final data = doc.data();
        final credit = credits[_string(data['reporterUid'])];
        final current = existing[doc.id];
        final currentCredit = current?['reporterName'] is String ? current!['reporterName'] as String : null;
        if (current != null &&
            current['kind'] == TransparencyEntry.kindResolved &&
            currentCredit == credit) {
          continue;
        }
        final entry = _entry(data, TransparencyEntry.kindResolved,
            crew: _string(data['assignedCrew']),
            note: _string(data['resolutionNote']),
            reporterName: credit);
        if (entry != null) {
          writes.add((_db.collection(TransparencyEntry.collection).doc(doc.id), {...entry, 'at': data['resolvedAt'] as Timestamp}));
        }
      }
      for (final doc in quarantined.docs) {
        final data = doc.data();
        if (existing.containsKey(doc.id)) continue;
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

  /// Names of the reporters among [uids] who opted in to credit. A profile that cannot be
  /// read simply gets no credit.
  Future<Map<String, String>> _credits(Set<String> uids) async {
    final names = <String, String>{};
    await Future.wait([
      for (final uid in uids.where((u) => u.isNotEmpty))
        _db.collection('users').doc(uid).get().then((snapshot) {
          final name = TransparencyEntry.creditFor(snapshot.data());
          if (name != null) names[uid] = name;
        }, onError: (Object _) {}),
    ]);
    return names;
  }

  static Map<String, Object>? _entry(
    Map<String, dynamic> data,
    String kind, {
    String reason = '',
    String crew = '',
    String note = '',
    String? reporterName,
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
      reporterName: reporterName,
    );
  }

  static String _string(Object? value) => value is String ? value : '';
}
