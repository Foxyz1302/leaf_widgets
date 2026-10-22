import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:example/bench/bench_video_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

class _Probe {
  int rebuilds = 0;
  int newElements = 0;
  int layouts = 0;
  int paints = 0;
  final _seen = Expando<bool>();
  late DebugPrintCallback _savedPrint;

  void install() {
    debugOnRebuildDirtyWidget = (element, _) {
      rebuilds++;
      if (_seen[element] == null) {
        _seen[element] = true;
        newElements++;
      }
    };
    debugOnProfilePaint = (_) => paints++;
    debugPrintLayouts = true;
    _savedPrint = debugPrint;
    final saved = _savedPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.startsWith('Laying out')) {
        layouts++;
        return;
      }
      saved(message, wrapWidth: wrapWidth);
    };
  }

  void uninstall() {
    debugOnRebuildDirtyWidget = null;
    debugOnProfilePaint = null;
    debugPrintLayouts = false;
    debugPrint = _savedPrint;
  }
}

class _Phase {
  _Phase(this.name);

  final String name;
  final rebuilds = <int>[];
  final newElements = <int>[];
  final layouts = <int>[];
  final paints = <int>[];
  int tickingFrames = 0;
  Map<String, int> counters = const {};

  static Map<String, num> _dist(List<int> values) {
    if (values.isEmpty) return {'total': 0};
    final sorted = [...values]..sort();
    return {
      'total': values.fold(0, (a, b) => a + b),
      'perFrame': double.parse((values.fold(0, (a, b) => a + b) / values.length).toStringAsFixed(1)),
      'p90': sorted[((sorted.length - 1) * 0.9).round()],
      'max': sorted.last,
    };
  }

  Map<String, Object> toJson() => {
    'frames': rebuilds.length,
    'tickingFrames': tickingFrames,
    'rebuilds': _dist(rebuilds),
    'newElements': _dist(newElements),
    'layouts': _dist(layouts),
    'paints': _dist(paints),
    'counters': counters,
  };
}

class _TestImage extends ImageProvider<_TestImage> {
  const _TestImage(this.id, this.image);

  final int id;
  final ui.Image image;

  @override
  Future<_TestImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_TestImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(Future<ImageInfo>.delayed(const Duration(milliseconds: 40), () => ImageInfo(image: image.clone())));

  @override
  bool operator ==(Object other) => other is _TestImage && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class _AnimatedTestImage extends ImageProvider<_AnimatedTestImage> {
  _AnimatedTestImage(this.frames);

  final List<ui.Image> frames;
  int emitted = 0;

  @override
  Future<_AnimatedTestImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(_AnimatedTestImage key, ImageDecoderCallback decode) => _FrameTicker(this);
}

class _FrameTicker extends ImageStreamCompleter {
  _FrameTicker(this.provider) {
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      setImage(ImageInfo(image: provider.frames[provider.emitted % provider.frames.length].clone()));
      provider.emitted++;
    });
  }

  final _AnimatedTestImage provider;
  late final Timer _timer;

  @override
  void onDisposed() {
    _timer.cancel();
    super.onDisposed();
  }
}

enum _Kind { image, leafImage, video }

const _layout = [
  _Kind.image,
  _Kind.video,
  _Kind.leafImage,
  _Kind.video,
  _Kind.image,
  _Kind.leafImage,
  _Kind.video,
  _Kind.image,
  _Kind.video,
  _Kind.video,
  _Kind.leafImage,
  _Kind.video,
];

void _report(String name, Object data) => debugPrint('HEADLESS_BENCH $name ${jsonEncode(data)}');

Map<String, int> _layerCounts(Layer root) {
  final counts = <String, int>{};
  void visit(Layer layer) {
    counts.update('all', (v) => v + 1, ifAbsent: () => 1);
    if (layer is ShaderMaskLayer) counts.update('shaderMask', (v) => v + 1, ifAbsent: () => 1);
    if (layer is OpacityLayer) counts.update('opacity', (v) => v + 1, ifAbsent: () => 1);
    if (layer is ContainerLayer) {
      var child = layer.firstChild;
      while (child != null) {
        visit(child);
        child = child.nextSibling;
      }
    }
  }

  visit(root);
  return counts;
}

void main() {
  testWidgets('swipe workload: rebuilds, layouts, paints and player lifecycle per phase', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    BenchCounters.reset();

    final base = (await tester.runAsync(() => createTestImage(width: 300, height: 200)))!;
    final thumb = (await tester.runAsync(() => createTestImage(width: 160, height: 90)))!;
    final tiles = [for (var i = 0; i < 24; i++) _TestImage(100 + i, base)];
    final navigator = GlobalKey<NavigatorState>();
    final controller = PageController();
    addTearDown(controller.dispose);
    final session = 's${DateTime.now().microsecondsSinceEpoch}';
    final hostTick = ValueNotifier<int>(0);
    addTearDown(hostTick.dispose);
    BenchCounters.scrollProbe = () => controller.hasClients && controller.position.isScrollingNotifier.value;

    Widget buildPage(BuildContext context, int index) {
      BenchCounters.pageBuilds++;
      final kind = _layout[index];
      final Widget child = switch (kind) {
        _Kind.image => LeafZoomable.image(image: Image(image: _TestImage(index, base), fit: BoxFit.contain)),
        _Kind.leafImage => LeafZoomable(child: LeafImage(image: _TestImage(index, base), fit: BoxFit.contain)),
        _Kind.video => LeafVideoPage(
          createAdapter: () => BenchVideoAdapter(seed: index),
          url: 'bench://video/$index',
          headers: {'Referer': 'https://bench.local/', 'X-Session': session},
          aspectRatio: 16 / 9,
          thumbnail: Image(image: _TestImage(200 + index, thumb), fit: BoxFit.cover),
          controlsBuilder: (context, adapter) => LeafVideoControls(adapter: adapter),
        ),
      };
      return LeafViewerHero(tag: 'bench_$index', child: child);
    }

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: Scaffold(
          body: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
            itemCount: tiles.length,
            itemBuilder: (context, i) => LeafImage(image: tiles[i], fit: BoxFit.cover),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    final probe = _Probe()..install();
    final phases = <_Phase>[];
    late _Phase phase;
    var startCounters = BenchCounters.snapshot();
    var clockMs = 0;

    void begin(String name) {
      phase = _Phase(name);
      phases.add(phase);
      startCounters = BenchCounters.snapshot();
      BenchCounters.resetPeaks();
    }

    void end() {
      final now = BenchCounters.snapshot();
      phase.counters = {for (final e in now.entries) e.key: e.value - (startCounters[e.key] ?? 0), ...BenchCounters.peaks()};
      phase = _Phase('gap');
    }

    Future<void> frame(int ms) async {
      final r = probe.rebuilds, n = probe.newElements, l = probe.layouts, p = probe.paints;
      await tester.pump(Duration(milliseconds: ms));
      clockMs += ms;
      phase.rebuilds.add(probe.rebuilds - r);
      phase.newElements.add(probe.newElements - n);
      phase.layouts.add(probe.layouts - l);
      phase.paints.add(probe.paints - p);
      if (SchedulerBinding.instance.transientCallbackCount > 0) phase.tickingFrames++;
    }

    Future<void> settle(int ms) async {
      for (var t = 0; t < ms; t += 16) {
        await frame(16);
      }
    }

    Future<void> gesture(Offset from, Offset step, int moves, {int holdMs = 0}) async {
      final g = await tester.createGesture();
      await g.down(from, timeStamp: Duration(milliseconds: clockMs));
      for (var i = 0; i < moves; i++) {
        await g.moveBy(step, timeStamp: Duration(milliseconds: clockMs + 8));
        await frame(8);
      }
      await settle(holdMs);
      await g.up(timeStamp: Duration(milliseconds: clockMs + 8));
    }

    int page() => (controller.page ?? 0).round();

    try {
      begin('open');
      unawaited(
        navigator.currentState!.push(
          PageRouteBuilder<void>(
            opaque: false,
            barrierColor: Colors.transparent,
            transitionDuration: const Duration(milliseconds: 200),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            transitionsBuilder: (context, animation, secondaryAnimation, child) =>
                FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
            pageBuilder: (context, animation, secondaryAnimation) => Scaffold(
              backgroundColor: Colors.transparent,
              body: ValueListenableBuilder<int>(
                valueListenable: hostTick,
                builder: (context, tick, _) => LeafViewer(
                  pageCount: _layout.length,
                  pageController: controller,
                  enableChrome: true,
                  enableSwipeGestures: true,
                  backgroundBuilder: (context, progress) => ColoredBox(color: Colors.black.withValues(alpha: 0.87 * (1 - progress))),
                  pageBuilder: buildPage,
                ),
              ),
            ),
          ),
        ),
      );
      await settle(2000);
      end();
      _report('layers-after-open', _layerCounts(tester.binding.renderViews.first.debugLayer!));

      final size = tester.getSize(find.byType(LeafViewer));
      final center = size.center(Offset.zero);
      final last = _layout.length - 1;

      begin('animate');
      for (var i = 0; i < last; i++) {
        unawaited(controller.animateToPage(i + 1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut));
        await settle(650);
      }
      for (var i = last; i > 0; i--) {
        unawaited(controller.animateToPage(i - 1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut));
        await settle(650);
      }
      end();

      begin('fling');
      for (var i = 0; i < 6; i++) {
        await gesture(Offset(size.width * 0.75, center.dy), const Offset(-30, 0), 8);
        await settle(650);
      }
      for (var i = 0; i < 6; i++) {
        await gesture(Offset(size.width * 0.25, center.dy), const Offset(30, 0), 8);
        await settle(650);
      }
      end();

      begin('drag');
      final dragStep = size.width * 0.6 / 40;
      for (var i = 0; i < 4; i++) {
        await gesture(Offset(size.width * 0.85, center.dy), Offset(-dragStep, 0), 40, holdMs: 64);
        await settle(600);
      }
      for (var i = 0; i < 4; i++) {
        await gesture(Offset(size.width * 0.15, center.dy), Offset(dragStep, 0), 40, holdMs: 64);
        await settle(600);
      }
      end();

      begin('dismiss');
      for (var i = 0; i < 4; i++) {
        await gesture(center, Offset(0, size.height * 0.18 / 25), 25, holdMs: 80);
        await settle(900);
      }
      end();

      begin('jump');
      for (var i = 0; i < 3; i++) {
        unawaited(controller.animateToPage(page() + 3 > last ? last : page() + 3, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut));
        await settle(900);
      }
      for (var i = 0; i < 3; i++) {
        unawaited(controller.animateToPage(page() - 3 < 0 ? 0 : page() - 3, duration: const Duration(milliseconds: 400), curve: Curves.easeInOut));
        await settle(900);
      }
      end();

      unawaited(controller.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut));
      await settle(1000);

      begin('host-rebuild');
      for (var i = 0; i < 10; i++) {
        hostTick.value++;
        await settle(200);
      }
      end();
      await settle(3000);

      Future<Map<String, Object>> idle(String name) async {
        begin(name);
        var wanted = 0;
        const slots = 125;
        for (var i = 0; i < slots; i++) {
          await tester.binding.delayed(const Duration(milliseconds: 16));
          if (tester.binding.hasScheduledFrame) wanted++;
          await frame(0);
          clockMs += 16;
        }
        final measured = phase;
        end();
        return {'framesWantedPerSecond': (wanted / (slots * 0.016)).round(), ...measured.toJson()};
      }

      final chrome = LeafViewer.chromeOf(tester.element(find.byType(LeafVideoPage).first))!;
      final hidden = await idle('playing-chrome-hidden');
      final hiddenWasHidden = !chrome.visible;
      chrome.show();
      final visible = await idle('playing-chrome-visible');
      _report('playing-chrome-hidden', {'chromeHidden': hiddenWasHidden, ...hidden});
      _report('playing-chrome-visible', visible);
      _report('layers-end', _layerCounts(tester.binding.renderViews.first.debugLayer!));
    } finally {
      probe.uninstall();
      BenchCounters.scrollProbe = null;
    }

    for (final p in phases.where((p) => !p.name.startsWith('playing'))) {
      _report(p.name, p.toJson());
    }

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    _report('lifecycle-totals', BenchCounters.snapshot());
    imageCache.clear();
  });

  testWidgets('animated image under LeafZoomable.image: rebuilds per image frame', (tester) async {
    final frames = (await tester.runAsync(() async => [for (var i = 0; i < 4; i++) await createTestImage(width: 320, height: 240, cache: false)]))!;
    final provider = _AnimatedTestImage(frames);
    await tester.pumpWidget(
      MaterialApp(
        home: LeafViewer(
          pageCount: 1,
          enableSwipeGestures: true,
          pageBuilder: (context, i) => LeafZoomable.image(image: Image(image: provider, fit: BoxFit.contain)),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    final probe = _Probe()..install();
    final emittedBefore = provider.emitted;
    try {
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      probe.uninstall();
    }
    final emitted = provider.emitted - emittedBefore;
    _report('animated-image', {
      'imageFrames': emitted,
      'rebuilds': probe.rebuilds,
      'rebuildsPerImageFrame': double.parse((probe.rebuilds / emitted).toStringAsFixed(1)),
      'layouts': probe.layouts,
      'paints': probe.paints,
    });
    await tester.pumpWidget(const SizedBox.shrink());
    imageCache.clear();
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('arena: displacement before the PageView drag starts', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final image = (await tester.runAsync(() => createTestImage(width: 300, height: 200)))!;

    Future<Map<String, Object?>> measure(String name, Widget content, {void Function(WidgetTester tester)? prepare}) async {
      double? startPx;
      double? firstMovePx;
      var moved = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n is ScrollStartNotification) startPx ??= moved;
                if (n is ScrollUpdateNotification && (n.scrollDelta ?? 0) != 0) firstMovePx ??= moved;
                return false;
              },
              child: content,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      prepare?.call(tester);
      await tester.pump(const Duration(milliseconds: 500));
      final g = await tester.startGesture(tester.getCenter(find.byType(Scaffold)));
      for (var i = 0; i < 40; i++) {
        moved += 1;
        await g.moveBy(const Offset(-1, 0));
        await tester.pump(const Duration(milliseconds: 8));
      }
      await g.up();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      return {'name': name, 'dragStartPx': startPx, 'firstPageMovePx': firstMovePx};
    }

    Widget zoomable(BuildContext context, int i) => LeafZoomable.image(image: Image(image: _TestImage(300 + i, image), fit: BoxFit.contain));

    final results = [
      await measure('plain PageView', PageView(children: [for (var i = 0; i < 3; i++) ColoredBox(color: Color(0xFF102030 + i))])),
      await measure(
        'PageView with a tap GestureDetector per page',
        PageView(children: [for (var i = 0; i < 3; i++) GestureDetector(onTap: () {}, child: ColoredBox(color: Color(0xFF102030 + i)))]),
      ),
      await measure(
        'LeafViewer, plain pages (no LeafZoomable)',
        LeafViewer(pageCount: 3, enableSwipeGestures: true, pageBuilder: (context, i) => ColoredBox(color: Color(0xFF102030 + i))),
      ),
      await measure('LeafViewer, LeafZoomable at 1x', LeafViewer(pageCount: 3, enableSwipeGestures: true, pageBuilder: zoomable)),
      await measure(
        'LeafViewer, LeafVideoPage + LeafVideoControls',
        LeafViewer(
          pageCount: 3,
          enableSwipeGestures: true,
          enableChrome: true,
          pageBuilder: (context, i) => LeafVideoPage(
            createAdapter: () => BenchVideoAdapter(seed: i),
            url: 'bench://$i',
            controlsBuilder: (context, adapter) => LeafVideoControls(adapter: adapter),
          ),
        ),
      ),
      await measure(
        'LeafViewer, zoomed 3x clamped at right edge',
        LeafViewer(pageCount: 3, enableSwipeGestures: true, pageBuilder: zoomable),
        prepare: (tester) => LeafViewer.controllerOf(tester.element(find.byType(LeafZoomable).first))!
          ..scaleUpdate(3, Offset.zero, Offset.zero)
          ..panBy(const Offset(-100000, 0)),
      ),
      await measure(
        'LeafViewer, zoomed 3x centered (pan claims)',
        LeafViewer(pageCount: 3, enableSwipeGestures: true, pageBuilder: zoomable),
        prepare: (tester) => LeafViewer.controllerOf(tester.element(find.byType(LeafZoomable).first))!..scaleUpdate(3, Offset.zero, Offset.zero),
      ),
    ];
    _report('arena', results);
    imageCache.clear();
  });

  testWidgets('decoded image size per page path', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final bytes = (await tester.runAsync(() async {
      final image = await createTestImage(width: 4000, height: 3000, cache: false);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;

    Future<Map<String, Object?>> decoded(String name, Widget Function(ImageProvider provider) page) async {
      imageCache
        ..clear()
        ..clearLiveImages();
      final provider = MemoryImage(Uint8List.fromList(bytes));
      await tester.pumpWidget(MaterialApp(home: LeafViewer(pageCount: 1, pageBuilder: (context, i) => page(provider))));
      ui.Image? result;
      for (var i = 0; i < 40 && result == null; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        final raws = tester.widgetList<RawImage>(find.byType(RawImage)).where((r) => r.image != null);
        if (raws.isNotEmpty) result = raws.first.image;
      }
      final w = result?.width, h = result?.height;
      await tester.pumpWidget(const SizedBox.shrink());
      return {'name': name, 'decoded': w == null ? null : '${w}x$h', 'mib': w == null ? null : double.parse((w * h! * 4 / 1048576).toStringAsFixed(1))};
    }

    final results = [
      await decoded('LeafZoomable.image(Image(provider))', (p) => LeafZoomable.image(image: Image(image: p, fit: BoxFit.contain))),
      await decoded('LeafZoomable(LeafImage(provider))', (p) => LeafZoomable(child: LeafImage(image: p, fit: BoxFit.contain))),
      await decoded('LeafImage(cacheWidth: 1080)', (p) => LeafZoomable(child: LeafImage(image: p, fit: BoxFit.contain, cacheWidth: 1080))),
      await decoded(
        'Image(ResizeImage(fit 1080x2400))',
        (p) => LeafZoomable.image(
          image: Image(image: ResizeImage(p, width: 1080, height: 2400, policy: ResizeImagePolicy.fit), fit: BoxFit.contain),
        ),
      ),
    ];
    _report('decode', {'viewportPx': '1080x2400', 'sourcePx': '4000x3000', 'results': results});
    imageCache.clear();
  });
}
