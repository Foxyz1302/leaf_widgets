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
      // Neighbours are alive but must not carry heroes.
      expect(find.byType(Hero), findsOneWidget);
      expect(find.byKey(const ValueKey('page-0')), findsOneWidget);

      controller.jumpToPage(1);
      await tester.pumpAndSettle();
      expect(find.byType(Hero), findsOneWidget);
      expect(tester.widget<Hero>(find.byType(Hero)).tag, 'post_1');
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
