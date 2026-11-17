/// Why a user can or cannot vote on a report. The Firestore rules enforce tier,
/// ownership, and one vote per user. The distance check exists only here.
enum VoteEligibility {
  allowed,
  needsUpgrade,
  ownReport,
  locationUnknown,
  tooFar,
}

abstract final class VotePolicy {
  static const double radiusMeters = 200;

  /// Weight of a vote by tier. Must match `voteValues()` in `firestore.rules`.
  static int weightForTier(int tier) {
    if (tier >= 3) return 2;
    if (tier == 2) return 1;
    return 0;
  }

  static VoteEligibility check({
    required int tier,
    required String uid,
    required String reporterUid,
    required double? distanceMeters,
  }) {
    if (weightForTier(tier) == 0) return VoteEligibility.needsUpgrade;
    if (reporterUid == uid) return VoteEligibility.ownReport;
    if (distanceMeters == null) return VoteEligibility.locationUnknown;
    if (distanceMeters > radiusMeters) return VoteEligibility.tooFar;
    return VoteEligibility.allowed;
  }

  /// The message for a blocked vote, or null when voting is allowed.
  static String? explain(VoteEligibility eligibility) => switch (eligibility) {
        VoteEligibility.allowed => null,
        VoteEligibility.needsUpgrade => 'Sign in with Google to vote on hazards.',
        VoteEligibility.ownReport => 'You cannot vote on your own report.',
        VoteEligibility.locationUnknown => 'Turn on location to vote.',
        VoteEligibility.tooFar => 'Voting opens within 200 m of the hazard.',
      };
}
