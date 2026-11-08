import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

import 'kit_fakes.dart';

void main() {
  testWidgets('no controls and no defaults: the legacy controls, unchanged', (tester) async {
    await tester.pumpWidget(MaterialApp(home: LeafVideoPage(createAdapter: KitAdapter.new, url: 'u')));
    await tester.pump();
    expect(find.byType(LeafVideoControls), findsOneWidget);
    expect(find.byType(LeafPlayerControls), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('LeafPlayerDefaults(controls:) switches pages without a controlsBuilder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LeafPlayerDefaults(
          controls: LeafControlsSpec.minimal,
          child: Column(
            children: [
              Expanded(child: LeafVideoPage(createAdapter: KitAdapter.new, url: 'a')),
              Expanded(
                child: LeafVideoPage(
                  createAdapter: KitAdapter.new,
                  url: 'b',
                  controlsBuilder: (context, adapter) => const SizedBox(key: ValueKey('own')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(LeafPlayerControls), findsOneWidget);
    expect(find.byKey(const ValueKey('own')), findsOneWidget);
    expect(find.byType(LeafVideoControls), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });

  test('controls and controlsBuilder together assert', () {
    expect(
      () => LeafVideoPage(createAdapter: KitAdapter.new, url: 'u', controls: LeafControlsSpec.mobile, controlsBuilder: (_, _) => const SizedBox()),
      throwsAssertionError,
    );
  });

  testWidgets('in a chrome-enabled viewer: paused holds the chrome, playing lets it hide; the page never writes the hold', (tester) async {
    final adapters = <KitAdapter>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LeafViewer(
          pageCount: 3,
          enableSwipeGestures: true,
          enableChrome: true,
          pageBuilder: (context, i) => LeafVideoPage(
            createAdapter: () => KitAdapter()..let(adapters.add),
            url: 'u$i',
            controls: LeafControlsSpec.mobile,
          ),
        ),
      ),
    );
    await tester.pump();
    final chrome = LeafViewer.chromeOf(tester.element(find.byType(LeafVideoPage).first))!;
    expect(adapters.first.isPlaying, isTrue);
    await tester.pump(const Duration(seconds: 4));
    expect(chrome.visible, isFalse, reason: 'playing: the chrome auto-hides');
    adapters.first.pause();
    await tester.pump();
    expect(chrome.visible, isTrue, reason: 'paused: shown and held');
    await tester.pump(const Duration(seconds: 5));
    expect(chrome.visible, isTrue);
    expect(find.byType(LeafPlayerControls), findsOneWidget, reason: 'controls only on the settled page');

    await tester.tap(find.byKey(const ValueKey('leaf-control-next')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(LeafViewer.currentIndexListOf(tester.element(find.byType(LeafVideoPage).first))!.value, 1);
    adapters[1].play();
    await tester.pump(const Duration(seconds: 4));
    expect(chrome.visible, isFalse, reason: "the old page's paused hold left with it");
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });
  testWidgets('desktop viewer: bare arrows still page, Shift+arrows seek; the kit takes focus on a click', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final adapters = <KitAdapter>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LeafViewer(
          pageCount: 3,
          pageBuilder: (context, i) => LeafVideoPage(
            createAdapter: () => KitAdapter()..let(adapters.add),
            url: 'u$i',
            controls: LeafControlsSpec.uosc,
          ),
        ),
      ),
    );
    await tester.pump();
    final index = LeafViewer.currentIndexListOf(tester.element(find.byType(LeafVideoPage).first))!;
    await tester.tapAt(const Offset(400, 200), kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'LeafPlayerControls');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(adapters.first.seeks, [const Duration(seconds: 1)]);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(index.value, 1);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'LeafPlayerControls', reason: 'the settled page took focus from the viewer');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
    debugDefaultTargetPlatformOverride = null;
  });
}

extension<T> on T {
  T let(void Function(T) f) {
    f(this);
    return this;
  }
}
