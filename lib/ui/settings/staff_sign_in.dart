import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/staff_auth.dart';
import '../../theme/app_theme.dart';

/// Settings section for city staff: email sign-in, or sign-out when signed in with email.
class StaffSignInSection extends StatefulWidget {
  const StaffSignInSection({
    super.key,
    required this.profile,
    required this.isEmailSession,
    required this.onSignIn,
    required this.onSignOut,
  });

  final UserProfile profile;
  final bool isEmailSession;

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
