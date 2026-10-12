import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

void main() {
  testWidgets('backgrounding pauses a playing child, foreground resumes it', (tester) async {
    var pauses = 0;
    var resumes = 0;
    var playing = true;

    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => VideoLifecycleGuard(
          isPlaying: playing,
          onPause: () {
            pauses++;
            setState(() => playing = false);
          },
          onResume: () {
            resumes++;
            setState(() => playing = true);
          },
          child: const SizedBox.shrink(),
        ),
      ),
    ));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(pauses, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(resumes, 1);
  });

  testWidgets('idle child gets no calls on background round-trip', (tester) async {
    var pauses = 0;
    var resumes = 0;

    await tester.pumpWidget(MaterialApp(
      home: VideoLifecycleGuard(
        isPlaying: false,
        onPause: () => pauses++,
        onResume: () => resumes++,
        child: const SizedBox.shrink(),
      ),
    ));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(pauses, 0);
    expect(resumes, 0);
  });

  testWidgets('covering route pauses, uncovering resumes', (tester) async {
    var pauses = 0;
    var resumes = 0;
    var playing = true;

    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => VideoLifecycleGuard(
          isPlaying: playing,
          onPause: () {
            pauses++;
            setState(() => playing = false);
          },
          onResume: () {
            resumes++;
            setState(() => playing = true);
          },
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog(context: context, builder: (_) => const Text('cover')),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('cover'), findsOneWidget);
    expect(pauses, 1);

    Navigator.of(tester.element(find.text('cover'))).pop();
    await tester.pumpAndSettle();
    expect(resumes, 1);
  });
}
