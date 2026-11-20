import '../../models/hazard_category.dart';
import '../../models/incident.dart';

/// A map filter chip: everything, High risk only, or one category.
class MapFilter {
  const MapFilter._(this.key, this.label);

  static const all = MapFilter._('all', 'All');
  static const highRisk = MapFilter._('high', 'High risk');
  static MapFilter category(String category) => MapFilter._(category, category);

  /// All chips in display order.
  static final List<MapFilter> chips = [
    all,
    highRisk,
    for (final category in HazardCategory.all) MapFilter.category(category),
  ];

  final String key;
  final String label;

  bool matches(Incident incident) => switch (key) {
        'all' => true,
        'high' => incident.riskLevel == 'High',
        _ => incident.category == key,
      };

  @override
  bool operator ==(Object other) => other is MapFilter && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// True when every word of the search text starts a word of the report: its HZD
/// reference, category, risk level ("high", "high risk"), status ("active",
/// "in progress"), "verified", or its AI summary. Case does not matter, and word order
/// does not matter, so "pothole high" and "high risk pothole" both work.
bool matchesSearch(Incident incident, String query) {
  final wanted = _words(query);
  if (wanted.isEmpty) return true;
  final words = _searchWords(incident);
  return wanted.every((w) => words.any((word) => word.startsWith(w)));
}

final RegExp _separators = RegExp(r'[^a-z0-9]+');

List<String> _words(String text) => [for (final w in text.toLowerCase().split(_separators)) if (w.isNotEmpty) w];

List<String> _searchWords(Incident incident) => _words([
      incident.reference,
      incident.category,
      '${incident.riskLevel} risk',
      incident.status == Incident.statusInProgress ? 'in progress' : 'active',
      if (incident.isVerified) 'verified',
      incident.aiSummary,
    ].join(' '));

List<Incident> applyMapFilter(List<Incident> incidents, MapFilter filter, String query) =>
    [for (final incident in incidents) if (filter.matches(incident) && matchesSearch(incident, query)) incident];

/// High-risk reports in [current] whose ids were not in [seen]. Used for the
/// "new high-risk report" banner, so the first load never triggers it.
List<Incident> newHighRisk(Set<String> seen, List<Incident> current) =>
    [for (final incident in current) if (incident.riskLevel == 'High' && !seen.contains(incident.id)) incident];
