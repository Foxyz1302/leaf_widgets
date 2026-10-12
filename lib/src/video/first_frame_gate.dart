import 'dart:async';
import 'dart:collection';

/// Caps concurrent first-frame decodes across feed tiles.
///
/// The expensive moment is a video's first decode + first texture present.
/// Preloading N tiles at build bursts N of those at once and drops scroll
/// frames. Tiles `await` [enter] before opening media; the gate lets
/// [maxConcurrent] through and queues the rest, releasing the next waiter on
/// [exit] (first frame shown, playback started, or tile disposed).
/// Player-agnostic: works for media_kit and native players alike.
class FirstFrameGate {
  /// Maximum simultaneous first-frame decodes. Two suits midrange SoCs.
  FirstFrameGate({this.maxConcurrent = 2}) : assert(maxConcurrent > 0);

  final int maxConcurrent;

  int _active = 0;
  final _waiters = Queue<Completer<void>>();

  /// Waits for a decode slot. Completes immediately when one is free.
  Future<void> enter() {
    if (_active < maxConcurrent) {
      _active++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  /// Frees this holder's slot, handing it to the longest waiter if any.
  /// Exiting without entering only clamps; it never goes negative.
  void exit() {
    if (_waiters.isNotEmpty) {
      _waiters.removeFirst().complete();
      return;
    }
    if (_active > 0) _active--;
  }

  /// Current holders, for diagnostics.
  int get activeCount => _active;

  /// Queued waiters, for diagnostics.
  int get waitingCount => _waiters.length;
}
