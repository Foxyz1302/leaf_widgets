import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

class FakeAdapter extends VideoPlayerAdapter {
  FakeAdapter(this.duration);

  @override
  Duration duration;
  bool playing = true;
  Duration currentPosition = Duration.zero;

  final _positionCtrl = StreamController<Duration>.broadcast();
  final _bufferCtrl = StreamController<Duration>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _readyCtrl = StreamController<void>.broadcast();
  final _errorCtrl = StreamController<Object>.broadcast();

  @override
  Widget get surface => const SizedBox.shrink();

  @override
  Future<void> load({required String url, Map<String, String>? headers}) async {}

  void emitPlaying(bool value) {
    playing = value;
    _playingCtrl.add(value);
  }

  void emitPosition(Duration value) {
    currentPosition = value;
    _positionCtrl.add(value);
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
  Duration get position => currentPosition;
  @override
  Duration get buffer => Duration.zero;
  @override
  bool get isPlaying => playing;

  @override
  void play() => emitPlaying(true);
  @override
  void pause() => emitPlaying(false);
  @override
  void playOrPause() => playing ? pause() : play();
  @override
  void seek(Duration target) {}
  @override
  void dispose() {}
}

typedef _Host = ({String name, Type type, Widget Function(VideoPlayerAdapter adapter) build});

final _hosts = <_Host>[
  (
    name: 'LeafScrubber',
    type: LeafScrubber,
    build: (adapter) => MaterialApp(
      home: Scaffold(body: Center(child: SizedBox(width: 600, child: LeafScrubber(adapter, knob: true)))),
    ),
  ),
  (name: 'LeafVideoControls scrubber', type: LeafVideoControls, build: (adapter) => MaterialApp(home: Scaffold(body: LeafVideoControls(adapter: adapter)))),
];

void main() {
  for (final host in _hosts) {
    testWidgets('${host.name}: long video repaints from events alone; a short clip ticks only while playing', (tester) async {
      final adapter = FakeAdapter(const Duration(minutes: 50));
      await tester.pumpWidget(host.build(adapter));
      expect(find.descendant(of: find.byType(host.type), matching: find.byWidgetPredicate((w) => w is CustomPaint && w.painter != null)), findsOneWidget);
      for (var i = 1; i <= 15; i++) {
        adapter.emitPosition(Duration(milliseconds: 33 * i));
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      adapter.duration = const Duration(seconds: 4);
      for (var i = 16; i <= 18; i++) {
        adapter.emitPosition(Duration(milliseconds: 33 * i));
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      adapter.emitPlaying(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.binding.transientCallbackCount, 0);

      adapter.emitPlaying(true);
      for (var i = 19; i <= 28; i++) {
        adapter.emitPosition(Duration(milliseconds: 33 * i));
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.binding.transientCallbackCount, 0);
    });
  }
}
