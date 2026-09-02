import 'dart:math';

import 'package:flutter/material.dart';

/// The kind of animation currently playing.
enum _AnimKind { pop, shake }

/// Heart toggle button with async-aware animation.
///
/// All motion uses Flutter's built-in [Curves] for smooth 120 Hz output.
///
/// - **idle** — shows the current heart (outlined / filled)
/// - **pending** — a network call is in flight; icon pulses gently
/// - **animating (pop)** — server accepted → `easeOut` up + `elasticOut` settle
/// - **animating (shake)** — server rejected → horizontal wobble via `easeOutBack`
///
/// If [onChanged] is omitted the toggle is instant (no pending state).
class AnimatedFavoriteButton extends StatefulWidget {
  final bool isFavorited;
  final double size;
  final Future<bool> Function(bool newIsFavorited)? onChanged;

  const AnimatedFavoriteButton({
    super.key,
    this.isFavorited = false,
    this.size = 24,
    this.onChanged,
  });

  @override
  State<AnimatedFavoriteButton> createState() => _AnimatedFavoriteButtonState();
}

class _AnimatedFavoriteButtonState extends State<AnimatedFavoriteButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  late bool _current;
  bool? _target;
  _AnimKind? _animKind;

  // ── Pre-built animation tweens (reusable across frames) ────────────────────

  late final Animatable<double> _favPop = TweenSequence<double>([
    TweenSequenceItem(
      weight: 35,
      tween: Tween(begin: 1.0, end: 1.40).chain(CurveTween(curve: Curves.easeOut)),
    ),
    TweenSequenceItem(
      weight: 65,
      tween: Tween(begin: 1.40, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)),
    ),
  ]);

  late final Animatable<double> _unfavPop = TweenSequence<double>([
    TweenSequenceItem(
      weight: 30,
      tween: Tween(begin: 1.0, end: 0.82).chain(CurveTween(curve: Curves.easeIn)),
    ),
    TweenSequenceItem(
      weight: 70,
      tween: Tween(begin: 0.82, end: 1.0).chain(CurveTween(curve: Curves.elasticOut)),
    ),
  ]);

  @override
  void initState() {
    super.initState();
    _current = widget.isFavorited;
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 450));
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(AnimatedFavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync internal state with external prop when not mid-animation.
    if (_animKind == null && _target == null) {
      if (widget.isFavorited != _current) {
        _current = widget.isFavorited;
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    if (_ctrl.isAnimating || _target != null) return;

    final desired = !_current;
    _target = desired;

    if (widget.onChanged == null) {
      _current = desired;
      _animKind = _AnimKind.pop;
      await _ctrl.forward(from: 0.0);
      if (mounted) _cleanUp();
      return;
    }

    // ── 1. Pending ──────────────────────────────────────────────────────────
    setState(() {});

    try {
      final success = await widget.onChanged!(desired);
      if (!mounted) return;

      if (success) {
        _current = desired;
        _animKind = _AnimKind.pop;
      } else {
        _animKind = _AnimKind.shake;
      }
    } catch (_) {
      if (!mounted) return;
      _animKind = _AnimKind.shake;
    }

    // ── 2. Animate ──────────────────────────────────────────────────────────
    await _ctrl.forward(from: 0.0);
    if (mounted) _cleanUp();
  }

  void _cleanUp() {
    _animKind = null;
    _target = null;
    setState(() {});
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = _ctrl.value;
    final pending = widget.onChanged != null && _target != null && _animKind == null;

    // Icon & colour
    bool showFilled;
    Color color;

    if (_animKind == _AnimKind.pop) {
      final filling = _target ?? true;
      showFilled = filling ? t > 0.35 : t < 0.30;
      color = showFilled ? Colors.red : cs.onSurfaceVariant;
    } else if (_animKind == _AnimKind.shake) {
      showFilled = _current;
      color = Colors.red.shade200;
    } else {
      showFilled = _current;
      color = _current ? Colors.red : cs.onSurfaceVariant;
    }

    Widget icon = Icon(
      showFilled ? Icons.favorite : Icons.favorite_border,
      size: widget.size,
      color: color,
    );

    // Transforms
    if (pending) {
      icon = _Pulse(child: icon);
    } else if (_animKind == _AnimKind.pop) {
      final scale = (_target ?? true) ? _favPop.evaluate(_ctrl) : _unfavPop.evaluate(_ctrl);
      icon = Transform.scale(scale: scale, child: icon);
    } else if (_animKind == _AnimKind.shake) {
      // Decaying oscillation: easeOut envelope × sine
      final amplitude = Curves.easeOut.transform(t) * 5.0;
      final offset = amplitude * sin(t * pi * 6); // 3 full wobbles
      icon = Transform.translate(offset: Offset(offset, 0), child: icon);
    }

    // Material tap target: 40 dp circle, red-tinted hover, ink splash.
    const tapSize = 40.0;
    return SizedBox(
      width: tapSize,
      height: tapSize,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(tapSize / 2),
          hoverColor: Colors.red.withValues(alpha: 0.10),
          splashColor: Colors.red.withValues(alpha: 0.20),
          highlightColor: Colors.red.withValues(alpha: 0.08),
          onTap: _handleTap,
          child: Center(child: icon),
        ),
      ),
    );
  }
}

/// Subtle opacity + scale pulse for the pending (in-flight) state.
class _Pulse extends StatefulWidget {
  final Widget child;
  const _Pulse({required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
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
        final v = Curves.easeInOutSine.transform(_ctrl.value);
        return Opacity(
          opacity: 0.45 + 0.55 * v,
          child: Transform.scale(
            scale: 0.92 + 0.08 * v,
            child: widget.child,
          ),
        );
      },
    );
  }
}
