import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/staff_auth.dart';
import '../../theme/app_theme.dart';
import '../common/feedback.dart';

/// Settings section for city staff.
///
/// - Guests see the email and password form (for city-issued email accounts, or a
///   Google admin who set a staff password). Google sign-in lives in the Account
///   section, not here.
/// - Google accounts see their name and email, "Check staff access", and, for staff,
///   "Set staff password" so the email form also works with their Google email.
/// - Email staff accounts see who is signed in and Sign out.
class StaffSignInSection extends StatefulWidget {
  const StaffSignInSection({
    super.key,
    required this.profile,
    required this.isEmailSession,
    required this.onSignIn,
    required this.onSignOut,
    this.googleEmail,
    this.hasPassword = false,
    this.onCheckAccess,
    this.onSetPassword,
  });

  final UserProfile profile;
  final bool isEmailSession;

  /// Set when the account is linked to Google.
  final String? googleEmail;

  /// True when the account can also sign in with email and password.
  final bool hasPassword;

  /// Reloads the profile. Resolves to the fresh copy, or null when it could not load.
  final Future<UserProfile?> Function()? onCheckAccess;

  /// Resolves to the signed-in profile. Throws [StaffSignInFailed].
  final Future<UserProfile> Function(String email, String password) onSignIn;

  /// Adds or changes the staff password. Throws [StaffSignInFailed]. Null hides the button.
  final Future<void> Function(String password)? onSetPassword;

  final Future<void> Function() onSignOut;

  @override
  State<StaffSignInSection> createState() => _StaffSignInSectionState();
}

class _StaffSignInSectionState extends State<StaffSignInSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  ({String text, FeedbackTone tone})? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _say(String text, FeedbackTone tone) => setState(() => _message = (text: text, tone: tone));

  ButtonStyle get _outline => OutlinedButton.styleFrom(
        foregroundColor: context.palette.ink,
        side: BorderSide(color: context.palette.ink.withValues(alpha: 0.45), width: 1.2),
        shape: const RoundedRectangleBorder(borderRadius: AppTheme.radiusMd),
      );

  /// The user's Google name, then their email, for messages.
  String get _who {
    final name = widget.profile.displayName;
    if (name != null && name.isNotEmpty) return name;
    final email = widget.googleEmail;
    return email == null || email.isEmpty ? 'this account' : email;
  }

  Future<void> _checkAccess() async {
    final check = widget.onCheckAccess;
    if (check == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final profile = await check();
    if (!mounted) return;
    setState(() => _busy = false);
    if (profile == null) {
      _say('Could not load your account. Check your connection and try again.', FeedbackTone.error);
    } else if (profile.isStaff) {
      _say('Staff access is on. Open the Dispatch tab.', FeedbackTone.success);
    } else {
      _say('No staff role on this account yet. Ask an admin to give $_who the ADMIN or DISPATCHER role.',
          FeedbackTone.error);
    }
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final profile = await widget.onSignIn(_email.text, _password.text);
      _password.clear();
      if (mounted && !profile.isStaff) {
        _say('Signed in, but this account has no staff role yet. Ask an admin.', FeedbackTone.error);
      }
    } on StaffSignInFailed catch (failure) {
      if (mounted) _say(failure.message, FeedbackTone.error);
    } catch (_) {
      if (mounted) _say('Sign-in failed. Try again.', FeedbackTone.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setPassword() async {
    final save = widget.onSetPassword;
    if (save == null) return;
    final saved = await showDialog<bool>(context: context, builder: (_) => _PasswordDialog(onSave: save));
    if (saved == true && mounted) {
      _say(
        'Staff password saved. You can now also sign in with ${widget.googleEmail} and this password.',
        FeedbackTone.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final googleEmail = widget.googleEmail;
    final message = _message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (googleEmail != null)
          ..._googleBlock(googleEmail)
        else if (widget.isEmailSession)
          ..._emailBlock()
        else
          ..._guestBlock(),
        if (message != null) ...[
          const SizedBox(height: 8),
          FeedbackMessage(message.text, tone: message.tone),
        ],
      ],
    );
  }

  List<Widget> _googleBlock(String email) {
    final textTheme = Theme.of(context).textTheme;
    final name = widget.profile.displayName;
    final isStaff = widget.profile.isStaff;
    return [
      const Text('City staff', style: _heading),
      const SizedBox(height: 4),
      Container(
        decoration: BoxDecoration(
          color: context.palette.sage,
          borderRadius: AppTheme.radiusMd,
          border: Border.all(color: context.palette.ink.withValues(alpha: 0.22)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (name != null && name.isNotEmpty) Text(name, style: textTheme.titleSmall),
            if (email.isNotEmpty) Text(email, style: textTheme.bodySmall),
            Text('Google account · ${widget.profile.tierTitle}', style: textTheme.bodySmall),
          ],
        ),
      ),
      const SizedBox(height: 8),
      if (!isStaff)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Staff access comes from the role on your profile, so no password is needed.',
            style: textTheme.bodySmall,
          ),
        ),
      OutlinedButton(
        onPressed: _busy ? null : _checkAccess,
        style: _outline,
        child: Text(_busy ? 'Checking...' : 'Check staff access'),
      ),
      if (isStaff && widget.onSetPassword != null) ...[
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : _setPassword,
          style: _outline,
          child: Text(widget.hasPassword ? 'Change staff password' : 'Set staff password'),
        ),
        const SizedBox(height: 4),
        Text(
          widget.hasPassword
              ? 'You can sign in with Google or with $email and your staff password.'
              : 'Optional: set a password to also sign in with $email in the staff form.',
          style: textTheme.bodySmall,
        ),
      ],
      const SizedBox(height: 8),
      OutlinedButton(onPressed: _busy ? null : widget.onSignOut, style: _outline, child: const Text('Sign out')),
      const SizedBox(height: 4),
      Text(
        'Your points and reports stay on this Google account. After signing out you browse as a guest.',
        style: textTheme.bodySmall,
      ),
    ];
  }

  List<Widget> _emailBlock() => [
        const Text('Staff account', style: _heading),
        const SizedBox(height: 8),
        Text('Signed in as ${widget.profile.tierTitle}.', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: _busy ? null : widget.onSignOut, style: _outline, child: const Text('Sign out')),
      ];

  List<Widget> _guestBlock() {
    final textTheme = Theme.of(context).textTheme;
    return [
      const Text('City staff', style: _heading),
      const SizedBox(height: 4),
      Text(
        'Sign in with the email account the city gave you. A Google admin can use their Google email '
        'here after setting a staff password in Settings. This replaces the guest session on this phone.',
        style: textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Staff email', border: OutlineInputBorder(borderRadius: AppTheme.radiusMd)),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: _password,
        obscureText: true,
        autofillHints: const [AutofillHints.password],
        decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder(borderRadius: AppTheme.radiusMd)),
        onSubmitted: (_) => _signIn(),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: _busy ? null : _signIn,
        style: _outline.copyWith(minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48))),
        child: Text(_busy ? 'Signing in...' : 'Sign in as staff'),
      ),
    ];
  }

  static const _heading = TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 22);
}

/// Asks for a new staff password twice. Pops `true` once [onSave] succeeds.
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.onSave});

  final Future<void> Function(String password) onSave;

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.length < FirebaseStaffAuth.minPasswordLength) {
      setState(() => _error = 'Use at least ${FirebaseStaffAuth.minPasswordLength} characters.');
      return;
    }
    if (_password.text != _confirm.text) {
      setState(() => _error = 'The two passwords do not match.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave(_password.text);
      if (mounted) Navigator.of(context).pop(true);
    } on StaffSignInFailed catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save the password. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return AlertDialog(
      title: const Text('Staff password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'New password', border: OutlineInputBorder(borderRadius: AppTheme.radiusMd)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirm,
            obscureText: true,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: 'Repeat password', border: OutlineInputBorder(borderRadius: AppTheme.radiusMd)),
          ),
          if (error != null) ...[const SizedBox(height: 8), FeedbackMessage.error(error)],
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        TextButton(onPressed: _busy ? null : _save, child: Text(_busy ? 'Saving...' : 'Save')),
      ],
    );
  }
}
