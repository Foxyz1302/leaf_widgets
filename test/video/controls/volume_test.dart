import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

import 'kit_fakes.dart';

const _spec = LeafControlsSpec(
  layout: LeafControlsLayout(
    slots: {
      LeafSlot.bottomStart: [LeafControl.playPause, LeafControl.volume],
      LeafSlot.overlay: [LeafControl.volumeFlash],
    },
  ),
);

void main() {
  testWidgets('the speaker mutes and restores; the wheel on it steps 5', (tester) async {
    final a = FullKitAdapter()..vol = 60;
    final c = LeafPlayerController(a);
    await tester.pumpWidget(kitHarness(c, spec: _spec));
    final speaker = find.descendant(of: find.byKey(const ValueKey('leaf-control-volume')), matching: find.byType(LeafControlButton));
    await tester.tap(speaker);
    expect(a.vol, 0);
    await tester.tap(speaker);
    expect(a.vol, 60);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(speaker)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -60)));
    expect(a.vol, 65);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 120)));
    expect(a.vol, 60);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('the wheel anywhere shows the readout for about a second; sideways is nothing', (tester) async {
    final a = FullKitAdapter()..vol = 50;
    final c = LeafPlayerController(a);
    await tester.pumpWidget(kitHarness(c, spec: _spec));
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(const Offset(400, 200)));
    await tester.sendEventToBinding(mouse.scroll(const Offset(80, 10)));
    expect(a.vol, 50);
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 60)));
    expect(a.vol, 45);
    await tester.pump();
    expect(find.byKey(const ValueKey('leaf-volume-readout')), findsOneWidget);
    expect(find.text('45 %'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.byKey(const ValueKey('leaf-volume-readout')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('a list under the mouse claims the wheel first', (tester) async {
    final a = FullKitAdapter()..vol = 50;
    final c = LeafPlayerController(a);
    final list = LeafControl.widget(
      id: 'list',
      width: 120,
      builder: (context) => SizedBox(
        width: 120,
        height: 40,
        child: ListView(children: [for (var i = 0; i < 20; i++) Text('row $i')]),
      ),
    );
    await tester.pumpWidget(kitHarness(c, spec: LeafControlsSpec(layout: _spec.layout.withSlot(LeafSlot.bottomEnd, [list]))));
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(find.text('row 0'))));
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 60)));
    expect(a.vol, 50);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
}
