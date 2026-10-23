import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

class _AnimatedImage extends ImageProvider<_AnimatedImage> {
  const _AnimatedImage(this.frame);

  final ui.Image frame;

  @override
  Future<_AnimatedImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_AnimatedImage key, ImageDecoderCallback decode) => _Ticking(frame);
}

class _Ticking extends ImageStreamCompleter {
  _Ticking(ui.Image frame) {
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) => setImage(ImageInfo(image: frame.clone())));
  }

  late final Timer _timer;

  @override
  void onDisposed() {
    _timer.cancel();
    super.onDisposed();
  }
}

class _StaticImage extends ImageProvider<_StaticImage> {
  const _StaticImage(this.image, this.id);

  final ui.Image image;
  final String id;

  @override
  Future<_StaticImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_StaticImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: image.clone())));

  @override
  bool operator ==(Object other) => other is _StaticImage && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  imageCache
    ..clear()
    ..clearLiveImages();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('LeafZoomable.image re-reads the size when its image changes', (tester) async {
    final wide = (await tester.runAsync(() => createTestImage(width: 400, height: 200, cache: false)))!;
    final tall = (await tester.runAsync(() => createTestImage(width: 200, height: 400, cache: false)))!;
    Widget viewer(ImageProvider provider) => MaterialApp(
          home: LeafViewer(pageCount: 1, pageBuilder: (context, i) => LeafZoomable.image(image: Image(image: provider))),
        );
    await tester.pumpWidget(viewer(_StaticImage(wide, 'wide')));
    await tester.pump();
    final zoom = LeafViewer.controllerOf(tester.element(find.byType(LeafZoomable)))!;
    expect(zoom.childSize, const Size(800, 400));
    expect(zoom.originalSize, const Size(400, 200));

    await tester.pumpWidget(viewer(_StaticImage(tall, 'tall')));
    await tester.pump();
    expect(zoom.childSize, const Size(300, 600));
    expect(zoom.originalSize, const Size(200, 400));
    await _unmount(tester);
  });

  testWidgets('LeafZoomable.image does not rebuild on every frame of an animated image', (tester) async {
    final frame = (await tester.runAsync(() => createTestImage(width: 320, height: 240, cache: false)))!;
    await tester.pumpWidget(MaterialApp(home: LeafZoomable.image(image: Image(image: _AnimatedImage(frame)))));
    await tester.pump(const Duration(milliseconds: 100));

    var zoomableRebuilds = 0;
    debugOnRebuildDirtyWidget = (element, _) {
      if (element.widget is RawGestureDetector) zoomableRebuilds++;
    };
    try {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnRebuildDirtyWidget = null;
    }
    expect(zoomableRebuilds, 0);
    await _unmount(tester);
  });

  testWidgets('LeafZoomable.image releases the frames it inspects', (tester) async {
    final frame = (await tester.runAsync(() => createTestImage(width: 320, height: 240, cache: false)))!;
    await tester.pumpWidget(MaterialApp(home: LeafZoomable.image(image: Image(image: _AnimatedImage(frame)))));
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(frame.debugGetOpenHandleStackTraces()!.length, lessThan(6));
    await _unmount(tester);
  });
}
