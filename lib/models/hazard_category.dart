/// The fixed hazard categories. Must match `CATEGORIES` in proxy/src/triage.js
/// and `categories()` in firestore.rules.
abstract final class HazardCategory {
  static const String pothole = 'Pothole';
  static const String electrical = 'Electrical';
  static const String flooding = 'Flooding';
  static const String obstruction = 'Obstruction';
  static const String lighting = 'Lighting';
  static const String other = 'Other';

  static const List<String> all = [pothole, electrical, flooding, obstruction, lighting, other];

  /// Maps any label onto the fixed list, case-insensitively. Unknown labels become [other].
  static String normalize(String label) {
    final lower = label.trim().toLowerCase();
    for (final category in all) {
      if (category.toLowerCase() == lower) return category;
    }
    return other;
  }
}
