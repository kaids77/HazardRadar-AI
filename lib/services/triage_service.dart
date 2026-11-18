import '../models/hazard_category.dart';
import '../models/triage_result.dart';
import 'proxy_client.dart';

/// Turns a citizen's raw note into a category, risk level, and summary.
abstract interface class TriageService {
  /// Never throws for a non-empty note. Implementations that can fail must fall back.
  Future<TriageResult> classify(String note);
}

/// Calls the local proxy, which holds the Groq key. The app never sees that key.
class ProxyTriageService {
  const ProxyTriageService(this._proxy);

  final ProxyClient _proxy;

  /// Returns null on any failure: network error, timeout, non-200, or a malformed body.
  Future<TriageResult?> tryClassify(String note) async {
    try {
      return TriageResult.tryFromJson(await _proxy.postJson('triage', {'note': note}));
    } on ProxyException {
      return null;
    }
  }
}

/// On-device classifier used when the proxy is unavailable, so a report never fails.
/// Keywords cover English, Tagalog, and Cebuano. They match whole words only, so
/// "baha" (flood) does not match "bahay" (house). Rules are checked in order, so the
/// higher-risk categories come first.
class KeywordTriageService implements TriageService {
  const KeywordTriageService();

  static final _rules = <_Rule>[
    _Rule(HazardCategory.electrical, 'High', const [
      'wire', 'wires', 'live wire', 'spark', 'sparks', 'sparking', 'electric', 'electrical',
      'electrocution', 'transformer', 'cable', 'cables', 'kuryente', 'kable', 'koryente',
      'nag-spark', 'nagspark', 'poste',
    ], 'Possible electrical hazard reported.', 'Keep clear and alert the electric utility.'),
    _Rule(HazardCategory.flooding, 'Medium', const [
      'flood', 'flooded', 'flooding', 'baha', 'binaha', 'bahain', 'nagbaha', 'drain', 'drainage',
      'clogged', 'barado', 'nakabara', 'kanal', 'canal', 'tubig', 'water',
    ], 'Flooding or blocked drainage reported.', 'Avoid the area and report to the local drainage office.'),
    _Rule(HazardCategory.lighting, 'Low', const [
      'streetlight', 'streetlights', 'street light', 'street lights', 'lamp', 'lamppost', 'dark',
      'ilaw', 'walang ilaw', 'patay ang ilaw', 'patay na ilaw', 'suga', 'walay suga', 'ngitngit', 'madilim',
    ], 'Broken or missing street lighting reported.', 'Use a lit route at night and notify the city electrician.'),
    _Rule(HazardCategory.pothole, 'Medium', const [
      'pothole', 'potholes', 'crater', 'sinkhole', 'hole', 'crack', 'cracked', 'butas', 'lubak',
      'lungag', 'buslot', 'guba', 'sira ang daan',
    ], 'Road surface damage reported.', 'Slow down, avoid the damaged lane, and notify public works.'),
    _Rule(HazardCategory.obstruction, 'Low', const [
      'fallen', 'tree', 'blocked', 'obstruction', 'obstructed', 'debris', 'garbage', 'rocks',
      'landslide', 'natumba', 'nahulog', 'kahoy', 'puno', 'basura', 'sagbot', 'nakaharang', 'harang',
    ], 'Obstruction reported on the path.', 'Take an alternate route until it is cleared.'),
  ];

  @override
  Future<TriageResult> classify(String note) async {
    final text = note.toLowerCase();
    for (final rule in _rules) {
      if (rule.matches(text)) {
        return TriageResult(
          category: rule.category,
          riskLevel: rule.riskLevel,
          aiSummary: rule.summary,
          recommendedAction: rule.action,
          aiProcessed: false,
        );
      }
    }
    return const TriageResult(
      category: HazardCategory.other,
      riskLevel: 'Low',
      aiSummary: 'Hazard reported by a commuter.',
      recommendedAction: 'A reviewer will check this report.',
      aiProcessed: false,
    );
  }
}

class _Rule {
  _Rule(this.category, this.riskLevel, List<String> keywords, this.summary, this.action)
      : _pattern = RegExp(
          '(^|[^a-z0-9])(${keywords.map(RegExp.escape).join('|')})(?=[^a-z0-9]|\$)',
        );

  final String category;
  final String riskLevel;
  final String summary;
  final String action;
  final RegExp _pattern;

  bool matches(String lowerText) => _pattern.hasMatch(lowerText);
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
