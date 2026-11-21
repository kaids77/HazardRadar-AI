import 'package:latlong2/latlong.dart';

import '../geo/geohash.dart';
import '../geo/philippines.dart';
import '../models/report.dart';
import '../models/triage_result.dart';
import 'auth_service.dart';
import 'report_rejected.dart';
import 'report_repository.dart';
import 'triage_service.dart';

export 'report_rejected.dart';

/// Validates a draft, triages the note, and stores the report.
/// The wizard calls [review] for the AI preview, then [publish].
class ReportService {
  const ReportService({
    required this.auth,
    required this.triage,
    required this.repository,
  });

  final AuthService auth;
  final TriageService triage;
  final ReportRepository repository;

  /// Triages the note for the review step. Never fails for a valid note: the
  /// offline classifier answers when the AI is unreachable.
  Future<TriageResult> review(String note) => triage.classify(_validNote(note));

  /// Stores a reviewed report. [result] is what the user saw on the review step.
  Future<String> publish({
    required String note,
    required LatLng location,
    required CompressedPhoto? photo,
    required TriageResult result,
  }) async {
    final trimmed = _validNote(note);
    if (photo == null) throw const ReportRejected('Take a photo of the hazard.');
    if (!philippinesBounds.contains(location)) {
      throw const ReportRejected('Reports can only be filed inside the Philippines.');
    }

    final uid = await auth.ensureSignedIn();
    return repository.create(
      NewReport(
        reporterUid: uid,
        note: trimmed,
        latitude: location.latitude,
        longitude: location.longitude,
        geohash: encodeGeohash(location.latitude, location.longitude),
        triage: result,
        photo: photo,
      ),
    );
  }

  /// Triage and publish in one step, without a review.
  Future<String> submit({
    required String note,
    required LatLng location,
    required CompressedPhoto? photo,
  }) async {
    final trimmed = _validNote(note);
    if (photo == null) throw const ReportRejected('Take a photo of the hazard.');
    if (!philippinesBounds.contains(location)) {
      throw const ReportRejected('Reports can only be filed inside the Philippines.');
    }
    final result = await triage.classify(trimmed);
    return publish(note: trimmed, location: location, photo: photo, result: result);
  }

  static String _validNote(String note) {
    final trimmed = note.trim();
    if (trimmed.isEmpty) throw const ReportRejected('Describe the hazard in a few words.');
    if (trimmed.length > NewReport.maxNoteLength) {
      throw const ReportRejected('The note is too long. Keep it under 500 characters.');
    }
    return trimmed;
  }
}
