import 'dart:async';

import 'package:flutter/material.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

/// A fake player for the controls demo: a painted moving frame, a 24 min
/// "episode" with chapters, volume, rate, playback status and cached
/// ranges, all in Dart.
class DemoKitAdapter extends VideoPlayerAdapter
    with HasVolume, HasPlaybackStatus, HasPlaybackRate, HasChapters, HasBufferedRanges {
  DemoKitAdapter({this.total = const Duration(minutes: 24), this.withChapters = true});

  final Duration total;
  final bool withChapters;

  final _frame = ValueNotifier(0);
  final _position = StreamController<Duration>.broadcast();
  final _buffer = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _ready = StreamController<void>.broadcast();
  final _error = StreamController<Object>.broadcast();
  final _volume = StreamController<double>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _rate = StreamController<double>.broadcast();
  final _chapters = StreamController<List<LeafChapter>>.broadcast();
  final _ranges = StreamController<List<LeafTimeRange>>.broadcast();

  Timer? _ticker;
  Duration _pos = Duration.zero;
  Duration _cached = Duration.zero;
  bool _isPlaying = false;
  bool _loaded = false;
  bool _readyFired = false;
  double _vol = 100;
  double _speed = 1;
  bool _disposed = false;

  @override
  Widget get surface => RepaintBoundary(child: CustomPaint(painter: _DemoFrame(_frame), size: Size.infinite));

  @override
  Future<void> load({required String url, Map<String, String>? headers}) async {
    _buffering.add(true);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (_disposed) return;
    _loaded = true;
    _duration.add(total);
    _buffering.add(false);
    _cached = const Duration(seconds: 40);
    _buffer.add(_cached);
    _ranges.add(bufferedRanges);
    _chapters.add(chapters);
    if (_isPlaying) _start();
  }

  void _start() {
    _ticker?.cancel();
    if (!_loaded || _disposed) return;
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _frame.value++;
      _pos += Duration(microseconds: (33000 * _speed).round());
      if (_pos >= total) {
        _pos = total;
        _position.add(_pos);
        pause();
        _completed.add(true);
        return;
      }
      _position.add(_pos);
      if (!_readyFired) {
        _readyFired = true;
        _ready.add(null);
      }
      if (_frame.value % 30 == 0) {
        final ahead = _pos + const Duration(seconds: 40);
        _cached = ahead > total ? total : ahead;
        _buffer.add(_cached);
        _ranges.add(bufferedRanges);
      }
    });
  }

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Stream<Duration> get bufferStream => _buffer.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<void> get readyStream => _ready.stream;
  @override
  Stream<Object> get errorStream => _error.stream;
  @override
  Duration get position => _pos;
  @override
  Duration get duration => _loaded ? total : Duration.zero;
  @override
  Duration get buffer => _cached;
  @override
  bool get isPlaying => _isPlaying;

  @override
  void play() {
    if (_disposed || _isPlaying) return;
    if (_pos >= total) _pos = Duration.zero;
    _isPlaying = true;
    _playing.add(true);
    _completed.add(false);
    _start();
  }

  @override
  void pause() {
    if (_disposed) return;
    _ticker?.cancel();
    if (!_isPlaying) return;
    _isPlaying = false;
    _playing.add(false);
  }

  @override
  void playOrPause() => _isPlaying ? pause() : play();

  @override
  void seek(Duration target) {
    _pos = target < Duration.zero ? Duration.zero : (target > total ? total : target);
    _position.add(_pos);
    _completed.add(false);
  }

  @override
  Stream<double> get volumeStream => _volume.stream;
  @override
  double get volume => _vol;
  @override
  void setVolume(double volume) {
    _vol = volume;
    _volume.add(volume);
  }

  @override
  Stream<Duration> get durationStream => _duration.stream;
  @override
  Stream<bool> get bufferingStream => _buffering.stream;
  @override
  bool get isBuffering => !_loaded;
  @override
  Stream<bool> get completedStream => _completed.stream;
  @override
  bool get isCompleted => false;

  @override
  Stream<double> get rateStream => _rate.stream;
  @override
  double get rate => _speed;
  @override
  void setRate(double rate) {
    _speed = rate;
    _rate.add(rate);
  }

  @override
  Stream<List<LeafChapter>> get chaptersStream => _chapters.stream;
  @override
  List<LeafChapter> get chapters {
    if (!withChapters || !_loaded) return const [];
    const starts = [('Prologue', 0), ('OP', 90), ('Part A', 180), ('Part B', 720), ('ED', 1290), ('Preview', 1380)];
    return [
      for (var i = 0; i < starts.length; i++)
        LeafChapter(
          index: i,
          title: starts[i].$1,
          start: Duration(seconds: starts[i].$2),
          end: i + 1 < starts.length ? Duration(seconds: starts[i + 1].$2) : total,
        ),
    ];
  }

  @override
  Stream<List<LeafTimeRange>> get bufferedRangesStream => _ranges.stream;
  @override
  List<LeafTimeRange> get bufferedRanges => [
    LeafTimeRange(_pos > const Duration(seconds: 20) ? _pos - const Duration(seconds: 20) : Duration.zero, _cached),
    if (total > const Duration(minutes: 20)) LeafTimeRange(const Duration(minutes: 20), const Duration(minutes: 21)),
  ];

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _ticker?.cancel();
    for (final c in [_position, _buffer, _playing, _ready, _error, _volume, _duration, _buffering, _completed, _rate, _chapters, _ranges]) {
      c.close();
    }
    _frame.dispose();
  }
}

class _DemoFrame extends CustomPainter {
  _DemoFrame(this.frame) : super(repaint: frame);

  final ValueNotifier<int> frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1B2A3A));
    final t = (frame.value % 180) / 180;
    canvas.drawCircle(
      Offset(size.width * t, size.height / 2),
      size.shortestSide / 6,
      Paint()..color = const Color(0xFF6FCF97),
    );
  }

  @override
  bool shouldRepaint(_DemoFrame oldDelegate) => false;
}
