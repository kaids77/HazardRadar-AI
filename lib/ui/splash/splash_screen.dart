import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// Full-screen launch screen: photo background, serif wordmark, and tagline.
///
/// After [displayDuration] it fades into the screen built by [nextBuilder].
/// The next screen is injected so this widget does not depend on routing.
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.nextBuilder,
    this.displayDuration = const Duration(milliseconds: 2500),
    this.transitionDuration = const Duration(milliseconds: 600),
  });

  static const String backgroundAsset = 'assets/images/splash.jpg';
  static const String wordmark = 'HazardRadar AI';
  static const String tagline = 'See the risk before you walk into it.';

  final WidgetBuilder nextBuilder;
  final Duration displayDuration;
  final Duration transitionDuration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeIn;
  late final Animation<double> _contentOpacity;
  Timer? _advanceTimer;

  @override
  void initState() {
    super.initState();
    _fadeIn = AnimationController(
      vsync: this,
      duration: widget.transitionDuration,
    )..forward();
    _contentOpacity = CurvedAnimation(parent: _fadeIn, curve: Curves.easeOut);
    _advanceTimer = Timer(widget.displayDuration, _advance);
  }

  void _advance() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: widget.transitionDuration,
        pageBuilder: (context, animation, secondaryAnimation) =>
            widget.nextBuilder(context),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _advanceTimer?.cancel();
    _fadeIn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            SplashScreen.backgroundAsset,
            fit: BoxFit.cover,
            // Shows a flat sage panel until the photo is added.
            errorBuilder: (context, error, stackTrace) =>
                const ColoredBox(color: AppColors.sage),
          ),
          // Flat dark scrim so the cream text stays readable. Not a glow.
          const ColoredBox(color: Color(0x73000000)),
          SafeArea(
            child: FadeTransition(
              opacity: _contentOpacity,
              child: const _SplashContent(),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashContent extends StatelessWidget {
  const _SplashContent();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              SplashScreen.wordmark,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSerifDisplay',
                fontSize: 52,
                height: 1.05,
                color: AppColors.cream,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              SplashScreen.tagline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSerifDisplay',
                fontStyle: FontStyle.italic,
                fontSize: 20,
                color: AppColors.cream,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
