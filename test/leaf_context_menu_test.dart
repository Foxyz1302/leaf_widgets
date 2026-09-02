import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

Future<void> _openMenu(WidgetTester tester) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(LeafContextMenu)),
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryButton,
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200)); // entrance animation
  await gesture.up();
}

Widget _host(List<ContextMenuEntry> entries) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: LeafContextMenu(entries: entries, child: const Text('trigger')),
        ),
      ),
    );

void main() {
  testWidgets('async action: spinner → check, menu locked while running, auto-dismiss on success', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(_host([ContextMenuAsyncAction(label: 'Copy image', task: (_) => completer.future)]));

    await _openMenu(tester);
    expect(find.text('Copy image'), findsOneWidget);

    await tester.tap(find.text('Copy image'));
    await tester.pump();
    expect(find.text('Copying…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Outside taps are ignored while the task runs.
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    expect(find.text('Copying…'), findsOneWidget);

    completer.complete();
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700)); // doneDuration
    await tester.pump(const Duration(milliseconds: 150)); // exit animation
    expect(find.text('Copied'), findsNothing);
  });

  testWidgets('async action: reported progress drives a determinate bar', (tester) async {
    final completer = Completer<void>();
    await tester.pumpWidget(_host([
      ContextMenuAsyncAction(label: 'Copy image', task: (onProgress) {
        onProgress?.call(0.5);
        return completer.future;
      }),
    ]));

    await _openMenu(tester);
    await tester.tap(find.text('Copy image'));
    await tester.pump();

    final bar = tester.widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(bar.value, 0.5);

    completer.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
  });

  testWidgets('async action: failure shows error label and calls onError', (tester) async {
    Object? seen;
    await tester.pumpWidget(_host([
      ContextMenuAsyncAction(
        label: 'Copy image',
        task: (_) async => throw StateError('boom'),
        onError: (e, _) => seen = e,
      ),
    ]));

    await _openMenu(tester);
    await tester.tap(find.text('Copy image'));
    await tester.pump();

    expect(find.text('Failed'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(seen, isA<StateError>());

    await tester.pump(const Duration(milliseconds: 1400)); // errorDuration
    await tester.pump(const Duration(milliseconds: 150)); // exit animation
    expect(find.text('Failed'), findsNothing);
  });

  testWidgets('other entries are disabled while an async action runs', (tester) async {
    final completer = Completer<void>();
    var syncTaps = 0;
    await tester.pumpWidget(_host([
      ContextMenuAction(label: 'Sync item', onTap: () => syncTaps++),
      ContextMenuAsyncAction(label: 'Copy image', task: (_) => completer.future),
    ]));

    await _openMenu(tester);
    await tester.tap(find.text('Copy image'));
    await tester.pump();

    await tester.tap(find.text('Sync item'));
    await tester.pump();
    expect(syncTaps, 0);
    expect(find.text('Copying…'), findsOneWidget);

    completer.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
  });
}
