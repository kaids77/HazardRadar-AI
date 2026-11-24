import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/hazard_category.dart';
import '../models/incident.dart';
import '../models/transparency_entry.dart';
import 'level_policy.dart';

/// Thrown when a staff action is refused or invalid. The message is safe to show.
class DispatchFailed implements Exception {
  const DispatchFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Staff (Level 4+) actions on the city queue. Every write matches isStaffUpdate()
/// and isResolveCredit() in firestore.rules.
abstract interface class DispatchRepository {
  /// Open reports (ACTIVE and IN_PROGRESS), any visibility. Staff can read all of them.
  Stream<List<Incident>> watchQueue({int limit = 300});

  /// Totals that are not in the open queue.
  Future<({int resolved, int quarantined})> closedCounts();

  /// ACTIVE -> IN_PROGRESS, optionally assigning a crew.
  Future<void> startWork(Incident incident, {String? crew});

  /// IN_PROGRESS -> RESOLVED with a note, crediting the reporter +10 CTP in the same write.
  Future<void> resolve(Incident incident, {required String note, required String staffUid});

  Future<void> setCrew(Incident incident, String crew);

  /// Replaces the AI category and risk level.
  Future<void> overrideTriage(Incident incident, {required String category, required String riskLevel});
}

abstract final class DispatchPolicy {
  static const int maxNoteLength = 300;
  static const int maxCrewLength = 60;
  static const List<String> riskLevels = ['High', 'Medium', 'Low'];

  /// High first, then Medium, then Low; oldest first within a level.
  static List<Incident> sortQueue(Iterable<Incident> incidents) {
    int rank(Incident i) => switch (i.riskLevel) { 'High' => 0, 'Medium' => 1, 'Low' => 2, _ => 3 };
    final far = DateTime.utc(9999);
    return incidents.toList()
      ..sort((a, b) {
        final byRisk = rank(a).compareTo(rank(b));
        return byRisk != 0 ? byRisk : (a.createdAt ?? far).compareTo(b.createdAt ?? far);
      });
  }

  /// The only status a ticket can move to next, or null when resolved.
  static String? nextStatus(String status) => switch (status) {
        Incident.statusActive => Incident.statusInProgress,
        Incident.statusInProgress => Incident.statusResolved,
        _ => null,
      };

  static String validNote(String note) {
    final trimmed = note.trim();
    if (trimmed.isEmpty) throw const DispatchFailed('Write a short resolution note.');
    if (trimmed.length > maxNoteLength) {
      throw const DispatchFailed('Keep the note under $maxNoteLength characters.');
    }
    return trimmed;
  }

  static String validCrew(String crew) {
    final trimmed = crew.trim();
    if (trimmed.length > maxCrewLength) throw const DispatchFailed('Keep the crew name under 60 characters.');
    return trimmed;
  }
}

class FirestoreDispatchRepository implements DispatchRepository {
  FirestoreDispatchRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _incidents => _db.collection('incidents');

  /// One whereIn filter and no orderBy, so no composite index is needed. Sorted in the app.
  @override
  Stream<List<Incident>> watchQueue({int limit = 300}) =>
      Stream<List<Incident>>.multi((controller) {
        final sub = _incidents
            .where('status', whereIn: const [Incident.statusActive, Incident.statusInProgress])
            .limit(limit)
            .snapshots()
            .map((snapshot) => [for (final doc in snapshot.docs) ?Incident.tryFromFirestore(doc.id, doc.data())])
            .listen(
              controller.add,
              onError: controller.addError,
              onDone: controller.close,
            );
        controller.onCancel = sub.cancel;
      });

  @override
  Future<({int resolved, int quarantined})> closedCounts() async {
    final resolved = await _incidents.where('status', isEqualTo: Incident.statusResolved).count().get();
    final quarantined =
        await _incidents.where('visibility', isEqualTo: Incident.visibilityQuarantined).count().get();
    return (resolved: resolved.count ?? 0, quarantined: quarantined.count ?? 0);
  }

  @override
  Future<void> startWork(Incident incident, {String? crew}) => _guard(() {
        if (incident.status != Incident.statusActive) throw const DispatchFailed('This report is not active.');
        final name = crew == null ? '' : DispatchPolicy.validCrew(crew);
        return _incidents.doc(incident.id).update({
          'status': Incident.statusInProgress,
          'inProgressAt': FieldValue.serverTimestamp(),
          if (name.isNotEmpty) 'assignedCrew': name,
        });
      });

  @override
  Future<void> resolve(Incident incident, {required String note, required String staffUid}) => _guard(() {
        if (incident.status != Incident.statusInProgress) {
          throw const DispatchFailed('Start work on the report before resolving it.');
        }
        final text = DispatchPolicy.validNote(note);
        final reporter = _db.collection('users').doc(incident.reporterUid);
        final ref = _incidents.doc(incident.id);
        return _db.runTransaction((transaction) async {
          final data = (await transaction.get(reporter)).data();
          if (data == null) throw const DispatchFailed('The reporter\'s profile no longer exists.');
          // Fresh copy, so the public log entry copies the current category, risk, and crew.
          final current = (await transaction.get(ref)).data() ?? const <String, dynamic>{};
          transaction
            ..update(ref, {
              'status': Incident.statusResolved,
              'resolvedAt': FieldValue.serverTimestamp(),
              'resolvedBy': staffUid,
              'resolutionNote': text,
            })
            ..update(reporter, {
              'ctp': _int(data['ctp']) + LevelPolicy.ctpPerResolved,
              'reportsResolved': _int(data['reportsResolved']) + 1,
              'lastResolvedId': incident.id,
            })
            ..set(_db.collection(TransparencyEntry.collection).doc(incident.id), {
              ...TransparencyEntry.fields(
                category: current['category'] is String ? current['category'] as String : incident.category,
                riskLevel: current['riskLevel'] is String ? current['riskLevel'] as String : incident.riskLevel,
                kind: TransparencyEntry.kindResolved,
                crew: current['assignedCrew'] is String ? current['assignedCrew'] as String : '',
                resolutionNote: text,
                // Only when the reporter turned on "Show my name on my resolved reports".
                reporterName: TransparencyEntry.creditFor(data),
              ),
              // Same server time as resolvedAt, which the rules compare.
              'at': FieldValue.serverTimestamp(),
            });
        });
      });

  @override
  Future<void> setCrew(Incident incident, String crew) =>
      _guard(() => _incidents.doc(incident.id).update({'assignedCrew': DispatchPolicy.validCrew(crew)}));

  @override
  Future<void> overrideTriage(Incident incident, {required String category, required String riskLevel}) =>
      _guard(() {
        if (!HazardCategory.all.contains(category) || !DispatchPolicy.riskLevels.contains(riskLevel)) {
          throw const DispatchFailed('Pick a category and a risk level from the list.');
        }
        return _incidents.doc(incident.id).update({'category': category, 'riskLevel': riskLevel});
      });

  static int _int(Object? value) => value is int ? value : 0;

  /// Turns a rules refusal into a readable message.
  static Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw const DispatchFailed('Not allowed. Your staff role may have changed.');
      }
      rethrow;
    }
  }
}
