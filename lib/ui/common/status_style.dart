import 'package:flutter/material.dart';

import '../../models/incident.dart';
import '../../theme/app_theme.dart';

/// Label and flat colors for a report's status badge.
({String label, Color background, Color foreground}) statusStyle(BuildContext context, Incident incident) {
  if (incident.isQuarantined) {
    return (label: 'Disputed', background: context.palette.ink, foreground: context.palette.paper);
  }
  return switch (incident.status) {
    Incident.statusInProgress => (
        label: 'In progress',
        background: AppColors.inProgress,
        foreground: AppColors.onInProgress,
      ),
    Incident.statusResolved => (label: 'Resolved by city', background: context.palette.sage, foreground: context.palette.ink),
    _ => (label: 'Active', background: AppColors.redOrange, foreground: AppColors.onRedOrange),
  };
}

/// A rounded rectangular badge with a subtle outline.
class FlatBadge extends StatelessWidget {
  const FlatBadge({super.key, required this.label, required this.background, required this.foreground});

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: foreground.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}
