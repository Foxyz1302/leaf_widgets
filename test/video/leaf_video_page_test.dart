import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

/// Scripted fake player: records commands, lets tests push stream events.
class FakeAdapter extends VideoPlayerAdapter {
  bool failLoad = false;
  bool disposed = false;
  bool playing = false;
  int loads = 0;
  Duration currentPosition = Duration.zero;

  final plays = <int>[];
  final pauses = <int>[];

  final _positionCtrl = StreamController<Duration>.broadcast();
  final _bufferCtrl = StreamController<Duration>.broadcast();
  final _playingCtrl = StreamController<bool>.broadcast();
  final _readyCtrl = StreamController<void>.broadcast();
  final _errorCtrl = StreamController<Object>.broadcast();

  @override
  Widget get surface => const ColoredBox(color: Color(0xFF332211));

  @override
  Future<void> load({required String url, Map<String, String>? headers}) async {
    loads++;
    if (failLoad) throw Exception('load failed');
  }

  void emitPlaying(bool value) {
    playing = value;
    _playingCtrl.add(value);
  }

  void emitReady() => _readyCtrl.add(null);

  void emitPosition(Duration value) => _positionCtrl.add(value);

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
  void play() {
    playing = true;
    plays.add(plays.length);
  }
  @override
  void pause() {
    playing = false;
    pauses.add(pauses.length);
  }
  @override
  void playOrPause() => playing ? pause() : play();
  @override
  void seek(Duration target) {}
  @override
  void dispose() => disposed = true;
}

void main() {
  late PageController controller;
  final adapters = <int, FakeAdapter>{};
  BuildContext? pageContext;

  Widget harness({required int pageCount, int initialPage = 0, bool enableChrome = false, Map<int, FakeAdapter> inject = const {}}) {
    adapters.clear();
    pageContext = null;
    controller = PageController(initialPage: initialPage);
    return MaterialApp(
      home: Scaffold(
        body: LeafViewer(
          pageCount: pageCount,
          enableChrome: enableChrome,
          pageController: controller,
          pageBuilder: (context, i) {
            pageContext ??= context;
            final adapter = adapters.putIfAbsent(i, () => inject[i] ?? FakeAdapter());
            return LeafVideoPage(
              key: ValueKey(i),
              createAdapter: () => adapter,
              url: 'https://example.com/$i.mp4',
              thumbnail: Text('thumb $i'),
            );
          },
        ),
      ),
    );
  }

  testWidgets('neighbour pages buffer but stay silent; settled page plays', (tester) async {
    await tester.pumpWidget(harness(pageCount: 2));
    await tester.pumpAndSettle();

    expect(adapters[0]!.plays.length, 1);
    expect(adapters[1], isNotNull);
    expect(adapters[1]!.plays, isEmpty);
  });

  testWidgets('neighbours load one at a time, after the settled page shows its first frame', (tester) async {
    await tester.pumpWidget(harness(pageCount: 3, initialPage: 1));
    await tester.pumpAndSettle();
    expect(adapters[1]!.loads, 1);
    expect(adapters[0]!.loads + adapters[2]!.loads, 0);

    adapters[1]!.emitReady();
    await tester.pumpAndSettle();
    expect(adapters[0]!.loads + adapters[2]!.loads, 1, reason: 'one neighbour at a time');

    (adapters[0]!.loads == 1 ? adapters[0]! : adapters[2]!).emitReady();
    await tester.pumpAndSettle();
    expect(adapters[0]!.loads + adapters[2]!.loads, 2);
    expect(adapters[0]!.plays, isEmpty);
    expect(adapters[2]!.plays, isEmpty);
  });

  testWidgets('opening the viewer loads the settled page first; neighbours wait for its first frame', (tester) async {
    await tester.pumpWidget(harness(pageCount: 2));
    await tester.pumpAndSettle();
    expect(adapters[0]!.loads, 1);
    expect(adapters[1]!.loads, 0);

    adapters[0]!.emitReady();
    await tester.pumpAndSettle();
    expect(adapters[1]!.loads, 1);
  });

  testWidgets('a neighbour still waiting to load loads at once when it becomes the settled page', (tester) async {
    await tester.pumpWidget(harness(pageCount: 2));
    await tester.pumpAndSettle();
    expect(adapters[1]!.loads, 0);

    controller.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(adapters[1]!.loads, 1);
    expect(adapters[1]!.playing, isTrue);
  });

  testWidgets('swiping pauses the old page and plays the new one; swiping back resumes', (tester) async {
    await tester.pumpWidget(harness(pageCount: 2));
    await tester.pumpAndSettle();
    expect(adapters[0]!.plays.length, 1);

    controller.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(adapters[0]!.playing, isFalse);
    expect(adapters[1]!.playing, isTrue);

    controller.jumpToPage(0);
    await tester.pumpAndSettle();
    expect(adapters[1]!.playing, isFalse);
    expect(adapters[0]!.playing, isTrue);
  });

  testWidgets('the next video starts only once the swipe has settled', (tester) async {
    await tester.pumpWidget(harness(pageCount: 2));
    await tester.pumpAndSettle();
    final g = await tester.startGesture(const Offset(700, 300));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(-50, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(adapters[1]!.playing, isFalse);
    expect(adapters[0]!.playing, isTrue);

    await g.up();
    await tester.pumpAndSettle();
    expect(adapters[1]!.playing, isTrue);
    expect(adapters[0]!.playing, isFalse);
  });

  testWidgets('ready event drops the thumbnail', (tester) async {
    await tester.pumpWidget(harness(pageCount: 1));
    await tester.pumpAndSettle();
    expect(find.text('thumb 0'), findsOneWidget);

    adapters[0]!.emitReady();
    await tester.pumpAndSettle();
    expect(find.text('thumb 0'), findsNothing);
  });

  testWidgets('load failure shows retry UI; retry reloads and plays', (tester) async {
    await tester.pumpWidget(harness(pageCount: 1, inject: {0: FakeAdapter()..failLoad = true}));
    await tester.pumpAndSettle();
    expect(find.text('Tap to retry'), findsOneWidget);

    adapters[0]!.failLoad = false;
    await tester.tap(find.text('Tap to retry'));
    await tester.pumpAndSettle();
    expect(find.text('Tap to retry'), findsNothing);
    expect(adapters[0]!.plays.length, 1);
  });

  testWidgets('chrome policy: pause shows and holds chrome, playing releases the hold', (tester) async {
    await tester.pumpWidget(harness(pageCount: 1, enableChrome: true));
    await tester.pumpAndSettle();
    final chrome = LeafViewer.chromeOf(pageContext!)!;

    adapters[0]!.emitPlaying(true);
    await tester.pump();

    adapters[0]!.emitPlaying(false);
    await tester.pumpAndSettle();
    expect(chrome.visible, isTrue);
    await tester.pump(const Duration(seconds: 4));
    expect(chrome.visible, isTrue, reason: 'paused video must hold chrome up');

    adapters[0]!.emitPlaying(true);
    await tester.pump(const Duration(seconds: 4));
    expect(chrome.visible, isFalse, reason: 'playing releases the hold; timer hides chrome');
  });

  testWidgets('hidden chrome drops the control bar: no ticking while playing, back on show', (tester) async {
    await tester.pumpWidget(harness(pageCount: 1, enableChrome: true));
    await tester.pumpAndSettle();
    final chrome = LeafViewer.chromeOf(pageContext!)!;
    final adapter = adapters[0]!..emitPlaying(true);
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(chrome.visible, isFalse);
    expect(find.textContaining(' / '), findsNothing);

    adapter.emitPosition(const Duration(seconds: 5));
    await tester.pump();
    expect(tester.binding.transientCallbackCount, 0);

    chrome.show();
    await tester.pump();
    expect(find.text('00:00 / 01:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('scrubber ticks repaint the scrubber, not the whole control bar', (tester) async {
    await tester.pumpWidget(harness(pageCount: 1, enableChrome: true));
    await tester.pumpAndSettle();
    final adapter = adapters[0]!..currentPosition = const Duration(milliseconds: 500);
    adapter.emitPosition(adapter.currentPosition);
    await tester.pump();
    var timeTextPaints = 0;
    debugOnProfilePaint = (renderObject) {
      if (renderObject is RenderParagraph && renderObject.text.toPlainText().contains(' / ')) timeTextPaints++;
    };
    try {
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    } finally {
      debugOnProfilePaint = null;
    }
    expect(timeTextPaints, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('disposing the page disposes the adapter', (tester) async {
    await tester.pumpWidget(harness(pageCount: 1));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(adapters[0]!.disposed, isTrue);
  });

  testWidgets('rebuilding with equal headers does not reload; changed headers do', (tester) async {
    final adapter = FakeAdapter();
    Widget page(String session) => MaterialApp(
          home: LeafVideoPage(
            createAdapter: () => adapter,
            url: 'https://example.com/v.mp4',
            headers: {'Referer': 'https://example.com/', 'X-Session': session},
          ),
        );
    await tester.pumpWidget(page('a'));
    await tester.pumpAndSettle();
    expect(adapter.loads, 1);

    await tester.pumpWidget(page('a'));
    await tester.pumpAndSettle();
    expect(adapter.loads, 1);

    await tester.pumpWidget(page('b'));
    await tester.pumpAndSettle();
    expect(adapter.loads, 2);
  });
}
