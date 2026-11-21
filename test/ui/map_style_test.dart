import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/map/map_style.dart';

void main() {
  test('tile tint filter can be built from the cream token', () {
    expect(tileTintFilter(), isA<ColorFilter>());
    expect(tileTintFilter(), tileTintFilter(tint: AppColors.cream));
  });

  testWidgets('tinted tile builder wraps the tile in a color filter', (tester) async {
    late Widget wrapped;
    await tester.pumpWidget(
      Builder(builder: (context) {
        wrapped = tintedTileBuilder(context, const SizedBox(), Object());
        return wrapped;
      }),
    );
    expect(find.byType(ColorFiltered), findsOneWidget);
  });
}
