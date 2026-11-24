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
    _ => (label: 'Active', background: AppColors.riskHigh, foreground: AppColors.onError),
  };
}

/// Text/outline color for a status badge when drawn with a transparent background ([FlatBadge.outlined]).
Color statusTextColor(BuildContext context, Incident incident) {
  if (incident.isQuarantined) return context.palette.ink;
  return switch (incident.status) {
    Incident.statusInProgress => AppColors.inProgress,
    Incident.statusResolved => AppColors.riskLow,
    _ => AppColors.riskHigh,
  };
}

/// A rounded rectangular badge. When [outlined] is true, it draws a transparent
/// background with [foreground] as both the text color and border color.
class FlatBadge extends StatelessWidget {
  const FlatBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.outlined = false,
  });

  const FlatBadge.outlined({
    super.key,
    required this.label,
    required Color color,
  })  : background = Colors.transparent,
        foreground = color,
        outlined = true;

  final String label;
  final Color background;
  final Color foreground;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: outlined ? foreground.withValues(alpha: 0.7) : foreground.withValues(alpha: 0.2),
          width: outlined ? 1.2 : 1.0,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: outlined ? 2.5 : 3),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground, fontWeight: FontWeight.w600),
      ),
    );
  }
}
