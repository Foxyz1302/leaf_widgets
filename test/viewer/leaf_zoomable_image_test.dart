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

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  imageCache
    ..clear()
    ..clearLiveImages();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
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
}
