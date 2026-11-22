import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:hazardradarai/models/chat.dart';
import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/services/chat_service.dart';
import 'package:hazardradarai/services/detour_service.dart';
import 'package:hazardradarai/services/proxy_client.dart';
import 'package:hazardradarai/ui/chat/chat_controller.dart';

const _from = LatLng(10.3236, 123.9322);
const _to = LatLng(10.33, 123.9322);

Incident _h(String id, String risk) => Incident(
      id: id,
      category: 'Electrical',
      riskLevel: risk,
      aiSummary: 's',
      latitude: 10.3268,
      longitude: 123.9322,
      netVotes: 0,
    );

final _good = {
  'path': [
    [10.3236, 123.9322],
    [10.3268, 123.935],
    [10.33, 123.9322],
  ],
  'distanceMeters': 1330,
  'durationSeconds': 1064,
  'clearanceMeters': 140,
  'alternatives': 2,
};

ProxyDetourService _service(Future<http.Response> Function(http.Request) handler) => ProxyDetourService(
      ProxyClient(baseUrl: Uri.parse('http://127.0.0.1:3000/'), idToken: () async => 't', client: MockClient(handler)),
    );

void main() {
  test('parses a route and writes a plain summary', () {
    final route = DetourRoute.tryFromJson(_good)!;
    expect(route.path, hasLength(3));
    expect(route.summary, '1.3 km · 18 min walk · stays 140 m from High and Medium hazards');
    expect(
      DetourRoute.tryFromJson({..._good, 'clearanceMeters': null})!.summary,
      endsWith('no High or Medium hazards nearby'),
    );
  });

  test('rejects malformed paths and points outside the Philippines', () {
    expect(DetourRoute.tryFromJson({..._good, 'path': [[10.3, 123.9]]}), isNull);
    expect(DetourRoute.tryFromJson({..._good, 'path': [[1.35, 103.8], [10.3, 123.9]]}), isNull);
    expect(DetourRoute.tryFromJson({..._good, 'path': 'nope'}), isNull);
  });

  test('a risky shortest route comes back for the red line; a safe route stays green', () {
    final route = DetourRoute.tryFromJson({
      ..._good,
      'direct': {..._good, 'distanceMeters': 900, 'clearanceMeters': 8},
    })!;
    expect(route.isSafe, isTrue);
    expect(route.riskyDirect?.distanceMeters, 900);

    // A broken extra route is dropped.
    expect(DetourRoute.tryFromJson({..._good, 'direct': {'path': 'x'}})!.direct, isNull);

    // Chosen route is safer than direct (10 m vs 3 m) → riskyDirect is returned for red line.
    final stuck = DetourRoute.tryFromJson({
      ..._good,
      'clearanceMeters': 10,
      'direct': {..._good, 'clearanceMeters': 3},
    })!;
    expect(stuck.isSafe, isFalse);
    expect(stuck.isSaferThanDirect, isTrue);
    expect(stuck.riskyDirect?.clearanceMeters, 3);
  });

  test('sends only High and Medium hazards and maps failures to a message', () async {
    late Map<String, dynamic> sent;
    final service = _service((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      expect(request.url.path, '/detour');
      return http.Response(jsonEncode(_good), 200);
    });

    final route = await service.route(from: _from, to: _to, hazards: [_h('a', 'High'), _h('b', 'Low')]);

    expect(route.distanceMeters, 1330);
    expect(sent['from'], {'lat': _from.latitude, 'lon': _from.longitude});
    expect((sent['hazards'] as List), hasLength(1));

    final down = _service((_) async => http.Response('{}', 502));
    expect(down.route(from: _from, to: _to, hazards: const []), throwsA(isA<DetourUnavailable>()));
  });

  test('Safe detour mode adds a local "pick a destination" action to each reply', () async {
    final chat = ChatController(_Echo())..setMode(ChatMode.detour);
    await chat.send('Safest way to the market?', incidents: const [], around: _from);
    expect(chat.messages.last.actions, contains(const PlanDetour()));
  });
}

class _Echo implements ChatService {
  @override
  Future<ChatReply> ask(
    String message, {
    required List<Incident> incidents,
    required LatLng around,
    List<ChatTurn> history = const [],
    ChatMode? mode,
    ReportStatusSummary? status,
  }) async =>
      const ChatReply(reply: 'Avoid the wire on Lopez Jaena.', actions: []);
}
