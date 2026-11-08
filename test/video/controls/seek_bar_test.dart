import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';
import 'package:leaf_widgets/src/video/controls/items/seek_bar.dart' show RenderLeafSeekBar;
import 'package:leaf_widgets/src/video/controls/media_math.dart' show chaptersFromStarts;

import 'kit_fakes.dart';

const _total = Duration(seconds: 100);

LeafControlsTheme get _theme => LeafControlsTheme.forLook(LeafLook.material, const ColorScheme.dark());

Widget _bar(LeafPlayerController c, {LeafSeekBarLook look = LeafSeekBarLook.line, LeafControlsVisibility? visibility, bool times = false}) =>
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: 1000,
            child: LeafSeekBar(controller: c, theme: _theme, look: look, visibility: visibility, timesInside: times),
          ),
        ),
      ),
    );

RenderLeafSeekBar _render(WidgetTester tester) => tester.allRenderObjects.whereType<RenderLeafSeekBar>().single;

void main() {
  late FullKitAdapter a;
  late LeafPlayerController c;

  setUp(() {
    a = FullKitAdapter(total: _total);
    c = LeafPlayerController(a);
    a.durationCtrl.add(_total);
  });

  tearDown(() => c.dispose());

  void wide(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('press seeks, drag moves seek (throttled), release seeks and the target is held', (tester) async {
    wide(tester);
    final v = LeafAutoHideVisibility();
    await tester.pumpWidget(_bar(c, visibility: v));
    final box = tester.getRect(find.byType(LeafSeekBar));
    final g = await tester.startGesture(Offset(box.left + 100, box.center.dy));
    expect(a.seeks, [secs(10)]);
    for (var i = 1; i <= 10; i++) {
      await g.moveBy(const Offset(20, 0), timeStamp: Duration(milliseconds: 20 * i));
    }
    expect(a.seeks.length, lessThan(6), reason: 'moves are throttled');
    await tester.pump();
    expect(v.held, isTrue, reason: 'a drag holds the controls up');
    await g.up(timeStamp: const Duration(milliseconds: 260));
    expect(a.seeks.last, secs(30));
    expect(c.pendingSeek.value, secs(30));
    a.emitPosition(secs(10));
    expect(c.pendingSeek.value, secs(30), reason: 'the old position does not snap the bar back');
    await tester.pump(const Duration(seconds: 3));
    expect(v.held, isFalse);
    v.dispose();
  });

  testWidgets('paints only when the played part moves a physical pixel', (tester) async {
    wide(tester);
    await tester.pumpWidget(_bar(c));
    final r = _render(tester);
    final start = r.debugPaintCount;
    for (var ms = 0; ms < 50; ms += 5) {
      a.emitPosition(Duration(milliseconds: ms));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(r.debugPaintCount - start, lessThanOrEqualTo(1));
    a.emitPosition(secs(50));
    await tester.pump(const Duration(milliseconds: 100));
    expect(r.debugPaintCount - start, lessThanOrEqualTo(2));
    expect(tester.binding.hasScheduledFrame, isFalse);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('hover: the chapter title above the time, above the bar', (tester) async {
    wide(tester);
    a.chaptersCtrl.add(chaptersFromStarts([('Intro', Duration.zero), ('Part A', secs(50))], _total));
    await tester.pumpWidget(_bar(c));
    final box = tester.getRect(find.byType(LeafSeekBar));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(Offset(box.left + 700, box.center.dy));
    await tester.pump();
    expect(find.text('Part A'), findsOneWidget);
    expect(find.text('1:10'), findsOneWidget);
    expect(tester.getCenter(find.text('Part A')).dy, lessThan(tester.getCenter(find.text('1:10')).dy));
    expect(tester.getRect(find.byKey(const ValueKey('leaf-seek-tip'))).bottom, lessThanOrEqualTo(box.top));
    await mouse.moveTo(Offset(box.left + 100, box.top - 200));
    await tester.pump();
    expect(find.byKey(const ValueKey('leaf-seek-tip')), findsNothing);
    await mouse.removePointer();
  });

  testWidgets('band: a press on a chapter dot jumps there; one on the right time switches it', (tester) async {
    wide(tester);
    a.chaptersCtrl.add(chaptersFromStarts([('Intro', Duration.zero), ('Part A', secs(50))], _total));
    await tester.pumpWidget(_bar(c, look: LeafSeekBarLook.band, times: true));
    final box = tester.getRect(find.byType(LeafSeekBar));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(box.left + 500, box.top + 1));
    await tester.pump();
    await mouse.down(Offset(box.left + 500, box.top + 1));
    await mouse.up();
    expect(a.seeks, [secs(50)]);
    expect(c.timeFormat.value, LeafTimeFormat.elapsedTotal);
    await mouse.moveTo(Offset(box.right - 20, box.center.dy));
    await mouse.down(Offset(box.right - 20, box.center.dy));
    await mouse.up();
    expect(c.timeFormat.value, LeafTimeFormat.remaining);
    expect(a.seeks.length, 1, reason: 'the time switch does not seek');
    await mouse.removePointer();
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the collapsed band is inert', (tester) async {
    final reveal = AnimationController(vsync: const TestVSync(), value: 0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: LeafSeekBar(controller: c, theme: _theme, look: LeafSeekBarLook.band, reveal: reveal),
          ),
        ),
      ),
    );
    final box = tester.getRect(find.byType(LeafSeekBar));
    expect(box.height, 3);
    await tester.tapAt(box.center);
    expect(a.seeks, isEmpty);
    reveal.dispose();
  });

  testWidgets('inside a LeafViewer a drag on the bar seeks and never pages', (tester) async {
    final pages = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LeafViewer(
          pageCount: 2,
          enableSwipeGestures: true,
          onPageChanged: pages.add,
          pageBuilder: (context, i) => Align(
            alignment: Alignment.bottomCenter,
            child: LeafSeekBar(controller: c, theme: _theme),
          ),
        ),
      ),
    );
    final bar = tester.getRect(find.byType(LeafSeekBar).first);
    final g = await tester.startGesture(Offset(bar.right - 50, bar.center.dy));
    for (var i = 0; i < 20; i++) {
      await g.moveBy(const Offset(-30, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(pages, isEmpty);
    expect(a.seeks, isNotEmpty);
    await tester.pump(const Duration(seconds: 3));
  });
}
