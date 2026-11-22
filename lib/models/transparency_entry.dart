import 'package:cloud_firestore/cloud_firestore.dart';

import 'incident.dart';

/// One public record in `transparency/{incidentId}`: what happened to a report.
/// Holds only safe fields; never the reporter, the note, or the photo.
/// Field names and values must match the transparency rules in firestore.rules.
class TransparencyEntry {
  const TransparencyEntry({
    required this.incidentId,
    required this.category,
    required this.riskLevel,
    required this.kind,
    this.reason = '',
    this.crew = '',
    this.resolutionNote = '',
    this.at,
  });

  static const String collection = 'transparency';

  static const String kindResolved = 'RESOLVED';
  static const String kindQuarantined = 'QUARANTINED';
  static const String kindRestored = 'RESTORED';
  static const String kindPurged = 'PURGED';

  static const String reasonCommunityVotes = 'COMMUNITY_VOTES';
  static const String reasonSentinelFlag = 'SENTINEL_FLAG';

  final String incidentId;
  final String category;
  final String riskLevel;
  final String kind;
  final String reason;
  final String crew;
  final String resolutionNote;
  final DateTime? at;

  String get reference => Incident.referenceFor(incidentId);

  bool get isResolved => kind == kindResolved;

  /// Quarantined, restored, and removed entries all come from moderation, so they share a filter.
  bool get isModeration => !isResolved;

  /// Plain words for the public list and for Radar AI.
  String get kindLabel => switch (kind) {
        kindResolved => 'Resolved by city',
        kindQuarantined => 'Quarantined',
        kindRestored => 'Restored by a moderator',
        kindPurged => 'Removed as spam',
        _ => kind,
      };

  String? get reasonLabel => switch (reason) {
        reasonCommunityVotes => 'Community votes: marked fixed or fake',
        reasonSentinelFlag => 'Flagged as spam or duplicate by a Sentinel',
        _ => null,
      };

  /// Fields for a new entry. [at] is written separately (server time, or resolvedAt).
  static Map<String, Object> fields({
    required String category,
    required String riskLevel,
    required String kind,
    String reason = '',
    String crew = '',
    String resolutionNote = '',
  }) =>
      {
        'category': category,
        'riskLevel': riskLevel,
        'kind': kind,
        'reason': reason,
        'crew': crew,
        'resolutionNote': resolutionNote,
      };

  /// Returns null for documents missing required fields, so one bad entry never breaks the list.
  static TransparencyEntry? tryFromFirestore(String id, Map<String, Object?> data) {
    final category = data['category'];
    final riskLevel = data['riskLevel'];
    final kind = data['kind'];
    if (category is! String || riskLevel is! String || kind is! String) return null;
    final at = data['at'];
    return TransparencyEntry(
      incidentId: id,
      category: category,
      riskLevel: riskLevel,
      kind: kind,
      reason: data['reason'] is String ? data['reason'] as String : '',
      crew: data['crew'] is String ? data['crew'] as String : '',
      resolutionNote: data['resolutionNote'] is String ? data['resolutionNote'] as String : '',
      at: at is Timestamp ? at.toDate() : null,
    );
  }
}
