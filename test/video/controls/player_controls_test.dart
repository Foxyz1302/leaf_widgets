import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';
import 'package:leaf_widgets/src/video/controls/media_math.dart' show chaptersFromStarts;

import 'kit_fakes.dart';

const _presets = {
  'mobile': LeafControlsSpec.mobile,
  'desktop': LeafControlsSpec.desktop,
  'uosc': LeafControlsSpec.uosc,
  'minimal': LeafControlsSpec.minimal,
};

const _widths = [320.0, 360.0, 412.0, 800.0, 1280.0, 1920.0, 2560.0, 3440.0];

int _count<T extends Layer>(Layer root) {
  var n = 0;
  void visit(Layer l) {
    if (l is T) n++;
    if (l is ContainerLayer) {
      var c = l.firstChild;
      while (c != null) {
        visit(c);
        c = c.nextSibling;
      }
    }
  }

  visit(root);
  return n;
}

FullKitAdapter _playing() {
  final a = FullKitAdapter(total: const Duration(minutes: 24));
  a.durationCtrl.add(const Duration(minutes: 24));
  return a;
}

void main() {
  for (final MapEntry(key: name, value: spec) in _presets.entries) {
    testWidgets('$name: every width without overflow, both windowed and fullscreen', (tester) async {
      debugDefaultTargetPlatformOverride = name == 'mobile' ? TargetPlatform.android : TargetPlatform.linux;
      tester.view.devicePixelRatio = 1;
      for (final w in _widths) {
        tester.view.physicalSize = Size(w, w * 9 / 16 + 100);
        final a = _playing()
          ..chapterList = chaptersFromStarts([('A', Duration.zero), ('OP', secs(30)), ('B', secs(120))], const Duration(minutes: 24));
        final c = LeafPlayerController(a, actions: const LeafPlayerActions(title: 'A long episode title that has to ellipsize somewhere', onNext: _noop, onPrevious: _noop));
        for (final full in [false, true]) {
          await tester.pumpWidget(kitHarness(c, spec: spec, size: Size(w, w * 9 / 16), fullscreen: full));
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$name at $w${full ? ' fullscreen' : ''}');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        c.dispose();
      }
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('desktop: the bottom row is drawn in the layout order', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final a = _playing()..chapterList = chaptersFromStarts([('A', Duration.zero), ('B', secs(60))], const Duration(minutes: 24));
    final fs = _Fs();
    final c = LeafPlayerController(a, actions: const LeafPlayerActions(onNext: _noop, onPrevious: _noop))..attachFullscreen(fs);
    await tester.pumpWidget(kitHarness(c, spec: LeafControlsSpec.desktop, size: const Size(1280, 720)));
    final ids = ['playPause', 'previous', 'next', 'chapterPrevious', 'chapterNext', 'volume', 'time', 'fullscreen'];
    final xs = [for (final id in ids) tester.getCenter(find.byKey(ValueKey('leaf-control-$id'))).dx];
    expect(xs, orderedEquals([...xs]..sort()));
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('hidden: no seek bar, no position listeners, nothing ticking (mobile)', (tester) async {
    final a = _playing();
    final c = LeafPlayerController(a);
    await tester.pumpWidget(kitHarness(c, spec: LeafControlsSpec.mobile));
    a.emitPlaying(true);
    await tester.pump();
    expect(find.byType(LeafSeekBar), findsOneWidget);
    expect(c.debugPositionListeners, greaterThan(0));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    expect(c.controlsVisible.value, isFalse);
    expect(find.byType(LeafSeekBar), findsNothing);
    expect(c.debugPositionListeners, 0);
    for (var i = 0; i < 30; i++) {
      a.emitPosition(Duration(milliseconds: 33 * i));
    }
    await tester.pump(const Duration(milliseconds: 16));
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('hidden on desktop: only the progress line listens', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final a = _playing();
    final c = LeafPlayerController(a);
    await tester.pumpWidget(kitHarness(c, spec: LeafControlsSpec.desktop));
    a.emitPlaying(true);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('leaf-progress-line')), findsOneWidget);
    expect(c.debugPositionListeners, 1);
    expect(SchedulerBinding.instance.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final MapEntry(key: name, value: spec) in _presets.entries) {
    testWidgets('$name: no BackdropFilter, no OpacityLayer once settled', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox.expand())));
      await tester.pump(const Duration(milliseconds: 300));
      final baseline = _count<OpacityLayer>(tester.binding.renderViews.first.debugLayer!);
      final a = _playing();
      final c = LeafPlayerController(a);
      await tester.pumpWidget(kitHarness(c, spec: spec));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(BackdropFilter), findsNothing);
      final root = tester.binding.renderViews.first.debugLayer!;
      expect(_count<BackdropFilterLayer>(root), 0);
      expect(_count<OpacityLayer>(root), baseline);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
  }

  testWidgets('a parent rebuild stops at the host', (tester) async {
    var builds = 0;
    final probe = LeafControl.widget(
      id: 'probe',
      width: 10,
      builder: (context) {
        builds++;
        return const SizedBox(width: 10, height: 10);
      },
    );
    final spec = LeafControlsSpec(layout: const LeafControlsLayout().withSlot(LeafSlot.bottomStart, [LeafControl.playPause, probe]));
    final c = LeafPlayerController(_playing());
    final tick = ValueNotifier(0);
    await tester.pumpWidget(
      ValueListenableBuilder<int>(
        valueListenable: tick,
        builder: (context, v, _) => kitHarness(c, spec: spec),
      ),
    );
    final before = builds;
    for (var i = 0; i < 5; i++) {
      tick.value++;
      await tester.pump();
    }
    expect(builds, before);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  group('layout', () {
    test('presets carry the documented items', () {
      List<String> ids(LeafControlsSpec s, LeafSlot slot) => [for (final c in s.layout[slot]) c.id];
      expect(ids(LeafControlsSpec.desktop, LeafSlot.bottomStart), [
        'playPause',
        'previous',
        'next',
        'chapterPrevious',
        'chapterNext',
        'volume',
        'time',
      ]);
      expect(ids(LeafControlsSpec.uosc, LeafSlot.bottomBelow), ['seekBar']);
      expect(LeafControlsSpec.uosc.layout.capsules, isTrue);
      expect(ids(LeafControlsSpec.mobile, LeafSlot.center), ['previous', 'bigPlay', 'next', 'buffering']);
      expect(ids(LeafControlsSpec.mobile.fullscreen!, LeafSlot.topStart), ['back', 'title']);
      expect(ids(LeafControlsSpec.minimal, LeafSlot.center), ['bigPlayWhilePaused', 'buffering']);
      expect(LeafControlsSpec.adaptive().resolve(desktop: true), LeafControlsSpec.uosc);
      expect(LeafControlsSpec.adaptive().resolve(desktop: false), LeafControlsSpec.mobile);
    });

    test('withSlot, without, insertAfter / insertBefore', () {
      final l = LeafControlsSpec.desktop.layout
          .without({'chapterPrevious', 'chapterNext'})
          .insertAfter('playPause', LeafControl.seekBy(const Duration(seconds: 10)))
          .insertBefore('playPause', LeafControl.seekBy(const Duration(seconds: -10)))
          .withSlot(LeafSlot.topEnd, [LeafControl.fullscreen]);
      expect([for (final c in l[LeafSlot.bottomStart]) c.id], ['seekBy-10', 'playPause', 'seekBy10', 'previous', 'next', 'volume', 'time']);
      expect(l[LeafSlot.topEnd].single.id, 'fullscreen');
    });

    test('fromIds and toIds round-trip (the line seek bar is the catalog one)', () {
      final ids = LeafControlsSpec.desktop.layout.toIds();
      final back = LeafControlsLayout.fromIds(ids);
      expect(back.toIds(), ids);
      expect(LeafControlsLayout.fromIds({LeafSlot.bottomStart: ['playPause', 'nope']}).toIds(), {
        LeafSlot.bottomStart: ['playPause'],
      });
    });

    testWidgets('hidden ids and missing capabilities drop items; availability follows the media', (tester) async {
      final a = KitAdapter();
      final c = LeafPlayerController(a);
      final spec = LeafControlsSpec(layout: const LeafControlsLayout().withSlot(LeafSlot.bottomStart, [LeafControl.playPause, LeafControl.volume, LeafControl.time]));
      await tester.pumpWidget(kitHarness(c, spec: spec));
      expect(find.byKey(const ValueKey('leaf-control-volume')), findsNothing, reason: 'no HasVolume');
      c.prefs.hidden = {'time'};
      await tester.pump();
      expect(find.byKey(const ValueKey('leaf-control-time')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();

      final f = FullKitAdapter();
      final c2 = LeafPlayerController(f);
      final chapterSpec = LeafControlsSpec(layout: const LeafControlsLayout().withSlot(LeafSlot.bottomStart, [LeafControl.chapterNext]));
      await tester.pumpWidget(kitHarness(c2, spec: chapterSpec));
      expect(find.byKey(const ValueKey('leaf-control-chapterNext')), findsNothing);
      f.chaptersCtrl.add(chaptersFromStarts([('A', Duration.zero), ('B', secs(60))], const Duration(minutes: 24)));
      await tester.pump();
      expect(find.byKey(const ValueKey('leaf-control-chapterNext')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      c2.dispose();
    });
  });
}

void _noop() {}

class _Fs implements LeafFullscreenHandle {
  @override
  bool get canFullscreen => true;
  @override
  void enterFullscreen() {}
  @override
  void exitFullscreen() {}
}
