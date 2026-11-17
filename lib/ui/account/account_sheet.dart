import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/account_linker.dart';
import '../../services/session_service.dart';
import '../../theme/app_theme.dart';

/// Opens the account sheet. Resolves to the upgraded profile, or null if nothing changed.
Future<UserProfile?> showAccountSheet(
  BuildContext context, {
  required UserProfile profile,
  required SessionService session,
}) {
  return showModalBottomSheet<UserProfile>(
    context: context,
    backgroundColor: AppColors.cream,
    elevation: 0,
    shape: const RoundedRectangleBorder(),
    isScrollControlled: true,
    builder: (_) => AccountSheet(profile: profile, session: session),
  );
}

/// Shows the user's level and, for guests, the Google upgrade.
class AccountSheet extends StatefulWidget {
  const AccountSheet({super.key, required this.profile, required this.session});

  final UserProfile profile;
  final SessionService session;

  @override
  State<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<AccountSheet> {
  bool _busy = false;
  String? _error;

  bool get _isGuest => widget.profile.tier == UserProfile.tierCommuterObserver;

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
          children: [
            Text('Level ${widget.profile.tier}', style: textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              widget.profile.tierTitle,
              style: const TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 28, color: AppColors.ink),
            ),
            const SizedBox(height: 12),
            Text(
              _isGuest
                  ? 'You are browsing as a guest and can file 3 reports a day. '
                      'Link a Google account to file 10 a day and vote on hazards near you. '
                      'Your reports stay with you.'
                  : 'Your account is linked. You can vote on hazards within 200 m.',
              style: textTheme.bodyLarge,
            ),
            if (_isGuest) ...[
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _busy ? null : _continueWithGoogle,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: const RoundedRectangleBorder(),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onRedOrange),
                      )
                    : const Text('Continue with Google'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
