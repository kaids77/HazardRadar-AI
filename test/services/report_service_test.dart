import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:hazardradarai/models/report.dart';
import 'package:hazardradarai/models/triage_result.dart';
import 'package:hazardradarai/services/auth_service.dart';
import 'package:hazardradarai/services/photo_service.dart';
import 'package:hazardradarai/services/report_repository.dart';
import 'package:hazardradarai/services/report_service.dart';
import 'package:hazardradarai/services/triage_service.dart';

class _Auth implements AuthService {
  @override
  Future<String> ensureSignedIn() async => 'uid-1';
}

class _Triage implements TriageService {
  @override
  Future<TriageResult> classify(String note) async => const TriageResult(
        category: 'Road',
        riskLevel: 'Medium',
        aiSummary: 'Pothole.',
        recommendedAction: 'Avoid.',
      );
}

class _Repo implements ReportRepository {
  NewReport? saved;

  @override
  Future<String> create(NewReport report) async {
    saved = report;
    return 'incident-1';
  }
}

final _photo = CompressedPhoto(bytes: Uint8List.fromList([1, 2, 3]));
const _cebu = LatLng(10.3236, 123.9322);

void main() {
  late _Repo repo;
  late ReportService service;

  setUp(() {
    repo = _Repo();
    service = ReportService(auth: _Auth(), triage: _Triage(), repository: repo);
  });

  test('stores a valid report with the signed-in uid and a geohash', () async {
    final id = await service.submit(note: '  pothole  ', location: _cebu, photo: _photo);

    expect(id, 'incident-1');
    expect(repo.saved?.reporterUid, 'uid-1');
    expect(repo.saved?.note, 'pothole');
    expect(repo.saved?.geohash, hasLength(6));
  });

  test('rejects empty and oversized notes, missing photo, and locations outside the Philippines', () async {
    expect(service.submit(note: '   ', location: _cebu, photo: _photo), throwsA(isA<ReportRejected>()));
    expect(service.submit(note: 'x' * 501, location: _cebu, photo: _photo), throwsA(isA<ReportRejected>()));
    expect(service.submit(note: 'ok', location: _cebu, photo: null), throwsA(isA<ReportRejected>()));
    expect(
      service.submit(note: 'ok', location: const LatLng(1.35, 103.82), photo: _photo),
      throwsA(isA<ReportRejected>()),
    );
    expect(repo.saved, isNull);
  });

  test('incident fields use exactly the keys the Firestore rules allow', () async {
    await service.submit(note: 'pothole', location: _cebu, photo: _photo);
    final report = repo.saved!;

    expect(report.incidentFields().keys.toSet(), {
      'reporterUid', 'category', 'riskLevel', 'aiSummary', 'recommendedAction',
      'note', 'latitude', 'longitude', 'geohash', 'status', 'visibility', 'netVotes',
    });
    expect(report.incidentFields()['status'], 'ACTIVE');
    expect(report.incidentFields()['visibility'], 'PUBLIC');
    expect(report.incidentFields()['netVotes'], 0);
    expect(report.photoFields().keys.toSet(), {'reporterUid', 'mimeType', 'imageBase64'});
  });

  group('compressToLimit', () {
    test('returns the first result within the limit', () async {
      final tried = <int>[];
      final bytes = await compressToLimit(
        (quality) async {
          tried.add(quality);
          return Uint8List(quality > 60 ? 200 : 50);
        },
        maxBytes: 100,
      );
      expect(bytes, hasLength(50));
      expect(tried, [80, 65, 50]);
    });

    test('throws when no quality is small enough', () {
      expect(
        compressToLimit((_) async => Uint8List(500), maxBytes: 100),
        throwsA(isA<PhotoTooLargeException>()),
      );
    });
  });
}
