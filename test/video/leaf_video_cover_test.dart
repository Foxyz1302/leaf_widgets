import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:leaf_widgets/leaf_widgets.dart';

class FakeAdapter extends VideoPlayerAdapter {
  bool playing = false;
  bool disposed = false;
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
  Future<void> load({required String url, Map<String, String>? headers}) async {}

  void emitPlaying(bool value) {
    playing = value;
    _playingCtrl.add(value);
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
  Duration get position => Duration.zero;
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
  testWidgets('the exact tree flow: viewer → sheet → opaque route → back → sheet close', (tester) async {
    final adapter = FakeAdapter();
    final viewerKey = GlobalKey();

    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              PageRouteBuilder(
                opaque: false,
                pageBuilder: (_, _, _) => LeafViewer(
                  key: viewerKey,
                  pageCount: 1,
                  enableChrome: true,
                  pageBuilder: (context, i) => LeafVideoPage(
                    createAdapter: () => adapter,
                    url: 'https://example.com/v.mp4',
                    thumbnail: const Text('thumb'),
                  ),
                ),
              ),
            ),
            child: const Text('open viewer'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open viewer'));
    await tester.pumpAndSettle();
    expect(adapter.playing, isTrue, reason: 'settled video page plays');

    // Open the details sheet over the viewer.
    final viewerContext = viewerKey.currentContext!;
    showModalBottomSheet(
      context: viewerContext,
      isScrollControlled: true,
      builder: (sheetContext) => TextButton(
        onPressed: () => Navigator.of(sheetContext).push(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('the tree'))),
        ),
        child: const Text('tap a tag'),
      ),
    );
    await tester.pumpAndSettle();
    expect(adapter.playing, isFalse, reason: 'sheet covering the viewer pauses the video');

    // Go down the tree: opaque route pushed on top of the sheet.
    await tester.tap(find.text('tap a tag'));
    await tester.pumpAndSettle();
    expect(find.text('the tree'), findsOneWidget);
    expect(adapter.playing, isFalse, reason: 'opaque route over the sheet must keep the video paused');

    // Back out of the tree: sheet still open, still covered.
    Navigator.of(viewerContext).pop();
    await tester.pumpAndSettle();
    expect(adapter.playing, isFalse, reason: 'back under the sheet the video stays paused');

    // Close the sheet: resume.
    Navigator.of(viewerContext).pop();
    await tester.pumpAndSettle();
    expect(adapter.playing, isTrue, reason: 'closing the last cover resumes playback');
  });
}
