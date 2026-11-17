import 'package:latlong2/latlong.dart';

import '../geo/geohash.dart';
import '../geo/philippines.dart';
import '../models/report.dart';
import 'auth_service.dart';
import 'report_repository.dart';
import 'triage_service.dart';

/// A report the app refuses to send. The message is safe to show to the user.
class ReportRejected implements Exception {
  const ReportRejected(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Validates a draft, triages the note, and stores the report.
class ReportService {
  const ReportService({
    required this.auth,
    required this.triage,
    required this.repository,
  });

  final AuthService auth;
  final TriageService triage;
  final ReportRepository repository;

  Future<String> submit({
    required String note,
    required LatLng location,
    required CompressedPhoto? photo,
  }) async {
    final trimmed = note.trim();
    if (trimmed.isEmpty) throw const ReportRejected('Describe the hazard in a few words.');
    if (trimmed.length > NewReport.maxNoteLength) {
      throw const ReportRejected('The note is too long. Keep it under 500 characters.');
    }
    if (photo == null) throw const ReportRejected('Take a photo of the hazard.');
    if (!philippinesBounds.contains(location)) {
      throw const ReportRejected('Reports can only be filed inside the Philippines.');
    }

    final uid = await auth.ensureSignedIn();
    final result = await triage.classify(trimmed);

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
}
