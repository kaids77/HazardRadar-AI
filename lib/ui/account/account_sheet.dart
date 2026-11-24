import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/account_linker.dart';
import '../../services/level_policy.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../common/feedback.dart';

/// Why the upgrade prompt opened. Changes only the first line of text.
enum UpgradeReason { manual, vote, reportLimit }

/// What each level allows, in plain words. Matches the limits and rules in
/// report_limit_policy.dart, vote_policy.dart, and firestore.rules.
List<String> levelPrivileges(UserProfile profile) {
  final override = profile.rateLimitOverride && profile.tier <= UserProfile.tierCivicScout;
  return [
    ...switch (profile.tier) {
      1 => const [
          'Browse the hazard map and ask Radar AI.',
          'File up to 3 reports a day.',
          'Sign in with Google to vote on hazards.',
        ],
      2 => const [
          'File up to 10 reports a day.',
          'Vote Still here or Fixed or fake on hazards within 200 m. Your vote counts 1.',
        ],
      3 => const [
          'File as many reports as you need.',
          'Vote on hazards within 200 m. Your vote counts 2.',
          'Flag spam or duplicate reports. They leave the map until a moderator checks them.',
          'Pick a focus badge in My Reports.',
        ],
      _ => [
          'File as many reports as you need. Your votes count 2.',
          'Dispatch tab: start work, assign crews, resolve tickets, and correct AI ratings.',
          'Review quarantined reports and restore them to the map.',
          if (profile.isAdmin) ...[
            'Manage users: role, account status, and the emergency daily-limit override.',
            'See city analytics and permanently purge spam.',
          ],
        ],
    },
    if (override) 'An admin turned off your daily report limit.',
  ];
}

/// Opens the account sheet. For guests it is the Google upgrade prompt.
/// Resolves to the upgraded profile, or null if nothing changed.
Future<UserProfile?> showAccountSheet(
  BuildContext context, {
  required UserProfile profile,
  required SessionService session,
  UpgradeReason reason = UpgradeReason.manual,
}) {
  return showModalBottomSheet<UserProfile>(
    context: context,
    backgroundColor: context.palette.paper,
    elevation: 0,
    shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusSheet),
    isScrollControlled: true,
    builder: (_) => AccountSheet(profile: profile, session: session, reason: reason),
  );
}

/// Shows the user's level and, for guests, the Google upgrade with its benefits.
class AccountSheet extends StatefulWidget {
  const AccountSheet({
    super.key,
    required this.profile,
    required this.session,
    this.reason = UpgradeReason.manual,
  });

  final UserProfile profile;
  final SessionService session;
  final UpgradeReason reason;

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  bool _busy = false;
  String? _error;

  bool get _isGuest => widget.profile.tier == UserProfile.tierCommuterObserver;

  static const _benefits = [
    'Vote on hazards within 200 m of you: Still here or Fixed or fake.',
    'File up to 10 reports a day instead of 3.',
    'Earn trust points toward Neighborhood Sentinel at 250.',
    'Your reports and points stay with you.',
  ];

  String get _reasonText => switch (widget.reason) {
        UpgradeReason.vote => 'Voting needs a linked Google account. It keeps the map free of spam votes.',
        UpgradeReason.reportLimit => 'Guests can file 3 reports a day, and you reached that today.',
        UpgradeReason.manual => 'You are browsing as a guest.',
      };

  Future<void> _continueWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final upgraded = await widget.session.upgradeWithGoogle();
      if (!mounted) return;
      if (upgraded != null) Navigator.of(context).pop(upgraded);
    } on LinkFailed catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (error) {
      // Debug builds show the real cause, such as permission-denied. Release builds do not.
      const message = 'Could not upgrade your account. Try again.';
      if (mounted) setState(() => _error = kDebugMode ? '$message\n$error' : message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _isGuest ? _guest(textTheme) : _linked(textTheme),
        ),
      ),
    );
  }

  List<Widget> _linked(TextTheme textTheme) {
    final profile = widget.profile;
    final name = profile.displayName?.trim();
    final progress = LevelPolicy.progress(profile);
    final target = progress.target;
    return [
      if (name != null && name.isNotEmpty) ...[
        Text(name, style: textTheme.titleMedium),
        const SizedBox(height: 2),
      ],
      Text('Level ${profile.tier}', style: textTheme.labelLarge),
      const SizedBox(height: 4),
      Text(profile.tierTitle, style: _title),
      const SizedBox(height: 16),
      Row(
        children: [
          _Stat(label: 'Trust points', value: '${profile.ctp}'),
          _Stat(label: 'Reports', value: '${profile.reportsTotal}'),
          _Stat(label: 'Resolved', value: '${profile.reportsResolved}'),
          _Stat(label: 'Accuracy', value: '${(profile.accuracy * 100).round()}%'),
        ],
      ),
      const SizedBox(height: 16),
      if (target != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 8,
            child: LinearProgressIndicator(
              value: progress.fraction,
              backgroundColor: context.palette.sage,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text('${profile.ctp} / $target points to ${progress.nextTitle}', style: textTheme.bodyMedium),
        if (progress.hint != null) Text(progress.hint!, style: textTheme.bodySmall),
      ] else
        Text(
          profile.isStaff ? 'City staff level. Set by an admin.' : 'Highest citizen level.',
          style: textTheme.bodyMedium,
        ),
      const SizedBox(height: 16),
      Text('What you can do', style: textTheme.titleMedium),
      const SizedBox(height: 8),
      for (final line in levelPrivileges(profile)) _bullet(line, textTheme),
      const SizedBox(height: 8),
      Text('You earn 10 points for each report, and 10 more when the city resolves it.', style: textTheme.bodySmall),
    ];
  }

  Widget _bullet(String text, TextTheme textTheme) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(top: 7, right: 10),
              decoration: BoxDecoration(
                color: context.palette.ink,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Expanded(child: Text(text, style: textTheme.bodyMedium)),
          ],
        ),
      );

  List<Widget> _guest(TextTheme textTheme) => [
        Text('Level 1 · ${widget.profile.tierTitle}', style: textTheme.labelLarge),
        const SizedBox(height: 4),
        Text('Become a Civic Scout', style: _title),
        const SizedBox(height: 12),
        Text(_reasonText, style: textTheme.bodyLarge),
        const SizedBox(height: 12),
        for (final benefit in _benefits) _bullet(benefit, textTheme),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _continueWithGoogle,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
          ),
          child: _busy
              ? SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : const Text('Continue with Google'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: context.palette.ink,
            minimumSize: const Size.fromHeight(44),
            shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
          ),
          child: const Text('Continue as guest'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          FeedbackMessage.error(_error!, onDismiss: () => setState(() => _error = null)),
        ],
      ];

  static const _title = TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 28);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        children: [
          Text(value, style: textTheme.titleMedium),
          Text(label, textAlign: TextAlign.center, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}
