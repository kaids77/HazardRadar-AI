import 'hazard_category.dart';

/// Structured output of hazard triage. Matches the proxy `/triage` response and
/// the limits in `firestore.rules` (category from the fixed list, text fields 500 characters).
class TriageResult {
  const TriageResult({
    required this.category,
    required this.riskLevel,
    required this.aiSummary,
    required this.recommendedAction,
    this.aiProcessed = true,
  });

  static const List<String> riskLevels = ['Low', 'Medium', 'High'];
  static const int maxCategoryLength = 40;
  static const int maxTextLength = 500;

  final String category;
  final String riskLevel;
  final String aiSummary;
  final String recommendedAction;

  /// False when the on-device keyword classifier produced this result.
  /// Those reports are re-checked by the AI later.
  final bool aiProcessed;

  /// Returns null unless every field is present, within limits, and the risk level is known.
  /// The category is mapped onto the fixed list. The app does not trust the network.
  static TriageResult? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final category = _text(json['category'], maxCategoryLength);
    final aiSummary = _text(json['aiSummary'], maxTextLength);
    final recommendedAction = _text(json['recommendedAction'], maxTextLength);
    final riskLevel = json['riskLevel'];
    if (category == null || aiSummary == null || recommendedAction == null) return null;
    if (riskLevel is! String || !riskLevels.contains(riskLevel)) return null;
    return TriageResult(
      category: HazardCategory.normalize(category),
      riskLevel: riskLevel,
      aiSummary: aiSummary,
      recommendedAction: recommendedAction,
    );
  }

  static String? _text(Object? value, int maxLength) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) return null;
    return trimmed;
  }
}
