import '../geo/philippine_day.dart';
import '../models/user_profile.dart';

enum ReportBlock { none, guestLimit, scoutLimit, banned, suspended }

class ReportAllowance {
  const ReportAllowance({required this.block, required this.usedToday, this.limit});

  final ReportBlock block;
  final int usedToday;

  /// Null means unlimited.
  final int? limit;

  bool get allowed => block == ReportBlock.none;
  int? get remaining => limit == null ? null : (limit! - usedToday).clamp(0, limit!);
}

/// Client-side copy of the daily limit in firestore.rules (dailyLimit and reportCounterOk).
/// The rules are the real check; this gives the user a clear message before the camera opens.
abstract final class ReportLimitPolicy {
  static int? limitForTier(int tier) => switch (tier) {
        1 => 3,
        2 => 10,
        _ => null,
      };

  /// Today's count. A count from an earlier Philippine day no longer applies.
  static int usedToday(UserProfile profile, DateTime now) {
    final day = profile.reportDay;
    if (day == null || !day.isAtSameMomentAs(philippineDay(now))) return 0;
    return profile.reportCount;
  }

  static ReportAllowance check(UserProfile profile, DateTime now) {
    final used = usedToday(profile, now);
    if (profile.accountStatus == UserProfile.accountBanned) {
      return ReportAllowance(block: ReportBlock.banned, usedToday: used);
    }
    if (profile.isBlockedAt(now)) {
      return ReportAllowance(block: ReportBlock.suspended, usedToday: used);
    }
    final limit = profile.rateLimitOverride ? null : limitForTier(profile.tier);
    if (limit != null && used >= limit) {
      final block = profile.tier == UserProfile.tierCommuterObserver ? ReportBlock.guestLimit : ReportBlock.scoutLimit;
      return ReportAllowance(block: block, usedToday: used, limit: limit);
    }
    return ReportAllowance(block: ReportBlock.none, usedToday: used, limit: limit);
  }

  /// The message for a blocked report, or null when reporting is allowed.
  static String? explain(ReportAllowance allowance) => switch (allowance.block) {
        ReportBlock.none => null,
        ReportBlock.guestLimit =>
          'Guests can file 3 reports a day. Sign in with Google to file up to 10.',
        ReportBlock.scoutLimit =>
          'You reached today\'s limit of ${allowance.limit} reports. It resets at midnight.',
        ReportBlock.banned => 'This account can no longer file reports.',
        ReportBlock.suspended => 'This account is suspended and cannot file reports right now.',
      };
}
