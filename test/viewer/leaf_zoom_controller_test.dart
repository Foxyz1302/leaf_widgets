import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

const viewport = Size(800, 600);

LeafZoomController _make({Size child = const Size(400, 300), Size? original, double maxScale = 5.0}) {
  final ctrl = LeafZoomController(maxScale: maxScale, vsync: TestVSync());
  ctrl.updateLayout(viewport: viewport, childSize: child, originalSize: original);
  return ctrl;
}

// photo_view reference implementations (verified against 0.15.0 source)
(double, double) _pvCorners(Size outer, Size child, double scale, bool vertical) {
  final dim = vertical ? child.height : child.width;
  final outerDim = vertical ? outer.height : outer.width;
  final diff = dim * scale - outerDim;
  return (-diff / 2, diff / 2);
}

Offset _pvClamp(Offset pos, double scale, Size outer, Size child) {
  double fx = 0;
  if (outer.width < child.width * scale) {
    final (min, max) = _pvCorners(outer, child, scale, false);
    fx = pos.dx.clamp(min, max);
  }
  double fy = 0;
  if (outer.height < child.height * scale) {
    final (min, max) = _pvCorners(outer, child, scale, true);
    fy = pos.dy.clamp(min, max);
  }
  return Offset(fx, fy);
}

// First pump starts the ticker (elapsed 0), the second advances past the
// 200ms zoom animation.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  group('clamp & corners (property test vs photo_view formulas)', () {
    for (final child in const [Size(400, 300), Size(300, 200), Size(200, 300), Size(1000, 500)]) {
      for (final scale in const [1.0, 2.0, 3.5, 5.0]) {
        test('viewport $viewport child $child scale $scale', () {
          final ctrl = _make(child: child);
          ctrl.wheelZoom(-(scale - 1) * 1000, viewport.center(Offset.zero));
          ctrl.panBy(const Offset(100000, -100000));
          final expected = _pvClamp(const Offset(100000, -100000), scale.clamp(1.0, 5.0), viewport, child);
          expect(ctrl.scale, scale.clamp(1.0, 5.0));
          expect(ctrl.position.dx, closeTo(expected.dx, 1e-6));
          expect(ctrl.position.dy, closeTo(expected.dy, 1e-6));
        });
      }
    }
  });

  group('edge-release (HitCorners port)', () {
    // child 400x300, scale 3 → X corners ±200, Y corners ±150
    LeafZoomController zoomed() {
      final ctrl = _make(child: const Size(400, 300));
      ctrl.wheelZoom(-2000, const Offset(400, 300));
      expect(ctrl.scale, 3.0);
      return ctrl;
    }

    test('at 1× never claims', () {
      final ctrl = _make();
      expect(ctrl.shouldClaim(const Offset(10, 10)), isFalse);
      expect(ctrl.shouldClaim(const Offset(-10, 0)), isFalse);
    });

    test('free position claims any direction', () {
      final ctrl = zoomed();
      expect(ctrl.shouldClaim(const Offset(10, 10)), isTrue);
      expect(ctrl.shouldClaim(const Offset(-10, 0)), isTrue);
      expect(ctrl.shouldClaim(const Offset(0, -10)), isTrue);
    });

    test('panned right: release on rightward drag, claim on leftward', () {
      final ctrl = zoomed();
      ctrl.panBy(const Offset(10000, 0));
      expect(ctrl.position.dx, 200);
      expect(ctrl.shouldClaim(const Offset(10, 0)), isFalse);
      expect(ctrl.shouldClaim(const Offset(-10, 0)), isTrue);
    });

    test('panned down: release on downward drag, claim on upward', () {
      final ctrl = zoomed();
      ctrl.panBy(const Offset(0, 10000));
      expect(ctrl.position.dy, 150);
      expect(ctrl.shouldClaim(const Offset(0, 10)), isFalse);
      expect(ctrl.shouldClaim(const Offset(0, -10)), isTrue);
    });

    test('fully clamped: release; one free axis: claim (Axis.values)', () {
      final ctrl = zoomed();
      ctrl.panBy(const Offset(10000, 10000));
      expect(ctrl.shouldClaim(const Offset(10, 10)), isFalse);
      ctrl.panBy(const Offset(-10000, 0));
      expect(ctrl.shouldClaim(const Offset(10, 10)), isTrue);
    });

    test('cross-axis drag at edge is a claim when the other axis is free', () {
      final ctrl = zoomed();
      ctrl.panBy(const Offset(10000, 0)); // X max, Y free
      expect(ctrl.shouldClaim(const Offset(0, 10)), isTrue);
      expect(ctrl.shouldClaim(const Offset(10, 10)), isTrue);
    });
  });

  group('double-tap cycle', () {
    testWidgets('1× → covered → 1:1 → 1×', (tester) async {
      final ctrl = _make(child: const Size(300, 200), original: const Size(1200, 800));
      ctrl.doubleTap(const Offset(400, 300));
      await _settle(tester);
      expect(ctrl.scale, closeTo(3.0, 1e-6)); // covered
      ctrl.doubleTap(const Offset(400, 300));
      await _settle(tester);
      expect(ctrl.scale, closeTo(1.5, 1e-6)); // 1:1 = 1/contained(0.667)
      ctrl.doubleTap(const Offset(400, 300));
      await _settle(tester);
      expect(ctrl.scale, closeTo(1.0, 1e-6));
    });

    testWidgets('skips states that change nothing (no originalSize)', (tester) async {
      final ctrl = _make(child: const Size(300, 200));
      ctrl.doubleTap(const Offset(400, 300));
      await _settle(tester);
      expect(ctrl.scale, closeTo(3.0, 1e-6));
      ctrl.doubleTap(const Offset(400, 300));
      await _settle(tester);
      expect(ctrl.scale, closeTo(1.0, 1e-6));
    });

    testWidgets('small image: 1:1 clamps to 1× and is skipped', (tester) async {
      final ctrl = _make(child: const Size(400, 300), original: const Size(400, 300));
      ctrl.doubleTap(const Offset(400, 300));
      await _settle(tester);
      expect(ctrl.scale, closeTo(2.0, 1e-6)); // covered
      ctrl.doubleTap(const Offset(400, 300));
      await _settle(tester);
      expect(ctrl.scale, closeTo(1.0, 1e-6)); // 1:1=0.5 clamped → skipped
    });

    testWidgets('panned/pinched state resets to 1× on double-tap', (tester) async {
      final ctrl = _make(child: const Size(400, 300));
      ctrl.wheelZoom(-2000, const Offset(400, 300)); // zoomedIn via gesture
      ctrl.doubleTap(const Offset(400, 300));
      await _settle(tester);
      expect(ctrl.scale, closeTo(1.0, 1e-6));
      expect(ctrl.position, Offset.zero);
    });

    testWidgets('zoom-in anchors the tap point', (tester) async {
      final ctrl = _make(child: const Size(300, 200), original: const Size(1200, 800));
      // At covered (3×) the Y axis exactly fits (200·3 == 600) → clamped to 0,
      // so tap along X only: target (−20, 0) is inside the ±50 X corners.
      final tap = const Offset(410, 300);
      ctrl.doubleTap(tap);
      await _settle(tester);
      final vpc = viewport.center(Offset.zero);
      final expected = (tap - vpc) * (1 - 3.0);
      expect(ctrl.position.dx, closeTo(expected.dx, 1e-6));
      expect(ctrl.position.dy, closeTo(expected.dy, 1e-6));
      final screen = vpc + ctrl.position + (tap - vpc) * ctrl.scale;
      expect(screen.dx, closeTo(tap.dx, 1e-4));
      expect(screen.dy, closeTo(tap.dy, 1e-4));
    });
  });

  group('gestures', () {
    test('scaleUpdate scales around the focal point and focal-pans', () {
      final ctrl = _make(child: const Size(500, 400));
      ctrl.scaleUpdate(2.0, const Offset(400, 300), const Offset(400, 300));
      expect(ctrl.scale, 2.0);
      expect(ctrl.position, const Offset(-100, -100)); // clamped anchor
      ctrl.scaleUpdate(2.0, const Offset(400, 300), const Offset(430, 320));
      expect(ctrl.position, const Offset(-70, -80)); // focal delta (30, 20)
      expect(ctrl.scale, 2.0);
    });

    test('scaleUpdate with unchanged scale is a pure pan', () {
      final ctrl = _make(child: const Size(500, 400));
      ctrl.scaleUpdate(2.0, const Offset(400, 300), const Offset(400, 300));
      ctrl.scaleUpdate(2.0, const Offset(400, 300), const Offset(430, 320));
      expect(ctrl.position, const Offset(-70, -80));
    });

    test('scaleUpdate clamps to max and fires zoom limit', () {
      var limits = 0;
      final ctrl = _make(child: const Size(400, 300), maxScale: 5.0)..onZoomLimit = () => limits++;
      ctrl.scaleUpdate(100, const Offset(400, 300), const Offset(400, 300));
      expect(ctrl.scale, 5.0);
      expect(limits, 1);
    });

    test('wheel zooms cursor-anchored and clamps', () {
      final ctrl = _make(child: const Size(400, 300));
      ctrl.wheelZoom(-2000, const Offset(200, 150));
      expect(ctrl.scale, 3.0);
      expect(ctrl.position, const Offset(200, 150)); // clamped corner anchor
      ctrl.wheelZoom(2000, const Offset(200, 150));
      expect(ctrl.scale, 1.0);
      expect(ctrl.position, Offset.zero);
    });

    test('wheel fires zoom limit at 1.0 and max', () {
      var limits = 0;
      final ctrl = _make(child: const Size(400, 300))..onZoomLimit = () => limits++;
      ctrl.wheelZoom(-4000, const Offset(400, 300)); // → 5.0
      expect(limits, 1);
      ctrl.wheelZoom(4000, const Offset(400, 300)); // → 1.0
      expect(limits, 2);
    });

    test('pan clamps to corners per axis', () {
      final ctrl = _make(child: const Size(400, 300));
      ctrl.wheelZoom(-2000, const Offset(400, 300)); // 3× → X corners ±200, Y ±150
      ctrl.panBy(const Offset(1000, 1000));
      expect(ctrl.position, const Offset(200, 150));
      ctrl.panBy(const Offset(-3000, -3000));
      expect(ctrl.position, const Offset(-200, -150));
    });

    test('fits axis stays zeroed while the other pans', () {
      final ctrl = _make(child: const Size(300, 200));
      ctrl.wheelZoom(-2000, const Offset(400, 300)); // 3× → X overhang 100 (±50), Y exactly fits → zeroed
      ctrl.panBy(const Offset(1000, 1000));
      expect(ctrl.position.dx, 50);
      expect(ctrl.position.dy, 0);
    });

    test('imageRect is the centered contained rect', () {
      final ctrl = _make(child: const Size(400, 300));
      expect(ctrl.imageRect, const Rect.fromLTWH(200, 150, 400, 300));
      ctrl.wheelZoom(-2000, const Offset(400, 300)); // 3× → 1200×900, corners ±200/±150
      ctrl.panBy(const Offset(100, 50));
      expect(ctrl.imageRect, const Rect.fromLTWH(-100, -100, 1200, 900));
    });
  });

  group('fling', () {
    // Scale 3× with child 400×300 → X overhang 400 (corners ±200), Y overhang 300 (±150).
    LeafZoomController flingZoomed() {
      final ctrl = _make(child: const Size(400, 300));
      ctrl.wheelZoom(-2000, const Offset(400, 300));
      return ctrl;
    }

    testWidgets('decays with friction and stops', (tester) async {
      final ctrl = flingZoomed();
      ctrl.startFling(const Offset(2000, 0));
      expect(ctrl.isFlinging, isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(ctrl.position.dx, greaterThan(0));
      for (var i = 0; i < 300; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (!ctrl.isFlinging) break;
      }
      expect(ctrl.isFlinging, isFalse);
    });

    testWidgets('clamps while flinging', (tester) async {
      final ctrl = flingZoomed();
      ctrl.startFling(const Offset(100000, 0));
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ctrl.position.dx, 200);
      ctrl.cancelGesture();
      await tester.pump();
    });

    testWidgets('tap-to-stop via cancelGesture', (tester) async {
      final ctrl = flingZoomed();
      ctrl.startFling(const Offset(2000, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      ctrl.cancelGesture();
      expect(ctrl.isFlinging, isFalse);
      await tester.pump();
    });
  });

  group('animation interrupt', () {
    testWidgets('cancel mid-zoom-in keeps the current frame', (tester) async {
      final ctrl = _make(child: const Size(300, 200));
      ctrl.doubleTap(const Offset(400, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      ctrl.cancelGesture();
      expect(ctrl.scale, greaterThan(1.0));
      expect(ctrl.scale, lessThan(3.0));
    });

    testWidgets('cancel mid-zoom-out snaps to 1×', (tester) async {
      final ctrl = _make(child: const Size(300, 200));
      ctrl.doubleTap(const Offset(400, 300));
      await _settle(tester); // covered
      ctrl.doubleTap(const Offset(400, 300)); // → 1×
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      ctrl.cancelGesture();
      expect(ctrl.scale, 1.0);
      expect(ctrl.position, Offset.zero);
    });
  });

  group('layout changes', () {
    test('cycle states recompute on layout change', () {
      final ctrl = _make(child: const Size(300, 200));
      // covered = 3 at 800×600
      // force state via wheel? states only change via doubleTap/gestures; use doubleTap in testWidgets? plain test: wheelZoom sets zoomedIn (kept).
      ctrl.updateLayout(viewport: const Size(400, 300), childSize: const Size(300, 200));
      expect(ctrl.scale, 1.0);
      // zoomedIn state keeps its scale
      ctrl.wheelZoom(-1000, const Offset(200, 150));
      expect(ctrl.scale, 2.0);
      ctrl.updateLayout(viewport: const Size(400, 300), childSize: const Size(300, 200));
      expect(ctrl.scale, 2.0);
      expect(ctrl.position, Offset.zero); // reclamped
    });
  });
}
