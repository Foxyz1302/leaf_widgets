import 'dart:async';

import 'package:flutter/material.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

class BenchCounters {
  static int creates = 0;
  static int loads = 0;
  static int disposes = 0;
  static int pageBuilds = 0;
  static int live = 0;
  static int loaded = 0;
  static int peakLive = 0;
  static int peakLoaded = 0;
  static int createsWhileScrolling = 0;
  static int loadsWhileScrolling = 0;
  static int disposesWhileScrolling = 0;
  static int plays = 0;
  static int playsMidSwipe = 0;
  static int pausesMidSwipe = 0;
  static int decoding = 0;
  static int peakDecoding = 0;
  static final readySeeds = <int>[];

  static bool Function()? scrollProbe;
  static bool Function()? midSwipeProbe;

  static bool get _scrolling => scrollProbe?.call() ?? false;
  static bool get _midSwipe => midSwipeProbe?.call() ?? false;

  static void reset() {
    creates = loads = disposes = pageBuilds = live = loaded = peakLive = peakLoaded = 0;
    createsWhileScrolling = loadsWhileScrolling = disposesWhileScrolling = 0;
    plays = playsMidSwipe = pausesMidSwipe = decoding = peakDecoding = 0;
    readySeeds.clear();
  }

  static void resetPeaks() {
    peakLive = live;
    peakLoaded = loaded;
    peakDecoding = decoding;
  }

  static Map<String, int> snapshot() => {
    'pageBuilds': pageBuilds,
    'creates': creates,
    'loads': loads,
    'disposes': disposes,
    'createsWhileScrolling': createsWhileScrolling,
    'loadsWhileScrolling': loadsWhileScrolling,
    'disposesWhileScrolling': disposesWhileScrolling,
    'plays': plays,
    'playsMidSwipe': playsMidSwipe,
    'pausesMidSwipe': pausesMidSwipe,
  };

  static Map<String, int> peaks() => {'peakLive': peakLive, 'peakLoaded': peakLoaded, 'peakDecoding': peakDecoding};
}

void spin(int ms) {
  if (ms <= 0) return;
  final sw = Stopwatch()..start();
  while (sw.elapsedMicroseconds < ms * 1000) {}
}

class BenchVideoAdapter extends VideoPlayerAdapter {
  BenchVideoAdapter({required this.seed, this.loadCostMs = 0, this.disposeCostMs = 0, int createCostMs = 0}) {
    BenchCounters.creates++;
    if (BenchCounters._scrolling) BenchCounters.createsWhileScrolling++;
    BenchCounters.live++;
    BenchCounters.peakLive = BenchCounters.peakLive < BenchCounters.live ? BenchCounters.live : BenchCounters.peakLive;
    spin(createCostMs);
  }

  final int seed;
  final int loadCostMs;
  final int disposeCostMs;

  final ValueNotifier<int> _frame = ValueNotifier(0);
  final _positionCtrl = StreamController<Duration>.broadcast();
  final _bufferCtrl = StreamController<Duration>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _readyCtrl = StreamController<void>.broadcast();
  final _errorCtrl = StreamController<Object>.broadcast();

  Timer? _ticker;
  bool _loadStarted = false;
  bool _awaitingFirstFrame = false;
  bool _loaded = false;
  bool _playing = false;
  bool _disposed = false;
  Duration _position = Duration.zero;
  Duration _buffer = Duration.zero;

  @override
  Widget get surface => RepaintBoundary(child: CustomPaint(painter: _FramePainter(_frame, seed), size: Size.infinite));

  @override
  Future<void> load({required String url, Map<String, String>? headers}) async {
    BenchCounters.loads++;
    if (BenchCounters._scrolling) BenchCounters.loadsWhileScrolling++;
    if (!_loadStarted) {
      _loadStarted = true;
      BenchCounters.loaded++;
      BenchCounters.peakLoaded = BenchCounters.peakLoaded < BenchCounters.loaded ? BenchCounters.loaded : BenchCounters.peakLoaded;
    }
    _beginFirstFrame();
    spin(loadCostMs);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (_disposed) return;
    _loaded = true;
    _buffer = const Duration(seconds: 8);
    _bufferCtrl.add(_buffer);
    Future<void>.delayed(const Duration(milliseconds: 80), () {
      if (_disposed) return;
      _endFirstFrame();
      BenchCounters.readySeeds.add(seed);
      _readyCtrl.add(null);
    });
    if (_playing) _start();
  }

  void _beginFirstFrame() {
    if (_awaitingFirstFrame) return;
    _awaitingFirstFrame = true;
    BenchCounters.decoding++;
    if (BenchCounters.decoding > BenchCounters.peakDecoding) BenchCounters.peakDecoding = BenchCounters.decoding;
  }

  void _endFirstFrame() {
    if (!_awaitingFirstFrame) return;
    _awaitingFirstFrame = false;
    BenchCounters.decoding--;
  }

  void _start() {
    _ticker?.cancel();
    if (!_loaded || _disposed) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _frame.value++;
      _position += const Duration(milliseconds: 33);
      if (_position >= duration) _position = Duration.zero;
      _positionCtrl.add(_position);
      if (_frame.value % 15 == 0) {
        _buffer = _position + const Duration(seconds: 8);
        _bufferCtrl.add(_buffer);
      }
    });
  }

  @override
  Stream<Duration> get positionStream => _positionCtrl.stream;
  @override
  Stream<Duration> get bufferStream => _bufferCtrl.stream;
  @override
  Stream<bool> get playingStream => _playingCtrl.stream;
  @override
  Stream<void> get readyStream => _readyCtrl.stream;
  @override
  Stream<Object> get errorStream => _errorCtrl.stream;

  @override
  Duration get position => _position;
  @override
  Duration get duration => const Duration(seconds: 60);
  @override
  Duration get buffer => _buffer;
  @override
  bool get isPlaying => _playing;

  @override
  void play() {
    if (_disposed || _playing) return;
    BenchCounters.plays++;
    if (BenchCounters._midSwipe) BenchCounters.playsMidSwipe++;
    _playing = true;
    _playingCtrl.add(true);
    _start();
  }

  @override
  void pause() {
    if (_disposed) return;
    _ticker?.cancel();
    _ticker = null;
    if (!_playing) return;
    if (BenchCounters._midSwipe) BenchCounters.pausesMidSwipe++;
    _playing = false;
    _playingCtrl.add(false);
  }

  @override
  void playOrPause() => _playing ? pause() : play();

  @override
  void seek(Duration target) {
    _position = target;
    _positionCtrl.add(target);
  }

  @override
  void dispose() {
    if (_disposed) return;
    BenchCounters.disposes++;
    if (BenchCounters._scrolling) BenchCounters.disposesWhileScrolling++;
    BenchCounters.live--;
    if (_loadStarted) BenchCounters.loaded--;
    _endFirstFrame();
    spin(disposeCostMs);
    _disposed = true;
    _ticker?.cancel();
    _positionCtrl.close();
    _bufferCtrl.close();
    _playingCtrl.close();
    _readyCtrl.close();
    _errorCtrl.close();
    _frame.dispose();
  }
}

class _FramePainter extends CustomPainter {
  _FramePainter(this.frame, this.seed) : super(repaint: frame);

  final ValueNotifier<int> frame;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final hue = (seed * 53 % 360).toDouble();
    canvas.drawRect(Offset.zero & size, Paint()..color = HSVColor.fromAHSV(1, hue, 0.5, 0.35).toColor());
    final t = (frame.value % 90) / 90;
    canvas.drawCircle(
      Offset(size.width * t, size.height / 2),
      size.shortestSide / 6,
      Paint()..color = HSVColor.fromAHSV(1, (hue + 180) % 360, 0.6, 0.9).toColor(),
    );
  }

  @override
  bool shouldRepaint(_FramePainter oldDelegate) => oldDelegate.seed != seed || oldDelegate.frame != frame;
}

/// [BenchVideoAdapter] with the capabilities the controls kit reads: volume
/// (the volume item, wheel, readout) and chapters (the chapter buttons and
/// marks).
class BenchKitAdapter extends BenchVideoAdapter with HasVolume, HasChapters {
  BenchKitAdapter({required super.seed});

  final _volume = StreamController<double>.broadcast();
  double _level = 100;

  @override
  Stream<double> get volumeStream => _volume.stream;
  @override
  double get volume => _level;
  @override
  void setVolume(double volume) {
    _level = volume;
    _volume.add(volume);
  }

  @override
  Stream<List<LeafChapter>> get chaptersStream => const Stream.empty();
  @override
  List<LeafChapter> get chapters => const [
    LeafChapter(index: 0, title: 'Intro', start: Duration.zero, end: Duration(seconds: 10)),
    LeafChapter(index: 1, title: 'Main', start: Duration(seconds: 10), end: Duration(seconds: 50)),
    LeafChapter(index: 2, title: 'Credits', start: Duration(seconds: 50), end: Duration(seconds: 60)),
  ];

  @override
  void dispose() {
    _volume.close();
    super.dispose();
  }
}
