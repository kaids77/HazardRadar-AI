import 'package:cloud_firestore/cloud_firestore.dart';

import '../geo/philippine_day.dart';
import '../models/report.dart';
import 'level_policy.dart';
import 'report_rejected.dart';

abstract interface class ReportRepository {
  /// Stores the report, its photo, and the reporter's daily counter together.
  /// Returns the new incident id. Either everything is written or nothing is.
  /// Throws [ReportRejected] when the server refuses (daily limit or blocked account).
  Future<String> create(NewReport report);
}

/// The reporter's daily counter after one more report on [today].
/// Mirrors reportCounterOk() in firestore.rules.
({DateTime day, int count}) nextReportCounter(Map<String, Object?>? profile, DateTime today) {
  final day = profile?['reportDay'];
  final count = profile?['reportCount'];
  final sameDay = day is Timestamp && day.toDate().isAtSameMomentAs(today);
  return (day: today, count: (sameDay && count is int ? count : 0) + 1);
}

class FirestoreReportRepository implements ReportRepository {
  FirestoreReportRepository({FirebaseFirestore? firestore, DateTime Function()? clock})
      : _db = firestore ?? FirebaseFirestore.instance,
        _clock = clock ?? DateTime.now;

  final FirebaseFirestore _db;
  final DateTime Function() _clock;

  @override
  Future<String> create(NewReport report) async {
    final incident = _db.collection('incidents').doc();
    final photo = incident.collection('photo').doc('main');
    final user = _db.collection('users').doc(report.reporterUid);

    try {
      // A transaction reads the current counter and writes all three documents at once,
      // so the rules can check the photo owner and the counter with getAfter.
      await _db.runTransaction((transaction) async {
        final profile = (await transaction.get(user)).data();
        final counter = nextReportCounter(profile, philippineDay(_clock()));
        final tier = profile?['tier'];
        transaction
          ..set(incident, {
            ...report.incidentFields(),
            // The rules require the reporter's current tier, shown as a trust badge on the report.
            'reporterTier': tier is int ? tier : 1,
            'createdAt': FieldValue.serverTimestamp(),
          })
          ..set(photo, {...report.photoFields(), 'createdAt': FieldValue.serverTimestamp()})
          ..update(user, {
            'reportDay': Timestamp.fromDate(counter.day),
            'reportCount': counter.count,
            'lastReportId': incident.id,
            // Every published report earns +10 Civic Trust Points (checked by the rules).
            'ctp': _int(profile?['ctp']) + LevelPolicy.ctpPerReport,
            'reportsTotal': _int(profile?['reportsTotal']) + 1,
          });
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const ReportRejected(
          'The report was refused. You may have reached today\'s limit, or your account is restricted.',
        );
      }
      rethrow;
    }
    return incident.id;
  }

  static int _int(Object? value) => value is int ? value : 0;
}
