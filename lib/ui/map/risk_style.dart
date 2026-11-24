import 'package:flutter/material.dart';

import '../../models/hazard_category.dart';
import '../../models/incident.dart';
import '../../theme/app_theme.dart';

/// Flat marker color for a risk level. Solid colors only, with no glow or gradient.
Color riskColor(String riskLevel) {
  switch (riskLevel) {
    case 'Low':
      return AppColors.riskLow;
    case 'Medium':
      return AppColors.riskMedium;
    case 'High':
      return AppColors.riskHigh;
    default:
      return AppColors.ink;
  }
}

/// Pin color: a crew working on it wins over the risk color.
Color pinColor(Incident incident) =>
    incident.status == Incident.statusInProgress ? AppColors.inProgress : riskColor(incident.riskLevel);

/// Readable icon color on top of [pinColor]: black on high-risk red, cream on the darker colors.
Color pinIconColor(Incident incident) {
  if (incident.status == Incident.statusInProgress) return AppColors.onInProgress;
  return incident.riskLevel == 'High' ? AppColors.onError : AppColors.cream;
}

IconData categoryIcon(String category) => switch (category) {
      HazardCategory.pothole => Icons.add_road,
      HazardCategory.electrical => Icons.bolt,
      HazardCategory.flooding => Icons.water_drop,
      HazardCategory.obstruction => Icons.block,
      HazardCategory.lighting => Icons.lightbulb_outline,
      _ => Icons.priority_high,
    };
