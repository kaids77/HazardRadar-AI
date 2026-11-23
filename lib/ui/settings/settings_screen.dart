import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../common/pull_to_refresh.dart';
import '../common/status_style.dart';
import '../common/user_avatar.dart';
import '../map/incident_evidence.dart';

/// The Settings tab: account (name, photo, level), appearance, data, and staff.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.profile,
    required this.settings,
    this.name,
    this.photo,
    this.hasAccount = false,
    this.onAccount,
    this.onEditName,
    this.onChangePhoto,
    this.onCreditName,
    this.staffSection,
    this.onRefresh,
  });

  final UserProfile profile;
  final AppSettings settings;

  /// The name shown for the account. Null falls back to the level title.
  final String? name;
  final Uint8List? photo;

  /// True for Google and staff email accounts. Guests see the Google sign-in instead.
  final bool hasAccount;

  /// Opens the account sheet (Google sign-in for guests, level details otherwise).
  final VoidCallback? onAccount;

  /// Null hides the "Edit name" button.
  final VoidCallback? onEditName;

  /// Null hides the "Change photo" button.
  final VoidCallback? onChangePhoto;

  /// Turns the public "Reported by" credit on or off. Null hides the switch (guests).
  final ValueChanged<bool>? onCreditName;

  /// Extra section for staff sign-in or tools.
  final Widget? staffSection;

  /// Reloads the profile (level, role) on pull-to-refresh.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final palette = context.palette;
    final shownName = name ?? profile.tierTitle;
    final outline = OutlinedButton.styleFrom(
      foregroundColor: palette.ink,
      side: BorderSide(color: palette.ink),
      shape: const RoundedRectangleBorder(),
    );
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => PullToRefresh(
        onRefresh: onRefresh ?? () async {},
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Account', style: _heading),
            const SizedBox(height: 12),
            Row(
              children: [
                UserAvatar(name: hasAccount ? shownName : null, photo: photo, size: 64),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shownName, style: textTheme.titleLarge, overflow: TextOverflow.ellipsis),
                      Text('${profile.tierTitle} · Level ${profile.tier}', style: textTheme.bodySmall),
                      const SizedBox(height: 6),
                      _AccountStatusBadge(profile: profile),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onEditName != null)
                  OutlinedButton(onPressed: onEditName, style: outline, child: const Text('Edit name')),
                if (onChangePhoto != null)
                  OutlinedButton(onPressed: onChangePhoto, style: outline, child: const Text('Change photo')),
                if (onAccount != null)
                  hasAccount
                      ? TextButton(
                          onPressed: onAccount,
                          style: TextButton.styleFrom(shape: const RoundedRectangleBorder()),
                          child: const Text('Level details'),
                        )
                      : ElevatedButton(
                          onPressed: onAccount,
                          style: ElevatedButton.styleFrom(shape: const RoundedRectangleBorder()),
                          child: const Text('Sign in with Google'),
                        ),
              ],
            ),
            if (onCreditName != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show my name on my resolved reports'),
                subtitle: Text(
                  'Your name appears in Report transparency only on reports the city resolved. '
                  'Turning it off hides your name.',
                  style: textTheme.bodySmall,
                ),
                value: profile.creditName,
                onChanged: onCreditName,
              ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            const Text('Appearance', style: _heading),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final (mode, label) in const [(ThemeMode.light, 'Light'), (ThemeMode.dark, 'Dark')])
                  ChoiceChip(
                    label: Text(label),
                    selected: settings.themeMode == mode,
                    onSelected: (_) => settings.setThemeMode(mode),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            const Text('Data', style: _heading),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Data saver'),
              subtitle: Text('Report photos load only when you tap them.', style: textTheme.bodySmall),
              value: settings.dataSaver,
              onChanged: settings.setDataSaver,
            ),
            if (staffSection != null) ...[
              const Divider(),
              const SizedBox(height: 16),
              staffSection!,
            ],
          ],
        ),
      ),
    );
  }

  static const _heading = TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 22);
}

class _AccountStatusBadge extends StatelessWidget {
  const _AccountStatusBadge({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final status = profile.accountStatus;
    final until = profile.suspendedUntil;
    final (background, foreground) = switch (status) {
      UserProfile.accountBanned || UserProfile.accountSuspended => (AppColors.redOrange, AppColors.onRedOrange),
      UserProfile.accountWarned => (AppColors.riskMedium, AppColors.ink),
      _ => (AppColors.riskLow, AppColors.cream),
    };
    final detail = switch (status) {
      UserProfile.accountWarned => 'A moderator issued a warning on this account.',
      UserProfile.accountSuspended =>
        until == null
            ? 'Reporting and voting are paused while this account is suspended.'
            : 'Suspended until ${formatPhilippineTime(until)}.',
      UserProfile.accountBanned => 'Reporting and voting are disabled on this account.',
      _ => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FlatBadge(label: 'Status: $status', background: background, foreground: foreground),
        if (detail != null) ...[
          const SizedBox(height: 4),
          Text(detail, style: textTheme.bodySmall),
        ],
      ],
    );
  }
}
