import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/incident.dart';
import '../../models/user_profile.dart';
import '../../services/avatar_repository.dart';
import '../../services/user_admin_repository.dart';
import '../../theme/app_theme.dart';
import 'user_manager_screen.dart';

/// Shared by the staff screens: keeps a uid → profile map from the users list (staff can
/// read profiles) and builds the "Reported by" line that opens the user page.
mixin ReporterLookup<T extends StatefulWidget> on State<T> {
  /// Profiles source. Null shows the level stored on the report only.
  UserAdminRepository? get reporterSource;

  /// The staff member looking at the screen.
  UserProfile get viewer;

  AvatarRepository? get reporterAvatars => null;

  StreamSubscription<List<UserProfile>>? _reporterSub;
  Map<String, UserProfile> _reporters = const {};

  void startReporterLookup() {
    _reporterSub?.cancel();
    _reporterSub = reporterSource?.watchUsers().listen(
      (users) {
        if (mounted) setState(() => _reporters = {for (final u in users) u.uid: u});
      },
      // Names are a convenience; the cards still work without them.
      onError: (Object _) {},
    );
  }

  void stopReporterLookup() => _reporterSub?.cancel();

  Widget reporterLineFor(Incident incident) {
    final source = reporterSource;
    final reporter = _reporters[incident.reporterUid];
    return ReporterLine(
      reporter: reporter,
      fallbackTier: incident.reporterTier,
      onOpen: source == null || reporter == null
          ? null
          : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => UserDetailScreen(
                    admin: viewer,
                    uid: reporter.uid,
                    users: source,
                    avatars: reporterAvatars,
                    canEdit: viewer.isAdmin,
                  ),
                ),
              ),
    );
  }
}

/// Staff only: "Reported by [name] · [level]" on queue and quarantine cards.
/// Never shows the uid. Tapping opens the user page when [onOpen] is set.
class ReporterLine extends StatelessWidget {
  const ReporterLine({super.key, required this.reporter, required this.fallbackTier, this.onOpen});

  /// The reporter's profile, or null while profiles load or when it is missing.
  final UserProfile? reporter;

  /// The level stored on the report, used until the profile is known.
  final int fallbackTier;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final reporter = this.reporter;
    final text = reporter == null
        ? 'Reported by a ${UserProfile(uid: '', role: '', tier: fallbackTier, accountStatus: '').tierTitle}'
        : 'Reported by ${userLabel(reporter)} · ${reporter.tierTitle}'
            '${reporter.accountStatus == UserProfile.accountActive ? '' : ' · ${reporter.accountStatus}'}';
    final line = Text(
      text,
      style: textTheme.bodySmall?.copyWith(
        color: context.palette.ink,
        decoration: onOpen == null ? null : TextDecoration.underline,
      ),
    );
    if (onOpen == null || reporter == null) return line;
    return Semantics(
      button: true,
      label: 'Open the reporter, ${userLabel(reporter)}',
      excludeSemantics: true,
      child: InkWell(onTap: onOpen, child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: line)),
    );
  }
}
