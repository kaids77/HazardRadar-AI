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

/// True when [incident] matches the search text: its HZD reference or its category.
bool matchesSearch(Incident incident, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return incident.reference.toLowerCase().contains(q) || incident.category.toLowerCase().contains(q);
}

List<Incident> applyMapFilter(List<Incident> incidents, MapFilter filter, String query) =>
    [for (final incident in incidents) if (filter.matches(incident) && matchesSearch(incident, query)) incident];

/// High-risk reports in [current] whose ids were not in [seen]. Used for the
/// "new high-risk report" banner, so the first load never triggers it.
List<Incident> newHighRisk(Set<String> seen, List<Incident> current) =>
    [for (final incident in current) if (incident.riskLevel == 'High' && !seen.contains(incident.id)) incident];
