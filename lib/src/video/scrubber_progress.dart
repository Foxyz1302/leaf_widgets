import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'leaf_video_adapter.dart';

/// Mean time between an adapter's advancing position events, in µs. Kept per
/// adapter so a scrubber rebuilt when the controls come back knows it at once.
final _eventIntervals = Expando<double>();

/// Played and buffered extents of a scrubber track, shared by [LeafScrubber]
/// and the touch controls' scrubber, drawn by [ScrubberTrackPainter].
///
/// While the video plays and no drag is in progress, the played position runs
/// on from the last position event at 1× (adapters report no rate), at most
/// two event intervals past it, so a stalled player stops the bar soon after.
/// An event behind the shown position holds the bar until playback catches
/// up; only an event behind the previous one (seek, loop) moves it back.
///
/// Listeners hear about a change only once an edge has moved by a physical
/// pixel. The ticker runs only while playing, and only when the events alone
/// would step the played edge by more than a pixel; otherwise each event
/// repaints. No timers.
class ScrubberProgress extends ChangeNotifier {
  ScrubberProgress(this._adapter, TickerProvider vsync) {
    _ticker = vsync.createTicker((_) => _advance());
    _listen();
  }

  VideoPlayerAdapter _adapter;
  late final Ticker _ticker;
  final _clock = GestureBinding.instance.samplingClock.stopwatch()..start();
  final _subs = <StreamSubscription<Object?>>[];

  bool _playing = false;
  bool _dragging = false;
  bool _running = false;
  double _anchorMs = 0;
  int _anchorUs = 0;
  int? _lastAdvanceUs;
  double _shownMs = 0;
  double _bufferMs = 0;
  double _played = 0;
  double _buffered = 0;

  /// Track width in physical pixels, set at layout.
  double extent = 0;

  /// Played fraction of the track, as last notified.
  double get played => _played;

  /// Buffered fraction of the track, as last notified.
  double get buffered => _buffered;

  set adapter(VideoPlayerAdapter value) {
    if (identical(value, _adapter)) return;
    _cancel();
    _adapter = value;
    _listen();
    _updateTicker();
  }

  /// A drag shows the reported position as it is and stops the extrapolation.
  set dragging(bool value) {
    if (value == _dragging) return;
    _dragging = value;
    if (value) _stop();
    _updateTicker();
  }

  double? get _interval => _eventIntervals[_adapter];

  static double _ms(Duration value) => value.inMicroseconds / 1000;

  void _listen() {
    final adapter = _adapter;
    _playing = adapter.isPlaying;
    _stop();
    _anchorMs = _shownMs = _ms(adapter.position);
    _anchorUs = _clock.elapsedMicroseconds;
    _bufferMs = _ms(adapter.buffer);
    _subs
      ..add(adapter.positionStream.listen(_onPosition))
      ..add(adapter.bufferStream.listen(_onBuffer))
      ..add(adapter.playingStream.listen(_onPlaying));
    _commit();
  }

  void _cancel() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
  }

  void _stop() {
    _running = false;
    _lastAdvanceUs = null;
  }

  void _onPosition(Duration position) {
    final ms = _ms(position);
    if (ms == _anchorMs) return;
    final now = _clock.elapsedMicroseconds;
    final live = _playing && !_dragging;
    if (live && ms > _anchorMs) {
      final last = _lastAdvanceUs;
      if (last != null) {
        final interval = _interval;
        final sample = (now - last).toDouble();
        _eventIntervals[_adapter] = interval == null ? sample : interval + (sample - interval) / 4;
      }
      _running = true;
      if (ms > _shownMs) _shownMs = ms;
    } else {
      _shownMs = ms;
    }
    if (live) _lastAdvanceUs = now;
    _anchorMs = ms;
    _anchorUs = now;
    _commit();
    _updateTicker();
  }

  void _onBuffer(Duration buffer) {
    _bufferMs = _ms(buffer);
    _commit();
  }

  void _onPlaying(bool playing) {
    if (playing == _playing) return;
    _playing = playing;
    if (!playing) _stop();
    _updateTicker();
  }

  void _advance() {
    final interval = _interval;
    if (!_running || interval == null) return;
    final elapsedUs = math.min((_clock.elapsedMicroseconds - _anchorUs).toDouble(), 2 * interval);
    final target = math.min(_anchorMs + elapsedUs / 1000, _ms(_adapter.duration));
    if (target <= _shownMs) return;
    _shownMs = target;
    _commit();
  }

  void _updateTicker() {
    final interval = _interval;
    final totalMs = _ms(_adapter.duration);
    final wanted = _running && interval != null && totalMs > 0 && extent * interval / 1000 / totalMs > 1;
    if (wanted == _ticker.isActive) return;
    if (wanted) {
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }

  void _commit() {
    final totalMs = _ms(_adapter.duration);
    final played = totalMs > 0 ? (_shownMs / totalMs).clamp(0.0, 1.0) : 0.0;
    final buffered = totalMs > 0 ? (_bufferMs / totalMs).clamp(0.0, 1.0) : 0.0;
    if (!_moved(played, _played) && !_moved(buffered, _buffered)) return;
    _played = played;
    _buffered = buffered;
    notifyListeners();
  }

  bool _moved(double next, double shown) => extent > 0 ? (next - shown).abs() * extent >= 1 : next != shown;

  @override
  void dispose() {
    _cancel();
    _ticker.dispose();
    super.dispose();
  }
}

/// Paints a [ScrubberProgress] into a rounded track: background, buffered
/// and played fills, and with [knob] a 12 px white dot centred on the played
/// edge, drawn over the track and past its height.
class ScrubberTrackPainter extends CustomPainter {
  ScrubberTrackPainter(this.progress, {required this.playedColor, this.knob = false}) : super(repaint: progress);

  final ScrubberProgress progress;
  final Color playedColor;
  final bool knob;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final played = Rect.fromLTWH(0, 0, progress.played * size.width, size.height);
    canvas
      ..save()
      ..clipRRect(RRect.fromRectAndRadius(bounds, const Radius.circular(3)))
      ..drawRect(bounds, Paint()..color = Colors.white12)
      ..drawRect(Rect.fromLTWH(0, 0, progress.buffered * size.width, size.height), Paint()..color = Colors.white30)
      ..drawRect(played, Paint()..color = playedColor)
      ..restore();
    if (knob) {
      final x = math.max(6.0, math.min(played.width, size.width - 6));
      canvas.drawCircle(Offset(x, size.height / 2), 6, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(ScrubberTrackPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.playedColor != playedColor || oldDelegate.knob != knob;
}
