import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

void main() {
  test('immediate entry while slots are free', () async {
    final gate = FirstFrameGate(maxConcurrent: 2);
    await gate.enter();
    await gate.enter();
    expect(gate.activeCount, 2);
    expect(gate.waitingCount, 0);
    gate.exit();
    gate.exit();
    expect(gate.activeCount, 0);
  });

  test('third entrant waits, exit hands the slot over', () async {
    final gate = FirstFrameGate(maxConcurrent: 2);
    await gate.enter();
    await gate.enter();

    var thirdIn = false;
    final pending = gate.enter().then((_) => thirdIn = true);
    await Future<void>.delayed(Duration.zero);
    expect(thirdIn, isFalse);
    expect(gate.waitingCount, 1);

    gate.exit();
    await pending;
    expect(thirdIn, isTrue);
    expect(gate.activeCount, 2);

    gate.exit();
    gate.exit();
    expect(gate.activeCount, 0);
  });

  test('exit without enter never goes negative', () {
    final gate = FirstFrameGate(maxConcurrent: 1);
    gate.exit();
    expect(gate.activeCount, 0);
  });
}
