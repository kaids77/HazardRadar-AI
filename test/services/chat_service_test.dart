import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:hazardradarai/models/chat.dart';
import 'package:hazardradarai/models/incident.dart';
import 'package:hazardradarai/services/chat_service.dart';
import 'package:hazardradarai/services/proxy_client.dart';
import 'package:hazardradarai/ui/chat/chat_controller.dart';

const _here = LatLng(10.3236, 123.9322);

Incident _incident(String id, double lat, {String reporter = 'secret-uid'}) => Incident(
      id: id,
      category: 'Road',
      riskLevel: 'Medium',
      aiSummary: 'Pothole $id.',
      latitude: lat,
      longitude: 123.9322,
      netVotes: 0,
      reporterUid: reporter,
    );

ProxyChatService _service(MockClient client) => ProxyChatService(
      ProxyClient(baseUrl: Uri.parse('http://127.0.0.1:3000/'), idToken: () async => 't', client: client),
    );

void main() {
  group('ChatReply.tryFromJson', () {
    test('keeps known map actions and report actions, drops the rest and duplicates', () {
      final reply = ChatReply.tryFromJson({
        'reply': ' Avoid Lopez Jaena St. ',
        'actions': [
          {'type': 'showOnMap', 'incidentId': 'a'},
          {'type': 'showOnMap', 'incidentId': 'a'},
          {'type': 'showOnMap', 'incidentId': 'made-up'},
          {'type': 'openReport'},
          {'type': 'deleteEverything'},
          'junk',
        ],
      }, {'a'});

      expect(reply?.reply, 'Avoid Lopez Jaena St.');
      expect(reply?.actions, [const ShowOnMap('a'), const OpenReport()]);
    });

    test('rejects a missing or empty reply', () {
      expect(ChatReply.tryFromJson({'reply': '  '}, {}), isNull);
      expect(ChatReply.tryFromJson({'actions': []}, {}), isNull);
      expect(ChatReply.tryFromJson('text', {}), isNull);
    });
  });

  test('nearestIncidents sorts by distance and caps the list', () {
    final list = [_incident('far', 10.40), _incident('near', 10.3237), _incident('mid', 10.33)];
    expect(nearestIncidents(list, _here, limit: 2).map((i) => i.id), ['near', 'mid']);
  });

  group('ProxyChatService', () {
    test('sends only the nearest 20 incidents with whitelisted fields', () async {
      late Map<String, dynamic> sent;
      final service = _service(MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        expect(request.url.path, '/chat');
        return http.Response(jsonEncode({'reply': 'All clear.', 'actions': []}), 200);
      }));
      final many = [for (var i = 0; i < 25; i++) _incident('i$i', 10.3236 + i * 0.001)];

      final reply = await service.ask(' safe? ', incidents: many, around: _here);

      expect(reply.reply, 'All clear.');
      expect(sent['message'], 'safe?');
      final incidents = sent['incidents'] as List;
      expect(incidents, hasLength(20));
      expect((incidents.first as Map).keys.toSet(), {'id', 'category', 'riskLevel', 'aiSummary'});
      expect(jsonEncode(sent).contains('secret-uid'), isFalse);
    });

    test('turns proxy failures and empty replies into ChatUnavailable', () async {
      final down = _service(MockClient((_) async => http.Response('', 503)));
      expect(down.ask('hi', incidents: const [], around: _here), throwsA(isA<ChatUnavailable>()));

      final empty = _service(MockClient((_) async => http.Response(jsonEncode({'reply': ''}), 200)));
      expect(empty.ask('hi', incidents: const [], around: _here), throwsA(isA<ChatUnavailable>()));
    });

    test('rejects empty and oversized questions without calling the proxy', () async {
      var calls = 0;
      final service = _service(MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }));
      expect(service.ask('  ', incidents: const [], around: _here), throwsA(isA<ChatUnavailable>()));
      expect(service.ask('x' * 501, incidents: const [], around: _here), throwsA(isA<ChatUnavailable>()));
      await Future<void>.delayed(Duration.zero);
      expect(calls, 0);
    });
  });

  group('ChatController', () {
    test('adds the question and the answer, and records errors', () async {
      final ok = ChatController(_service(MockClient(
        (_) async => http.Response(jsonEncode({'reply': 'Stay left.', 'actions': []}), 200),
      )));
      await ok.send('route?', incidents: const [], around: _here);
      expect(ok.messages.map((m) => m.text), [ChatController.greeting, 'route?', 'Stay left.']);
      expect(ok.error, isNull);

      final failing = ChatController(_service(MockClient((_) async => http.Response('', 500))));
      await failing.send('route?', incidents: const [], around: _here);
      expect(failing.messages, hasLength(2));
      expect(failing.error, isNotNull);
      expect(failing.waiting, isFalse);
    });
  });
}
