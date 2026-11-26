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
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/report/wizard/report_draft.dart';
import 'package:hazardradarai/ui/report/wizard/report_wizard_screen.dart';

const _cebu = LatLng(10.3236, 123.9322);

// 1x1 transparent PNG, enough for Image.memory to decode.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);

class _Auth implements AuthService {
  @override
  Future<String> ensureSignedIn() async => 'uid-1';
}

class _Repo implements ReportRepository {
  final saved = <NewReport>[];

  @override
  Future<String> create(NewReport report) async {
    saved.add(report);
    return 'id';
  }
}

class _Photos implements PhotoCapture {
  int cameraCalls = 0;

  @override
  Future<CompressedPhoto?> takePhoto() async {
    cameraCalls++;
    return CompressedPhoto(bytes: _png);
  }
}

class _Location implements LocationProvider {
  _Location(this.fix);

  final LocationFix? fix;

  @override
  Future<LatLng> currentOrFallback() async => fix?.position ?? _cebu;

  @override
  Future<LatLng?> current() async => fix?.position;

  @override
  Future<LocationFix?> currentFix() async => fix;

  @override
  Stream<LocationFix> watchFix() => const Stream.empty();
}

Future<_Repo> _open(WidgetTester tester, {LocationFix? fix = const LocationFix(_cebu, accuracyMeters: 4)}) async {
  final repo = _Repo();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: ReportWizardScreen(
        reports: ReportService(auth: _Auth(), triage: const KeywordTriageService(), repository: repo),
        photos: _Photos(),
        location: _Location(fix),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return repo;
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.text('Next'));
  await tester.pump();
  await tester.pump();
}

void main() {
  group('ReportDraft', () {
    test('keeps the pin within 100 m of the GPS fix', () {
      final draft = ReportDraft()..setFix(const LocationFix(_cebu));
      const near = LatLng(10.3240, 123.9322); // about 44 m north
      expect(draft.movePin(near), near);

      final far = draft.movePin(const LatLng(10.3336, 123.9322)); // about 1.1 km north
      expect(const Distance().as(LengthUnit.Meter, _cebu, far), closeTo(100, 1));
      expect(far.latitude, greaterThan(_cebu.latitude));
    });

    test('movePin skips redundant notifications when the pin has not moved', () {
      final draft = ReportDraft()..setFix(const LocationFix(_cebu));
      var notifications = 0;
      draft.addListener(() => notifications++);

      draft.movePin(_cebu);
      expect(notifications, 0);

      const moved = LatLng(10.3240, 123.9322);
      draft.movePin(moved);
      expect(notifications, 1);

      draft.movePin(moved);
      expect(notifications, 1);
    });

    test('each step needs its input before advancing', () {
      final draft = ReportDraft();
      expect(draft.canAdvance, isFalse);
      draft.setFix(const LocationFix(_cebu));
      draft.next();
      expect(draft.step, WizardStep.photo);
      draft.next();
      expect(draft.step, WizardStep.photo);
      draft.setPhoto(CompressedPhoto(bytes: _png));
      draft.next();
      expect(draft.step, WizardStep.notes);
      draft.setNote('   ');
      expect(draft.blocker, isNotNull);
    });

    test('a location outside the Philippines cannot advance', () {
      final draft = ReportDraft()..setFix(const LocationFix(LatLng(1.35, 103.82)));
      expect(draft.blocker, contains('Philippines'));
    });

    test('changing the note clears the AI result', () async {
      final draft = ReportDraft()..setNote('pothole');
      draft.setTriage(await const KeywordTriageService().classify('pothole'));
      draft.setNote('pothole and flood');
      expect(draft.triage, isNull);
    });
  });

  testWidgets('walks through the four steps and publishes after the AI review', (tester) async {
    final repo = await _open(tester);

    expect(find.text('Step 1 of 4: Location'), findsOneWidget);
    expect(find.text('±4 m'), findsOneWidget);
    await _tapNext(tester);

    expect(find.text('Step 2 of 4: Photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
    await _tapNext(tester);
    expect(find.text('Take a photo of the hazard.'), findsOneWidget);
    await tester.tap(find.text('Choose from gallery'));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('KB JPEG'), findsOneWidget);
    await tester.tap(find.byType(Image));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('KB JPEG'), findsOneWidget);
    await _tapNext(tester);

    expect(find.text('Step 3 of 4: Notes'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Malaking butas sa daan');
    await _tapNext(tester);

    expect(find.text('Step 4 of 4: AI review'), findsOneWidget);
    expect(find.text('Pothole'), findsOneWidget);
    expect(find.text('Classified offline'), findsOneWidget);
    expect(repo.saved, isEmpty);

    await tester.tap(find.text('Publish report'));
    await tester.pump();
    await tester.pump();

    expect(repo.saved, hasLength(1));
    expect(repo.saved.single.note, 'Malaking butas sa daan');
    expect(repo.saved.single.triage.category, 'Pothole');
  });

  testWidgets('without GPS the wizard asks for location and never uses the fallback', (tester) async {
    final repo = await _open(tester, fix: null);

    expect(find.text('Turn on location to file a report.'), findsOneWidget);
    expect(find.text('Step 1 of 4: Location'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(find.textContaining('Turn on location'), findsWidgets);
    expect(repo.saved, isEmpty);
  });
}
