/// Build-time settings, passed with `--dart-define`. Nothing here is committed.
///
/// flutter run --dart-define=PROXY_URL=http://127.0.0.1:3000/ --dart-define=PROXY_TOKEN=...
///
/// Without both values the app still works and triages reports on the device.
abstract final class AppConfig {
  static const String proxyUrl = String.fromEnvironment('PROXY_URL');
  static const String proxyToken = String.fromEnvironment('PROXY_TOKEN');

  /// The proxy base URL, or null when it is missing or not an absolute http(s) URL.
  static Uri? parseProxyUrl(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasAuthority) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    // Uri.resolve drops the last path segment unless the path ends with a slash.
    return uri.path.endsWith('/') ? uri : uri.replace(path: '${uri.path}/');
  }
}
