import '../models/user_profile.dart';

/// Progress toward the next level, for the My Reports card.
class LevelProgress {
  const LevelProgress({required this.ctp, this.target, this.nextTitle, this.hint});

  final int ctp;

  /// CTP needed for the next level, or null at the top citizen level.
  final int? target;
  final String? nextTitle;
  final String? hint;

  double get fraction => target == null ? 1 : (ctp / target!).clamp(0, 1).toDouble();
}

/// Level thresholds. Must match the self-upgrade rules in firestore.rules.
abstract final class LevelPolicy {
  static const int scoutCtp = 50;
  static const int sentinelCtp = 250;
  static const double sentinelAccuracy = 0.85;
  static const int ctpPerReport = 10;
  static const int ctpPerResolved = 10;

  static LevelProgress progress(UserProfile profile) {
    return switch (profile.tier) {
      1 => LevelProgress(
          ctp: profile.ctp,
          target: scoutCtp,
          nextTitle: 'Civic Scout',
          hint: 'Earn $scoutCtp points, or sign in with Google now.',
        ),
      2 => LevelProgress(
          ctp: profile.ctp,
          target: sentinelCtp,
          nextTitle: 'Neighborhood Sentinel',
          hint: 'Needs $sentinelCtp points and at least 85% of your reports resolved.',
        ),
      _ => LevelProgress(ctp: profile.ctp),
    };
  }
}
