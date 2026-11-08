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

/// One bar item for [fitBar]: its width as drawn, the volume slider's room
/// beside it ([sliderWidth], volume only) and its width compacted
/// ([compactWidth], the clock showing elapsed only).
@immutable
class LeafFitItem {
  const LeafFitItem(this.id, this.width, {this.priority = 50, this.sliderWidth = 0, this.compactWidth});

  final String id;
  final double width;

  /// The lowest drops into ⋯ first; 1000 and above never drop.
  final int priority;
  final double sliderWidth;
  final double? compactWidth;
}

/// Where the volume slider goes: beside the speaker ([beside], [width]
/// wide), sliding out on hover ([width] wide), or nowhere ([width] 0; the
/// wheel and keys still set it).
@immutable
class LeafSliderRoom {
  const LeafSliderRoom({required this.beside, required this.width});

  static const none = LeafSliderRoom(beside: false, width: 0);

  final bool beside;
  final double width;

  @override
  bool operator ==(Object other) => other is LeafSliderRoom && other.beside == beside && other.width == width;

  @override
  int get hashCode => Object.hash(beside, width);

  @override
  String toString() => 'LeafSliderRoom(${beside ? 'beside' : 'hover'} $width)';
}

/// What a bar shows at its width.
@immutable
class LeafFitResult {
  const LeafFitResult({required this.shown, required this.overflow, required this.slider, required this.compactTime});

  final Set<String> shown;

  /// Dropped items, in bar order.
  final List<String> overflow;
  final LeafSliderRoom slider;
  final bool compactTime;
}

/// Under this the hover slider is not worth showing.
const _minSlider = 32.0;

/// Fits a bar of [width]. It gives up room in this order: the volume slider
/// slides out on hover instead of sitting beside the speaker (sync_relay's
/// `volumeSliderRoom`), the clock compacts to elapsed only, then items drop
/// into ⋯ ([overflowWidth] is its button) by ascending priority, the bar's
/// end first among equals.
LeafFitResult fitBar({
  List<LeafFitItem> start = const [],
  List<LeafFitItem> center = const [],
  List<LeafFitItem> end = const [],
  required double width,
  double overflowWidth = 0,
}) {
  final all = [...start, ...center, ...end];
  final kept = {for (final i in all) i.id};
  final slider = all.map((i) => i.sliderWidth).fold(0.0, (a, b) => a > b ? a : b);
  var compact = false;
  double used() {
    var sum = 0.0;
    for (final i in all) {
      if (!kept.contains(i.id)) continue;
      sum += compact ? (i.compactWidth ?? i.width) : i.width;
    }
    if (kept.length < all.length) sum += overflowWidth;
    return sum;
  }

  LeafFitResult result() {
    final hasVolume = all.any((i) => i.sliderWidth > 0 && kept.contains(i.id));
    final spare = width - used();
    final room = !hasVolume
        ? LeafSliderRoom.none
        : spare >= slider
        ? LeafSliderRoom(beside: true, width: slider)
        : (spare < _minSlider ? LeafSliderRoom.none : LeafSliderRoom(beside: false, width: spare));
    return LeafFitResult(
      shown: Set.unmodifiable(kept),
      overflow: List.unmodifiable([for (final i in all) if (!kept.contains(i.id)) i.id]),
      slider: room,
      compactTime: compact,
    );
  }

  if (used() <= width) return result();
  if (all.any((i) => i.compactWidth != null)) {
    compact = true;
    if (used() <= width) return result();
  }
  final droppable = [
    for (var k = 0; k < all.length; k++)
      if (all[k].priority < 1000) (k, all[k]),
  ]..sort((a, b) => a.$2.priority != b.$2.priority ? a.$2.priority.compareTo(b.$2.priority) : b.$1.compareTo(a.$1));
  for (final (_, item) in droppable) {
    if (used() <= width) break;
    kept.remove(item.id);
  }
  return result();
}
