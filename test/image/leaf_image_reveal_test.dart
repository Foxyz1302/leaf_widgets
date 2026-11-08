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

class _CountingController extends AnimationController {
  _CountingController() : super(vsync: const TestVSync(), duration: const Duration(milliseconds: 100));

  int statusListeners = 0;

  @override
  void addStatusListener(AnimationStatusListener listener) {
    statusListeners++;
    super.addStatusListener(listener);
  }

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    statusListeners--;
    super.removeStatusListener(listener);
  }
}

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

  testWidgets('GradientRevealAnimation.curve shapes the sweep', (tester) async {
    final image = (await tester.runAsync(() {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 40, 30), Paint()..color = const Color(0xFFFF0000));
      return recorder.endRecording().toImage(40, 30);
    }))!;
    final boundary = GlobalKey();
    await tester.pumpWidget(Center(
      child: RepaintBoundary(
        key: boundary,
        child: LeafImage(
          image: _DelayedImage(image),
          width: 40,
          height: 30,
          revealAnimation: const GradientRevealAnimation(curve: Threshold(0.9)),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final pixels = (await tester.runAsync(() async {
      final shot = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
      return shot.toByteData(format: ui.ImageByteFormat.rawRgba);
    }))!;
    expect(pixels.getUint8((15 * 40 + 2) * 4 + 3), 0);
    imageCache.clear();
  });

  testWidgets('rebuilding the built-in reveals leaves no status listeners behind', (tester) async {
    final controller = _CountingController();
    addTearDown(controller.dispose);
    for (final reveal in const <LeafRevealAnimation>[GradientRevealAnimation(), FadeRevealAnimation()]) {
      for (var i = 0; i < 5; i++) {
        await tester.pumpWidget(Builder(builder: (context) => reveal.build(context, const SizedBox(width: 10, height: 10), controller)));
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    expect(controller.statusListeners, 0);
  });
}
