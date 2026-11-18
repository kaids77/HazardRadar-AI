import 'package:cloud_firestore/cloud_firestore.dart';

/// A hazard report. Mirrors the `incidents/{id}` fields in firestore.rules.
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
    this.note = '',
    this.status = statusActive,
    this.visibility = visibilityPublic,
    this.aiProcessed = true,
    this.createdAt,
    this.reporterTier = 1,
    this.photoBytes,
    this.assignedCrew,
    this.resolutionNote,
    this.inProgressAt,
    this.resolvedAt,
  });

  static const String statusActive = 'ACTIVE';
  static const String statusInProgress = 'IN_PROGRESS';
  static const String statusResolved = 'RESOLVED';
  static const String visibilityPublic = 'PUBLIC';
  static const String visibilityQuarantined = 'QUARANTINED';

  final String id;
  final String category;
  final String riskLevel;
  final String aiSummary;
  final double latitude;
  final double longitude;
  final int netVotes;
  final String reporterUid;
  final String recommendedAction;
  final String note;
  final String status;
  final String visibility;

  /// False when the offline keyword classifier was used. Missing in older documents counts as true.
  final bool aiProcessed;
  final DateTime? createdAt;

  /// The reporter's level when the report was filed, shown as a trust badge.
  final int reporterTier;

  /// Size of the stored photo. Null on reports filed before this field existed.
  final int? photoBytes;
  final String? assignedCrew;
  final String? resolutionNote;
  final DateTime? inProgressAt;
  final DateTime? resolvedAt;

  bool get isQuarantined => visibility == visibilityQuarantined;

  /// Three net votes make a report a verified hazard.
  static const int verifiedThreshold = 3;
  bool get isVerified => netVotes >= verifiedThreshold;

  /// Short human reference, for example HZD-4F9A2C. Derived from the document id, no counter.
  String get reference => 'HZD-${id.length >= 6 ? id.substring(0, 6) : id}'.toUpperCase();

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
    final createdAt = data['createdAt'];
    return Incident(
      id: id,
      category: category,
      riskLevel: riskLevel,
      aiSummary: aiSummary,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      netVotes: netVotes is int ? netVotes : 0,
      reporterUid: _string(data['reporterUid']),
      recommendedAction: _string(data['recommendedAction']),
      note: _string(data['note']),
      status: _string(data['status'], statusActive),
      visibility: _string(data['visibility'], visibilityPublic),
      aiProcessed: data['aiProcessed'] is bool ? data['aiProcessed'] as bool : true,
      createdAt: _date(createdAt),
      reporterTier: data['reporterTier'] is int ? data['reporterTier'] as int : 1,
      photoBytes: data['photoBytes'] is int ? data['photoBytes'] as int : null,
      assignedCrew: data['assignedCrew'] is String ? data['assignedCrew'] as String : null,
      resolutionNote: data['resolutionNote'] is String ? data['resolutionNote'] as String : null,
      inProgressAt: _date(data['inProgressAt']),
      resolvedAt: _date(data['resolvedAt']),
    );
  }

  static DateTime? _date(Object? value) => value is Timestamp ? value.toDate() : null;

  static String _string(Object? value, [String fallback = '']) => value is String ? value : fallback;
}
