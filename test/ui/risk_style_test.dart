import 'package:flutter_test/flutter_test.dart';

import 'package:hazardradarai/theme/app_theme.dart';
import 'package:hazardradarai/ui/map/risk_style.dart';

void main() {
  test('risk levels map to the flat palette colors', () {
    expect(riskColor('Low'), AppColors.riskLow);
    expect(riskColor('Medium'), AppColors.riskMedium);
    expect(riskColor('High'), AppColors.riskHigh);
  });

  test('unknown risk levels fall back to ink', () {
    expect(riskColor('Critical'), AppColors.ink);
  });
}
