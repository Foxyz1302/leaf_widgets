import 'package:flutter/gestures.dart';

/// Multi-touch pan/pinch recognizer for [LeafViewer] pages.
///
/// Ported from photo_view's `PhotoViewGestureRecognizer` (MIT): a
/// [ScaleGestureRecognizer] that decides per move event whether to claim the
/// gesture via [shouldClaim].
///
/// Unlike photo_view, the decision is made once on the first meaningful move
/// (beyond finger-jitter tolerance) and resolved immediately (accept or
/// reject) — this prevents the recognizer's own slop-based auto-accept
/// (18-36px, see `_advanceStateMachine`) from outracing the PageView's drag
/// (18px) on large per-event deltas.
///
/// Rejecting leaves the arena to the parent (the PageView's horizontal drag
/// or the viewer's dismiss drag) — this is what makes edge-release work: a
/// drag starting at a fully clamped position pages/dismisses instead of
/// panning.
///
/// This recognizer must NOT touch the base's private bookkeeping
/// (`_pointerLocations`, `_initialFocalPoint`, `_currentFocalPoint`):
/// [ScaleGestureRecognizer.handleEvent] recomputes its own focal/span state
/// from those fields on every event, and re-stamping them here corrupts the
/// pinch anchor and the double-tap arena.
class LeafPanZoomRecognizer extends ScaleGestureRecognizer {
  LeafPanZoomRecognizer({required this.shouldClaim, super.debugOwner});

  /// Whether a pan with the given finger delta should be claimed.
  final bool Function(Offset fingerDelta) shouldClaim;

  /// Movement under this distance is treated as finger jitter — it never
  /// decides the claim, letting a double-tap run its course on a noisy tap.
  static const double _jitterSlop = 4.0;

  int _activePointers = 0;
  Offset _moveDelta = Offset.zero;
  int? _movingPointer;
  bool _claimDecided = false;
  bool _claimed = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _activePointers++;
    super.addAllowedPointer(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _activePointers = 0;
    _moveDelta = Offset.zero;
    _movingPointer = null;
    _claimDecided = false;
    _claimed = false;
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent && !event.synthesized) {
      if (event.pointer == _movingPointer) {
        _moveDelta += event.localDelta;
      } else {
        _movingPointer = event.pointer;
        _moveDelta = event.localDelta;
      }

      if (!_claimDecided && !_claimed && _moveDelta.distance > _jitterSlop) {
        _claimDecided = true;
        if (_activePointers > 1 || shouldClaim(_moveDelta)) {
          _claimed = true;
          // Full arena claim (NOT acceptGesture alone — that only sets the
          // local state, leaving the arena open so another member can later
          // win and reject us while `started`). The base handler then runs
          // safely: the arena is already resolved in our favor.
          resolve(GestureDisposition.accepted);
          super.handleEvent(event);
          return;
        }
        // Reject BEFORE the base's own auto-accept (pan slop 18-36px): the
        // arena removes us and stops tracking (state becomes `ready`), so
        // `super.handleEvent` must not run — it asserts on `ready` state.
        resolve(GestureDisposition.rejected);
        return;
      }
    }

    super.handleEvent(event);
  }
}
