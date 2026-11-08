import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';
import 'package:leaf_widgets/src/video/controls/media_math.dart' show chaptersFromStarts;

import 'kit_fakes.dart';

Duration s(num secs) => Duration(milliseconds: (secs * 1000).round());

class _Fullscreen implements LeafFullscreenHandle {
  _Fullscreen(this.controller);

  final LeafPlayerController controller;
  int enters = 0, exits = 0;

  @override
  bool get canFullscreen => true;

  @override
  void enterFullscreen() {
    enters++;
    controller.setFullscreen(true);
  }

  @override
  void exitFullscreen() {
    exits++;
    controller.setFullscreen(false);
  }
}

void main() {
  group('throttled position', () {
    testWidgets('30 Hz in gives at most 10 Hz out, and the trailing value lands', (tester) async {
      final a = KitAdapter();
      final c = LeafPlayerController(a);
      final seen = <Duration>[];
      void l() => seen.add(c.position.value);
      c.position.addListener(l);
      for (var i = 1; i <= 30; i++) {
        a.emitPosition(Duration(milliseconds: 33 * i));
        await tester.pump(const Duration(milliseconds: 33));
      }
      await tester.pump(const Duration(milliseconds: 200));
      expect(seen.length, lessThanOrEqualTo(11));
      expect(seen.length, greaterThanOrEqualTo(9));
      expect(seen.last, const Duration(milliseconds: 990));
      c.position.removeListener(l);
      c.dispose();
    });

    testWidgets('no timer and no notifications without listeners; value stays raw', (tester) async {
      final a = KitAdapter();
      final c = LeafPlayerController(a);
      a.emitPosition(s(1));
      a.emitPosition(s(2));
      expect(c.position.debugTimerActive, isFalse);
      expect(c.position.value, s(2));
      void l() {}
      c.position.addListener(l);
      a.emitPosition(s(3));
      expect(c.position.debugTimerActive, isTrue);
      c.position.removeListener(l);
      expect(c.position.debugTimerActive, isFalse);
      expect(c.debugPositionListeners, 0);
      c.dispose();
    });

    testWidgets('seek and play/pause flush at once', (tester) async {
      final a = KitAdapter();
      final c = LeafPlayerController(a);
      var count = 0;
      void l() => count++;
      c.position.addListener(l);
      a.emitPosition(s(1));
      expect(count, 1);
      a.emitPosition(s(1.03));
      expect(count, 1);
      c.seek(s(30));
      expect(count, 2);
      a.emitPosition(s(30));
      expect(count, 3, reason: 'the cooldown was dropped by the seek');
      a.emitPlaying(true);
      expect(count, 4);
      await tester.pump(const Duration(seconds: 3));
      c.position.removeListener(l);
      c.dispose();
    });
  });

  testWidgets('positionSeconds notifies once per displayed second', (tester) async {
    final a = KitAdapter();
    final c = LeafPlayerController(a);
    var count = 0;
    c.positionSeconds.addListener(() => count++);
    for (var ms = 0; ms <= 3000; ms += 100) {
      a.emitPosition(Duration(milliseconds: ms));
    }
    expect(count, 3);
    expect(c.positionSeconds.value, 3);
    c.dispose();
  });

  group('duration', () {
    testWidgets('from the stream when the adapter has HasPlaybackStatus', (tester) async {
      final a = FullKitAdapter(total: s(60));
      final c = LeafPlayerController(a);
      a.total = s(90);
      a.emitPosition(s(1));
      expect(c.duration.value, s(60), reason: 'the getter is not polled');
      a.durationCtrl.add(s(120));
      expect(c.duration.value, s(120));
      c.dispose();
    });

    testWidgets('else re-read on player events, change-detected', (tester) async {
      final a = KitAdapter(total: Duration.zero);
      final c = LeafPlayerController(a);
      var count = 0;
      c.duration.addListener(() => count++);
      a.total = s(60);
      a.emitPosition(s(1));
      a.emitPosition(s(2));
      a.bufferCtrl.add(s(5));
      expect(c.duration.value, s(60));
      expect(count, 1);
      c.dispose();
    });

    testWidgets('without HasPlaybackStatus, buffering until the first frame', (tester) async {
      final a = KitAdapter();
      final c = LeafPlayerController(a);
      expect(c.buffering.value, isTrue);
      a.readyCtrl.add(null);
      expect(c.buffering.value, isFalse);
      c.dispose();
    });
  });

  group('pending seek', () {
    testWidgets('shown until the player is within 1.5 s of it', (tester) async {
      final a = KitAdapter();
      final c = LeafPlayerController(a);
      a.emitPosition(s(5));
      c.seek(s(600));
      expect(c.pendingSeek.value, s(600));
      expect(c.positionSeconds.value, 600);
      a.emitPosition(s(5.1));
      expect(c.pendingSeek.value, s(600), reason: 'the old position arrived first');
      expect(c.positionSeconds.value, 600);
      a.emitPosition(s(599));
      expect(c.pendingSeek.value, isNull);
      expect(c.positionSeconds.value, 599);
      c.dispose();
    });

    testWidgets('dropped after 2 s without catching up', (tester) async {
      final a = KitAdapter();
      final c = LeafPlayerController(a);
      c.seek(s(600));
      await tester.pump(const Duration(milliseconds: 1900));
      expect(c.pendingSeek.value, s(600));
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.pendingSeek.value, isNull);
      expect(c.positionSeconds.value, 0);
      c.dispose();
    });

    testWidgets('seekBy steps from the pending target, so key repeats add up', (tester) async {
      final a = KitAdapter();
      final c = LeafPlayerController(a);
      c.seekBy(s(5));
      c.seekBy(s(5));
      expect(a.seeks, [s(5), s(10)]);
      c.seekBy(-s(60));
      expect(a.seeks.last, Duration.zero);
      c.seek(s(99999));
      expect(a.seeks.last, a.total, reason: 'clamped to the duration');
      await tester.pump(const Duration(seconds: 3));
      c.dispose();
    });
  });

  testWidgets('currentChapter and skipOffer notify only on change', (tester) async {
    final a = FullKitAdapter(total: s(24 * 60));
    final c = LeafPlayerController(a);
    a.durationCtrl.add(s(24 * 60));
    a.chaptersCtrl.add(chaptersFromStarts([('Prologue', Duration.zero), ('OP', s(30)), ('Part A', s(120))], s(24 * 60)));
    var chapterTicks = 0, offerTicks = 0;
    c.currentChapter.addListener(() => chapterTicks++);
    c.skipOffer.addListener(() => offerTicks++);
    for (var t = 0.0; t < 40; t += 0.5) {
      a.emitPosition(s(t));
    }
    expect(c.currentChapter.value, 1);
    expect(chapterTicks, 1);
    expect(c.skipOffer.value?.label, 'Skip OP');
    expect(offerTicks, 1);
    expect(c.execute(const LeafPlayerCommand.skip()), isTrue);
    expect(a.seeks.last, s(120));
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  });

  group('volume', () {
    testWidgets('steps of 5 clamped to the max; mute restores; each step flashes', (tester) async {
      final a = FullKitAdapter();
      final c = LeafPlayerController(a, volumeMax: 100);
      a.setVolume(98);
      c.execute(const LeafPlayerCommand.stepVolume(1));
      expect(a.vol, 100);
      c.execute(const LeafPlayerCommand.stepVolume(-2));
      expect(a.vol, 90);
      c.toggleMute();
      expect(a.vol, 0);
      c.toggleMute();
      expect(a.vol, 90);
      expect(c.volumeFlash.value, 4);
      c.execute(const LeafPlayerCommand.setVolume(250));
      expect(a.vol, 100);
      c.dispose();
    });

    testWidgets('without HasVolume: unhandled, no volume listenable', (tester) async {
      final c = LeafPlayerController(KitAdapter());
      expect(c.volume, isNull);
      expect(c.execute(const LeafPlayerCommand.stepVolume(1)), isFalse);
      expect(c.execute(const LeafPlayerCommand.toggleMute()), isFalse);
      c.dispose();
    });
  });

  testWidgets('rate steps on the quarter grid and resets', (tester) async {
    final a = FullKitAdapter();
    final c = LeafPlayerController(a);
    c.execute(const LeafPlayerCommand.stepRate(0.25));
    c.execute(const LeafPlayerCommand.stepRate(0.25));
    expect(a.speed, 1.5);
    c.execute(const LeafPlayerCommand.resetRate());
    expect(a.speed, 1.0);
    c.execute(const LeafPlayerCommand.setRate(10));
    expect(a.speed, 4.0);
    c.dispose();
  });

  testWidgets('subtitle cycling goes through Off', (tester) async {
    final a = FullKitAdapter();
    a.trackState = const LeafTracks(
      subtitle: [
        LeafTrack(id: '1', kind: LeafTrackKind.subtitle, language: 'en'),
        LeafTrack(id: '2', kind: LeafTrackKind.subtitle, language: 'ja'),
      ],
      selectedSubtitle: '1',
    );
    final c = LeafPlayerController(a);
    final picked = <String?>[];
    for (var i = 0; i < 3; i++) {
      c.execute(const LeafPlayerCommand.cycleTrack(LeafTrackKind.subtitle));
      picked.add(a.trackState.selectedSubtitle);
    }
    expect(picked, ['2', null, '1']);
    c.dispose();
  });

  testWidgets('app overrides take play and seek', (tester) async {
    final a = KitAdapter();
    var toggles = 0;
    final seeks = <Duration>[];
    final c = LeafPlayerController(a, actions: LeafPlayerActions(onTogglePlay: () => toggles++, onSeek: seeks.add));
    c.execute(const LeafPlayerCommand.togglePlay());
    c.execute(const LeafPlayerCommand.seekTo(Duration(seconds: 7)));
    expect(toggles, 1);
    expect(a.plays + a.pauses, 0);
    expect(seeks, [s(7)]);
    expect(a.seeks, isEmpty);
    c.updateActions(const LeafPlayerActions());
    c.togglePlay();
    expect(a.plays, 1);
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  });

  testWidgets('ended: play restarts from the top', (tester) async {
    final a = KitAdapter(total: s(10));
    final c = LeafPlayerController(a);
    a.emitPosition(s(10));
    a.emitPlaying(false);
    expect(c.playState.value, LeafPlayState.ended);
    c.togglePlay();
    expect(a.seeks.last, Duration.zero);
    expect(a.plays, 1);
    await tester.pump(const Duration(seconds: 3));
    c.dispose();
  });

  testWidgets('Esc order: info, then fullscreen, then unhandled', (tester) async {
    final c = LeafPlayerController(KitAdapter());
    final fs = _Fullscreen(c);
    c.attachFullscreen(fs);
    expect(c.fullscreenAvailable.value, isTrue);
    c.execute(const LeafPlayerCommand.toggleFullscreen());
    c.execute(const LeafPlayerCommand.toggleInfo());
    expect(c.execute(const LeafPlayerCommand.dismiss()), isTrue);
    expect(c.infoVisible.value, isFalse);
    expect(c.fullscreen.value, isTrue);
    expect(c.execute(const LeafPlayerCommand.dismiss()), isTrue);
    expect(c.fullscreen.value, isFalse);
    expect(c.execute(const LeafPlayerCommand.dismiss()), isFalse);
    expect((fs.enters, fs.exits), (1, 1));
    c.dispose();
  });

  testWidgets('time format cycles and lands in the prefs', (tester) async {
    final prefs = LeafControlsPrefs();
    final c = LeafPlayerController(KitAdapter(), prefs: prefs);
    c.execute(const LeafPlayerCommand.cycleTimeFormat());
    expect(prefs.timeFormat, LeafTimeFormat.remaining);
    expect(c.timeFormat.value, LeafTimeFormat.remaining);
    expect(LeafControlsPrefs.fromJson(prefs.toJson()).timeFormat, LeafTimeFormat.remaining);
    c.dispose();
    prefs.dispose();
  });

  test('the source is redacted to host and file name', () {
    final c = LeafPlayerController(KitAdapter())..source = 'https://media.example/Videos/abc/stream.mkv?api_key=SECRET';
    expect(c.redactedSource, 'media.example/…/stream.mkv');
    c.dispose();
  });

  test('commands have value equality', () {
    expect(const LeafPlayerCommand.seekBy(Duration(seconds: 5)), const LeafPlayerCommand.seekBy(Duration(seconds: 5)));
    expect(const LeafPlayerCommand.seekBy(Duration(seconds: 5)), isNot(const LeafPlayerCommand.seekTo(Duration(seconds: 5))));
    expect(const LeafPlayerCommand.togglePlay(), const LeafPlayerCommand.togglePlay());
    expect(LeafPlayerCommand.custom('x', () {}), LeafPlayerCommand.custom('x', () {}));
  });

  testWidgets('dispose cancels every adapter subscription', (tester) async {
    final a = FullKitAdapter();
    final c = LeafPlayerController(a);
    expect(a.positionCtrl.hasListener, isTrue);
    c.dispose();
    expect(a.positionCtrl.hasListener, isFalse);
    expect(a.volumeCtrl.hasListener, isFalse);
    expect(a.chaptersCtrl.hasListener, isFalse);
  });
}
