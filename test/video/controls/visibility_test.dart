import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

void main() {
  group('auto-hide', () {
    testWidgets('hides after the delay; real mouse movement brings them back', (tester) async {
      final v = LeafAutoHideVisibility();
      expect(v.visible.value, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(v.visible.value, isFalse);
      v.pointerMoved(const Offset(10, 10));
      expect(v.visible.value, isTrue);
      await tester.pump(const Duration(seconds: 3));
      expect(v.visible.value, isFalse);
      v.pointerMoved(const Offset(10.2, 10.2));
      expect(v.visible.value, isFalse, reason: 'a widget appearing under a still pointer is no movement');
      v.pointerMoved(const Offset(14, 10));
      expect(v.visible.value, isTrue);
      v.dispose();
    });

    testWidgets('the pointer leaving hides at once, unless held', (tester) async {
      final v = LeafAutoHideVisibility();
      v.pointerExited();
      expect(v.visible.value, isFalse);
      v.wake();
      v.hold(#drag, true);
      await tester.pump();
      v.pointerExited();
      expect(v.visible.value, isTrue);
      v.hold(#drag, false);
      await tester.pump(const Duration(seconds: 3));
      expect(v.visible.value, isFalse);
      v.dispose();
    });

    testWidgets('holds are a set, coalesced in a microtask; held shows, release restarts the countdown', (tester) async {
      final v = LeafAutoHideVisibility();
      await tester.pump(const Duration(seconds: 3));
      expect(v.visible.value, isFalse);
      v.hold(#menu, true);
      v.hold(#menu, true);
      v.hold(#paused, true);
      expect(v.held, isFalse, reason: 'not before the microtask');
      await tester.pump();
      expect(v.held, isTrue);
      expect(v.visible.value, isTrue);
      await tester.pump(const Duration(seconds: 10));
      expect(v.visible.value, isTrue);
      v.hold(#menu, false);
      await tester.pump(const Duration(seconds: 10));
      expect(v.visible.value, isTrue, reason: 'still paused');
      v.hold(#paused, false);
      await tester.pump(const Duration(milliseconds: 2900));
      expect(v.visible.value, isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(v.visible.value, isFalse);
      v.dispose();
    });

    testWidgets('suppress draws them hidden and gives them back as they were', (tester) async {
      final suppress = ValueNotifier(false);
      final v = LeafAutoHideVisibility(suppress: suppress);
      suppress.value = true;
      expect(v.visible.value, isFalse);
      suppress.value = false;
      expect(v.visible.value, isTrue);
      v.dispose();
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('LeafControlsHoldRegion holds while the mouse is on it', (tester) async {
      final hold = LeafControlsHold();
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: LeafControlsHoldRegion(hold: hold, child: const SizedBox(width: 50, height: 50)),
          ),
        ),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.byType(LeafControlsHoldRegion)));
      await tester.pump();
      expect(hold.held, isTrue);
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(hold.held, isFalse);
      await mouse.removePointer();
      hold.dispose();
    });
  });

  group('viewer chrome bridge', () {
    testWidgets('the active bridge is the only writer of chrome.hold', (tester) async {
      final chrome = LeafViewerChrome();
      final a = LeafViewerChromeVisibility(chrome);
      final b = LeafViewerChromeVisibility(chrome);
      a.activate();
      a.hold(#paused, true);
      b.hold(#paused, false);
      await tester.pump();
      expect(a.isOwner, isTrue);
      await tester.pump(const Duration(seconds: 5));
      expect(chrome.visible, isTrue, reason: 'held by the active page');

      b.hold(#menu, true);
      await tester.pump();
      a.hold(#paused, false);
      await tester.pump(const Duration(seconds: 5));
      expect(chrome.visible, isFalse, reason: "the inactive page's hold never reached the chrome");

      a.deactivate();
      b.activate();
      await tester.pump(const Duration(seconds: 5));
      expect(chrome.visible, isTrue, reason: 'the new owner wrote its hold and showed the chrome');
      b.dispose();
      await tester.pump(const Duration(seconds: 5));
      expect(chrome.visible, isFalse, reason: 'released on dispose');
      a.dispose();
      chrome.dispose();
    });

    testWidgets('an inactive page releases the hold', (tester) async {
      final chrome = LeafViewerChrome();
      final a = LeafViewerChromeVisibility(chrome)..activate();
      a.hold(#paused, true);
      await tester.pump();
      a.deactivate();
      await tester.pump(const Duration(seconds: 5));
      expect(chrome.visible, isFalse);
      a.dispose();
      chrome.dispose();
    });

    testWidgets('wake, hide and toggle drive the chrome', (tester) async {
      final chrome = LeafViewerChrome();
      final v = LeafViewerChromeVisibility(chrome)..activate();
      v.hide();
      expect(v.visible.value, isFalse);
      v.toggle();
      expect(v.visible.value, isTrue);
      v.dispose();
      chrome.dispose();
    });
  });
}
