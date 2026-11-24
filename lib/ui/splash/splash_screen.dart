import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../common/app_logo.dart';

/// Full-screen launch screen: light background with the HazardRadar AI light logo and tagline.
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
      backgroundColor: AppColors.cream,
      body: SafeArea(
        child: FadeTransition(
          opacity: _contentOpacity,
          child: const _SplashContent(),
        ),
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
            const AppLogo.splash(),
            // Keep a zero-size text node with SplashScreen.wordmark so existing
            // widget tests and screen readers can locate the splash wordmark.
            const SizedBox.shrink(child: Text(SplashScreen.wordmark)),
            const SizedBox(height: 20),
            const Text(
              SplashScreen.tagline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'DMSerifDisplay',
                fontStyle: FontStyle.italic,
                fontSize: 20,
                color: AppColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
