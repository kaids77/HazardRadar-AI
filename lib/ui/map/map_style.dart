import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Tile tint that keeps the OpenStreetMap base map in the app palette.
///
/// Colors are pulled partway toward gray ([saturation] of the original is kept),
/// then multiplied by cream. Water, parks, and roads stay distinguishable, but
/// the map reads as one warm tone so the risk pins stand out.
ColorFilter tileTintFilter({Color tint = AppColors.cream, double saturation = 0.55}) {
  // Rec. 709 luminance weights.
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final s = saturation, k = 1 - saturation;
  final r = tint.r, g = tint.g, b = tint.b;
  return ColorFilter.matrix(<double>[
    r * (k * lr + s), r * k * lg, r * k * lb, 0, 0,
    g * k * lr, g * (k * lg + s), g * k * lb, 0, 0,
    b * k * lr, b * k * lg, b * (k * lb + s), 0, 0,
    0, 0, 0, 1, 0,
  ]);
}

/// Wraps a loaded tile so every tile on the map gets the same [tileTintFilter].
Widget tintedTileBuilder(BuildContext context, Widget tileWidget, Object tile) {
  return ColorFiltered(colorFilter: _filter, child: tileWidget);
}

final ColorFilter _filter = tileTintFilter();
