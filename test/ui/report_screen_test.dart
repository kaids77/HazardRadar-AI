import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:hazardradarai/models/report.dart';
import 'package:hazardradarai/services/auth_service.dart';
import 'package:hazardradarai/services/location_service.dart';
import 'package:hazardradarai/services/photo_service.dart';
import 'package:hazardradarai/services/report_repository.dart';
import 'package:hazardradarai/services/report_service.dart';
import 'package:hazardradarai/services/triage_service.dart';
import 'package:hazardradarai/ui/report/report_screen.dart';

class _Auth implements AuthService {
  @override
  Future<String> ensureSignedIn() async => 'uid-1';
}

class _Repo implements ReportRepository {
  int created = 0;

  @override
  Future<String> create(NewReport report) async {
    created++;
    return 'id';
  }
}

class _Photos implements PhotoCapture {
  @override
  Future<CompressedPhoto?> takePhoto() async => CompressedPhoto(
        // 1x1 transparent PNG, enough for Image.memory to decode.
        bytes: Uint8List.fromList(const [
          0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
          0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
          0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
          0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
          0x42, 0x60, 0x82,
        ]),
      );
}

class _Location implements LocationProvider {
  _Location(this.position);

  final LatLng? position;

  @override
  Future<LatLng> currentOrFallback() async => position ?? GeolocatorLocationService.fallbackCenter;

  @override
  Future<LatLng?> current() async => position;
}

Widget _screen(_Repo repo, LatLng? position) => MaterialApp(
      home: ReportScreen(
        reports: ReportService(
          auth: _Auth(),
          triage: const KeywordTriageService(),
          repository: repo,
        ),
        photos: _Photos(),
        location: _Location(position),
      ),
    );

void main() {
  testWidgets('asks for a photo before sending', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(_screen(repo, GeolocatorLocationService.fallbackCenter));

    await tester.enterText(find.byType(TextField), 'pothole');
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(find.text('Take a photo of the hazard.'), findsOneWidget);
    expect(repo.created, 0);
  });

  testWidgets('tells the user to enable location instead of using the fallback', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(_screen(repo, null));

    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'pothole');
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(find.text('Turn on location to file a report.'), findsOneWidget);
    expect(repo.created, 0);
  });

  testWidgets('sends the report and closes when everything is valid', (tester) async {
    final repo = _Repo();
    await tester.pumpWidget(_screen(repo, GeolocatorLocationService.fallbackCenter));

    await tester.tap(find.text('Take a photo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'big pothole');
    await tester.tap(find.text('Send report'));
    await tester.pumpAndSettle();

    expect(repo.created, 1);
  });
}
