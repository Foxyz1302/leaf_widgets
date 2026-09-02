import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Double-tap cycle position (ported from photo_view's scale-state cycle,
/// adapted to our scale convention where 1.0 = contained).
enum _LeafZoomState { initial, covering, originalSize, zoomedIn, zoomedOut }

class _CornersRange {
  const _CornersRange(this.min, this.max);
  final double min;
  final double max;
}

class _HitCorners {
  const _HitCorners(this.hasHitMin, this.hasHitMax);
  final bool hasHitMin;
  final bool hasHitMax;
  bool get hasHitAny => hasHitMin || hasHitMax;
  bool get hasHitBoth => hasHitMin && hasHitMax;
}

/// Per-page zoom state for [LeafViewer].
///
/// Scale is relative to the contained (fit-to-screen) size, so 1.0 is the
/// resting scale. Position is the translation in screen pixels.
///
/// Boundary math (pan corners, clamping) and the double-tap cycle are ported
/// from photo_view (MIT) and verified by property tests; input handling,
/// fling physics and animation curves are our own.
class LeafZoomController extends ChangeNotifier {
  LeafZoomController({this.maxScale = 5.0, required TickerProvider vsync})
      : _vsync = vsync {
    _animCtrl = AnimationController(vsync: vsync, duration: _animDuration)
      ..addListener(_onAnimTick);
  }

  static const double _minScale = 1.0;
  static const Duration _animDuration = Duration(milliseconds: 200);

  /// Upper zoom limit (relative to contained).
  final double maxScale;
  final TickerProvider _vsync;
  late final AnimationController _animCtrl;

  /// Viewport (page) size in pixels. Set by [LeafZoomable] on layout.
  Size viewport = Size.zero;

  /// Contained (fit-to-screen) render size of the child. Set by
  /// [LeafZoomable] on layout.
  Size childSize = Size.zero;

  /// Full-resolution child size (for the 1:1 double-tap step).
  /// Null disables the 1:1 step.
  Size? originalSize;

  double _scale = 1.0;
  Offset _position = Offset.zero;

  _LeafZoomState _state = _LeafZoomState.initial;
  bool _snapOnCancel = false;
  Animation<Matrix4>? _matrixAnim;

  Ticker? _flingTicker;
  double _flingVx = 0, _flingVy = 0;
  int _flingId = 0;
  bool _disposed = false;

  /// Fired when the scale reaches the 1.0 or max limit (haptics hook).
  VoidCallback? onZoomLimit;

  double get scale => _scale;
  Offset get position => _position;

  /// Whether the child is zoomed beyond the resting scale.
  bool get zoomed => _scale > 1.001;
  bool get isAnimating => _animCtrl.isAnimating;
  bool get isFlinging => _flingTicker?.isActive ?? false;
  bool get isInteracting => isAnimating || isFlinging;

  /// The on-screen rect of the child at the current scale/position.
  Rect get imageRect {
    final w = childSize.width * _scale;
    final h = childSize.height * _scale;
    return Rect.fromLTWH(
      (viewport.width - w) / 2 + _position.dx,
      (viewport.height - h) / 2 + _position.dy,
      w,
      h,
    );
  }

  /// Notify layout changes. Recomputes cycle-state scales and reclamps.
  void updateLayout({required Size viewport, required Size childSize, Size? originalSize}) {
    final changed = viewport != this.viewport || childSize != this.childSize || originalSize != this.originalSize;
    this.viewport = viewport;
    this.childSize = childSize;
    this.originalSize = originalSize;
    if (!changed || isInteracting) return;
    if (_state != _LeafZoomState.zoomedIn && _state != _LeafZoomState.zoomedOut) {
      _scale = _scaleForState(_state);
    }
    _position = _clampPosition(_position, _scale);
    notifyListeners();
  }

  // ── Gestures ────────────────────────────────────────────────────────────

  /// Cancel any running fling/animation. If the animation was heading back to
  /// 1×, snap there instantly so a following swipe pages instead of panning.
  void cancelGesture() {
    _cancelFling();
    if (_animCtrl.isAnimating) {
      _animCtrl.stop();
      if (_snapOnCancel) {
        _snapToInitial();
      }
    }
  }

  /// Single-finger pan while zoomed.
  void panBy(Offset delta) {
    _setZoom(_scale, _position + delta);
  }

  /// Unified pan/pinch update: scale to [newScale] while keeping the child
  /// point under [prevFocal] anchored to [curFocal]. For a pure pan the scale
  /// is unchanged and this reduces to `position += curFocal - prevFocal`.
  void scaleUpdate(double newScale, Offset prevFocal, Offset curFocal) {
    final oldScale = _scale;
    final clamped = newScale.clamp(_minScale, maxScale);
    final anchored = curFocal + (_position - prevFocal) * (clamped / oldScale);
    _setZoom(clamped, anchored);
    _checkHaptic(oldScale, _scale);
  }

  /// Cursor-anchored wheel zoom.
  void wheelZoom(double scrollDy, Offset cursor) {
    _cancelFling();
    final oldScale = _scale;
    final newScale = (_scale * (1 - scrollDy * 0.001)).clamp(_minScale, maxScale);
    if (newScale == oldScale) return;
    final vpc = Offset(viewport.width / 2, viewport.height / 2);
    final anchored = (cursor - vpc) + (_position - (cursor - vpc)) * (newScale / oldScale);
    _setZoom(newScale, anchored);
    _checkHaptic(oldScale, _scale);
  }

  /// Double-tap: advance the 1× → covered → 1:1 → 1× cycle, zooming in
  /// around [tapPoint].
  void doubleTap(Offset tapPoint) {
    cancelGesture();
    final state = _state;
    if (state == _LeafZoomState.zoomedIn || state == _LeafZoomState.zoomedOut) {
      _animateToState(_LeafZoomState.initial, tapPoint);
      return;
    }
    var prevScale = _scaleForState(state);
    var prevState = state;
    var nextScale = prevScale;
    var nextState = state;
    do {
      prevScale = nextScale;
      prevState = nextState;
      nextState = _cycle(prevState);
      nextScale = _scaleForState(nextState);
    } while (prevScale == nextScale && state != nextState);
    if (prevScale == nextScale) return;
    _animateToState(nextState, tapPoint);
  }

  /// Velocity-proportional pan fling (friction 0.92/frame, tap-to-stop).
  void startFling(Offset velocity) {
    _cancelFling();
    final speed = velocity.distance;
    if (speed < 50) return;
    _flingVx = velocity.dx;
    _flingVy = velocity.dy;
    _flingId++;
    final id = _flingId;
    const friction = 0.92;
    _flingTicker = _vsync.createTicker((elapsed) {
      if (_disposed || _flingId != id) {
        _cancelFling();
        return;
      }
      if (Offset(_flingVx, _flingVy).distance < 5) {
        _cancelFling();
        return;
      }
      _setZoom(_scale, _position + Offset(_flingVx / 60, _flingVy / 60));
      _flingVx *= friction;
      _flingVy *= friction;
    })..start();
  }

  // ── Edge-release (ported from photo_view's HitCornersDetector) ──────────

  /// Whether a drag with per-event [fingerDelta] should be claimed as a pan.
  /// Claims when either axis can still move the child; releases only when
  /// fully clamped (the LoliSnatcher `Axis.values` behaviour).
  ///
  /// [fingerDelta] is the raw finger movement. The ported corner rules use
  /// photo_view's sign convention (negated movement), so the delta is
  /// inverted internally.
  bool shouldClaim(Offset fingerDelta) => shouldMoveX(fingerDelta) || shouldMoveY(fingerDelta);

  bool shouldMoveX(Offset fingerDelta) => _shouldMoveAxis(_hitCornersX(), -fingerDelta.dx, -fingerDelta.dy);
  bool shouldMoveY(Offset fingerDelta) => _shouldMoveAxis(_hitCornersY(), -fingerDelta.dy, -fingerDelta.dx);

  bool _shouldMoveAxis(_HitCorners corners, double mainAxisMove, double crossAxisMove) {
    if (mainAxisMove == 0) return false;
    if (!corners.hasHitAny) return true;
    final axisBlocked = corners.hasHitBoth || (corners.hasHitMax ? mainAxisMove > 0 : mainAxisMove < 0);
    return !axisBlocked;
  }

  _HitCorners _hitCornersX() {
    final childWidth = childSize.width * _scale;
    if (viewport.width >= childWidth) return const _HitCorners(true, true);
    final x = -_position.dx;
    final corners = _cornersX();
    return _HitCorners(x <= corners.min, x >= corners.max);
  }

  _HitCorners _hitCornersY() {
    final childHeight = childSize.height * _scale;
    if (viewport.height >= childHeight) return const _HitCorners(true, true);
    final y = -_position.dy;
    final corners = _cornersY();
    return _HitCorners(y <= corners.min, y >= corners.max);
  }

  _CornersRange _cornersX({double? scale}) {
    final widthDiff = childSize.width * (scale ?? _scale) - viewport.width;
    return _CornersRange(-widthDiff / 2, widthDiff / 2);
  }

  _CornersRange _cornersY({double? scale}) {
    final heightDiff = childSize.height * (scale ?? _scale) - viewport.height;
    return _CornersRange(-heightDiff / 2, heightDiff / 2);
  }

  Offset _clampPosition(Offset position, double scale) {
    final computedWidth = childSize.width * scale;
    final computedHeight = childSize.height * scale;
    double finalX = 0;
    if (viewport.width < computedWidth) {
      final c = _cornersX(scale: scale);
      finalX = position.dx.clamp(c.min, c.max);
    }
    double finalY = 0;
    if (viewport.height < computedHeight) {
      final c = _cornersY(scale: scale);
      finalY = position.dy.clamp(c.min, c.max);
    }
    return Offset(finalX, finalY);
  }

  // ── Double-tap cycle (ported from photo_view's nextScaleState) ──────────

  double _scaleForState(_LeafZoomState state) {
    switch (state) {
      case _LeafZoomState.initial:
      case _LeafZoomState.zoomedIn:
      case _LeafZoomState.zoomedOut:
        return _minScale;
      case _LeafZoomState.covering:
        return _clampScale(math.max(viewport.width / childSize.width, viewport.height / childSize.height));
      case _LeafZoomState.originalSize:
        final o = originalSize;
        if (o == null || o.width <= 0 || o.height <= 0) return _minScale;
        final contained = math.min(viewport.width / o.width, viewport.height / o.height);
        return _clampScale(1 / contained);
    }
  }

  double _clampScale(double s) => s.clamp(_minScale, maxScale);

  _LeafZoomState _cycle(_LeafZoomState s) {
    switch (s) {
      case _LeafZoomState.initial:
        return _LeafZoomState.covering;
      case _LeafZoomState.covering:
        return _LeafZoomState.originalSize;
      case _LeafZoomState.originalSize:
        return _LeafZoomState.initial;
      case _LeafZoomState.zoomedIn:
      case _LeafZoomState.zoomedOut:
        return _LeafZoomState.initial;
    }
  }

  void _animateToState(_LeafZoomState target, Offset tapPoint) {
    final targetScale = _scaleForState(target);
    final Offset targetPosition;
    if (targetScale > _scale) {
      final vpc = Offset(viewport.width / 2, viewport.height / 2);
      targetPosition = _clampPosition(
        (tapPoint - vpc) + (_position - (tapPoint - vpc)) * (targetScale / _scale),
        targetScale,
      );
    } else {
      targetPosition = Offset.zero;
    }
    _state = target;
    _animateZoomTo(targetScale, targetPosition);
  }

  void _animateZoomTo(double targetScale, Offset targetPosition) {
    _cancelFling();
    final begin = Matrix4.identity()
      ..setEntry(0, 3, _position.dx)
      ..setEntry(1, 3, _position.dy)
      ..setEntry(0, 0, _scale)
      ..setEntry(1, 1, _scale);
    final end = Matrix4.identity()
      ..setEntry(0, 3, targetPosition.dx)
      ..setEntry(1, 3, targetPosition.dy)
      ..setEntry(0, 0, targetScale)
      ..setEntry(1, 1, targetScale);
    _snapOnCancel = targetScale == _minScale;
    _matrixAnim = Matrix4Tween(begin: begin, end: end)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward(from: 0).whenCompleteOrCancel(() {
      if (_disposed) return;
      _scale = targetScale;
      _position = _clampPosition(targetPosition, targetScale);
      _snapOnCancel = false;
      notifyListeners();
    });
  }

  void _onAnimTick() {
    final anim = _matrixAnim;
    if (anim == null) return;
    _scale = anim.value.getMaxScaleOnAxis();
    final t = anim.value.getTranslation();
    _position = Offset(t.x, t.y);
    notifyListeners();
  }

  void _setZoom(double newScale, Offset newPosition) {
    if (newScale != _minScale) {
      _state = newScale > _minScale ? _LeafZoomState.zoomedIn : _LeafZoomState.zoomedOut;
    } else {
      _state = _LeafZoomState.initial;
    }
    final clamped = _clampPosition(newPosition, newScale);
    if (_scale == newScale && _position == clamped) return;
    _scale = newScale;
    _position = clamped;
    notifyListeners();
  }

  void _checkHaptic(double oldScale, double newScale) {
    if (oldScale == newScale) return;
    if ((newScale == _minScale && oldScale != _minScale) || (newScale == maxScale && oldScale != maxScale)) {
      onZoomLimit?.call();
    }
  }

  void _cancelFling() {
    final t = _flingTicker;
    if (t != null && t.isActive) t.stop();
    _flingTicker = null;
    _flingId++;
  }

  void _snapToInitial() {
    _scale = _minScale;
    _position = Offset.zero;
    _state = _LeafZoomState.initial;
    _snapOnCancel = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelFling();
    _animCtrl.removeListener(_onAnimTick);
    _animCtrl.dispose();
    super.dispose();
  }
}
