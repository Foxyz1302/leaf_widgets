import 'dart:math';

import 'package:flutter/material.dart';

/// A 4-pointed sparkle star that continuously rotates and pulses in size.
/// Use as a "New posts" indicator icon.
///
/// The silhouette is a concave-edged sparkle (sharp tips, curved bellies)
/// with an optional white-core shine gradient and a soft glow.
class AnimatedStar extends StatefulWidget {
  /// Base size of the canvas in logical pixels.
  final double size;

  /// Base color of the star (tips, glow, and the outer edge of the shine).
  final Color color;

  /// Inner (elbow) radius as a fraction of the outer radius.
  /// Smaller = deeper notches = sharper points.
  final double innerRatio;

  /// Concave curvature of the edges, 0..1.
  /// 0 = straight edges (classic star), ~0.3 = sparkle silhouette.
  final double edgeCurve;

  /// Distance of the star tips from the center, as a fraction of the half-size.
  /// Keep enough margin for [glowRatio] so the glow isn't clipped.
  final double outerRatio;

  /// Glow blur radius as a fraction of [size]. 0 = no glow.
  final double glowRatio;

  /// Opacity of the glow pass.
  final double glowOpacity;

  /// Whether to fill with a white-core shine gradient instead of flat color.
  final bool shine;

  const AnimatedStar({
    super.key,
    this.size = 24,
    this.color = Colors.amberAccent,
    this.innerRatio = 0.25,
    this.edgeCurve = 0.3,
    this.outerRatio = 0.8,
    this.glowRatio = 0.2,
    this.glowOpacity = 0.3,
    this.shine = true,
  });

  @override
  State<AnimatedStar> createState() => _AnimatedStarState();
}

class _AnimatedStarState extends State<AnimatedStar> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final v = _ctrl.value;

        // Smooth ease-in-out twinkle: 2 pulses per full rotation.
        final triangle = 1.0 - 2.0 * ((v * 2) % 1.0 - 0.5).abs();
        final scale = 0.70 + 0.30 * Curves.easeInOutSine.transform(triangle);

        return Transform.scale(
          scale: scale,
          child: Transform.rotate(
            angle: v * 2 * pi, // linear rotation — constant speed
            child: CustomPaint(
              size: Size.square(widget.size),
              painter: _FourPointStarPainter(
                color: widget.color,
                innerRatio: widget.innerRatio,
                edgeCurve: widget.edgeCurve,
                outerRatio: widget.outerRatio,
                glowRatio: widget.glowRatio,
                glowOpacity: widget.glowOpacity,
                shine: widget.shine,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FourPointStarPainter extends CustomPainter {
  final Color color;
  final double innerRatio;
  final double edgeCurve;
  final double outerRatio;
  final double glowRatio;
  final double glowOpacity;
  final bool shine;

  const _FourPointStarPainter({
    required this.color,
    required this.innerRatio,
    required this.edgeCurve,
    required this.outerRatio,
    required this.glowRatio,
    required this.glowOpacity,
    required this.shine,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final half = size.width / 2;
    final center = Offset(half, half);
    final outer = half * outerRatio;
    final inner = outer * innerRatio;
    final curve = edgeCurve.clamp(0.0, 1.0);

    final path = Path();
    for (var i = 0; i < 4; i++) {
      final tipAngle = i * pi / 2 - pi / 2;
      final tip = center + Offset(cos(tipAngle), sin(tipAngle)) * outer;
      final nextTip = center + Offset(cos(tipAngle + pi / 2), sin(tipAngle + pi / 2)) * outer;
      final elbowAngle = tipAngle + pi / 4;
      final elbow = center + Offset(cos(elbowAngle), sin(elbowAngle)) * inner;

      if (i == 0) {
        path.moveTo(tip.dx, tip.dy);
      } else {
        path.lineTo(tip.dx, tip.dy);
      }

      if (curve > 0) {
        // Each edge bows toward the center: control point pulled from the
        // edge midpoint toward the star's center.
        final mid1 = Offset((tip.dx + elbow.dx) / 2, (tip.dy + elbow.dy) / 2);
        final mid2 = Offset((elbow.dx + nextTip.dx) / 2, (elbow.dy + nextTip.dy) / 2);
        path.quadraticBezierTo(
          mid1.dx + (center.dx - mid1.dx) * curve,
          mid1.dy + (center.dy - mid1.dy) * curve,
          elbow.dx,
          elbow.dy,
        );
        path.quadraticBezierTo(
          mid2.dx + (center.dx - mid2.dx) * curve,
          mid2.dy + (center.dy - mid2.dy) * curve,
          nextTip.dx,
          nextTip.dy,
        );
      } else {
        path.lineTo(elbow.dx, elbow.dy);
        path.lineTo(nextTip.dx, nextTip.dy);
      }
    }
    path.close();

    // Glow pass
    if (glowRatio > 0 && glowOpacity > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withValues(alpha: glowOpacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRatio * size.width),
      );
    }

    // Fill pass — white-core radial gradient, light from the top-left
    final fill = Paint()..style = PaintingStyle.fill;
    if (shine) {
      fill.shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        radius: 1.2,
        colors: [Color.lerp(color, Colors.white, 0.85)!, color],
        stops: const [0.0, 0.45],
      ).createShader(Rect.fromCircle(center: center, radius: outer));
    } else {
      fill.color = color;
    }
    canvas.drawPath(path, fill);
  }

  @override
  bool shouldRepaint(_FourPointStarPainter old) =>
      old.color != color ||
      old.innerRatio != innerRatio ||
      old.edgeCurve != edgeCurve ||
      old.outerRatio != outerRatio ||
      old.glowRatio != glowRatio ||
      old.glowOpacity != glowOpacity ||
      old.shine != shine;
}
