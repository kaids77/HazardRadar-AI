import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Any failure talking to the proxy: no signed-in user, network, timeout, non-200,
/// or a body that is not JSON. Details stay in [reason] for logs and tests and are
/// never shown to users.
class ProxyException implements Exception {
  const ProxyException(this.reason);

  final String reason;

  @override
  String toString() => 'ProxyException: $reason';
}

/// Returns the current user's Firebase ID token, or null when nobody is signed in.
typedef IdTokenProvider = Future<String?> Function();

/// Shared HTTP client for the local proxy that holds the Groq key.
/// Each request carries the signed-in user's Firebase ID token.
class ProxyClient {
  ProxyClient({
    required Uri baseUrl,
    required IdTokenProvider idToken,
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  })  : _baseUrl = baseUrl,
        _idToken = idToken,
        _client = client ?? http.Client();

  final Uri _baseUrl;
  final IdTokenProvider _idToken;
  final http.Client _client;
  final Duration timeout;

  /// POSTs [body] as JSON to [path] and returns the decoded JSON response.
  Future<Object?> postJson(String path, Map<String, Object?> body) async {
    final String? token;
    try {
      token = await _idToken();
    } on Object catch (error) {
      throw ProxyException('id token: ${error.runtimeType}');
    }
    if (token == null || token.isEmpty) throw const ProxyException('not signed in');

    final http.Response response;
    try {
      response = await _client
          .post(
            _baseUrl.resolve(path),
            headers: {'content-type': 'application/json', 'authorization': 'Bearer $token'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const ProxyException('timeout');
    } on Object catch (error) {
      throw ProxyException('network: ${error.runtimeType}');
    }

    if (response.statusCode != 200) throw ProxyException('status ${response.statusCode}');
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ProxyException('body is not JSON');
    }
  }
}
