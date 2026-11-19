import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/incident.dart';
import 'dispatch_repository.dart';

/// Estimated Firestore storage used by report photos, against the free 1 GiB.
class StorageEstimate {
  const StorageEstimate({required this.usedBytes, required this.reports, required this.averagePhotoBytes});

  /// Firestore Spark plan stored-data limit.
  static const int limitBytes = 1024 * 1024 * 1024;

  /// Photos are stored as Base64 text, about 4/3 of the JPEG size.
  static const double base64Factor = 4 / 3;

  /// Rough size of the incident document itself, its index entries, and votes.
  static const int perReportOverheadBytes = 3 * 1024;

  /// Used for reports filed before photoBytes existed.
  static const int fallbackPhotoBytes = 100 * 1024;

  final int usedBytes;
  final int reports;
  final int averagePhotoBytes;

  double get fraction => (usedBytes / limitBytes).clamp(0, 1).toDouble();
  int get remainingBytes => (limitBytes - usedBytes).clamp(0, limitBytes);

  int get uploadsRemaining {
    final perReport = (averagePhotoBytes * base64Factor).round() + perReportOverheadBytes;
    return perReport <= 0 ? 0 : remainingBytes ~/ perReport;
  }

  /// [photoBytesSum] covers the [withBytes] reports that have photoBytes; the rest
  /// of [total] are estimated at the average (or [fallbackPhotoBytes]).
  factory StorageEstimate.compute({required int photoBytesSum, required int withBytes, required int total}) {
    final average = withBytes == 0 ? fallbackPhotoBytes : photoBytesSum ~/ withBytes;
    final photos = photoBytesSum + (total - withBytes).clamp(0, total) * average;
    final used = (photos * base64Factor).round() + total * perReportOverheadBytes;
    return StorageEstimate(usedBytes: used, reports: total, averagePhotoBytes: average);
  }
}

/// Quarantine review: staff restore reports, admins purge them for good.
abstract interface class ModerationRepository {
  Stream<List<Incident>> watchQuarantined({int limit = 100});

  /// Puts a quarantined report back on the public map with netVotes reset to 0.
  Future<void> restore(Incident incident);

  /// Deletes the report's votes, its photo, and the report itself. Admins only.
  /// Returns how many documents were deleted.
  Future<int> purge(Incident incident);

  Future<StorageEstimate> storage();
}

class FirestoreModerationRepository implements ModerationRepository {
  FirestoreModerationRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  /// Firestore allows at most 500 writes in one batch.
  static const int batchLimit = 500;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _incidents => _db.collection('incidents');

  @override
  Stream<List<Incident>> watchQuarantined({int limit = 100}) => _incidents
      .where('visibility', isEqualTo: Incident.visibilityQuarantined)
      .limit(limit)
      .snapshots()
      .map((s) => [for (final doc in s.docs) ?Incident.tryFromFirestore(doc.id, doc.data())]);

  @override
  Future<void> restore(Incident incident) => _guard(() async {
        if (!incident.isQuarantined) throw const DispatchFailed('This report is not quarantined.');
        await _incidents.doc(incident.id).update({'visibility': Incident.visibilityPublic, 'netVotes': 0});
      });

  @override
  Future<int> purge(Incident incident) async {
    var deleted = 0;
    await _guard(() async {
      final ref = _incidents.doc(incident.id);
      final votes = await ref.collection('votes').get();
      final refs = [for (final doc in votes.docs) doc.reference, ref.collection('photo').doc('main')];
      for (var start = 0; start < refs.length; start += batchLimit) {
        final batch = _db.batch();
        for (final doc in refs.skip(start).take(batchLimit)) {
          batch.delete(doc);
        }
        await batch.commit();
      }
      // The report goes last, so a failure part-way leaves it in the queue to purge again.
      await ref.delete();
      deleted = refs.length + 1;
    });
    return deleted;
  }

  @override
  Future<StorageEstimate> storage() async {
    final all = await _incidents.count().get();
    final withBytes = await _incidents.where('photoBytes', isGreaterThan: 0).aggregate(sum('photoBytes'), count()).get();
    return StorageEstimate.compute(
      photoBytesSum: (withBytes.getSum('photoBytes') ?? 0).round(),
      withBytes: withBytes.count ?? 0,
      total: all.count ?? 0,
    );
  }

  static Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') throw const DispatchFailed('Not allowed for your role.');
      rethrow;
    }
  }
}
