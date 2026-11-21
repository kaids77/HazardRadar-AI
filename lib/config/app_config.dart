/// Build-time settings. Nothing here is committed.
///
/// Copy dart_defines.example.json to dart_defines.json (gitignored), fill it in, then run:
/// flutter run --dart-define-from-file=dart_defines.json
///
/// Without PROXY_URL the app still works and triages reports on the device.
/// The proxy authenticates each request with the user's Firebase ID token.
abstract final class AppConfig {
  static const String proxyUrl = String.fromEnvironment('PROXY_URL');

  /// Optional web OAuth client id for Google sign-in on Android. When empty,
  /// Android reads default_web_client_id generated from google-services.json.
  static const String _googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');
  static String? get googleServerClientId =>
      _googleServerClientId.isEmpty ? null : _googleServerClientId;

  /// The proxy base URL, or null when it is missing or not an absolute http(s) URL.
  static Uri? parseProxyUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    // Uri.resolve drops the last path segment unless the path ends with a slash.
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }
}
