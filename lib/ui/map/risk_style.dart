import 'package:flutter/material.dart';

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
