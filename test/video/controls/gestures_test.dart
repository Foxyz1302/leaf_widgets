import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

import 'kit_fakes.dart';

class _Fs implements LeafFullscreenHandle {
  _Fs(this.c);

  final LeafPlayerController c;
  int toggles = 0;

  @override
  bool get canFullscreen => true;
  @override
  void enterFullscreen() {
    toggles++;
    c.setFullscreen(true);
  }

  @override
  void exitFullscreen() {
    toggles++;
    c.setFullscreen(false);
  }
}

void main() {
  testWidgets('touch: double-tap the sides seeks ±10 s and adds up; the middle plays; a tap toggles', (tester) async {
    final a = FullKitAdapter();
    final c = LeafPlayerController(a);
    a.emitPosition(secs(100));
    await tester.pumpWidget(kitHarness(c, spec: LeafControlsSpec.mobile, size: const Size(900, 450)));
    final box = tester.getRect(find.byType(LeafPlayerControls));
    Future<void> doubleTap(Offset at) async {
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
    }

    await doubleTap(Offset(box.right - 40, box.top + 100));
    await doubleTap(Offset(box.right - 40, box.top + 100));
    expect(a.seeks, [secs(110), secs(120)]);
    expect(find.text('+20 s'), findsOneWidget);
    await doubleTap(Offset(box.left + 40, box.top + 100));
    expect(a.seeks.last, secs(110));
    await tester.pump(const Duration(seconds: 1));
    final before = a.plays + a.pauses;
    await doubleTap(Offset(box.center.dx, box.top + 100));
    expect(a.plays + a.pauses, before + 1);
    a.emitPlaying(true);
    await tester.pump(const Duration(milliseconds: 400));
    final shown = c.controlsVisible.value;
    await tester.tapAt(Offset(box.left + 40, box.top + 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.controlsVisible.value, !shown);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('mouse: click plays at once; double-click on the picture goes fullscreen, not on the bars', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final a = FullKitAdapter();
    final c = LeafPlayerController(a);
    final fs = _Fs(c);
    c.attachFullscreen(fs);
    await tester.pumpWidget(kitHarness(c, spec: LeafControlsSpec.desktop, size: const Size(900, 500)));
    final box = tester.getRect(find.byType(LeafPlayerControls));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: box.center);
    await mouse.down(box.center);
    expect(a.plays, 1, reason: 'on pointer-down, no double-tap wait');
    await mouse.up();
    await mouse.down(box.center);
    await mouse.up();
    expect(fs.toggles, 1);
    await tester.pump(const Duration(milliseconds: 500));
    final time = tester.getCenter(find.byKey(const ValueKey('leaf-control-time')));
    final barSpot = Offset(time.dx + 200, time.dy);
    await mouse.moveTo(barSpot);
    await mouse.down(barSpot);
    await mouse.up();
    await mouse.down(barSpot);
    await mouse.up();
    expect(fs.toggles, 1, reason: 'the bar absorbs clicks');
    await mouse.removePointer();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop: hides after the delay while playing, mouse movement wakes; paused holds', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final a = FullKitAdapter();
    final c = LeafPlayerController(a);
    await tester.pumpWidget(kitHarness(c, spec: LeafControlsSpec.uosc));
    await tester.pump(const Duration(seconds: 4));
    expect(c.controlsVisible.value, isTrue, reason: 'paused');
    a.emitPlaying(true);
    await tester.pump(const Duration(seconds: 4));
    expect(c.controlsVisible.value, isFalse);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(300, 200));
    await mouse.moveTo(const Offset(320, 210));
    await tester.pump();
    expect(c.controlsVisible.value, isTrue);
    await mouse.removePointer();
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
