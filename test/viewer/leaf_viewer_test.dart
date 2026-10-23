import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

Widget _zoomablePage(BuildContext context, int i) => LeafZoomable(
      childSize: const Size(400, 300),
      originalSize: const Size(1600, 1200),
      child: Container(color: const Color(0xFF112233)),
    );

Widget _harness({
  Widget Function(BuildContext, int)? pageBuilder,
  ValueChanged<int>? onPageChanged,
  VoidCallback? onDismissed,
  VoidCallback? onTapOutside,
  ValueChanged<double>? onProgress,
  bool? enableSwipeGestures,
}) {
  return MaterialApp(
    home: Scaffold(
      body: LeafViewer(
        pageCount: 3,
        pageBuilder: pageBuilder ?? _zoomablePage,
        onPageChanged: onPageChanged,
        onDismissed: onDismissed,
        onTapOutside: onTapOutside,
        enableSwipeGestures: enableSwipeGestures,
        backgroundBuilder: onProgress == null
            ? null
            : (context, p) {
                onProgress(p);
                return Container(color: Colors.black);
              },
      ),
    ),
  );
}

LeafZoomController _controller(WidgetTester tester) {
  return LeafViewer.controllerOf(tester.element(find.byType(LeafZoomable)))!;
}

Future<void> _slowDrag(WidgetTester tester, Offset from, Offset delta, {int steps = 8}) async {
  final g = await tester.startGesture(from);
  await tester.pump();
  final step = delta / steps.toDouble();
  for (var i = 0; i < steps; i++) {
    await g.moveBy(step);
    await tester.pump(const Duration(milliseconds: 200));
  }
  await g.up();
  await tester.pumpAndSettle();
}

Future<void> _doubleTapAt(WidgetTester tester, Offset pos) async {
  await tester.tapAt(pos);
  await tester.pump(const Duration(milliseconds: 50));
  await tester.tapAt(pos);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _wheel(WidgetTester tester, double dy) async {
  await tester.sendEventToBinding(PointerScrollEvent(
    position: const Offset(400, 300),
    scrollDelta: Offset(0, dy),
    kind: PointerDeviceKind.mouse,
  ));
  await tester.pump();
}

// Pinch from (300,300)/(500,300) outward so the finger distance reaches [targetDist].
Future<void> _pinchOut(WidgetTester tester, double targetDist) async {
  final g1 = await tester.startGesture(const Offset(300, 300));
  final g2 = await tester.startGesture(const Offset(500, 300));
  await tester.pump();
  final spread = targetDist - 200;
  await g1.moveTo(Offset(300 - spread / 2, 300));
  await g2.moveTo(Offset(500 + spread / 2, 300));
  await tester.pump();
  await g1.up();
  await g2.up();
  await tester.pump(const Duration(milliseconds: 350)); // flush double-tap countdown
}

void main() {
  testWidgets('1× horizontal drag pages', (tester) async {
    var page = 0;
    await tester.pumpWidget(_harness(onPageChanged: (i) => page = i));
    await _slowDrag(tester, const Offset(700, 300), const Offset(-500, 0));
    expect(page, 1);
  });

  testWidgets('mouse drag pages (dragDevices fix)', (tester) async {
    var page = 0;
    await tester.pumpWidget(_harness(onPageChanged: (i) => page = i));
    final g = await tester.startGesture(const Offset(700, 300), kind: PointerDeviceKind.mouse);
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await g.moveBy(const Offset(-62.5, 0));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(page, 1);
  });

  testWidgets('zoomed pan does not page', (tester) async {
    var page = 0;
    await tester.pumpWidget(_harness(onPageChanged: (i) => page = i));
    await _pinchOut(tester, 600); // 3×, anchored at (-50,-150)
    final ctrl = _controller(tester);
    expect(ctrl.scale, 3.0);
    await _slowDrag(tester, const Offset(700, 300), const Offset(150, 0)); // pan right
    expect(ctrl.position.dx, 100);
    expect(page, 0);
  });

  testWidgets('zoomed + clamped at edge releases mid-drag and pages', (tester) async {
    var page = 0;
    await tester.pumpWidget(_harness(onPageChanged: (i) => page = i));
    await _pinchOut(tester, 600); // 3× at (-50,-150)
    final ctrl = _controller(tester);
    await _slowDrag(tester, const Offset(700, 300), const Offset(-250, 0)); // pan to X clamp
    expect(ctrl.position.dx, -200);
    expect(page, 0);
    await _slowDrag(tester, const Offset(700, 300), const Offset(-500, 0)); // released at edge → pages
    expect(page, 1);
  });

  testWidgets('zoomed + clamped vertically: continuing the drag dismisses', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(_harness(onDismissed: () => dismissed = true));
    await _pinchOut(tester, 600); // 3×, Y clamped at -150
    // Drag further up from the top clamp → edge-release dismiss (offset > 25%).
    await _slowDrag(tester, const Offset(400, 400), const Offset(0, -300), steps: 6);
    expect(dismissed, isTrue);
  });

  testWidgets('1× small vertical drag springs back without dismissing', (tester) async {
    var dismissed = false;
    var progress = 1.0;
    await tester.pumpWidget(_harness(onDismissed: () => dismissed = true, onProgress: (p) => progress = p));
    await tester.timedDrag(find.byType(LeafViewer), const Offset(0, 100), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(dismissed, isFalse);
    expect(progress, lessThan(0.001)); // spring settles asymptotically, never exactly 0
  });

  testWidgets('dismiss drag and spring-back do not re-invoke pageBuilder', (tester) async {
    final counts = <int, int>{};
    var frames = 0;
    await tester.pumpWidget(_harness(
      pageBuilder: (context, i) {
        counts[i] = (counts[i] ?? 0) + 1;
        return _zoomablePage(context, i);
      },
      onProgress: (_) => frames++,
    ));
    final before = Map.of(counts);
    await tester.timedDrag(find.byType(LeafViewer), const Offset(0, 100), const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(frames, greaterThan(5));
    expect(counts, before);
  });

  testWidgets('1× vertical drag past 25% flies off and dismisses', (tester) async {
    var dismissed = false;
    var sawProgress = false;
    await tester.pumpWidget(_harness(onDismissed: () => dismissed = true, onProgress: (p) {
      if (p > 0.2) sawProgress = true;
    }));
    await tester.timedDrag(find.byType(LeafViewer), const Offset(0, 400), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
    expect(sawProgress, isTrue);
  });

  testWidgets('1× fast small drag flies off via velocity', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(_harness(onDismissed: () => dismissed = true));
    await tester.timedDrag(find.byType(LeafViewer), const Offset(0, 100), const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });

  testWidgets('1× vertical drag anywhere dismisses (no off-image gate)', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(_harness(onDismissed: () => dismissed = true));
    // Image rect is (200,150,400,300) — starting above it still dismisses.
    await tester.timedDragFrom(const Offset(400, 40), const Offset(0, 400), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });

  testWidgets('tap outside the image pops, tap on the image does not', (tester) async {
    var outside = 0;
    await tester.pumpWidget(_harness(onTapOutside: () => outside++));
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 350)); // flush double-tap countdown
    expect(outside, 1);
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 350));
    expect(outside, 1);
  });

  testWidgets('wheel zooms from any scale in both directions', (tester) async {
    await tester.pumpWidget(_harness());
    await _wheel(tester, -1000);
    expect(_controller(tester).scale, closeTo(2.0, 0.01)); // zooms from 1×
    await _wheel(tester, -1000);
    expect(_controller(tester).scale, closeTo(4.0, 0.01));
    await _wheel(tester, 3000);
    expect(_controller(tester).scale, closeTo(1.0, 0.01));
    await _wheel(tester, 1000); // at 1×, wheel down clamps
    expect(_controller(tester).scale, 1.0);
  });

  testWidgets('double-tap cycles 1× → covered → 1:1 → 1× through the viewer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LeafViewer(
          pageCount: 3,
          pageBuilder: (context, i) => LeafZoomable(
            childSize: const Size(360, 300),
            originalSize: const Size(1440, 1200),
            child: Container(color: const Color(0xFF112233)),
          ),
        ),
      ),
    ));
    await _doubleTapAt(tester, const Offset(400, 300));
    expect(_controller(tester).scale, closeTo(2.22, 0.01)); // covered
    await _doubleTapAt(tester, const Offset(400, 300));
    expect(_controller(tester).scale, closeTo(2.0, 0.01)); // 1:1
    await _doubleTapAt(tester, const Offset(400, 300));
    expect(_controller(tester).scale, closeTo(1.0, 0.01));
  });

  testWidgets('pinch zooms around the focal point and focal-pans', (tester) async {
    await tester.pumpWidget(_harness());
    final g1 = await tester.startGesture(const Offset(300, 300));
    final g2 = await tester.startGesture(const Offset(500, 300));
    await tester.pump();
    await g1.moveTo(const Offset(100, 300)); // dist 400 → 2×, clamped to (0,0)
    await tester.pump();
    await g2.moveTo(const Offset(700, 300)); // dist 600 → 3×, anchored at (-50,-150)
    await tester.pump();
    final ctrl = _controller(tester);
    expect(ctrl.scale, closeTo(3.0, 1e-6));
    expect(ctrl.position, const Offset(-50, -150));
    await g1.moveBy(const Offset(50, 0)); // focal pan, distance unchanged
    await g2.moveBy(const Offset(50, 0));
    await tester.pump();
    expect(ctrl.position.dx, closeTo(0, 0.01));
    expect(ctrl.position.dy, closeTo(-150, 0.01));
    await g1.up();
    await g2.up();
    await tester.pump(const Duration(milliseconds: 350)); // flush double-tap countdown
  });

  testWidgets('per-page zoom state survives page switches', (tester) async {
    var page = 0;
    await tester.pumpWidget(_harness(onPageChanged: (i) => page = i));
    await _pinchOut(tester, 600); // page 0 zoomed to 3×
    await _slowDrag(tester, const Offset(700, 300), const Offset(-250, 0)); // pan to X clamp
    await _slowDrag(tester, const Offset(700, 300), const Offset(-500, 0)); // released at edge → page 1
    expect(page, 1);
    await _slowDrag(tester, const Offset(100, 300), const Offset(500, 0)); // page 0
    expect(page, 0);
    final ctrl = _controller(tester);
    expect(ctrl.scale, 3.0); // still zoomed
    expect(ctrl.position, const Offset(-200, -150)); // still clamped
  });

  testWidgets('pages without LeafZoomable dismiss and page but never pop', (tester) async {
    var dismissed = false;
    var outside = 0;
    var page = 0;
    await tester.pumpWidget(_harness(
      pageBuilder: (context, i) => Center(child: Text('page $i')),
      onDismissed: () => dismissed = true,
      onTapOutside: () => outside++,
      onPageChanged: (i) => page = i,
    ));
    await tester.tapAt(const Offset(10, 10));
    await tester.pump(const Duration(milliseconds: 350));
    expect(outside, 0);
    await _slowDrag(tester, const Offset(700, 300), const Offset(-500, 0));
    expect(page, 1);
    await tester.timedDrag(find.byType(LeafViewer), const Offset(0, 400), const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(dismissed, isTrue);
  });

  group('desktop mode', () {
    testWidgets('mouse drag at 1× neither pages nor dismisses', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      var page = 0;
      var dismissed = false;
      await tester.pumpWidget(_harness(onPageChanged: (i) => page = i, onDismissed: () => dismissed = true));
      final g = await tester.startGesture(const Offset(600, 300), kind: PointerDeviceKind.mouse);
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await g.moveBy(const Offset(-62.5, 0));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 350));
      expect(page, 0);
      final g2 = await tester.startGesture(const Offset(400, 200), kind: PointerDeviceKind.mouse);
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await g2.moveBy(const Offset(0, 37.5));
        await tester.pump(const Duration(milliseconds: 25));
      }
      await g2.up();
      await tester.pump(const Duration(milliseconds: 350));
      expect(dismissed, isFalse);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('double-tap does nothing on desktop', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(_harness());
      await _doubleTapAt(tester, const Offset(400, 300));
      expect(_controller(tester).scale, 1.0);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('zoomed mouse drag pans', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(_harness());
      await _pinchOut(tester, 600); // 3× via touch pinch
      final ctrl = _controller(tester);
      final g = await tester.startGesture(const Offset(700, 300), kind: PointerDeviceKind.mouse);
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await g.moveBy(const Offset(-18.75, 0));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await g.up();
      await tester.pump(const Duration(milliseconds: 350));
      expect(ctrl.position.dx, lessThan(0));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('default controls show on desktop and page via buttons', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      var page = 0;
      await tester.pumpWidget(_harness(onPageChanged: (i) => page = i));
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(page, 1);
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
      expect(page, 0);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('custom controlsBuilder replaces the default', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeafViewer(
            pageCount: 3,
            pageBuilder: _zoomablePage,
            controlsBuilder: (context, controls) => Text('custom ${controls.currentIndex}'),
          ),
        ),
      ));
      expect(find.text('custom 0'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('close button pops the route', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(body: LeafViewer(pageCount: 3, pageBuilder: _zoomablePage)),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LeafViewer), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(LeafViewer), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('paging via buttons does not rebuild pages (no black flash)', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final counts = <int, int>{};
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeafViewer(
            pageCount: 3,
            pageBuilder: (context, i) {
              counts[i] = (counts[i] ?? 0) + 1;
              return _zoomablePage(context, i);
            },
          ),
        ),
      ));
      expect(counts[0], 1);
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(counts[0], 1); // existing pages are never re-invoked
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('enableSwipeGestures: true emulates touch on desktop', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      var page = 0;
      var dismissed = false;
      await tester.pumpWidget(_harness(
        enableSwipeGestures: true,
        onPageChanged: (i) => page = i,
        onDismissed: () => dismissed = true,
      ));
      final g = await tester.startGesture(const Offset(600, 300), kind: PointerDeviceKind.mouse);
      await tester.pump();
      for (var i = 0; i < 8; i++) {
        await g.moveBy(const Offset(-62.5, 0));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(page, 1); // mouse swipe pages
      await tester.timedDrag(find.byType(LeafViewer), const Offset(0, 400), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(dismissed, isTrue); // mouse drag dismisses
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('enableSwipeGestures: true enables double-tap on desktop', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(_harness(enableSwipeGestures: true));
      await _doubleTapAt(tester, const Offset(400, 300));
      expect(_controller(tester).scale, greaterThan(1.0));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('enableSwipeGestures: false disables touch gestures on touch platforms', (tester) async {
      var dismissed = false;
      await tester.pumpWidget(_harness(enableSwipeGestures: false, onDismissed: () => dismissed = true));
      await tester.timedDrag(find.byType(LeafViewer), const Offset(0, 400), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(dismissed, isFalse);
      await _doubleTapAt(tester, const Offset(400, 300));
      expect(_controller(tester).scale, 1.0);
    });

    testWidgets('dismiss without onDismissed pops the route', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => Scaffold(
                  body: LeafViewer(pageCount: 3, pageBuilder: _zoomablePage, enableSwipeGestures: true),
                ),
              )),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.timedDrag(find.byType(LeafViewer), const Offset(0, 400), const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byType(LeafViewer), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
