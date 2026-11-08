import 'dart:async';

import 'package:flutter/material.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

/// A scriptable adapter: tests push events, the adapter counts calls.
class KitAdapter extends VideoPlayerAdapter {
  KitAdapter({this.total = const Duration(minutes: 24), this._surface});

  final Widget? _surface;
  Duration total;
  final positionCtrl = StreamController<Duration>.broadcast(sync: true);
  final bufferCtrl = StreamController<Duration>.broadcast(sync: true);
  final playingCtrl = StreamController<bool>.broadcast(sync: true);
  final readyCtrl = StreamController<void>.broadcast(sync: true);
  final errorCtrl = StreamController<Object>.broadcast(sync: true);

  Duration pos = Duration.zero;
  Duration buf = Duration.zero;
  bool isPlayingNow = false;
  int plays = 0, pauses = 0, loads = 0, disposes = 0;
  final seeks = <Duration>[];

  void emitPosition(Duration p) {
    pos = p;
    positionCtrl.add(p);
  }

  void emitPlaying(bool on) {
    isPlayingNow = on;
    playingCtrl.add(on);
  }

  @override
  Widget get surface => _surface ?? const ColoredBox(color: Colors.black);

  @override
  Future<void> load({required String url, Map<String, String>? headers}) async {
    loads++;
  }

  @override
  Stream<Duration> get positionStream => positionCtrl.stream;
  @override
  Stream<Duration> get bufferStream => bufferCtrl.stream;
  @override
  Stream<bool> get playingStream => playingCtrl.stream;
  @override
  Stream<void> get readyStream => readyCtrl.stream;
  @override
  Stream<Object> get errorStream => errorCtrl.stream;

  @override
  Duration get position => pos;
  @override
  Duration get duration => total;
  @override
  Duration get buffer => buf;
  @override
  bool get isPlaying => isPlayingNow;

  @override
  void play() {
    plays++;
    emitPlaying(true);
  }

  @override
  void pause() {
    pauses++;
    emitPlaying(false);
  }

  @override
  void playOrPause() => isPlayingNow ? pause() : play();

  @override
  void seek(Duration target) {
    seeks.add(target);
  }

  @override
  void dispose() {
    disposes++;
  }
}

/// [KitAdapter] with every capability the kit reads in phases 1–3.
class FullKitAdapter extends KitAdapter
    with HasVolume, HasPlaybackStatus, HasPlaybackRate, HasTracks, HasChapters, HasBufferedRanges {
  FullKitAdapter({super.total, super.surface});

  final volumeCtrl = StreamController<double>.broadcast(sync: true);
  final durationCtrl = StreamController<Duration>.broadcast(sync: true);
  final bufferingCtrl = StreamController<bool>.broadcast(sync: true);
  final completedCtrl = StreamController<bool>.broadcast(sync: true);
  final rateCtrl = StreamController<double>.broadcast(sync: true);
  final tracksCtrl = StreamController<LeafTracks>.broadcast(sync: true);
  final chaptersCtrl = StreamController<List<LeafChapter>>.broadcast(sync: true);
  final rangesCtrl = StreamController<List<LeafTimeRange>>.broadcast(sync: true);

  double vol = 100;
  double speed = 1;
  LeafTracks trackState = LeafTracks.empty;
  List<LeafChapter> chapterList = const [];

  @override
  Stream<double> get volumeStream => volumeCtrl.stream;
  @override
  double get volume => vol;
  @override
  void setVolume(double volume) {
    vol = volume;
    volumeCtrl.add(volume);
  }

  @override
  Stream<Duration> get durationStream => durationCtrl.stream;
  @override
  Stream<bool> get bufferingStream => bufferingCtrl.stream;
  @override
  bool get isBuffering => false;
  @override
  Stream<bool> get completedStream => completedCtrl.stream;
  @override
  bool get isCompleted => false;

  @override
  Stream<double> get rateStream => rateCtrl.stream;
  @override
  double get rate => speed;
  @override
  void setRate(double rate) {
    speed = rate;
    rateCtrl.add(rate);
  }

  @override
  Stream<LeafTracks> get tracksStream => tracksCtrl.stream;
  @override
  LeafTracks get tracks => trackState;
  @override
  void selectTrack(LeafTrackKind kind, String? id) {
    trackState = LeafTracks(
      video: trackState.video,
      audio: trackState.audio,
      subtitle: trackState.subtitle,
      selectedVideo: kind == LeafTrackKind.video ? id : trackState.selectedVideo,
      selectedAudio: kind == LeafTrackKind.audio ? id : trackState.selectedAudio,
      selectedSubtitle: kind == LeafTrackKind.subtitle ? id : trackState.selectedSubtitle,
    );
    tracksCtrl.add(trackState);
  }

  @override
  Stream<List<LeafChapter>> get chaptersStream => chaptersCtrl.stream;
  @override
  List<LeafChapter> get chapters => chapterList;

  @override
  Stream<List<LeafTimeRange>> get bufferedRangesStream => rangesCtrl.stream;
  @override
  List<LeafTimeRange> get bufferedRanges => const [];
}

/// A surface that counts its State's lifecycle (fullscreen moves it).
class CountingSurface extends StatefulWidget {
  const CountingSurface({super.key});

  static int inits = 0;
  static int disposes = 0;

  static void reset() => inits = disposes = 0;

  @override
  State<CountingSurface> createState() => _CountingSurfaceState();
}

class _CountingSurfaceState extends State<CountingSurface> {
  @override
  void initState() {
    super.initState();
    CountingSurface.inits++;
  }

  @override
  void dispose() {
    CountingSurface.disposes++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Color(0xFF101010), key: ValueKey('counting-surface'));
}
