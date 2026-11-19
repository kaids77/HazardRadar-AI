import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../services/dispatch_repository.dart';
import '../../theme/app_theme.dart';
import 'dispatch_queue_screen.dart';

/// The staff tab. Dispatchers (Level 4) see the queue and [staffTabs]; admins also
/// see [adminTabs] (users, analytics).
class DispatchScreen extends StatelessWidget {
  const DispatchScreen({
    super.key,
    required this.profile,
    required this.dispatch,
    this.staffTabs = const [],
    this.adminTabs = const [],
  });

  final UserProfile profile;
  final DispatchRepository dispatch;

  /// Extra (label, page) pairs shown to every staff member.
  final List<(String, Widget)> staffTabs;

  /// Extra (label, page) pairs shown only to admins.
  final List<(String, Widget)> adminTabs;

  @override
  Widget build(BuildContext context) {
    final tabs = <(String, Widget)>[
      ('Queue', DispatchQueueScreen(profile: profile, dispatch: dispatch)),
      ...staffTabs,
      if (profile.isAdmin) ...adminTabs,
    ];
    if (tabs.length == 1) return tabs.single.$2;
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        children: [
          ColoredBox(
            color: AppColors.cream,
            child: TabBar(
              isScrollable: true,
              labelColor: AppColors.ink,
              unselectedLabelColor: AppColors.ink,
              indicator: const BoxDecoration(color: AppColors.sage),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: AppColors.sage,
              tabs: [for (final (label, _) in tabs) Tab(text: label)],
            ),
          ),
          Expanded(child: TabBarView(children: [for (final (_, page) in tabs) page])),
        ],
      ),
    );
  }
}
