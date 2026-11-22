import '../models/user_profile.dart';

/// A moderation hint for staff. The app never applies it by itself; the admin decides.
class ModerationSuggestion {
  const ModerationSuggestion(this.title, this.reason, {this.isAction = false});

  final String title;
  final String reason;

  /// True when the hint asks the admin to consider a change (warn, suspend, ban).
  final bool isAction;
}

/// The moderation guideline (docs/PLAN_MODERATION_SIGNALS.md). [quarantined] are the
/// user's reports hidden right now, [removed] the ones an admin deleted as spam.
/// Restored and resolved reports never count. Each step escalates one level at a time.
ModerationSuggestion suggestModeration({
  required String accountStatus,
  required int quarantined,
  required int removed,
}) {
  final strikes = quarantined + removed;
  final count = strikes == 1 ? '1 report' : '$strikes reports';
  if (accountStatus == UserProfile.accountBanned) {
    return const ModerationSuggestion('Already banned', 'No further action is needed.');
  }
  if (strikes < 2) {
    return ModerationSuggestion(
      'No action',
      strikes == 0 ? 'No quarantined or removed reports.' : 'Only 1 report was quarantined or removed.',
    );
  }
  switch (accountStatus) {
    case UserProfile.accountSuspended:
      return strikes >= 5
          ? ModerationSuggestion('Consider a ban', '$count quarantined or removed, after a suspension.', isAction: true)
          : ModerationSuggestion('Keep the suspension', '$count quarantined or removed. A ban starts at 5.');
    case UserProfile.accountWarned:
      return strikes >= 3
          ? ModerationSuggestion('Suspend for 7 days', '$count quarantined or removed after a warning.', isAction: true)
          : ModerationSuggestion('Keep the warning', '$count quarantined or removed. A suspension starts at 3.');
    default:
      return ModerationSuggestion('Warn', '$count quarantined or removed.', isAction: true);
  }
}
