import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

Future<Uint8List> _detailedPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final rnd = math.Random(7);
  final w = width.toDouble(), h = height.toDouble();
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), [const Color(0xFFFFE0B0), const Color(0xFF203060)]),
  );
  final line = Paint()
    ..color = const Color(0xFF101010)
    ..strokeWidth = 1;
  for (var x = 0; x < width; x += 7) {
    canvas.drawLine(Offset(x + 0.5, 0), Offset(x + 0.5, h / 3), line);
  }
  for (var i = 0; i < 3000; i++) {
    canvas.drawCircle(Offset(rnd.nextDouble() * w, h / 3 + rnd.nextDouble() * h / 3), 1 + rnd.nextDouble() * 6, Paint()..color = Color(rnd.nextInt(0xFFFFFFFF)));
  }
  final text = TextPainter(
    text: const TextSpan(text: 'The quick brown fox jumps over the lazy dog 0123456789', style: TextStyle(fontSize: 22, color: Color(0xFF000000))),
    textDirection: TextDirection.ltr,
  )..layout();
  for (var y = 2 * h / 3; y < h - 30; y += 30) {
    text.paint(canvas, Offset(10, y));
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3.0;
  tester.view.display.size = const Size(1080, 2400);
  addTearDown(tester.view.reset);
  addTearDown(tester.view.display.reset);
}

Size? _shown(WidgetTester tester) {
  final image = tester.widget<RawImage>(find.byType(RawImage)).image;
  return image == null ? null : Size(image.width.toDouble(), image.height.toDouble());
}

Future<void> _decodeUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }
}

Widget _viewer(Widget page, {Key? key}) =>
    RepaintBoundary(key: key, child: MaterialApp(home: LeafViewer(pageCount: 1, pageBuilder: (context, i) => page)));

Future<(Size?, Uint8List)> _render(WidgetTester tester, Widget page) async {
  imageCache
    ..clear()
    ..clearLiveImages();
  final boundary = GlobalKey();
  await tester.pumpWidget(_viewer(page, key: boundary));
  await _decodeUntil(tester, () => _shown(tester) != null);
  final data = (await tester.runAsync(() async {
    final shot = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 3.0);
    return shot.toByteData(format: ui.ImageByteFormat.rawRgba);
  }))!;
  final decoded = _shown(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  return (decoded, data.buffer.asUint8List());
}

int _maxDelta(Uint8List a, Uint8List b) {
  var max = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    if (d > max) max = d;
  }
  return max;
}

void main() {
  testWidgets('at 1x a large image decodes at half size and renders like full resolution', (tester) async {
    _phone(tester);
    final png = (await tester.runAsync(() => _detailedPng(3200, 2400)))!;
    for (final quality in [FilterQuality.medium, FilterQuality.low, FilterQuality.high]) {
      final (fullSize, full) = await _render(
        tester,
        LeafZoomable(
          childSize: const Size(360, 270),
          child: Image(image: MemoryImage(Uint8List.fromList(png)), fit: BoxFit.contain, filterQuality: quality),
        ),
      );
      final (reducedSize, reduced) = await _render(
        tester,
        LeafZoomable.image(image: Image(image: MemoryImage(Uint8List.fromList(png)), fit: BoxFit.contain, filterQuality: quality)),
      );
      expect(fullSize, const Size(3200, 2400));
      expect(reducedSize, quality == FilterQuality.medium ? const Size(1600, 1200) : const Size(3200, 2400), reason: quality.name);
      expect(_maxDelta(full, reduced), quality == FilterQuality.medium ? lessThanOrEqualTo(1) : 0, reason: quality.name);
    }
    imageCache.clear();
  });

  testWidgets('zooming in swaps in the full resolution with no blank frame; settling at 1x swaps back', (tester) async {
    _phone(tester);
    final png = (await tester.runAsync(() => _detailedPng(3200, 2400)))!;
    await tester.pumpWidget(_viewer(LeafZoomable.image(image: Image(image: MemoryImage(png), fit: BoxFit.contain))));
    await _decodeUntil(tester, () => _shown(tester) != null);
    expect(_shown(tester), const Size(1600, 1200));
    final zoom = LeafViewer.controllerOf(tester.element(find.byType(LeafZoomable)))!;
    expect(zoom.originalSize, const Size(3200, 2400));

    zoom.scaleUpdate(3, Offset.zero, Offset.zero);
    final seen = <Size?>[];
    await _decodeUntil(tester, () {
      seen.add(_shown(tester));
      return _shown(tester) == const Size(3200, 2400);
    });
    expect(_shown(tester), const Size(3200, 2400));
    expect(seen, isNot(contains(null)));

    zoom.scaleUpdate(1, Offset.zero, Offset.zero);
    await tester.pump();
    expect(_shown(tester), isNotNull);
    await tester.pump();
    expect(_shown(tester), const Size(1600, 1200));
    await tester.pumpWidget(const SizedBox.shrink());
    imageCache.clear();
  });

  testWidgets('rotating the display keeps the same decode', (tester) async {
    _phone(tester);
    final png = (await tester.runAsync(() => _detailedPng(3200, 2400)))!;
    await tester.pumpWidget(_viewer(LeafZoomable.image(image: Image(image: MemoryImage(png), fit: BoxFit.contain))));
    await _decodeUntil(tester, () => _shown(tester) != null);
    final before = tester.widget<RawImage>(find.byType(RawImage)).image!;
    tester.view.physicalSize = const Size(2400, 1080);
    tester.view.display.size = const Size(2400, 1080);
    await tester.pump();
    final after = tester.widget<RawImage>(find.byType(RawImage)).image;
    expect(after, isNotNull);
    expect(after!.isCloneOf(before), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    imageCache.clear();
  });

  testWidgets('decodeFullResolution keeps the full decode at 1x', (tester) async {
    _phone(tester);
    final png = (await tester.runAsync(() => _detailedPng(3200, 2400)))!;
    await tester.pumpWidget(
      _viewer(LeafZoomable.image(decodeFullResolution: true, image: Image(image: MemoryImage(png), fit: BoxFit.contain))),
    );
    await _decodeUntil(tester, () => _shown(tester) != null);
    expect(_shown(tester), const Size(3200, 2400));
    await tester.pumpWidget(const SizedBox.shrink());
    imageCache.clear();
  });
}
