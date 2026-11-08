import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';
import 'package:leaf_widgets/src/video/controls/smooth_position.dart';

import 'kit_fakes.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  testWidgets('runs on between events at the rate, holds a late event, follows a seek back', (tester) async {
    final a = FullKitAdapter(total: const Duration(minutes: 1));
    final c = LeafPlayerController(a);
    final smooth = LeafSmoothPosition.of(c);
    final owner = Object();
    smooth.want(owner, () => 1);
    a.play();
    a.setRate(2);
    for (var t = 0; t <= 400; t += 100) {
      a.emitPosition(ms(t * 2));
      await tester.pump(ms(100));
    }
    await tester.pump(ms(50));
    final ran = smooth.value;
    expect(ran, greaterThan(ms(800)));
    expect(ran, lessThanOrEqualTo(ms(800 + 2 * 2 * 100)));

    a.emitPosition(ms(810));
    await tester.pump(ms(100));
    expect(smooth.value, greaterThanOrEqualTo(ran));

    a.emitPosition(ms(100));
    await tester.pump(ms(100));
    expect(smooth.value, lessThan(ms(500)));

    a.pause();
    await tester.pump(ms(100));
    final paused = smooth.value;
    await tester.pump(ms(300));
    expect(smooth.value, paused);
    smooth.release(owner);
    c.dispose();
  });
}
