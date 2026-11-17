import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Tile tint that keeps the OpenStreetMap base map in the app palette.
///
/// Each tile is reduced to luminance and multiplied by cream, so roads and
/// labels stay readable while the full-color tiles stop competing with the pins.
ColorFilter tileTintFilter({Color tint = AppColors.cream}) {
  // Rec. 709 luminance weights.
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final r = tint.r, g = tint.g, b = tint.b;
  return ColorFilter.matrix(<double>[
    lr * r, lg * r, lb * r, 0, 0,
    lr * g, lg * g, lb * g, 0, 0,
    lr * b, lg * b, lb * b, 0, 0,
    0, 0, 0, 1, 0,
  ]);
}

/// Wraps a loaded tile so every tile on the map gets the same [tileTintFilter].
Widget tintedTileBuilder(BuildContext context, Widget tileWidget, Object tile) {
  return ColorFiltered(colorFilter: _filter, child: tileWidget);
}

final ColorFilter _filter = tileTintFilter();
