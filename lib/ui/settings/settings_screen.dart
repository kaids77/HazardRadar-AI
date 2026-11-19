import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/app_settings.dart';
import '../../theme/app_theme.dart';
import '../common/pull_to_refresh.dart';

/// Tab 3 for citizens: account and data preferences.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.profile,
    required this.settings,
    this.onAccount,
    this.staffSection,
    this.onRefresh,
  });

  final UserProfile profile;
  final AppSettings settings;
  final VoidCallback? onAccount;

  /// Extra section for staff sign-in or tools, added by later screens.
  final Widget? staffSection;

  /// Reloads the profile (level, role) on pull-to-refresh.
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => PullToRefresh(
        onRefresh: onRefresh ?? () async {},
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text('Account', style: _heading),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(profile.tierTitle),
            subtitle: Text('Level ${profile.tier}'),
            trailing: onAccount == null
                ? null
                : TextButton(
                    onPressed: onAccount,
                    style: TextButton.styleFrom(foregroundColor: AppColors.ink, shape: const RoundedRectangleBorder()),
                    child: Text(profile.tier == UserProfile.tierCommuterObserver ? 'Sign in with Google' : 'Details'),
                  ),
          ),
          const Divider(),
          const SizedBox(height: 16),
          Text('Data', style: _heading),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Data saver'),
            subtitle: Text(
              'Report photos load only when you tap them.',
              style: textTheme.bodySmall,
            ),
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

  static const _heading = TextStyle(fontFamily: 'DMSerifDisplay', fontSize: 22, color: AppColors.ink);
}
