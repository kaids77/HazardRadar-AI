import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

/// The HazardRadar AI brand mark: the radar-warning triangle icon and optional
/// two-line or inline wordmark ("Hazard Radar AI") with "AI" in sage.
///
/// Adapts automatically to light and dark mode unless [forceLight] is true
/// (used by the splash screen, which always displays the light version).
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.iconSize = 32,
    this.fontSize = 20,
    this.twoLine = false,
    this.showWordmark = true,
    this.forceLight = false,
  });

  /// Compact single-line logo for the top AppBar.
  const AppLogo.appBar({super.key})
      : iconSize = 30,
        fontSize = 21,
        twoLine = false,
        showWordmark = true,
        forceLight = false;

  /// Full two-line logo for the splash screen (light version).
  const AppLogo.splash({super.key})
      : iconSize = 112,
        fontSize = 44,
        twoLine = true,
        showWordmark = true,
        forceLight = true;

  final double iconSize;
  final double fontSize;
  final bool twoLine;
  final bool showWordmark;
  final bool forceLight;

  @override
  Widget build(BuildContext context) {
    final isDark = !forceLight && Theme.of(context).brightness == Brightness.dark;
    final primaryColor = isDark ? AppColors.cream : AppColors.ink;
    const sageColor = AppColors.logoSage;

    final icon = CustomPaint(
      size: Size(iconSize * 1.12, iconSize),
      painter: _HazardLogoPainter(
        isDark: isDark,
        primaryColor: primaryColor,
        sageColor: sageColor,
      ),
    );

    if (!showWordmark) return icon;

    final baseStyle = TextStyle(
      fontFamily: 'DMSerifDisplay',
      fontSize: fontSize,
      height: 1.05,
      color: primaryColor,
    );
    final aiStyle = baseStyle.copyWith(color: sageColor);

    final textWidget = twoLine
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hazard', style: baseStyle),
              Text.rich(
                TextSpan(
                  style: baseStyle,
                  children: [
                    const TextSpan(text: 'Radar '),
                    TextSpan(text: 'AI', style: aiStyle),
                  ],
                ),
              ),
            ],
          )
        : Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                const TextSpan(text: 'HazardRadar '),
                TextSpan(text: 'AI', style: aiStyle),
              ],
            ),
          );

    return Semantics(
      label: 'HazardRadar AI',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            icon,
            SizedBox(width: twoLine ? 18 : 10),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: textWidget,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HazardLogoPainter extends CustomPainter {
  const _HazardLogoPainter({
    required this.isDark,
    required this.primaryColor,
    required this.sageColor,
  });

  final bool isDark;
  final Color primaryColor;
  final Color sageColor;

  static double _rad(double deg) => deg * math.pi / 180.0;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final scale = math.min(w / 1.12, h);

    final strokeW = scale * 0.082;
    final padX = strokeW * 0.7;
    final topY = strokeW * 0.65;
    final botY = h - strokeW * 0.65;
    final centerX = w * 0.5;
    final leftX = padX;
    final rightX = w - padX;
    final cornerR = scale * 0.075;

    final triPath = _roundedTrianglePath(
      Offset(centerX, topY),
      Offset(rightX, botY),
      Offset(leftX, botY),
      cornerR,
    );

    // Inner clip triangle offset inward by half the border stroke width (plus a tiny
    // breathing gap) so the radar rings never overlap the triangle border.
    final inset = strokeW * 0.62;
    final innerPath = _roundedTrianglePath(
      Offset(centerX, topY + inset * 1.95),
      Offset(rightX - inset * 1.72, botY - inset),
      Offset(leftX + inset * 1.72, botY - inset),
      math.max(0, cornerR - inset * 0.6),
    );

    canvas.save();
    canvas.clipPath(innerPath);

    final center = Offset(centerX, topY + (botY - topY) * 0.635);
    final innerColor = isDark ? sageColor : primaryColor;

    final ringStroke = scale * 0.036;
    final primaryArcPaint = Paint()
      ..color = innerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringStroke
      ..strokeCap = StrokeCap.butt;

    final sageArcPaint = Paint()
      ..color = sageColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringStroke
      ..strokeCap = StrokeCap.butt;

    // 3 concentric radar rings: r1, r2, r3
    final r1 = scale * 0.132;
    final r2 = scale * 0.215;
    final r3 = scale * 0.298;

    // Ring 1 (innermost): left & right arcs (primary in light, sage in dark), bottom arc (sage)
    _drawArc(canvas, center, r1, -36, 72, primaryArcPaint);
    _drawArc(canvas, center, r1, 144, 72, primaryArcPaint);
    _drawArc(canvas, center, r1, 56, 68, sageArcPaint);

    // Ring 2 (middle): left & right arcs (primary in light, sage in dark), bottom & top-side arcs (sage)
    _drawArc(canvas, center, r2, -38, 76, primaryArcPaint);
    _drawArc(canvas, center, r2, 142, 76, primaryArcPaint);
    _drawArc(canvas, center, r2, 54, 72, sageArcPaint);
    _drawArc(canvas, center, r2, -68, 16, sageArcPaint);
    _drawArc(canvas, center, r2, -128, 16, sageArcPaint);

    // Ring 3 (outermost): all sage arcs, clipped cleanly inside the inner triangle boundary
    _drawArc(canvas, center, r3, -22, 92, sageArcPaint);
    _drawArc(canvas, center, r3, 110, 92, sageArcPaint);
    _drawArc(canvas, center, r3, 76, 28, sageArcPaint);

    // Center dot of exclamation mark / radar origin
    final dotPaint = Paint()
      ..color = innerColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, scale * 0.046, dotPaint);

    // Tapered exclamation stem above the dot
    final stemTop = center.dy - scale * 0.355;
    final stemBot = center.dy - scale * 0.088;
    final topHalfW = scale * 0.052;
    final botHalfW = scale * 0.025;
    final stemPath = Path()
      ..moveTo(center.dx - topHalfW, stemTop)
      ..lineTo(center.dx + topHalfW, stemTop)
      ..lineTo(center.dx + botHalfW, stemBot)
      ..lineTo(center.dx - botHalfW, stemBot)
      ..close();
    canvas.drawPath(stemPath, dotPaint);

    canvas.restore();

    // Draw the triangle border on top so its edges are crisp and never overlapped.
    final triPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(triPath, triPaint);
  }

  void _drawArc(Canvas canvas, Offset center, double radius, double startDeg, double sweepDeg, Paint paint) {
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _rad(startDeg),
      _rad(sweepDeg),
      false,
      paint,
    );
  }

  Path _roundedTrianglePath(Offset p0, Offset p1, Offset p2, double radius) {
    final pts = [p0, p1, p2];
    final path = Path();
    for (var i = 0; i < 3; i++) {
      final prev = pts[(i + 2) % 3];
      final curr = pts[i];
      final next = pts[(i + 1) % 3];

      final v1 = (prev - curr);
      final v2 = (next - curr);
      final len1 = v1.distance;
      final len2 = v2.distance;
      final u1 = v1 / len1;
      final u2 = v2 / len2;

      final start = curr + u1 * radius;
      final end = curr + u2 * radius;

      if (i == 0) {
        path.moveTo(start.dx, start.dy);
      } else {
        path.lineTo(start.dx, start.dy);
      }
      path.quadraticBezierTo(curr.dx, curr.dy, end.dx, end.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _HazardLogoPainter oldDelegate) =>
      oldDelegate.isDark != isDark ||
      oldDelegate.primaryColor != primaryColor ||
      oldDelegate.sageColor != sageColor;
}
