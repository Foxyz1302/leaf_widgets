import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

void main() {
  late LeafToastController toasts;
  var underneath = 0;

  Future<void> host(WidgetTester tester, {int maxVisible = 6}) async {
    toasts = LeafToastController();
    addTearDown(toasts.dispose);
    underneath = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => LeafToastHost(controller: toasts, maxVisible: maxVisible, child: child!),
      home: Scaffold(body: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => underneath++, child: const SizedBox.expand())),
    ));
  }

  testWidgets('shows, expires after its duration and animates out', (tester) async {
    await host(tester);
    toasts.show('Saved', duration: const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(toasts.toasts, isEmpty);
    expect(find.text('Saved'), findsOneWidget, reason: 'still animating out');
    await tester.pumpAndSettle();
    expect(find.text('Saved'), findsNothing);
  });

  testWidgets('null duration stays until dismissed', (tester) async {
    await host(tester);
    final id = toasts.show('Sticky', duration: null);
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('Sticky'), findsOneWidget);
    toasts.dismiss(id);
    await tester.pumpAndSettle();
    expect(find.text('Sticky'), findsNothing);
  });

  testWidgets('clicks pass through plain toasts; onTap toasts take them and dismiss', (tester) async {
    await host(tester);
    toasts.show('Plain', duration: null);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plain'), warnIfMissed: false);
    expect(underneath, 1);

    var tapped = 0;
    toasts.show('Clickable', duration: null, onTap: () => tapped++);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clickable'));
    await tester.pumpAndSettle();
    expect(tapped, 1);
    expect(underneath, 1);
    expect(find.text('Clickable'), findsNothing);
  });

  testWidgets('keeps only the newest maxVisible on screen; title, leading and trailing render', (tester) async {
    await host(tester, maxVisible: 2);
    for (var i = 0; i < 4; i++) {
      toasts.show('t$i', duration: null);
    }
    toasts.show('body', title: 'Title', leading: const LeafToastIcon(Icons.info), trailing: const Text('tail'), duration: null);
    await tester.pumpAndSettle();
    expect(find.text('t2'), findsNothing);
    expect(find.text('t3'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('tail'), findsOneWidget);
    expect(find.byIcon(Icons.info), findsOneWidget);
  });
}
