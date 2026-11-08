import 'dart:ui';

import 'package:flutter/scheduler.dart';

class FramePhaseRange {
  FramePhaseRange(this.name, this.firstFrame);

  final String name;
  final int firstFrame;
  final _clock = Stopwatch()..start();
  int lastFrame = -1;
  double seconds = 0;

  void end(int frame) {
    lastFrame = frame;
    seconds = _clock.elapsedMicroseconds / 1e6;
  }
}

class FrameRecorder {
  final _timings = <FrameTiming>[];
  final _phases = <FramePhaseRange>[];

  void start() => SchedulerBinding.instance.addTimingsCallback(_timings.addAll);

  void stop() => SchedulerBinding.instance.removeTimingsCallback(_timings.addAll);

  static int get _frameNumber => PlatformDispatcher.instance.frameData.frameNumber;

  void beginPhase(String name) => _phases.add(FramePhaseRange(name, _frameNumber + 1));

  void endPhase() => _phases.last.end(_frameNumber);

  Map<String, Object> summary() {
    final result = <String, Object>{};
    for (final phase in _phases) {
      final frames = _timings.where((t) => t.frameNumber >= phase.firstFrame && t.frameNumber <= phase.lastFrame).toList();
      result[phase.name] = {..._stats(frames), 'fps': phase.seconds > 0 ? (frames.length / phase.seconds).round() : 0};
    }
    final all = _timings.where((t) => _phases.any((p) => t.frameNumber >= p.firstFrame && t.frameNumber <= p.lastFrame)).toList();
    result['all'] = _stats(all);
    return result;
  }

  static Map<String, Object> _stats(List<FrameTiming> frames) => {
    'frames': frames.length,
    'build': _durations(frames.map((t) => t.buildDuration.inMicroseconds).toList()),
    'raster': _durations(frames.map((t) => t.rasterDuration.inMicroseconds).toList()),
    'total': _durations(frames.map((t) => t.totalSpan.inMicroseconds).toList()),
  };

  static Map<String, Object> _durations(List<int> micros) {
    if (micros.isEmpty) return {'n': 0};
    micros.sort();
    double pct(double p) => micros[((micros.length - 1) * p).round()] / 1000;
    return {
      'p50': pct(0.5),
      'p90': pct(0.9),
      'p99': pct(0.99),
      'max': micros.last / 1000,
      'over8': micros.where((us) => us > 8333).length,
      'over16': micros.where((us) => us > 16667).length,
    };
  }
}
