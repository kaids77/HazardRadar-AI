/// A hazard report as shown on the map. Mirrors the `incidents/{id}` fields in firestore.rules.
class Incident {
  const Incident({
    required this.id,
    required this.category,
    required this.riskLevel,
    required this.aiSummary,
    required this.latitude,
    required this.longitude,
    required this.netVotes,
    this.reporterUid = '',
    this.recommendedAction = '',
  });

  final String id;
  final String category;
  final String riskLevel;
  final String aiSummary;
  final double latitude;
  final double longitude;
  final int netVotes;
  final String reporterUid;
  final String recommendedAction;

  /// Three net votes make a report a verified hazard.
  static const int verifiedThreshold = 3;
  bool get isVerified => netVotes >= verifiedThreshold;

  /// Returns null when required fields are missing or the coordinates are out of range.
  /// The map skips those documents instead of crashing.
  static Incident? tryFromFirestore(String id, Map<String, Object?> data) {
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    final category = data['category'];
    final riskLevel = data['riskLevel'];
    final aiSummary = data['aiSummary'];

    if (latitude is! num || longitude is! num) return null;
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) return null;
    if (category is! String || riskLevel is! String || aiSummary is! String) return null;

    final netVotes = data['netVotes'];
    return Incident(
      id: id,
      category: category,
      riskLevel: riskLevel,
      aiSummary: aiSummary,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      netVotes: netVotes is int ? netVotes : 0,
      reporterUid: data['reporterUid'] is String
          ? data['reporterUid'] as String
          : '',
      recommendedAction: data['recommendedAction'] is String
          ? data['recommendedAction'] as String
          : '',
    );
  }
}
