import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hazardradarai/config/app_config.dart';
import 'package:hazardradarai/models/triage_result.dart';
import 'package:hazardradarai/services/proxy_client.dart';
import 'package:hazardradarai/services/triage_service.dart';

const _good = {
  'category': 'Electrical',
  'riskLevel': 'High',
  'aiSummary': 'Sparking wire.',
  'recommendedAction': 'Call the utility.',
};

ProxyTriageService _proxy(MockClient client) => ProxyTriageService(
      ProxyClient(
        baseUrl: Uri.parse('http://127.0.0.1:3000/'),
        token: 'test-token',
        client: client,
      ),
    );

void main() {
  group('TriageResult.tryFromJson', () {
    test('accepts a valid object', () {
      expect(TriageResult.tryFromJson(_good)?.riskLevel, 'High');
    });

    test('rejects unknown risk levels, missing and oversized fields', () {
      expect(TriageResult.tryFromJson({..._good, 'riskLevel': 'Critical'}), isNull);
      expect(TriageResult.tryFromJson({..._good}..remove('aiSummary')), isNull);
      expect(TriageResult.tryFromJson({..._good, 'category': 'x' * 41}), isNull);
      expect(TriageResult.tryFromJson('nope'), isNull);
    });
  });

  group('ProxyTriageService', () {
    test('posts the note with the token header and parses the result', () async {
      late http.Request seen;
      final service = _proxy(MockClient((request) async {
        seen = request;
        return http.Response(jsonEncode(_good), 200);
      }));

      final result = await service.tryClassify('sparking wire');

      expect(seen.url.toString(), 'http://127.0.0.1:3000/triage');
      expect(seen.headers['x-proxy-token'], 'test-token');
      expect(jsonDecode(seen.body), {'note': 'sparking wire'});
      expect(result?.category, 'Electrical');
    });

    test('returns null on non-200, bad JSON, and network errors', () async {
      expect(await _proxy(MockClient((_) async => http.Response('{}', 401))).tryClassify('x'), isNull);
      expect(await _proxy(MockClient((_) async => http.Response('not json', 200))).tryClassify('x'), isNull);
      expect(await _proxy(MockClient((_) async => throw http.ClientException('down'))).tryClassify('x'), isNull);
    });

    test('returns null when the request times out', () async {
      final service = ProxyTriageService(
        ProxyClient(
          baseUrl: Uri.parse('http://127.0.0.1:3000/'),
          token: 't',
          timeout: const Duration(milliseconds: 20),
          client: MockClient((_) => Future.delayed(const Duration(seconds: 1), () => http.Response('{}', 200))),
        ),
      );
      expect(await service.tryClassify('x'), isNull);
    });
  });

  group('FallbackTriageService', () {
    test('uses the proxy result when it succeeds', () async {
      final service = FallbackTriageService(
        proxy: _proxy(MockClient((_) async => http.Response(jsonEncode(_good), 200))),
      );
      expect((await service.classify('anything')).aiSummary, 'Sparking wire.');
    });

    test('falls back to keywords when the proxy fails or is not configured', () async {
      final failing = FallbackTriageService(
        proxy: _proxy(MockClient((_) async => http.Response('', 500))),
      );
      expect((await failing.classify('Big pothole near the gate')).category, 'Road');
      expect((await const FallbackTriageService().classify('live wire sparking')).riskLevel, 'High');
      expect((await const FallbackTriageService().classify('something odd')).category, 'Other');
    });
  });

  group('AppConfig.parseProxyUrl', () {
    test('adds a trailing slash and rejects bad values', () {
      expect(AppConfig.parseProxyUrl('http://127.0.0.1:3000')?.toString(), 'http://127.0.0.1:3000/');
      expect(AppConfig.parseProxyUrl(''), isNull);
      expect(AppConfig.parseProxyUrl('ftp://host/'), isNull);
      expect(AppConfig.parseProxyUrl('not a url'), isNull);
    });
  });
}
