import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

void main() {
  group('LeafViewerChrome', () {
    testWidgets('auto-hide fires after hideDelay', (tester) async {
      final chrome = LeafViewerChrome();
      addTearDown(chrome.dispose);
      expect(chrome.visible, isTrue);
      await tester.pump(const Duration(seconds: 4));
      expect(chrome.visible, isFalse);
    });

    testWidgets('hold suppresses the timer until released', (tester) async {
      final chrome = LeafViewerChrome();
      addTearDown(chrome.dispose);
      chrome.hold = true;
      await tester.pump(const Duration(seconds: 4));
      expect(chrome.visible, isTrue);
      chrome.hold = false;
      await tester.pump(const Duration(seconds: 4));
      expect(chrome.visible, isFalse);
    });

    testWidgets('hide cancels a pending timer', (tester) async {
      final chrome = LeafViewerChrome();
      await tester.pump(const Duration(seconds: 2));
      chrome.hide();
      await tester.pump(const Duration(seconds: 4));
      expect(chrome.visible, isFalse);
      chrome.show();
      expect(chrome.visible, isTrue);
      chrome.dispose();
    });

    testWidgets('autoHide: false never hides', (tester) async {
      final chrome = LeafViewerChrome(autoHide: false);
      addTearDown(chrome.dispose);
      await tester.pump(const Duration(minutes: 1));
      expect(chrome.visible, isTrue);
    });
  });

  group('viewer chrome integration', () {
    testWidgets('tap on a zoomable page toggles chrome', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LeafViewer(
              pageCount: 1,
              enableChrome: true,
              pageBuilder: (context, i) => Stack(
                children: [
                  LeafZoomable(childSize: const Size(400, 300), child: Container(color: const Color(0xFF112233))),
                  LeafChrome(builder: (context) => Text(chromeState(context))),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('chrome: visible'), findsOneWidget);

      await tester.tap(find.byType(LeafZoomable));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('chrome: hidden'), findsOneWidget);

      await tester.tap(find.byType(LeafZoomable));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('chrome: visible'), findsOneWidget);
    });

    testWidgets('LeafChrome stops hit-testing while hidden', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LeafViewer(
              pageCount: 1,
              enableChrome: true,
              pageBuilder: (context, i) => Stack(
                children: [
                  LeafZoomable(childSize: const Size(400, 300), child: Container(color: const Color(0xFF112233))),
                  LeafChrome(
                    builder: (context) => Align(
                      alignment: Alignment.topRight,
                      child: IconButton(onPressed: () => pressed = true, icon: const Icon(Icons.ac_unit)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(LeafZoomable));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byIcon(Icons.ac_unit), warnIfMissed: false);
      expect(pressed, isFalse);

      await tester.tap(find.byType(LeafZoomable));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byIcon(Icons.ac_unit));
      expect(pressed, isTrue);
    });

    testWidgets('default desktop controls join the reveal and honour showPageCounter', (tester) async {
      Widget build({required bool showPageCounter}) => MaterialApp(
            home: Scaffold(
              body: LeafViewer(
                pageCount: 3,
                enableChrome: true,
                showPageCounter: showPageCounter,
                pageBuilder: (context, i) =>
                    LeafZoomable(childSize: const Size(400, 300), child: Container(color: const Color(0xFF112233))),
              ),
            ),
          );

      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.pumpWidget(build(showPageCounter: true));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);

      final chrome = LeafViewer.chromeOf(tester.element(find.byType(LeafZoomable)))!;
      await tester.tap(find.byType(LeafZoomable));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 200));
      expect(chrome.visible, isFalse);

      await tester.pumpWidget(build(showPageCounter: false));
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsNothing);
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('LeafViewerHero', () {
    testWidgets('only the settled page registers a hero', (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeafViewer(
            pageCount: 3,
            pageController: controller,
            pageBuilder: (context, i) =>
                LeafViewerHero(tag: 'post_$i', child: SizedBox.expand(key: ValueKey('page-$i'))),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // Neighbours are alive but their heroes must not fly.
      expect(_flightHeroTags(tester), ['post_0']);
      expect(find.byKey(const ValueKey('page-0')), findsOneWidget);

      controller.jumpToPage(1);
      await tester.pumpAndSettle();
      expect(_flightHeroTags(tester), ['post_1']);
    });

    testWidgets('page state survives the hero gate when the page changes', (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      final inits = <int, int>{};
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeafViewer(
            pageCount: 3,
            pageController: controller,
            pageBuilder: (context, i) => LeafViewerHero(tag: 'post_$i', child: _InitCounter(index: i, inits: inits)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      controller.jumpToPage(1);
      await tester.pumpAndSettle();
      controller.jumpToPage(0);
      await tester.pumpAndSettle();
      expect(inits, {0: 1, 1: 1, 2: 1});
    });

    testWidgets('popping the viewer flies only the active page back', (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: Row(key: const ValueKey('grid'), children: [
            for (var i = 0; i < 3; i++) Hero(tag: 'post_$i', child: SizedBox(width: 50, height: 50, key: ValueKey('grid-$i'))),
          ]),
        ),
      ));
      navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: LeafViewer(
            pageCount: 3,
            pageBuilder: (context, i) => LeafViewerHero(tag: 'post_$i', child: SizedBox.expand(key: ValueKey('page-$i'))),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      Finder inGrid(int i) => find.descendant(of: find.byKey(const ValueKey('grid')), matching: find.byKey(ValueKey('grid-$i')));
      expect(inGrid(0), findsNothing);
      expect(inGrid(1), findsOneWidget);
      expect(inGrid(2), findsOneWidget);
      await tester.pumpAndSettle();
      expect(inGrid(0), findsOneWidget);
    });

    testWidgets('behaves like a plain hero outside a viewer', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LeafViewerHero(tag: 'x', child: const SizedBox.expand()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(Hero), findsOneWidget);
    });
  });
}

String chromeState(BuildContext context) {
  final chrome = LeafViewer.chromeOf(context)!;
  return chrome.visible ? 'chrome: visible' : 'chrome: hidden';
}

List<Object> _flightHeroTags(WidgetTester tester) => [
      for (final element in find.byType(Hero).evaluate())
        if (element.findAncestorWidgetOfExactType<HeroMode>()?.enabled ?? true) (element.widget as Hero).tag,
    ];

class _InitCounter extends StatefulWidget {
  const _InitCounter({required this.index, required this.inits});

  final int index;
  final Map<int, int> inits;

  @override
  State<_InitCounter> createState() => _InitCounterState();
}

class _InitCounterState extends State<_InitCounter> {
  @override
  void initState() {
    super.initState();
    widget.inits.update(widget.index, (v) => v + 1, ifAbsent: () => 1);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
