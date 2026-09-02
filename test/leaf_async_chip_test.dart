import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

Widget _host(LeafAsyncChip chip) => MaterialApp(home: Scaffold(body: Center(child: chip)));

void main() {
  testWidgets('shows running spinner, then done label, then resets', (tester) async {
    final key = GlobalKey<LeafAsyncChipState>();
    await tester.pumpWidget(_host(LeafAsyncChip(
      key: key,
      doneLabel: 'Copied',
      child: const SizedBox(width: 100, height: 100),
    )));

    key.currentState!.run(task: (_) => Future<void>.delayed(const Duration(seconds: 1)), doneLabel: 'Image copied');
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Image copied'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Image copied'), findsNothing);
  });

  testWidgets('reports progress to a determinate spinner', (tester) async {
    final key = GlobalKey<LeafAsyncChipState>();
    await tester.pumpWidget(_host(LeafAsyncChip(
      key: key,
      child: const SizedBox(width: 100, height: 100),
    )));

    key.currentState!.run(task: (onProgress) async {
      onProgress?.call(0.5);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    final spinner = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
    expect(spinner.value, 0.5);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 1300));
  });

  testWidgets('shows error label, calls onError, then resets', (tester) async {
    final key = GlobalKey<LeafAsyncChipState>();
    Object? seenError;
    StackTrace? seenStack;
    await tester.pumpWidget(_host(LeafAsyncChip(
      key: key,
      errorLabel: 'Copy failed',
      onError: (e, st) {
        seenError = e;
        seenStack = st;
      },
      child: const SizedBox(width: 100, height: 100),
    )));

    key.currentState!.run(task: (_) async => throw StateError('boom'));
    await tester.pump();

    expect(find.text('Copy failed'), findsOneWidget);
    expect(seenError, isA<StateError>());
    expect(seenStack, isNotNull);

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Copy failed'), findsNothing);
  });

  testWidgets('ignores run() while a task is running', (tester) async {
    final key = GlobalKey<LeafAsyncChipState>();
    var runs = 0;
    await tester.pumpWidget(_host(LeafAsyncChip(
      key: key,
      doneLabel: 'Copied',
      child: const SizedBox(width: 100, height: 100),
    )));

    key.currentState!.run(task: (_) async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }, doneLabel: 'First');
    await tester.pump();
    key.currentState!.run(task: (_) async => runs++, doneLabel: 'Second');
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 200));
    expect(runs, 1);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1200));
  });
}
