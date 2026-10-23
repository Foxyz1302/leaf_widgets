import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

class _DelayedImage extends ImageProvider<_DelayedImage> {
  const _DelayedImage(this.image);

  final ui.Image image;

  @override
  Future<_DelayedImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_DelayedImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Future<ImageInfo>.delayed(const Duration(milliseconds: 20), () => ImageInfo(image: image.clone())));
}

int _shaderMasks(WidgetTester tester) => tester.layers.whereType<ShaderMaskLayer>().length;

void main() {
  testWidgets('gradient reveal masks while animating and drops the mask once revealed', (tester) async {
    final image = (await tester.runAsync(() => createTestImage(width: 40, height: 30)))!;
    await tester.pumpWidget(Center(child: LeafImage(image: _DelayedImage(image), width: 40, height: 30)));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_shaderMasks(tester), 1);

    await tester.pump(const Duration(milliseconds: 400));
    expect(_shaderMasks(tester), 0);
    expect(find.byType(RawImage), findsOneWidget);
    imageCache.clear();
  });

  testWidgets('a reveal that ends partially masked keeps its mask', (tester) async {
    final image = (await tester.runAsync(() => createTestImage(width: 40, height: 30)))!;
    await tester.pumpWidget(Center(
      child: LeafImage(image: _DelayedImage(image), width: 40, height: 30, revealAnimation: const GradientRevealAnimation(finalStop2: 1.0)),
    ));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 500));
    expect(_shaderMasks(tester), 1);
    imageCache.clear();
  });
}
