import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/account_linker.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';
import '../common/feedback.dart';

/// Why the upgrade prompt opened. Changes only the first line of text.
enum UpgradeReason { manual, vote, reportLimit }

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
    shape: const RoundedRectangleBorder(),
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

  List<Widget> _linked(TextTheme textTheme) => [
        Text('Level ${widget.profile.tier}', style: textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(widget.profile.tierTitle, style: _title),
        const SizedBox(height: 12),
        Text('Your account is linked. You can vote on hazards within 200 m.', style: textTheme.bodyLarge),
      ];

  List<Widget> _guest(TextTheme textTheme) => [
        Text('Level 1 · ${widget.profile.tierTitle}', style: textTheme.labelLarge),
        const SizedBox(height: 4),
        Text('Become a Civic Scout', style: _title),
        const SizedBox(height: 12),
        Text(_reasonText, style: textTheme.bodyLarge),
        const SizedBox(height: 12),
        for (final benefit in _benefits)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 7, right: 10), color: context.palette.ink),
                Expanded(child: Text(benefit, style: textTheme.bodyMedium)),
              ],
            ),
          ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _busy ? null : _continueWithGoogle,
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const RoundedRectangleBorder()),
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onRedOrange),
                )
              : const Text('Continue with Google'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            foregroundColor: context.palette.ink,
            minimumSize: const Size.fromHeight(44),
            shape: const RoundedRectangleBorder(),
          ),
          child: const Text('Continue as guest'),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          FeedbackMessage.error(_error!),
        ],
      ];

  static const _title = TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 28);
}
