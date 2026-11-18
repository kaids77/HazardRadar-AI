import 'dart:convert';
import 'dart:typed_data';

import 'triage_result.dart';

/// A compressed camera photo ready to be stored with a report.
class CompressedPhoto {
  const CompressedPhoto({required this.bytes, this.mimeType = 'image/jpeg'});

  /// Compressed size limit. 150 KB keeps the Base64 text far below the
  /// 900,000 character cap in `firestore.rules` and the 1 MiB document limit.
  static const int maxBytes = 150 * 1024;

  final Uint8List bytes;
  final String mimeType;
}

/// Everything needed to write one report. Built by `ReportService`, written by a `ReportRepository`.
class NewReport {
  const NewReport({
    required this.reporterUid,
    required this.note,
    required this.latitude,
    required this.longitude,
    required this.geohash,
    required this.triage,
    required this.photo,
  });

  static const int maxNoteLength = 500;

  final String reporterUid;
  final String note;
  final double latitude;
  final double longitude;
  final String geohash;
  final TriageResult triage;
  final CompressedPhoto photo;

  /// Fields of `incidents/{id}`, without `createdAt`. The key set must equal the
  /// allow-list in `firestore.rules`, or the write is denied.
  Map<String, Object> incidentFields() => {
        'reporterUid': reporterUid,
        'category': triage.category,
        'riskLevel': triage.riskLevel,
        'aiSummary': triage.aiSummary,
        'recommendedAction': triage.recommendedAction,
        'note': note,
        'latitude': latitude,
        'longitude': longitude,
        'geohash': geohash,
        'status': 'ACTIVE',
        'visibility': 'PUBLIC',
        'netVotes': 0,
        'aiProcessed': triage.aiProcessed,
        'photoBytes': photo.bytes.length,
      };

  /// Fields of `incidents/{id}/photo/main`, without `createdAt`.
  Map<String, Object> photoFields() => {
        'reporterUid': reporterUid,
        'mimeType': photo.mimeType,
        'imageBase64': base64Encode(photo.bytes),
      };
}
