import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/staff_auth.dart';
import '../../theme/app_theme.dart';

/// Settings section for city staff.
///
/// Email accounts sign in with a password. Google-linked accounts already have a
/// session, so staff access comes only from the role on their profile; this section
/// shows the Google name and email and a button to reload the role.
class StaffSignInSection extends StatefulWidget {
  const StaffSignInSection({
    super.key,
    required this.profile,
    required this.isEmailSession,
    required this.onSignIn,
    required this.onSignOut,
    this.googleEmail,
    this.onCheckAccess,
  });

  final UserProfile profile;
  final bool isEmailSession;

  /// Set when the account is linked to Google.
  final String? googleEmail;

  /// Reloads the profile. Resolves to the fresh copy, or null when it could not load.
  final Future<UserProfile?> Function()? onCheckAccess;

  /// Resolves to the signed-in profile. Throws [StaffSignInFailed].
  final Future<UserProfile> Function(String email, String password) onSignIn;
  final Future<void> Function() onSignOut;

  @override
  State<StaffSignInSection> createState() => _StaffSignInSectionState();
}

class _StaffSignInSectionState extends State<StaffSignInSection> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
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
    setState(() {
      _busy = false;
      _message = profile == null
          ? 'Could not load your account. Check your connection and try again.'
          : profile.isStaff
              ? 'Staff access is on. Open the Dispatch tab.'
              : 'No staff role on this account yet. Ask an admin to give $_who the ADMIN or DISPATCHER role.';
    });
  }

  /// The user's Google name, then their email, for messages and the account block.
  String get _who {
    final name = widget.profile.displayName;
    if (name != null && name.isNotEmpty) return name;
    final email = widget.googleEmail;
    return email == null || email.isEmpty ? 'this account' : email;
  }

  Widget _googleBlock(TextTheme textTheme, String email) {
    final name = widget.profile.displayName;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('City staff', style: _heading),
        const SizedBox(height: 4),
        Container(
          color: AppColors.sage,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
        if (!widget.profile.isStaff)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Staff access comes from the role on your profile, so no password is needed.',
              style: textTheme.bodySmall,
            ),
          ),
        OutlinedButton(
          onPressed: _busy ? null : _checkAccess,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.ink),
            shape: const RoundedRectangleBorder(),
          ),
          child: Text(_busy ? 'Checking...' : 'Check staff access'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : widget.onSignOut,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.ink),
            shape: const RoundedRectangleBorder(),
          ),
          child: const Text('Sign out'),
        ),
        const SizedBox(height: 4),
        Text(
          'Your points and reports stay on this Google account. After signing out you browse as a guest.',
          style: textTheme.bodySmall,
        ),
      ],
    );
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
        setState(() => _message = 'Signed in, but this account has no staff role yet. Ask an admin.');
      }
    } on StaffSignInFailed catch (failure) {
      if (mounted) setState(() => _message = failure.message);
    } catch (_) {
      if (mounted) setState(() => _message = 'Sign-in failed. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final googleEmail = widget.googleEmail;
    if (googleEmail != null && !widget.isEmailSession) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _googleBlock(textTheme, googleEmail),
          if (_message != null) ...[
            const SizedBox(height: 8),
            Text(_message!, style: textTheme.bodyMedium),
          ],
        ],
      );
    }
    if (widget.isEmailSession) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Staff account', style: _heading),
          const SizedBox(height: 8),
          Text('Signed in as ${widget.profile.tierTitle}.', style: textTheme.bodyMedium),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : widget.onSignOut,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.ink,
              side: const BorderSide(color: AppColors.ink),
              shape: const RoundedRectangleBorder(),
            ),
            child: const Text('Sign out'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('City staff', style: _heading),
        const SizedBox(height: 4),
        Text(
          'Dispatchers and admins sign in with the email account the city gave them. '
          'This replaces the guest session on this phone.',
          style: textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          decoration: const InputDecoration(labelText: 'Staff email', border: OutlineInputBorder(borderRadius: BorderRadius.zero)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          decoration: const InputDecoration(labelText: 'Password', border: OutlineInputBorder(borderRadius: BorderRadius.zero)),
          onSubmitted: (_) => _signIn(),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _busy ? null : _signIn,
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48), shape: const RoundedRectangleBorder()),
          child: Text(_busy ? 'Signing in...' : 'Sign in as staff'),
        ),
        if (_message != null) ...[
          const SizedBox(height: 8),
          Text(_message!, style: textTheme.bodyMedium),
        ],
      ],
    );
  }

  static const _heading = TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 22, color: AppColors.ink);
}
