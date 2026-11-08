import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';

import 'leaf_player_controller.dart';

/// The position the seek bar and the clock paint: [LeafPlayerController.position]
/// (about 10 Hz) run on between events, ported from leaf's legacy
/// `ScrubberProgress`.
///
/// While playing (no pending seek), the position runs on from the last
/// event by the elapsed time × the playback rate, at most two event
/// intervals past it, so a stalled player stops soon after. An event behind
/// the shown position holds it until playback catches up; only an event
/// behind the previous one (seek, loop) moves it back.
///
/// One per controller ([of]), shared by its consumers. Each consumer
/// [want]s a resolution (the time one of its steps stands for: a physical
/// pixel of the bar, a second of the clock) and repaints only when the
/// position crosses one. The ticker runs only while playing and only when
/// the events alone would step the finest resolution by more than one; no
/// timers. Without consumers it does not listen at all.
class LeafSmoothPosition extends ChangeNotifier {
  LeafSmoothPosition._(this._c);

  static final _shared = Expando<LeafSmoothPosition>('LeafSmoothPosition');

  static LeafSmoothPosition of(LeafPlayerController controller) => _shared[controller] ??= LeafSmoothPosition._(controller);

  final LeafPlayerController _c;
  late final Ticker _ticker = Ticker((_) => _advance(), debugLabel: 'LeafSmoothPosition');
  final _clock = GestureBinding.instance.samplingClock.stopwatch()..start();
  final _wants = <Object, double Function()>{};

  bool _listening = false;
  bool _running = false;
  double? _interval;
  double _anchorMs = 0;
  int _anchorUs = 0;
  int? _lastAdvanceUs;
  double _shownMs = 0;

  /// The position to paint: the pending seek while there is one.
  Duration get value => _c.pendingSeek.value ?? Duration(microseconds: (_shownMs * 1000).round());

  /// Registers [owner] with its resolution in ms ([stepMs], read whenever
  /// the ticker is reconsidered). Call again when the resolution changes.
  void want(Object owner, double Function() stepMs) {
    _wants[owner] = stepMs;
    if (!_listening) _listen();
    _updateTicker();
  }

  void release(Object owner) {
    if (_wants.remove(owner) == null) return;
    if (_wants.isEmpty) {
      _unlisten();
    } else {
      _updateTicker();
    }
  }

  static double _ms(Duration d) => d.inMicroseconds / 1000;

  double get _rate => _c.rate?.value ?? 1.0;

  bool get _live => _c.playing.value && _c.pendingSeek.value == null;

  void _listen() {
    _listening = true;
    _c.position.addListener(_onPosition);
    _c.playing.addListener(_onPlaying);
    _c.pendingSeek.addListener(_onPending);
    _c.rate?.addListener(_updateTicker);
    _c.duration.addListener(_updateTicker);
    _stop();
    _anchorMs = _shownMs = _ms(_c.position.value);
    _anchorUs = _clock.elapsedMicroseconds;
  }

  void _unlisten() {
    _listening = false;
    _c.position.removeListener(_onPosition);
    _c.playing.removeListener(_onPlaying);
    _c.pendingSeek.removeListener(_onPending);
    _c.rate?.removeListener(_updateTicker);
    _c.duration.removeListener(_updateTicker);
    _stop();
    if (_ticker.isActive) _ticker.stop();
  }

  void _stop() {
    _running = false;
    _lastAdvanceUs = null;
  }

  void _onPosition() {
    final ms = _ms(_c.position.value);
    if (ms == _anchorMs) return;
    final now = _clock.elapsedMicroseconds;
    final live = _live;
    if (live && ms > _anchorMs) {
      final last = _lastAdvanceUs;
      if (last != null) {
        final interval = _interval;
        final sample = (now - last).toDouble();
        _interval = interval == null ? sample : interval + (sample - interval) / 4;
      }
      _running = true;
      if (ms > _shownMs) _shownMs = ms;
    } else {
      _shownMs = ms;
    }
    if (live) _lastAdvanceUs = now;
    _anchorMs = ms;
    _anchorUs = now;
    notifyListeners();
    _updateTicker();
  }

  void _onPlaying() {
    if (!_live) _stop();
    _updateTicker();
  }

  void _onPending() {
    final pending = _c.pendingSeek.value;
    _stop();
    if (pending == null) {
      _anchorMs = _shownMs = _ms(_c.position.value);
      _anchorUs = _clock.elapsedMicroseconds;
    } else {
      _anchorMs = _shownMs = _ms(pending);
    }
    notifyListeners();
    _updateTicker();
  }

  void _advance() {
    final interval = _interval;
    if (!_running || interval == null || !_live) return;
    final elapsedUs = math.min((_clock.elapsedMicroseconds - _anchorUs).toDouble(), 2 * interval);
    final total = _ms(_c.duration.value);
    var target = _anchorMs + elapsedUs / 1000 * _rate;
    if (total > 0) target = math.min(target, total);
    if (target <= _shownMs) return;
    _shownMs = target;
    notifyListeners();
  }

  void _updateTicker() {
    final interval = _interval;
    var finest = double.infinity;
    for (final step in _wants.values) {
      finest = math.min(finest, step());
    }
    final wanted = _listening && _running && _live && interval != null && interval / 1000 * _rate > finest;
    if (wanted == _ticker.isActive) return;
    if (wanted) {
      _ticker.start();
    } else {
      _ticker.stop();
    }
  }
}
