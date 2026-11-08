import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';
import 'package:leaf_widgets/src/video/controls/media_math.dart' show chaptersFromStarts;

import 'kit_fakes.dart';

void main() {
  testWidgets('standard keys drive the controller; Space never presses a button', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final a = FullKitAdapter()..vol = 50;
    a.chapterList = chaptersFromStarts([('A', Duration.zero), ('B', secs(60)), ('C', secs(120))], const Duration(minutes: 24));
    final c = LeafPlayerController(a);
    await tester.pumpWidget(kitHarness(c, spec: LeafControlsSpec.desktop));
    await tester.tapAt(const Offset(400, 200));
    final plays = a.plays + a.pauses;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(a.plays + a.pauses, plays + 1, reason: 'one toggle, not the focused button too');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(a.seeks.last, secs(5));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    expect(a.seeks.last, secs(15));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(a.seeks.last, secs(14));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    expect(a.vol, 55);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    expect(a.vol, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    expect(a.seeks.last, secs(60), reason: 'PgUp is the next chapter, as in mpv');
    await tester.sendKeyEvent(LogicalKeyboardKey.digit5);
    expect(a.seeks.last, const Duration(minutes: 12));
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    expect(a.speed, 1.25);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    expect(c.infoVisible.value, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(c.infoVisible.value, isFalse);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test('hints, merge, without and the viewer exclusion', () {
    const k = LeafPlayerKeymap.standard;
    expect(k.hintFor(const LeafPlayerCommand.togglePlay()), 'Space');
    expect(k.tooltip('Fullscreen', const LeafPlayerCommand.toggleFullscreen()), 'Fullscreen (F)');
    final viewer = k.forViewer(Axis.horizontal);
    expect(viewer.bindings.where((b) => b.key == LogicalKeyboardKey.arrowLeft && !b.shift), isEmpty);
    expect(viewer.bindings.where((b) => b.key == LogicalKeyboardKey.arrowLeft && b.shift), isNotEmpty);
    expect(viewer.bindings.where((b) => b.key == LogicalKeyboardKey.arrowUp), isNotEmpty);
    final custom = k.merge([const LeafKeyBinding(LogicalKeyboardKey.space, LeafPlayerCommand.toggleFullscreen())]);
    expect(custom.bindings.first.command, const LeafPlayerCommand.toggleFullscreen());
    expect(k.without((b) => b.command is LeafToggleMute).hintFor(const LeafPlayerCommand.toggleMute()), isNull);
    expect(LeafPlayerKeymap.standard, LeafPlayerKeymap.standard.merge(const []));
  });
}
