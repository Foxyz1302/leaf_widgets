import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

class FakeAdapter extends VideoPlayerAdapter {
  bool playing = false;
  bool disposed = false;
  Duration currentPosition = Duration.zero;

  final _positionCtrl = StreamController<Duration>.broadcast();
  final _bufferCtrl = StreamController<Duration>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _readyCtrl = StreamController<void>.broadcast();
  final _errorCtrl = StreamController<Object>.broadcast();

  @override
  Widget get surface => const ColoredBox(color: Color(0xFF332211));

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
  Duration get duration => const Duration(seconds: 60);
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
  void dispose() => disposed = true;
}

class FakeVolumeAdapter extends FakeAdapter implements HasVolume {
  double _volume = 80;
  final setVolumes = <double>[];
  final _volumeCtrl = StreamController<double>.broadcast();

  @override
  Stream<double> get volumeStream => _volumeCtrl.stream;
  @override
  double get volume => _volume;
  @override
  void setVolume(double volume) {
    setVolumes.add(volume);
    _volume = volume;
    _volumeCtrl.add(volume);
  }
}

Widget harness(VideoPlayerAdapter adapter, {Duration hideDelay = const Duration(milliseconds: 500)}) {
  return MaterialApp(
    home: Scaffold(
      body: LeafDesktopVideoControls(adapter: adapter, hideDelay: hideDelay),
    ),
  );
}

AnimatedOpacity barOf(WidgetTester tester) {
  final found = find.byWidgetPredicate((w) => w is AnimatedOpacity && w.child is GestureDetector);
  return tester.widget<AnimatedOpacity>(found);
}

void main() {
  testWidgets('single click anywhere toggles playback', (tester) async {
    final adapter = FakeAdapter();
    await tester.pumpWidget(harness(adapter));
    expect(adapter.playing, isFalse);

    await tester.tap(find.byType(LeafDesktopVideoControls));
    await tester.pump(const Duration(milliseconds: 500));
    expect(adapter.playing, isTrue);

    await tester.tap(find.byType(LeafDesktopVideoControls));
    await tester.pump(const Duration(milliseconds: 500));
    expect(adapter.playing, isFalse);
  });

  testWidgets('bar hides after inactivity while playing, shows on pause', (tester) async {
    final adapter = FakeAdapter()..playing = true;
    await tester.pumpWidget(harness(adapter));
    expect(barOf(tester).opacity, 1.0);

    await tester.pump(const Duration(milliseconds: 600));
    expect(barOf(tester).opacity, 0.0);

    adapter.emitPlaying(false);
    await tester.pump();
    expect(barOf(tester).opacity, 1.0);
  });

  testWidgets('bar stays up while the cursor is active', (tester) async {
    final adapter = FakeAdapter()..playing = true;
    await tester.pumpWidget(harness(adapter));
    await tester.pump(const Duration(milliseconds: 400));
    expect(barOf(tester).opacity, 1.0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(barOf(tester).opacity, 1.0);

    await tester.pump(const Duration(milliseconds: 600));
    expect(barOf(tester).opacity, 0.0);
  });

  testWidgets('hidden bar is dropped after its fade-out: nothing ticks while playing, back on activity', (tester) async {
    final adapter = FakeAdapter()..playing = true;
    await tester.pumpWidget(harness(adapter));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(barOf(tester).opacity, 0.0);
    expect(find.byType(LeafScrubber), findsNothing);

    adapter.emitPosition(const Duration(seconds: 2));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(const Offset(400, 300));
    await tester.pump();
    expect(barOf(tester).opacity, 1.0);
    expect(find.byType(LeafScrubber), findsOneWidget);
  });

  testWidgets('a scrubber tick lays out and repaints nothing above the scrubber', (tester) async {
    final adapter = FakeAdapter()..playing = true;
    await tester.pumpWidget(harness(adapter, hideDelay: const Duration(hours: 1)));
    await tester.pump();
    adapter.emitPosition(const Duration(seconds: 20));
    await tester.pump();
    await tester.pump();

    final laidOut = <String>[];
    var timeTextPaints = 0;
    final saved = debugPrint;
    debugPrintLayouts = true;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.startsWith('Laying out')) laidOut.add(message);
    };
    debugOnProfilePaint = (renderObject) {
      if (renderObject is RenderParagraph && renderObject.text.toPlainText().contains(' / ')) timeTextPaints++;
    };
    try {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugPrint = saved;
      debugPrintLayouts = false;
      debugOnProfilePaint = null;
    }
    expect(laidOut, isEmpty);
    expect(timeTextPaints, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('volume UI only with HasVolume; mute toggles', (tester) async {
    await tester.pumpWidget(harness(FakeAdapter()));
    expect(find.byType(Slider), findsNothing);

    final volume = FakeVolumeAdapter();
    await tester.pumpWidget(harness(volume));
    expect(find.byType(Slider), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_up));
    await tester.pump();
    expect(volume.setVolumes, contains(0.0));
    expect(find.byIcon(Icons.volume_off), findsOneWidget);

    await tester.tap(find.byIcon(Icons.volume_off));
    await tester.pump();
    expect(volume.setVolumes.last, 80.0);
  });

  testWidgets('hovering the scrubber shows the time bubble before clicking', (tester) async {
    final adapter = FakeAdapter();
    await tester.pumpWidget(harness(adapter));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.moveTo(tester.getCenter(find.byType(LeafScrubber)));
    await tester.pump();
    expect(find.text('00:30'), findsOneWidget);

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(find.text('00:30'), findsNothing);
  });
}
