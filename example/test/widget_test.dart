import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

void main() {
  testWidgets('gallery builds and shows all sections', (tester) async {
    await tester.pumpWidget(const LeafWidgetsGalleryApp());

    expect(find.text('leaf_widgets gallery'), findsOneWidget);
    expect(find.byType(AnimatedStar), findsNWidgets(2));
    expect(find.byType(AnimatedFavoriteButton), findsNWidgets(2));
    expect(find.byType(LeafPopover), findsOneWidget);
    expect(find.byType(LeafContextMenu), findsOneWidget);
    expect(find.byType(LeafImage), findsOneWidget);
  });

  testWidgets('LeafViewer demo opens and closes', (tester) async {
    await tester.pumpWidget(const LeafWidgetsGalleryApp());

    // The gallery has perpetual animations, so pumpAndSettle can never settle.
    await tester.scrollUntilVisible(find.text('Open 3-image viewer'), 200);
    await tester.ensureVisible(find.text('Open 3-image viewer'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Open 3-image viewer'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400)); // route transition
    await tester.pump(); // let image loads fail while the widgets are alive

    expect(find.byType(LeafViewer), findsOneWidget);
    expect(find.byType(LeafZoomable), findsWidgets);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600)); // route pop
    expect(find.byType(LeafViewer), findsNothing);
  });
}
