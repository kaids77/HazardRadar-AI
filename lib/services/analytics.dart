import 'package:cloud_firestore/cloud_firestore.dart';

import '../geo/philippine_day.dart';
import '../models/hazard_category.dart';
import '../models/incident.dart';

/// City performance numbers, computed on the device from loaded reports (no extra reads).
class CityAnalytics {
  const CityAnalytics({
    required this.total,
    required this.activeHigh,
    required this.activeMedium,
    required this.activeLow,
    required this.inProgress,
    required this.resolved,
    required this.resolvedToday,
    required this.quarantined,
    required this.meanTimeToResolve,
    required this.categoryCounts,
    required this.hotspots,
    required this.aiProcessedShare,
  });

  final int total;
  final int activeHigh;
  final int activeMedium;
  final int activeLow;
  final int inProgress;
  final int resolved;
  final int resolvedToday;
  final int quarantined;

  /// Average time from report to resolution, or null with no resolved reports.
  final Duration? meanTimeToResolve;

  /// Every fixed category, in [HazardCategory.all] order, with its count.
  final Map<String, int> categoryCounts;

  /// Geohash cells with the most open reports, highest first.
  final List<({String geohash, int count})> hotspots;

  /// Share of reports classified by the AI rather than the offline fallback (0 to 1).
  final double aiProcessedShare;

  /// Resolved share of reports that are not quarantined (0 to 1).
  double get resolutionRate {
    final counted = total - quarantined;
    return counted <= 0 ? 0 : resolved / counted;
  }

  static CityAnalytics compute(List<Incident> incidents, DateTime now, {int hotspotCount = 5}) {
    final today = philippineDay(now);
    int countWhere(bool Function(Incident) test) => incidents.where(test).length;
    bool open(Incident i) => !i.isQuarantined && i.status == Incident.statusActive;

    final resolvedDurations = [
      for (final i in incidents)
        if (i.status == Incident.statusResolved && i.createdAt != null && i.resolvedAt != null)
          i.resolvedAt!.difference(i.createdAt!),
    ];
    final mttr = resolvedDurations.isEmpty
        ? null
        : Duration(
            microseconds:
                resolvedDurations.fold<int>(0, (total, d) => total + d.inMicroseconds) ~/ resolvedDurations.length,
          );

    final categories = {for (final c in HazardCategory.all) c: 0};
    for (final i in incidents) {
      final key = HazardCategory.normalize(i.category);
      categories[key] = categories[key]! + 1;
    }

    final cells = <String, int>{};
    for (final i in incidents) {
      if (i.isQuarantined || i.status == Incident.statusResolved || i.geohash.length < 6) continue;
      final cell = i.geohash.substring(0, 6);
      cells[cell] = (cells[cell] ?? 0) + 1;
    }
    final hotspots = cells.entries.toList()
      ..sort((a, b) => b.value != a.value ? b.value.compareTo(a.value) : a.key.compareTo(b.key));

    return CityAnalytics(
      total: incidents.length,
      activeHigh: countWhere((i) => open(i) && i.riskLevel == 'High'),
      activeMedium: countWhere((i) => open(i) && i.riskLevel == 'Medium'),
      activeLow: countWhere((i) => open(i) && i.riskLevel == 'Low'),
      inProgress: countWhere((i) => !i.isQuarantined && i.status == Incident.statusInProgress),
      resolved: countWhere((i) => i.status == Incident.statusResolved),
      resolvedToday: countWhere(
        (i) => i.status == Incident.statusResolved && i.resolvedAt != null && philippineDay(i.resolvedAt!) == today,
      ),
      quarantined: countWhere((i) => i.isQuarantined),
      meanTimeToResolve: mttr,
      categoryCounts: categories,
      hotspots: [for (final e in hotspots.take(hotspotCount)) (geohash: e.key, count: e.value)],
      aiProcessedShare: incidents.isEmpty ? 0 : countWhere((i) => i.aiProcessed) / incidents.length,
    );
  }
}

abstract interface class AnalyticsRepository {
  /// The newest reports of every status and visibility, up to [limit]. Staff only.
  Future<List<Incident>> recent({int limit = 500});
}

class FirestoreAnalyticsRepository implements AnalyticsRepository {
  FirestoreAnalyticsRepository({FirebaseFirestore? firestore}) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// A single-field orderBy, so no composite index is needed.
  @override
  Future<List<Incident>> recent({int limit = 500}) async {
    final snapshot = await _db.collection('incidents').orderBy('createdAt', descending: true).limit(limit).get();
    return [for (final doc in snapshot.docs) ?Incident.tryFromFirestore(doc.id, doc.data())];
  }
}

/// "4.2 h", "35 min", or "2.5 days".
String formatDuration(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes} min';
  if (d.inHours < 48) return '${(d.inMinutes / 60).toStringAsFixed(1)} h';
  return '${(d.inHours / 24).toStringAsFixed(1)} days';
}
