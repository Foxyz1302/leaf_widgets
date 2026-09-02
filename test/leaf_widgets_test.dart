import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

void main() {
  testWidgets('barrel exports build all widgets', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const AnimatedStar(),
              const AnimatedFavoriteButton(),
              LeafImage(image: MemoryImage(Uint8List(0))),
              LeafPopover(
                popoverBuilder: (context, controller) => const Card(child: Text('popover')),
                child: const Text('trigger'),
              ),
              LeafContextMenu(
                entries: const [ContextMenuAction(label: 'Copy')],
                child: const Text('menu'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(AnimatedStar), findsOneWidget);
    expect(find.byType(AnimatedFavoriteButton), findsOneWidget);
    expect(find.byType(LeafImage), findsOneWidget);
    expect(find.byType(LeafPopover), findsOneWidget);
    expect(find.byType(LeafContextMenu), findsOneWidget);
  });
}
