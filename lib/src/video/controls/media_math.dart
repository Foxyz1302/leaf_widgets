import 'package:flutter/foundation.dart';

import '../leaf_video_capabilities.dart';

/// "1:05", "1:02:03", "-0:04".
String formatClock(Duration d) {
  final negative = d.isNegative;
  final t = d.abs();
  String two(int n) => n.toString().padLeft(2, '0');
  final h = t.inHours, m = t.inMinutes % 60, s = t.inSeconds % 60;
  final body = h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
  return negative ? '-$body' : body;
}

/// Fraction of [total] at [d], 0..1 (0 without a duration).
double timelineFraction(Duration d, Duration total) {
  final t = total.inMicroseconds;
  if (t <= 0) return 0;
  return (d.inMicroseconds / t).clamp(0.0, 1.0);
}

/// Chapters from (title, start) pairs in start order: each ends where the
/// next starts, the last at [duration] (its start while that is unknown).
List<LeafChapter> chaptersFromStarts(List<(String, Duration)> starts, Duration duration) => [
  for (var i = 0; i < starts.length; i++)
    LeafChapter(
      index: i,
      title: starts[i].$1,
      start: starts[i].$2,
      end: i + 1 < starts.length ? starts[i + 1].$2 : (duration > starts[i].$2 ? duration : starts[i].$2),
    ),
];

/// Position in [chapters] of the chapter playing at [position], or null
/// (before the first chapter, or none).
int? chapterIndexAt(List<LeafChapter> chapters, Duration position) {
  int? at;
  for (var i = 0; i < chapters.length; i++) {
    if (chapters[i].start <= position) at = i;
  }
  return at;
}

/// mpv's `chapter-seek-threshold`: going back within this much of a
/// chapter's start goes to the chapter before it.
const chapterBackThreshold = Duration(seconds: 5);

/// Target of a chapter step ([delta] +1 = PgDn, -1 = PgUp), as mpv: back
/// goes to the current chapter's start, or the previous one within
/// [chapterBackThreshold] of it; forward to the next chapter's start. Null
/// when there is nowhere to go.
Duration? chapterStepTarget(List<LeafChapter> chapters, Duration position, int delta) {
  if (chapters.isEmpty || delta == 0) return null;
  final at = chapterIndexAt(chapters, position);
  if (delta > 0) {
    final next = (at ?? -1) + delta;
    return next < chapters.length ? chapters[next].start : null;
  }
  if (at == null) return null;
  var target = at + delta + 1;
  if (position - chapters[at].start < chapterBackThreshold) target--;
  return target >= 0 ? chapters[target].start : Duration.zero;
}

final _openingTitle = RegExp(r'\b(op|opening|intro)\d*\b', caseSensitive: false);
final _endingTitle = RegExp(r'\b(ed|ending|credits|outro)\d*\b', caseSensitive: false);

/// "OP", "OP1", "Opening", "Intro" (whole words, any case).
bool isOpeningTitle(String title) => _openingTitle.hasMatch(title);

/// "ED", "ED2", "Ending", "Credits", "Outro" (whole words, any case).
bool isEndingTitle(String title) => _endingTitle.hasMatch(title);

/// The skip pill's offer: jump to [target]. A [fixed] offer (the fallback
/// skip) moves with the position, so its equality ignores [target]: the
/// press skips relative to the moment it lands.
@immutable
class LeafSkipOffer {
  const LeafSkipOffer({required this.label, required this.target, this.kind, this.fixed = false});

  final String label;
  final Duration target;

  /// Null for the [fixed] fallback.
  final LeafSkipKind? kind;
  final bool fixed;

  @override
  bool operator ==(Object other) =>
      other is LeafSkipOffer && other.label == label && other.kind == kind && other.fixed == fixed && (fixed || other.target == target);

  @override
  int get hashCode => Object.hash(label, kind, fixed, fixed ? null : target);

  @override
  String toString() => 'LeafSkipOffer("$label" -> $target)';
}

/// The fallback skip needs media longer than this (an episode, not a clip).
const skipFallbackMinDuration = Duration(minutes: 20);

/// ... and is offered during this first part only.
const skipFallbackWindow = Duration(minutes: 6);

/// No offer in the last second of a range: the skip would do nothing.
const _skipTail = Duration(seconds: 1);

String skipLabelFor(LeafSkipKind kind) => switch (kind) {
  LeafSkipKind.intro => 'Skip intro',
  LeafSkipKind.outro => 'Skip outro',
  LeafSkipKind.recap => 'Skip recap',
  LeafSkipKind.preview => 'Skip preview',
  LeafSkipKind.commercial => 'Skip ad',
};

/// The skip offer at [position]:
/// - inside an app [segments] range: skip to its end;
/// - else inside the opening or ending chapter (titled like one, see
///   [isOpeningTitle]; only when no intro/outro segment exists): skip to its
///   end, labelled after the chapter ("Skip OP");
/// - else with [fallback] set, no opening known, no chapters (a chaptered
///   file without an OP chapter has none on purpose), media longer than
///   [skipFallbackMinDuration] and within its first [skipFallbackWindow]:
///   skip [fallback] ahead ("Skip 1:30").
LeafSkipOffer? skipOfferAt({
  required Duration position,
  required Duration duration,
  List<LeafSkipSegment> segments = const [],
  List<LeafChapter> chapters = const [],
  Duration? fallback,
}) {
  bool inside(Duration start, Duration end) => end > start && position >= start && position < end - _skipTail;
  for (final s in segments) {
    if (inside(s.start, s.end)) return LeafSkipOffer(label: s.label ?? skipLabelFor(s.kind), target: s.end, kind: s.kind);
  }
  bool hasSegment(LeafSkipKind kind) => segments.any((s) => s.kind == kind && s.end > s.start);
  LeafChapter? titled(bool Function(String) matches) {
    for (final c in chapters) {
      if (c.end > c.start && matches(c.title)) return c;
    }
    return null;
  }

  final opening = hasSegment(LeafSkipKind.intro) ? null : titled(isOpeningTitle);
  final ending = hasSegment(LeafSkipKind.outro) ? null : titled(isEndingTitle);
  String chapterLabel(LeafChapter c, LeafSkipKind kind) {
    final title = c.title.trim();
    return title.isNotEmpty && title.length <= 16 ? 'Skip $title' : skipLabelFor(kind);
  }

  if (opening != null && inside(opening.start, opening.end)) {
    return LeafSkipOffer(label: chapterLabel(opening, LeafSkipKind.intro), target: opening.end, kind: LeafSkipKind.intro);
  }
  if (ending != null && inside(ending.start, ending.end)) {
    return LeafSkipOffer(label: chapterLabel(ending, LeafSkipKind.outro), target: ending.end, kind: LeafSkipKind.outro);
  }
  final step = fallback;
  if (step != null &&
      opening == null &&
      !hasSegment(LeafSkipKind.intro) &&
      chapters.isEmpty &&
      duration > skipFallbackMinDuration &&
      position < skipFallbackWindow) {
    final to = position + step;
    return LeafSkipOffer(label: 'Skip ${formatClock(step)}', target: to < duration ? to : duration, fixed: true);
  }
  return null;
}

/// Where the part not downloaded yet starts (it runs to the end), as a
/// fraction; null when nothing known is missing. Only the end of the cache
/// ahead ([buffered]) is known; a cache within half a second of the end
/// leaves nothing.
double? uncachedFrom({required Duration position, required Duration buffered, required Duration duration}) {
  if (duration <= Duration.zero || buffered <= Duration.zero) return null;
  final from = buffered > position ? buffered : position;
  if (duration - from <= const Duration(milliseconds: 500)) return null;
  return timelineFraction(from, duration);
}

/// The band's cache label by the position ("12s"): the seconds buffered
/// ahead, while under [threshold] and the cache does not reach the end.
String? cacheLabel({
  required Duration position,
  required Duration buffered,
  required Duration duration,
  Duration threshold = const Duration(seconds: 60),
}) {
  if (duration <= Duration.zero || buffered <= Duration.zero) return null;
  if (duration - buffered <= const Duration(milliseconds: 500)) return null;
  final ahead = buffered > position ? buffered - position : Duration.zero;
  if (ahead >= threshold) return null;
  return '${(ahead.inMilliseconds / 1000).round()}s';
}

/// The band's height while it animates between hidden (0, a [lineSize]
/// line) and shown (1, [size] at [scale]).
double bandSize(double visibility, double scale, {double size = 36, double lineSize = 3}) =>
    lineSize + ((size * scale - lineSize) * visibility).roundToDouble();
