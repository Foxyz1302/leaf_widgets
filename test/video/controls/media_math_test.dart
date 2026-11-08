import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/src/video/controls/media_math.dart';
import 'package:leaf_widgets/src/video/leaf_video_capabilities.dart';

Duration s(num secs) => Duration(milliseconds: (secs * 1000).round());
Duration m(int min, [int sec = 0]) => Duration(minutes: min, seconds: sec);

final chapters = chaptersFromStarts([
  ('Prologue', Duration.zero),
  ('OP', m(0, 30)),
  ('Part A', m(2)),
  ('ED', m(20)),
  ('Part B', m(21, 30)),
], m(24));

void main() {
  test('clock format', () {
    expect(formatClock(s(65)), '1:05');
    expect(formatClock(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(formatClock(-s(4)), '-0:04');
  });

  test('chapters from starts: ends from the next start and the duration', () {
    expect(chapters[1], LeafChapter(index: 1, title: 'OP', start: m(0, 30), end: m(2)));
    expect(chapters.last.end, m(24));
    expect(chaptersFromStarts([('A', s(10))], Duration.zero).single.end, s(10));
  });

  group('chapter steps (PgUp / PgDn)', () {
    test('current chapter and forward steps', () {
      expect(chapterIndexAt(chapters, s(45)), 1);
      expect(chapterIndexAt(chapters, m(23)), 4);
      expect(chapterStepTarget(chapters, s(45), 1), m(2));
      expect(chapterStepTarget(chapters, m(22), 1), isNull);
    });

    test('back: current start, or the previous one near a start (mpv)', () {
      expect(chapterStepTarget(chapters, m(10), -1), m(2));
      expect(chapterStepTarget(chapters, m(2, 3), -1), s(30));
      expect(chapterStepTarget(chapters, s(2), -1), Duration.zero);
      expect(chapterStepTarget(const [], m(1), 1), isNull);
    });

    test('before the first chapter forward goes to it', () {
      final late = chaptersFromStarts([('A', m(1)), ('B', m(5))], m(10));
      expect(chapterIndexAt(late, s(10)), isNull);
      expect(chapterStepTarget(late, s(10), 1), m(1));
      expect(chapterStepTarget(late, s(10), -1), isNull);
    });
  });

  test('opening / ending titles: whole words, any case, numbered', () {
    for (final t in ['OP', 'op', 'OP1', 'OP 2', 'Opening', 'Intro']) {
      expect(isOpeningTitle(t), isTrue, reason: t);
    }
    for (final t in ['Opportunity', 'Operation', 'Introduction', 'Part A', '']) {
      expect(isOpeningTitle(t), isFalse, reason: t);
    }
    for (final t in ['ED', 'ED2', 'Ending', 'Credits', 'End Credits', 'Outro']) {
      expect(isEndingTitle(t), isTrue, reason: t);
    }
    for (final t in ['Edge', 'Edited', 'Part B', 'Preview', 'Red']) {
      expect(isEndingTitle(t), isFalse, reason: t);
    }
  });

  group('skip offers', () {
    LeafSkipOffer? at(Duration p, {List<LeafSkipSegment> segments = const [], List<LeafChapter>? marks, Duration? duration, Duration? fallback}) =>
        skipOfferAt(position: p, duration: duration ?? m(24), segments: segments, chapters: marks ?? chapters, fallback: fallback);

    test('chapter opening and ending, to their ends, named after the chapter', () {
      expect(at(s(29)), isNull);
      expect(at(s(30)), LeafSkipOffer(label: 'Skip OP', target: m(2), kind: LeafSkipKind.intro));
      expect(at(s(119.5)), isNull, reason: 'last second: nothing left to skip');
      expect(at(m(21)), LeafSkipOffer(label: 'Skip ED', target: m(21, 30), kind: LeafSkipKind.outro));
      expect(at(m(5)), isNull);
    });

    test('segments win over chapters', () {
      final seg = [LeafSkipSegment(kind: LeafSkipKind.intro, start: s(40), end: s(130))];
      expect(at(s(35), segments: seg), isNull, reason: 'an intro segment replaces the OP chapter');
      expect(at(s(60), segments: seg), LeafSkipOffer(label: 'Skip intro', target: s(130), kind: LeafSkipKind.intro));
      final recap = [LeafSkipSegment(kind: LeafSkipKind.recap, start: Duration.zero, end: s(20), label: 'Skip it')];
      expect(at(s(5), segments: recap)?.label, 'Skip it');
    });

    test('fallback: off by default; no opening, no chapters, over 20 min, first 6 min', () {
      expect(at(Duration.zero, marks: const []), isNull);
      const step = Duration(seconds: 90);
      expect(at(m(1), marks: const [], fallback: step), LeafSkipOffer(label: 'Skip 1:30', target: m(2, 30), fixed: true));
      expect(at(m(6), marks: const [], fallback: step), isNull);
      expect(at(m(1), marks: const [], duration: m(20), fallback: step), isNull);
      final plain = chaptersFromStarts([('Part A', Duration.zero), ('Part B', m(10))], m(24));
      expect(at(m(1), marks: plain, fallback: step), isNull, reason: 'chaptered without OP: none on purpose');
    });

    test('a fixed offer stays equal while its target moves', () {
      const step = Duration(seconds: 90);
      expect(at(m(1), marks: const [], fallback: step), at(m(1, 30), marks: const [], fallback: step));
    });
  });

  group('timeline math', () {
    test('missing part: from the cache end (or the position) to the end', () {
      expect(uncachedFrom(position: m(6), buffered: m(9), duration: m(24)), 9 / 24);
      expect(uncachedFrom(position: m(6), buffered: m(5), duration: m(24)), 6 / 24);
      expect(uncachedFrom(position: m(6), buffered: Duration.zero, duration: m(24)), isNull);
      expect(uncachedFrom(position: m(6), buffered: m(24), duration: m(24)), isNull);
    });

    test('cache label: seconds ahead, under 60 s, not when cached to the end', () {
      expect(cacheLabel(position: m(6), buffered: m(6, 30), duration: m(24)), '30s');
      expect(cacheLabel(position: m(6), buffered: m(5), duration: m(24)), '0s');
      expect(cacheLabel(position: m(6), buffered: m(7), duration: m(24)), isNull);
      expect(cacheLabel(position: m(23, 40), buffered: m(24), duration: m(24)), isNull);
    });

    test('band size: full band shown, line hidden, scaled', () {
      expect(bandSize(1, 1), 36);
      expect(bandSize(0, 1), 3);
      expect(bandSize(1, 1.25), 45);
    });
  });

  test('track labels: adapter label wins, else title · language · codec layout', () {
    const a = LeafTrack(id: '1', kind: LeafTrackKind.audio, language: 'jpn', codec: 'eac3', channels: 2);
    expect(a.label, 'jpn · EAC3 2.0');
    expect(const LeafTrack(id: '2', kind: LeafTrackKind.audio, label: 'Japanese').label, 'Japanese');
    expect(const LeafTrack(id: '3', kind: LeafTrackKind.subtitle).label, 'Track 3');
    expect(const LeafTracks(audio: [a], selectedAudio: '1'), const LeafTracks(audio: [a], selectedAudio: '1'));
  });

  group('fitBar', () {
    const play = LeafFitItem('playPause', 48, priority: 1000);
    const volume = LeafFitItem('volume', 48, priority: 40, sliderWidth: 72);
    const time = LeafFitItem('time', 110, priority: 1000, compactWidth: 60);
    const subs = LeafFitItem('subtitles', 48, priority: 30);
    const speed = LeafFitItem('speed', 48, priority: 20);
    const fullscreen = LeafFitItem('fullscreen', 48, priority: 1000);
    LeafFitResult fit(double width) =>
        fitBar(start: [play, volume, time], end: [subs, speed, fullscreen], width: width, overflowWidth: 48);

    test('wide: everything, the slider beside the speaker', () {
      final r = fit(800);
      expect(r.shown.length, 6);
      expect(r.overflow, isEmpty);
      expect(r.slider, const LeafSliderRoom(beside: true, width: 72));
      expect(r.compactTime, isFalse);
    });

    test('a bit narrower: the slider slides out on hover with the room left', () {
      final r = fit(400);
      expect(r.overflow, isEmpty);
      expect(r.slider.beside, isFalse);
      expect(r.slider.width, 400 - 350);
      expect(r.compactTime, isFalse);
    });

    test('narrower: no slider, then the clock compacts', () {
      expect(fit(352).slider, LeafSliderRoom.none);
      expect(fit(352).compactTime, isFalse);
      final r = fit(320);
      expect(r.compactTime, isTrue);
      expect(r.overflow, isEmpty);
    });

    test('narrowest: items drop into the overflow by priority, never the pinned ones', () {
      final r = fit(260);
      expect(r.overflow, ['subtitles', 'speed']);
      expect(r.shown, containsAll(['playPause', 'time', 'fullscreen', 'volume']));
      final tiny = fit(100);
      expect(tiny.shown, {'playPause', 'time', 'fullscreen'});
      expect(tiny.overflow, ['volume', 'subtitles', 'speed']);
    });

    test('equal priorities drop from the end of the bar first', () {
      final r = fitBar(
        start: const [LeafFitItem('a', 50), LeafFitItem('b', 50)],
        end: const [LeafFitItem('c', 50)],
        width: 100,
      );
      expect(r.overflow, ['c']);
    });
  });
}
