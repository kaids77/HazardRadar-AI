import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show PolylineLayer;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/models/user_profile.dart';
import 'package:hazardradarai/services/detour_service.dart';
import 'package:hazardradarai/services/incident_repository.dart';
import 'package:hazardradarai/services/location_service.dart';
import 'package:hazardradarai/services/vote_repository.dart';
import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/map/map_filter.dart';
import 'package:hazardradarai/ui/map/map_screen.dart';
import 'package:hazardradarai/ui/map/risk_style.dart';

Incident _i(String id, String category, String risk, {String status = 'ACTIVE'}) => Incident(
      id: id,
      category: category,
      riskLevel: risk,
      aiSummary: 's',
      latitude: 10.3236,
      longitude: 123.9322,
      netVotes: 0,
      status: status,
    );

final _items = [
  _i('abc123', 'Electrical', 'High'),
  _i('def456', 'Pothole', 'Medium'),
  _i('ghi789', 'Pothole', 'High', status: 'IN_PROGRESS'),
];

class _Stream implements IncidentRepository {
  final controller = StreamController<List<Incident>>.broadcast();

  @override
  Stream<List<Incident>> watchActivePublic({int limit = 150}) => controller.stream;

  @override
  Future<Uint8List?> loadPhoto(String incidentId) async => null;
}

class _Votes implements VoteRepository {
  @override
  Future<int> cast({required String incidentId, required String uid, required int value}) async => value;

  @override
  Future<void> flag({required String incidentId, required String uid}) async {}
}

class _Location implements LocationProvider {
  _Location([this.start = fix]);

  static const fix = LocationFix(GeolocatorLocationService.fallbackCenter, accuracyMeters: 6);

  final LocationFix start;
  final moves = StreamController<LocationFix>.broadcast();

  @override
  Future<LatLng> currentOrFallback() async => start.position;

  @override
  Future<LatLng?> current() async => start.position;

  @override
  Future<LocationFix?> currentFix() async => start;

  @override
  Stream<LocationFix> watchFix() => moves.stream;
}

void main() {
  detourTests();
  nearbyTests();

  test('filters by risk and category', () {
    expect(applyMapFilter(_items, MapFilter.all, ''), hasLength(3));
    expect(applyMapFilter(_items, MapFilter.highRisk, '').map((i) => i.id), ['abc123', 'ghi789']);
    expect(applyMapFilter(_items, MapFilter.category('Pothole'), '').map((i) => i.id), ['def456', 'ghi789']);
  });

  test('search matches the HZD reference or the category, ignoring case', () {
    expect(applyMapFilter(_items, MapFilter.all, 'hzd-abc').map((i) => i.id), ['abc123']);
    expect(applyMapFilter(_items, MapFilter.all, 'electr').map((i) => i.id), ['abc123']);
    expect(applyMapFilter(_items, MapFilter.all, 'flood'), isEmpty);
  });

  test('search matches risk level and status words in any case and order', () {
    expect(applyMapFilter(_items, MapFilter.all, 'High Risk').map((i) => i.id), ['abc123', 'ghi789']);
    expect(applyMapFilter(_items, MapFilter.all, 'high').map((i) => i.id), ['abc123', 'ghi789']);
    expect(applyMapFilter(_items, MapFilter.all, 'medium').map((i) => i.id), ['def456']);
    expect(applyMapFilter(_items, MapFilter.all, 'pothole high').map((i) => i.id), ['ghi789']);
    expect(applyMapFilter(_items, MapFilter.all, 'in progress').map((i) => i.id), ['ghi789']);
    expect(applyMapFilter(_items, MapFilter.all, 'low'), isEmpty);
  });

  test('only High reports not seen before raise the banner', () {
    expect(newHighRisk({'abc123'}, _items).map((i) => i.id), ['ghi789']);
    expect(newHighRisk({'abc123', 'ghi789'}, _items), isEmpty);
  });

  test('in-progress pins use the in-progress color', () {
    expect(pinColor(_items[2]), AppColors.inProgress);
    expect(pinColor(_items[0]), AppColors.riskHigh);
  });

  testWidgets('chips show counts, the GPS chip shows accuracy, and a new High report raises a banner',
      (tester) async {
    final repo = _Stream();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MapScreen(
            incidents: repo,
            location: _Location(),
            profile: const UserProfile(uid: 'u', role: 'CITIZEN', tier: 2, accountStatus: 'ACTIVE'),
            votes: _Votes(),
          ),
        ),
      ),
    );
    await tester.pump();
    repo.controller.add(_items.sublist(0, 2));
    await tester.pump();

    expect(find.text('All 2'), findsOneWidget);
    expect(find.text('High risk 1'), findsOneWidget);
    expect(find.text('GPS ±6 m'), findsOneWidget);
    expect(find.text('New high-risk report'), findsNothing);

    repo.controller.add(_items);
    await tester.pump();
    await tester.pump();

    expect(find.text('New high-risk report'), findsOneWidget);
    expect(find.textContaining('HZD-GHI789'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.text('New high-risk report'), findsNothing);
  });
}

class _Detour implements DetourService {
  LatLng? to;

  @override
  Future<DetourRoute> route({required LatLng from, required LatLng to, required List<Incident> hazards}) async {
    this.to = to;
    return DetourRoute(
      path: [from, to],
      distanceMeters: 800,
      durationSeconds: 600,
      clearanceMeters: 120,
      // The shortest way passes a hazard, so the map shows it too, in red.
      direct: DetourRoute(path: [from, to], distanceMeters: 600, durationSeconds: 450, clearanceMeters: 5),
    );
  }
}

void detourTests() {
  testWidgets('Safe route: tap the button, tap a destination, and the route summary appears', (tester) async {
    final detour = _Detour();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MapScreen(
            incidents: _Stream(),
            location: _Location(),
            profile: const UserProfile(uid: 'u', role: 'CITIZEN', tier: 2, accountStatus: 'ACTIVE'),
            votes: _Votes(),
            detour: detour,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byTooltip('Safe walking route'));
    await tester.pump();
    expect(find.text('Tap your destination on the map.'), findsOneWidget);

    await tester.tapAt(const Offset(400, 300));
    // flutter_map waits for the double-tap timeout before reporting a single tap.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(detour.to, isNotNull);
    expect(find.textContaining('stays 120 m from High and Medium hazards'), findsOneWidget);
    // Red risky shortest route underneath, green suggested route on top, and a key for both.
    final lines = tester.widget<PolylineLayer>(find.byType(PolylineLayer)).polylines;
    expect(lines.map((l) => l.color), [routeRiskyColor, routeSafeColor]);
    expect(find.text('Suggested safe route'), findsOneWidget);
    expect(find.text('Passes a hazard'), findsOneWidget);
    await tester.tap(find.text('Clear route'));
    await tester.pump();
    expect(find.textContaining('min walk'), findsNothing);
  });
}

void nearbyTests() {
  testWidgets('Nearby alert: walking within 100 m of a High hazard warns once per session', (tester) async {
    final repo = _Stream();
    // Start about 2.5 km away from the pins.
    final location = _Location(const LocationFix(LatLng(10.3400, 123.9500), accuracyMeters: 6));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: MapScreen(
            incidents: repo,
            location: location,
            profile: const UserProfile(uid: 'u', role: 'CITIZEN', tier: 2, accountStatus: 'ACTIVE'),
            votes: _Votes(),
          ),
        ),
      ),
    );
    await tester.pump();
    repo.controller.add(_items.sublist(0, 2));
    await tester.pump();
    expect(find.text('High-risk hazard nearby'), findsNothing);

    location.moves.add(_Location.fix);
    await tester.pump();
    await tester.pump();
    expect(find.text('High-risk hazard nearby'), findsOneWidget);
    expect(find.text('Electrical about 0 m from you. Tap to open.'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss nearby alert'));
    await tester.pump();
    expect(find.text('High-risk hazard nearby'), findsNothing);

    // Walking away and back does not repeat the alert for the same hazard.
    location.moves.add(const LocationFix(LatLng(10.3400, 123.9500)));
    await tester.pump();
    await tester.pump();
    expect(find.text('GPS on'), findsOneWidget);
    location.moves.add(_Location.fix);
    await tester.pump();
    await tester.pump();
    expect(find.text('GPS ±6 m'), findsOneWidget);
    expect(find.text('High-risk hazard nearby'), findsNothing);
  });
}
