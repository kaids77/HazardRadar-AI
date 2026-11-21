import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:hazardradarai/models/triage_result.dart';
import 'package:hazardradarai/services/proxy_client.dart';
import 'package:hazardradarai/services/report_enricher.dart';
import 'package:hazardradarai/services/triage_service.dart';

class _Repo implements PendingReportRepository {
  _Repo(this.pending);

  final List<PendingReport> pending;
  final applied = <String, TriageResult>{};

  @override
  Future<List<PendingReport>> pendingFor(String uid, {int limit = 5}) async => pending;

  @override
  Future<void> applyAi(String incidentId, TriageResult result) async => applied[incidentId] = result;
}

ProxyTriageService _proxy(Future<http.Response> Function(http.Request) handler) => ProxyTriageService(
      ProxyClient(baseUrl: Uri.parse('http://127.0.0.1:3000/'), idToken: () async => 't', client: MockClient(handler)),
    );

const _ai = {
  'category': 'Electrical',
  'riskLevel': 'High',
  'aiSummary': 'Sparking wire.',
  'recommendedAction': 'Call the utility.',
};

void main() {
  test('applies the AI result to each pending report', () async {
    final repo = _Repo(const [PendingReport(id: 'a', note: 'wire'), PendingReport(id: 'b', note: 'spark')]);
    final enricher = ReportEnricher(
      repository: repo,
      proxy: _proxy((_) async => http.Response(jsonEncode(_ai), 200)),
    );

    expect(await enricher.enrichPending('uid'), 2);
    expect(repo.applied.keys, ['a', 'b']);
    expect(repo.applied['a']?.riskLevel, 'High');
  });

  test('stops at the first proxy failure and leaves the rest pending', () async {
    var calls = 0;
    final repo = _Repo(const [PendingReport(id: 'a', note: 'wire'), PendingReport(id: 'b', note: 'spark')]);
    final enricher = ReportEnricher(
      repository: repo,
      proxy: _proxy((_) async {
        calls++;
        return http.Response('', 503);
      }),
    );

    expect(await enricher.enrichPending('uid'), 0);
    expect(calls, 1);
    expect(repo.applied, isEmpty);
  });
}
