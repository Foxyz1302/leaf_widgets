import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

void main() {
  testWidgets('hero source: returning while the route reverses, cleared once dismissed', (tester) async {
    final source = LeafHeroSource();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: Scaffold(body: source.hide('a', const SizedBox(key: Key('tile'), width: 10, height: 10))),
    ));
    source.value = 'a';
    final route = PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => const SizedBox.shrink(),
    );
    nav.currentState!.push(route);
    source.attach(route);
    await tester.pumpAndSettle();
    expect(source.value, 'a');
    expect(tester.widget<Visibility>(find.ancestor(of: find.byKey(const Key('tile'), skipOffstage: false), matching: find.byType(Visibility, skipOffstage: false))).visible, isFalse);

    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(source.returning, isTrue);
    expect(source.value, 'a');

    await tester.pumpAndSettle();
    expect(source.returning, isFalse);
    expect(source.value, isNull);
    source.dispose();
  });
}
