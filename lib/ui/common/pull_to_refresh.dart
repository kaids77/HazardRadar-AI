import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Pull down from the top of a list to reload it, in the app palette.
///
/// [child] must be a vertical scrollable. Give it
/// `physics: const AlwaysScrollableScrollPhysics()` so a short or empty list can
/// still be pulled.
class PullToRefresh extends StatelessWidget {
  const PullToRefresh({super.key, required this.onRefresh, required this.child});

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: Theme.of(context).colorScheme.primary,
      backgroundColor: context.palette.paper,
      elevation: 0,
      child: child,
    );
  }
}

/// Lets a mouse drag lists too, so pull-to-refresh works in desktop Chrome.
/// Flutter only drags with touch, stylus and trackpad by default.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {...super.dragDevices, PointerDeviceKind.mouse};
}
