import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

import 'bench_video_adapter.dart';
import 'frame_stats.dart';

const _createCostMs = int.fromEnvironment('BENCH_CREATE_COST_MS');
const _loadCostMs = int.fromEnvironment('BENCH_LOAD_COST_MS');
const _disposeCostMs = int.fromEnvironment('BENCH_DISPOSE_COST_MS');
const _outPath = String.fromEnvironment('BENCH_OUT');
const _autoExit = bool.fromEnvironment('BENCH_EXIT', defaultValue: true);

/// Scripted swipe benchmark over a mixed image/video [LeafViewer]:
/// `flutter run --profile -t lib/bench/viewer_bench.dart`. Prints one
/// `BENCH_PHASE` line per phase and a final `BENCH_RESULT` line.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final media = await _BenchMedia.generate();
  runApp(_BenchApp(media: media));
}

enum _Kind { image, leafImage, video }

class _PageSpec {
  const _PageSpec(this.kind, this.image);

  final _Kind kind;
  final ImageProvider image;
}

class _BenchMedia {
  _BenchMedia(this.pages, this.tiles);

  final List<_PageSpec> pages;
  final List<ImageProvider> tiles;

  static const _layout = [
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

  static Future<_BenchMedia> generate() async {
    final pages = <_PageSpec>[];
    for (var i = 0; i < _layout.length; i++) {
      final bytes = await switch (_layout[i]) {
        _Kind.video => _png(480, 270, i),
        _ when i == 4 => _png(6000, 4000, i),
        _ => _png(3000, 2000, i),
      };
      pages.add(_PageSpec(_layout[i], MemoryImage(bytes)));
    }
    final tiles = <ImageProvider>[for (var i = 0; i < 24; i++) MemoryImage(await _png(256, 256, 100 + i))];
    return _BenchMedia(pages, tiles);
  }

  static Future<Uint8List> _png(int width, int height, int seed) async {
    final rnd = math.Random(seed);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final w = width.toDouble(), h = height.toDouble();
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), [
          HSVColor.fromAHSV(1, (seed * 47 % 360).toDouble(), 0.6, 0.8).toColor(),
          HSVColor.fromAHSV(1, ((seed * 47 + 140) % 360).toDouble(), 0.7, 0.3).toColor(),
        ]),
    );
    for (var i = 0; i < 300; i++) {
      canvas.drawCircle(
        Offset(rnd.nextDouble() * w, rnd.nextDouble() * h),
        rnd.nextDouble() * w / 18,
        Paint()..color = Color(0xFF000000 | rnd.nextInt(0xFFFFFF)).withValues(alpha: 0.45),
      );
    }
    final image = await recorder.endRecording().toImage(width, height);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }
}

class _BenchApp extends StatelessWidget {
  const _BenchApp({required this.media});

  final _BenchMedia media;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark)),
      home: _GridPage(media: media),
    );
  }
}

class _GridPage extends StatefulWidget {
  const _GridPage({required this.media});

  final _BenchMedia media;

  @override
  State<_GridPage> createState() => _GridPageState();
}

class _GridPageState extends State<_GridPage> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1200), _openViewer);
  }

  void _openViewer() {
    if (!mounted) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
        pageBuilder: (context, animation, secondaryAnimation) => _ViewerPage(media: widget.media),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tiles = widget.media.tiles;
    return Scaffold(
      body: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 6, mainAxisSpacing: 4, crossAxisSpacing: 4),
        itemCount: tiles.length,
        itemBuilder: (context, i) => LeafImage(image: tiles[i], fit: BoxFit.cover),
      ),
    );
  }
}

class _ViewerPage extends StatefulWidget {
  const _ViewerPage({required this.media});

  final _BenchMedia media;

  @override
  State<_ViewerPage> createState() => _ViewerPageState();
}

class _ViewerPageState extends State<_ViewerPage> {
  final _controller = PageController();
  final _recorder = FrameRecorder();
  final _clock = Stopwatch()..start();
  final _session = 's${DateTime.now().microsecondsSinceEpoch}';
  final _counters = <String, Map<String, int>>{};
  Map<String, int> _phaseStart = const {};
  int _pointer = 1000;
  BuildContext? _pageContext;
  bool? _chromeHiddenDuringPlayback;

  @override
  void initState() {
    super.initState();
    BenchCounters.scrollProbe = () => _controller.hasClients && _controller.position.isScrollingNotifier.value;
    BenchCounters.midSwipeProbe = () {
      final page = _controller.hasClients ? _controller.page : null;
      return page != null && (page - page.round()).abs() > 0.01;
    };
    _recorder.start();
    _beginPhase('open');
    unawaited(_run());
  }

  @override
  void dispose() {
    BenchCounters.scrollProbe = null;
    BenchCounters.midSwipeProbe = null;
    _recorder.stop();
    _controller.dispose();
    super.dispose();
  }

  void _beginPhase(String name) {
    _phaseStart = BenchCounters.snapshot();
    BenchCounters.resetPeaks();
    _recorder.beginPhase(name);
    _counters[name] = const {};
  }

  void _endPhase(String name) {
    _recorder.endPhase();
    final now = BenchCounters.snapshot();
    _counters[name] = {for (final e in now.entries) e.key: e.value - (_phaseStart[e.key] ?? 0), ...BenchCounters.peaks()};
  }

  Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  int get _page => (_controller.page ?? 0).round();

  Future<void> _gesture(Offset from, Offset step, int moves, {int holdMs = 0}) async {
    final viewId = View.of(context).viewId;
    final pointer = _pointer++;
    void send(PointerEvent event) => GestureBinding.instance.handlePointerEvent(event);
    var position = from;
    send(PointerDownEvent(pointer: pointer, position: position, viewId: viewId, timeStamp: _clock.elapsed));
    for (var i = 0; i < moves; i++) {
      await _wait(8);
      position += step;
      send(PointerMoveEvent(pointer: pointer, position: position, delta: step, viewId: viewId, timeStamp: _clock.elapsed));
    }
    if (holdMs > 0) await _wait(holdMs);
    await _wait(8);
    send(PointerUpEvent(pointer: pointer, position: position, viewId: viewId, timeStamp: _clock.elapsed));
  }

  Future<void> _run() async {
    await _wait(1800);
    if (!mounted) return;
    _endPhase('open');
    final last = widget.media.pages.length - 1;
    final size = MediaQuery.sizeOf(context);
    final center = size.center(Offset.zero);

    _beginPhase('animate');
    for (var i = 0; i < last; i++) {
      await _controller.animateToPage(i + 1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      await _wait(350);
    }
    for (var i = last; i > 0; i--) {
      await _controller.animateToPage(i - 1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      await _wait(350);
    }
    _endPhase('animate');

    _beginPhase('fling');
    for (var i = 0; i < 6; i++) {
      await _gesture(Offset(size.width * 0.75, center.dy), const Offset(-45, 0), 8);
      await _wait(650);
    }
    for (var i = 0; i < 6; i++) {
      await _gesture(Offset(size.width * 0.25, center.dy), const Offset(45, 0), 8);
      await _wait(650);
    }
    _endPhase('fling');

    _beginPhase('drag');
    final dragStep = size.width * 0.55 / 50;
    for (var i = 0; i < 4; i++) {
      await _gesture(Offset(size.width * 0.85, center.dy), Offset(-dragStep, 0), 50, holdMs: 60);
      await _wait(600);
    }
    for (var i = 0; i < 4; i++) {
      await _gesture(Offset(size.width * 0.15, center.dy), Offset(dragStep, 0), 50, holdMs: 60);
      await _wait(600);
    }
    _endPhase('drag');

    _beginPhase('dismiss');
    for (var i = 0; i < 4; i++) {
      await _gesture(center, Offset(0, size.height * 0.2 / 25), 25, holdMs: 80);
      await _wait(900);
    }
    _endPhase('dismiss');

    _beginPhase('jump');
    for (var i = 0; i < 3; i++) {
      await _controller.animateToPage(math.min(_page + 3, last), duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      await _wait(500);
    }
    for (var i = 0; i < 3; i++) {
      await _controller.animateToPage(math.max(_page - 3, 0), duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      await _wait(500);
    }
    _endPhase('jump');

    await _controller.animateToPage(1, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    await _wait(4500);
    _beginPhase('playing-hidden');
    await _wait(3000);
    _endPhase('playing-hidden');
    final pageContext = _pageContext;
    final chrome = pageContext != null && pageContext.mounted ? LeafViewer.chromeOf(pageContext) : null;
    _chromeHiddenDuringPlayback = chrome == null ? null : !chrome.visible;
    chrome?.show();
    _beginPhase('playing-visible');
    await _wait(2000);
    _endPhase('playing-visible');

    for (var i = 0; i < 90; i++) {
      SchedulerBinding.instance.scheduleFrame();
      await SchedulerBinding.instance.endOfFrame;
    }
    await _wait(1200);
    _report();
  }

  void _report() {
    final phases = _recorder.summary();
    for (final entry in phases.entries) {
      final stats = Map<String, Object>.of(entry.value as Map<String, Object>);
      final counters = _counters[entry.key];
      if (counters != null) stats['counters'] = counters;
      phases[entry.key] = stats;
      debugPrint('BENCH_PHASE ${entry.key} ${jsonEncode(stats)}');
    }
    final result = {
      'config': {'createCostMs': _createCostMs, 'loadCostMs': _loadCostMs, 'disposeCostMs': _disposeCostMs},
      'chromeHiddenDuringPlayback': ?_chromeHiddenDuringPlayback,
      'phases': phases,
    };
    final json = jsonEncode(result);
    debugPrint('BENCH_RESULT $json');
    if (_outPath.isNotEmpty) File(_outPath).writeAsStringSync(json);
    if (_autoExit && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) exit(0);
  }

  Widget _buildPage(BuildContext context, int index) {
    BenchCounters.pageBuilds++;
    _pageContext ??= context;
    final spec = widget.media.pages[index];
    final child = switch (spec.kind) {
      _Kind.image => LeafZoomable.image(image: Image(image: spec.image, fit: BoxFit.contain, filterQuality: FilterQuality.high)),
      _Kind.leafImage => LeafZoomable(child: LeafImage(image: spec.image, fit: BoxFit.contain)),
      _Kind.video => LeafVideoPage(
        createAdapter: () =>
            BenchVideoAdapter(seed: index, createCostMs: _createCostMs, loadCostMs: _loadCostMs, disposeCostMs: _disposeCostMs),
        url: 'bench://video/$index',
        headers: {'Referer': 'https://bench.local/', 'X-Session': _session},
        aspectRatio: 16 / 9,
        thumbnail: Image(image: spec.image, fit: BoxFit.cover),
        controlsBuilder: (context, adapter) => LeafVideoControls(adapter: adapter),
      ),
    };
    return LeafViewerHero(tag: 'bench_$index', child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: LeafViewer(
        pageCount: widget.media.pages.length,
        pageController: _controller,
        enableChrome: true,
        enableSwipeGestures: true,
        controlsBuilder: (context, controls) => const SizedBox.shrink(),
        backgroundBuilder: (context, progress) => ColoredBox(color: Colors.black.withValues(alpha: 0.87 * (1 - progress))),
        pageBuilder: _buildPage,
      ),
    );
  }
}
