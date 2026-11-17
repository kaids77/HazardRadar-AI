import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'ui/home/home_placeholder.dart';
import 'ui/splash/splash_screen.dart';

void main() {
  runApp(const HazardRadarApp());
}

class HazardRadarApp extends StatelessWidget {
  const HazardRadarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HazardRadar AI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: SplashScreen(
        nextBuilder: (_) => const HomePlaceholder(),
      ),
    );
  }
}
