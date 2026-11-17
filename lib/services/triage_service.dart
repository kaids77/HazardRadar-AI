import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/triage_result.dart';

/// Turns a citizen's raw note into a category, risk level, and summary.
abstract interface class TriageService {
  /// Never throws for a non-empty note. Implementations that can fail must fall back.
  Future<TriageResult> classify(String note);
}

/// Calls the local proxy, which holds the Groq key. The app never sees that key.
class ProxyTriageService {
  ProxyTriageService({
    required Uri baseUrl,
    required String token,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  })  : _baseUrl = baseUrl,
        _token = token,
        _client = client ?? http.Client();

  final Uri _baseUrl;
  final String _token;
  final http.Client _client;
  final Duration timeout;

  /// Returns null on any failure: network error, timeout, non-200, or a malformed body.
  Future<TriageResult?> tryClassify(String note) async {
    try {
      final response = await _client
          .post(
            _baseUrl.resolve('triage'),
            headers: {'content-type': 'application/json', 'x-proxy-token': _token},
            body: jsonEncode({'note': note}),
          )
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      return TriageResult.tryFromJson(jsonDecode(utf8.decode(response.bodyBytes)));
    } on Object {
      return null;
    }
  }
}

/// On-device classifier used when the proxy is unavailable, so a report never fails.
class KeywordTriageService implements TriageService {
  const KeywordTriageService();

  static const _rules = <_Rule>[
    _Rule('Electrical', 'High', ['wire', 'spark', 'electric', 'live wire', 'transformer', 'pole', 'cable'],
        'Possible electrical hazard reported.', 'Keep clear and alert the electric utility.'),
    _Rule('Flooding', 'Medium', ['flood', 'baha', 'water', 'drain', 'clogged'],
        'Flooding or blocked drainage reported.', 'Avoid the area and report to the local drainage office.'),
    _Rule('Road', 'Medium', ['pothole', 'crater', 'hole', 'crack', 'sinkhole', 'road', 'butas'],
        'Road surface damage reported.', 'Slow down, avoid the damaged lane, and notify public works.'),
    _Rule('Obstruction', 'Low', ['fallen', 'tree', 'blocked', 'obstruct', 'debris', 'garbage'],
        'Obstruction reported on the path.', 'Take an alternate route until it is cleared.'),
  ];

  @override
  Future<TriageResult> classify(String note) async {
    final text = note.toLowerCase();
    for (final rule in _rules) {
      if (rule.keywords.any(text.contains)) {
        return TriageResult(
          category: rule.category,
          riskLevel: rule.riskLevel,
          aiSummary: rule.summary,
          recommendedAction: rule.action,
        );
      }
    }
    return const TriageResult(
      category: 'Other',
      riskLevel: 'Low',
      aiSummary: 'Hazard reported by a commuter.',
      recommendedAction: 'A reviewer will check this report.',
    );
  }
}

class _Rule {
  const _Rule(this.category, this.riskLevel, this.keywords, this.summary, this.action);

  final String category;
  final String riskLevel;
  final List<String> keywords;
  final String summary;
  final String action;
}

/// Tries the proxy first, then the offline classifier. [proxy] is null when
/// the app was built without a proxy URL, in which case only the fallback runs.
class FallbackTriageService implements TriageService {
  const FallbackTriageService({this.proxy, this.fallback = const KeywordTriageService()});

  final ProxyTriageService? proxy;
  final TriageService fallback;

  @override
  Future<TriageResult> classify(String note) async {
    final fromProxy = await proxy?.tryClassify(note);
    return fromProxy ?? await fallback.classify(note);
  }
}
