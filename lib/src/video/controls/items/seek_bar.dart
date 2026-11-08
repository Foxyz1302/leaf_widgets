import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../leaf_video_capabilities.dart';
import '../leaf_controls_theme.dart';
import '../leaf_controls_visibility.dart';
import '../leaf_player_command.dart';
import '../leaf_player_controller.dart';
import '../media_math.dart';
import 'leaf_control.dart';

enum LeafSeekBarLook {
  /// A Material track with a knob (sync_relay "Standard").
  line,

  /// The uosc band: tinted played part, position line, stripes over the
  /// part not downloaded, chapter dots, times inside.
  band,
}

enum LeafKnob { never, hover, always }

/// The seek bar item. In a bar slot it spans the width.
class LeafSeekBarControl extends LeafControl {
  const LeafSeekBarControl({
    this.look = LeafSeekBarLook.line,
    this.knob = LeafKnob.hover,
    this.chapters = true,
    this.hoverTip = true,
    this.collapseWhenHidden = false,
    this.timesInside = false,
    this.thin = false,
    this.hitHeight,
  });

  final LeafSeekBarLook look;
  final LeafKnob knob;
  final bool chapters;

  /// The time (and chapter title) above the bar under the mouse, or under
  /// the finger while dragging.
  final bool hoverTip;

  /// The band stays while the controls are hidden, shrunk to a line.
  final bool collapseWhenHidden;

  /// The band's elapsed and total / remaining times.
  final bool timesInside;

  /// A 2 px line with no hover growth (feed tiles).
  final bool thin;

  /// The line's hit height; the theme's by default.
  final double? hitHeight;

  @override
  String get id => 'seekBar';

  @override
  bool get persistent => collapseWhenHidden;

  @override
  double? estimatedWidth(LeafControlsTheme t) => null;

  @override
  int get priority => 1000;

  @override
  Widget build(BuildContext context, LeafControlContext c) => LeafSeekBar(
    controller: c.controller,
    visibility: c.visibility,
    theme: c.theme,
    look: look,
    knob: thin ? LeafKnob.never : knob,
    chapters: chapters && !thin,
    hoverTip: hoverTip && !thin,
    timesInside: timesInside,
    thin: thin,
    hitHeight: hitHeight,
    reveal: collapseWhenHidden ? c.reveal : null,
  );
}

/// The kit's seek bar: a [RenderLeafSeekBar] (its own repaint boundary;
/// repaints only when something it draws moves by a physical pixel) and a
/// hover tip above it.
class LeafSeekBar extends StatefulWidget {
  const LeafSeekBar({
    super.key,
    required this.controller,
    required this.theme,
    this.visibility,
    this.look = LeafSeekBarLook.line,
    this.knob = LeafKnob.hover,
    this.chapters = true,
    this.hoverTip = true,
    this.timesInside = false,
    this.thin = false,
    this.interactive = true,
    this.hitHeight,
    this.reveal,
  });

  final LeafPlayerController controller;
  final LeafControlsTheme theme;
  final LeafControlsVisibility? visibility;
  final LeafSeekBarLook look;
  final LeafKnob knob;
  final bool chapters;
  final bool hoverTip;
  final bool timesInside;
  final bool thin;
  final bool interactive;
  final double? hitHeight;

  /// The controls' fade: the band collapses with it. Null: always full.
  final Animation<double>? reveal;

  @override
  State<LeafSeekBar> createState() => _LeafSeekBarState();
}

class _LeafSeekBarState extends State<LeafSeekBar> {
  final _tip = ValueNotifier<double?>(null);
  bool _holding = false;

  void _onDrag(bool on) {
    if (_holding == on) return;
    _holding = on;
    widget.visibility?.hold(this, on);
  }

  @override
  void dispose() {
    if (_holding) widget.visibility?.hold(this, false);
    _tip.dispose();
    super.dispose();
  }

  double get _barHeight => widget.look == LeafSeekBarLook.band
      ? widget.theme.seekBar.bandHeight * widget.theme.scale
      : (widget.hitHeight ?? widget.theme.seekBar.lineHitHeight) * widget.theme.scale;

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final bar = _SeekBarRender(
      controller: widget.controller,
      theme: widget.theme,
      look: widget.look,
      knob: widget.knob,
      chapters: widget.chapters,
      timesInside: widget.timesInside,
      thin: widget.thin,
      interactive: widget.interactive,
      hitHeight: widget.hitHeight,
      reveal: widget.reveal,
      fontFamily: style.fontFamily,
      devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      onTip: widget.hoverTip ? (f) => _tip.value = f : null,
      onDrag: _onDrag,
    );
    if (!widget.hoverTip) return bar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        bar,
        Positioned(
          left: 0,
          right: 0,
          bottom: _barHeight + 6,
          height: 160,
          child: IgnorePointer(
            child: ValueListenableBuilder<double?>(
              valueListenable: _tip,
              builder: (context, f, _) => f == null
                  ? const SizedBox.shrink()
                  : CustomSingleChildLayout(
                      delegate: _TipLayout(f),
                      child: _SeekTip(controller: widget.controller, theme: widget.theme, fraction: f),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TipLayout extends SingleChildLayoutDelegate {
  _TipLayout(this.fraction);

  final double fraction;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size child) {
    const gap = 4.0;
    final x = (size.width * fraction - child.width / 2).clamp(gap, math.max(gap, size.width - gap - child.width)).toDouble();
    return Offset(x, size.height - child.height);
  }

  @override
  bool shouldRelayout(_TipLayout oldDelegate) => oldDelegate.fraction != fraction;
}

class _SeekTip extends StatelessWidget {
  const _SeekTip({required this.controller, required this.theme, required this.fraction});

  final LeafPlayerController controller;
  final LeafControlsTheme theme;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final at = controller.duration.value * fraction;
    final chapters = controller.chapters.value;
    final ci = chapterIndexAt(chapters, at);
    final title = ci == null ? '' : chapters[ci].title;
    final preview = controller.actions.seekPreview?.call(at);
    final s = theme.scale;
    return Container(
      key: const ValueKey('leaf-seek-tip'),
      constraints: const BoxConstraints(maxWidth: 320),
      padding: EdgeInsets.symmetric(horizontal: 10 * s, vertical: 5 * s),
      decoration: BoxDecoration(
        color: theme.tooltipFill,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.capsuleBorder, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (preview != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image(image: preview, height: 90 * s, gaplessPlayback: true),
              ),
            ),
          if (title.isNotEmpty)
            Text(
              title,
              key: const ValueKey('leaf-seek-tip-chapter'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.foreground, fontSize: 13 * s, fontWeight: FontWeight.w600),
            ),
          Text(
            formatClock(at),
            key: const ValueKey('leaf-seek-tip-time'),
            style: TextStyle(
              color: title.isEmpty ? theme.foreground : theme.foregroundDim,
              fontSize: 13 * s,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SeekBarRender extends LeafRenderObjectWidget {
  const _SeekBarRender({
    required this.controller,
    required this.theme,
    required this.look,
    required this.knob,
    required this.chapters,
    required this.timesInside,
    required this.thin,
    required this.interactive,
    required this.hitHeight,
    required this.reveal,
    required this.fontFamily,
    required this.devicePixelRatio,
    required this.onTip,
    required this.onDrag,
  });

  final LeafPlayerController controller;
  final LeafControlsTheme theme;
  final LeafSeekBarLook look;
  final LeafKnob knob;
  final bool chapters;
  final bool timesInside;
  final bool thin;
  final bool interactive;
  final double? hitHeight;
  final Animation<double>? reveal;
  final String? fontFamily;
  final double devicePixelRatio;
  final ValueChanged<double?>? onTip;
  final ValueChanged<bool> onDrag;

  @override
  RenderLeafSeekBar createRenderObject(BuildContext context) => RenderLeafSeekBar(
    controller: controller,
    theme: theme,
    look: look,
    knob: knob,
    chapters: chapters,
    timesInside: timesInside,
    thin: thin,
    interactive: interactive,
    hitHeight: hitHeight,
    reveal: reveal,
    fontFamily: fontFamily,
    devicePixelRatio: devicePixelRatio,
    onTip: onTip,
    onDrag: onDrag,
  );

  @override
  void updateRenderObject(BuildContext context, RenderLeafSeekBar r) {
    r
      ..controller = controller
      ..theme = theme
      ..look = look
      ..knob = knob
      ..chapters = chapters
      ..timesInside = timesInside
      ..thin = thin
      ..interactive = interactive
      ..hitHeight = hitHeight
      ..reveal = reveal
      ..fontFamily = fontFamily
      ..devicePixelRatio = devicePixelRatio
      ..onTip = onTip
      ..onDrag = onDrag;
  }
}

/// Wins the arena on pointer-down, so a drag that starts on the bar never
/// pages or dismisses a viewer.
class _EagerDrag extends OneSequenceGestureRecognizer {
  _EagerDrag({required this.onStart, required this.onUpdate, required this.onEnd, required this.onCancel});

  final void Function(Offset local, Duration time) onStart;
  final void Function(Offset local, Duration time) onUpdate;
  final void Function(Duration time) onEnd;
  final VoidCallback onCancel;
  bool _active = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
    _active = true;
    onStart(event.localPosition, event.timeStamp);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_active) return;
    if (event is PointerMoveEvent) {
      onUpdate(event.localPosition, event.timeStamp);
    } else if (event is PointerUpEvent) {
      _active = false;
      onEnd(event.timeStamp);
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      _active = false;
      onCancel();
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    if (_active) onCancel();
    _active = false;
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'leaf seek drag';
}

/// One cached [TextPainter]: laid out again only when its text changes.
class _Text {
  String? text;
  TextPainter? painter;

  TextPainter layout(String s, TextStyle style) {
    if (s == text && painter != null) return painter!;
    painter?.dispose();
    text = s;
    return painter = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr)..layout();
  }

  void dispose() {
    painter?.dispose();
    painter = null;
    text = null;
  }
}

/// The seek bar's render object: its own repaint boundary; subscribes to
/// the controller in [attach] and repaints only when what it draws changes
/// by at least one physical pixel (or a label's text changes).
class RenderLeafSeekBar extends RenderBox implements MouseTrackerAnnotation {
  RenderLeafSeekBar({
    required this._controller,
    required this._theme,
    required this._look,
    required this._knob,
    required this._chapters,
    required this._timesInside,
    required this._thin,
    required this._interactive,
    this._hitHeight,
    this._reveal,
    this._fontFamily,
    required double devicePixelRatio,
    this.onTip,
    required this.onDrag,
  }) : _dpr = devicePixelRatio {
    _drag = _EagerDrag(onStart: _dragStart, onUpdate: _dragUpdate, onEnd: _dragEnd, onCancel: _dragCancel);
  }

  ValueChanged<double?>? onTip;
  ValueChanged<bool> onDrag;
  late final _EagerDrag _drag;

  /// Paints since creation (tests: paints only on pixel changes).
  int debugPaintCount = 0;

  /// Paints of every seek bar (benchmarks).
  static int debugTotalPaints = 0;

  LeafPlayerController _controller;
  set controller(LeafPlayerController v) {
    if (identical(v, _controller)) return;
    if (attached) _unlisten();
    _controller = v;
    if (attached) _listen();
    markNeedsPaint();
  }

  LeafControlsTheme _theme;
  set theme(LeafControlsTheme v) {
    if (v == _theme) return;
    _theme = v;
    _texts();
    markNeedsLayout();
  }

  LeafSeekBarLook _look;
  set look(LeafSeekBarLook v) {
    if (v == _look) return;
    _look = v;
    markNeedsLayout();
  }

  LeafKnob _knob;
  set knob(LeafKnob v) {
    if (v == _knob) return;
    _knob = v;
    markNeedsPaint();
  }

  bool _chapters;
  set chapters(bool v) {
    if (v == _chapters) return;
    _chapters = v;
    markNeedsPaint();
  }

  bool _timesInside;
  set timesInside(bool v) {
    if (v == _timesInside) return;
    _timesInside = v;
    markNeedsPaint();
  }

  bool _thin;
  set thin(bool v) {
    if (v == _thin) return;
    _thin = v;
    markNeedsPaint();
  }

  bool _interactive;
  set interactive(bool v) => _interactive = v;

  double? _hitHeight;
  set hitHeight(double? v) {
    if (v == _hitHeight) return;
    _hitHeight = v;
    markNeedsLayout();
  }

  Animation<double>? _reveal;
  set reveal(Animation<double>? v) {
    if (identical(v, _reveal)) return;
    if (attached) _reveal?.removeListener(_onReveal);
    _reveal = v;
    if (attached) _reveal?.addListener(_onReveal);
    markNeedsLayout();
  }

  String? _fontFamily;
  set fontFamily(String? v) {
    if (v == _fontFamily) return;
    _fontFamily = v;
    _texts();
    markNeedsPaint();
  }

  double _dpr;
  set devicePixelRatio(double v) {
    if (v == _dpr) return;
    _dpr = v;
    markNeedsPaint();
  }

  double? _hoverX;
  double _hoverY = 0;
  bool _dragging = false;
  double _dragFraction = 0;
  Duration? _lastSentAt;
  Object? _painted;
  Rect? _rightTimeRect;
  final _elapsedText = _Text(), _rightText = _Text(), _cacheText = _Text();

  void _texts() {
    _elapsedText.dispose();
    _rightText.dispose();
    _cacheText.dispose();
  }

  double get _revealValue => _reveal?.value ?? 1;

  bool get _band => _look == LeafSeekBarLook.band;

  /// Collapsed: a progress line, no input.
  bool get _inert => !_interactive || (_band && _revealValue < 0.5);

  @override
  bool get isRepaintBoundary => true;

  void _listen() {
    final c = _controller;
    c.position.addListener(_onTick);
    c.pendingSeek.addListener(_onTick);
    c.duration.addListener(_onTick);
    c.buffered.addListener(_onTick);
    c.bufferedRanges?.addListener(_onTick);
    c.chapters.addListener(_onTick);
    c.timeFormat.addListener(_onTick);
  }

  void _unlisten() {
    final c = _controller;
    c.position.removeListener(_onTick);
    c.pendingSeek.removeListener(_onTick);
    c.duration.removeListener(_onTick);
    c.buffered.removeListener(_onTick);
    c.bufferedRanges?.removeListener(_onTick);
    c.chapters.removeListener(_onTick);
    c.timeFormat.removeListener(_onTick);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _listen();
    _reveal?.addListener(_onReveal);
  }

  @override
  void detach() {
    _unlisten();
    _reveal?.removeListener(_onReveal);
    if (_dragging) {
      _dragging = false;
      onDrag(false);
    }
    super.detach();
  }

  @override
  void dispose() {
    _drag.dispose();
    _texts();
    super.dispose();
  }

  void _onReveal() {
    if (_revealValue < 0.5 && _hoverX != null) {
      _hoverX = null;
      onTip?.call(null);
    }
    markNeedsLayout();
  }

  void _onTick() {
    if (!hasSize) return;
    if (_signature() != _painted) markNeedsPaint();
  }

  Duration get _duration => _controller.duration.value;

  double get _played {
    if (_dragging) return _dragFraction;
    return timelineFraction(_controller.pendingSeek.value ?? _controller.position.value, _duration);
  }

  int _px(double fraction) => (fraction * size.width * _dpr).round();

  List<(double, double)> _cachedSpans() {
    final d = _duration;
    if (d <= Duration.zero) return const [];
    final ranges = _controller.bufferedRanges?.value;
    if (ranges != null && ranges.isNotEmpty) {
      return [for (final r in ranges) (timelineFraction(r.start, d), timelineFraction(r.end, d))];
    }
    final b = _controller.buffered.value;
    return b > Duration.zero ? [(0.0, timelineFraction(b, d))] : const [];
  }

  List<(double, double)> _uncached() => uncachedParts(
    ranges: _controller.bufferedRanges?.value,
    position: _controller.position.value,
    buffered: _controller.buffered.value,
    duration: _duration,
  );

  String? _elapsedLabel() => _band && _timesInside && _duration > Duration.zero ? formatClock(_duration * _played) : null;

  String? _rightLabel() {
    if (!_band || !_timesInside) return null;
    final d = _duration;
    if (d <= Duration.zero) return null;
    if (_controller.timeFormat.value != LeafTimeFormat.remaining) return formatClock(d);
    final left = d - d * _played;
    return '-${formatClock(left.isNegative ? Duration.zero : left)}';
  }

  String? _cacheLabel() => _band && _timesInside
      ? cacheLabel(
          position: _controller.position.value,
          buffered: _controller.buffered.value,
          duration: _duration,
          threshold: _theme.seekBar.cacheLabelThreshold,
        )
      : null;

  Object _signature() => (
    _px(_played),
    Object.hashAll([for (final (a, b) in _band ? _uncached() : _cachedSpans()) (_px(a), _px(b))]),
    Object.hashAll([for (final c in _controller.chapters.value) c.start]),
    _elapsedLabel(),
    _rightLabel(),
    _cacheLabel(),
    _hoverX == null ? null : ((_hoverX! * _dpr).round(), (_hoverY * _dpr).round()),
    _dragging,
    size.height,
  );

  double _height() {
    final t = _theme.seekBar;
    final s = _theme.scale;
    if (_band) return bandSize(_revealValue, s, size: t.bandHeight, lineSize: t.bandCollapsedHeight);
    return (_hitHeight ?? t.lineHitHeight) * s;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(Size(constraints.maxWidth, _height()));

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  bool hitTestSelf(Offset position) => !_inert;

  // ── Input ──────────────────────────────────────────────────────────────

  @override
  MouseCursor get cursor => !_inert && _duration > Duration.zero ? SystemMouseCursors.click : MouseCursor.defer;

  @override
  PointerEnterEventListener? get onEnter => (e) => _hover(e.localPosition);

  @override
  PointerExitEventListener? get onExit => (e) {
    if (_dragging) return;
    _hoverX = null;
    onTip?.call(null);
    markNeedsPaint();
  };

  @override
  bool get validForMouseTracker => attached;

  void _hover(Offset at) {
    if (_inert || !hasSize) return;
    _hoverX = at.dx.clamp(0.0, size.width);
    _hoverY = at.dy;
    final d = _duration;
    if (d > Duration.zero) onTip?.call(_hoverFraction());
    markNeedsPaint();
  }

  /// The hovered chapter dot's fraction (band), else the pointer's.
  double _hoverFraction() {
    final hit = _dotAt(Offset(_hoverX!, _hoverY));
    return hit != null ? timelineFraction(_controller.chapters.value[hit].start, _duration) : _hoverX! / size.width;
  }

  int? _dotAt(Offset at) {
    if (!_band || !_chapters || _dragging) return null;
    final d = _duration;
    if (d <= Duration.zero) return null;
    final reach = _theme.seekBar.chapterDot * _theme.scale * 2.5;
    int? best;
    var bestD = double.infinity;
    final chapters = _controller.chapters.value;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].start <= Duration.zero) continue;
      final dist = (Offset(size.width * timelineFraction(chapters[i].start, d), 0) - at).distance;
      if (dist <= reach && dist < bestD) {
        best = i;
        bestD = dist;
      }
    }
    return best;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (_inert) return;
    if (event is PointerDownEvent) {
      _drag.addPointer(event);
    } else if (event is PointerHoverEvent) {
      _hover(event.localPosition);
    }
  }

  void _dragStart(Offset local, Duration time) {
    if (!hasSize || size.width <= 0) return;
    final rt = _rightTimeRect;
    if (rt != null && rt.inflate(2).contains(local)) {
      _controller.execute(const LeafPlayerCommand.cycleTimeFormat());
      return;
    }
    if (_duration <= Duration.zero) return;
    final dot = _dotAt(local);
    if (dot != null) {
      _controller.execute(LeafPlayerCommand.seekToChapter(dot));
      return;
    }
    _dragging = true;
    onDrag(true);
    _dragFraction = (local.dx / size.width).clamp(0.0, 1.0);
    _hoverX = local.dx.clamp(0.0, size.width);
    onTip?.call(_dragFraction);
    _lastSentAt = time;
    _controller.seek(_duration * _dragFraction);
    markNeedsPaint();
  }

  void _dragUpdate(Offset local, Duration time) {
    if (!_dragging) return;
    _dragFraction = (local.dx / size.width).clamp(0.0, 1.0);
    _hoverX = local.dx.clamp(0.0, size.width);
    onTip?.call(_dragFraction);
    final last = _lastSentAt;
    if (last == null || time - last >= const Duration(milliseconds: 80)) {
      _lastSentAt = time;
      _controller.seek(_duration * _dragFraction);
    }
    markNeedsPaint();
  }

  void _dragEnd(Duration time) {
    if (!_dragging) return;
    _controller.seek(_duration * _dragFraction);
    _dragging = false;
    onDrag(false);
    onTip?.call(null);
    _hoverX = null;
    markNeedsPaint();
  }

  void _dragCancel() {
    if (!_dragging) return;
    _dragging = false;
    onDrag(false);
    onTip?.call(null);
    markNeedsPaint();
  }

  // ── Paint ──────────────────────────────────────────────────────────────

  @override
  void paint(PaintingContext context, Offset offset) {
    debugPaintCount++;
    debugTotalPaints++;
    _painted = _signature();
    final canvas = context.canvas;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    _band ? _paintBand(canvas) : _paintLine(canvas);
    canvas.restore();
  }

  void _paintLine(Canvas canvas) {
    final t = _theme;
    final sb = t.seekBar;
    final w = size.width, h = size.height, cy = h / 2;
    final active = !_thin && (_hoverX != null || _dragging);
    final th = (_thin ? 2.0 : (active ? sb.lineHoverHeight : sb.lineHeight)) * (_thin ? 1 : t.scale);
    Rect seg(double a, double b) => Rect.fromLTRB(w * a, cy - th / 2, w * b, cy + th / 2);
    canvas.drawRect(seg(0, 1), Paint()..color = sb.trackColor);
    for (final (a, b) in _cachedSpans()) {
      canvas.drawRect(seg(a, b), Paint()..color = sb.bufferedColor);
    }
    final hx = _hoverX;
    if (hx != null && !_dragging && w > 0) canvas.drawRect(seg(0, hx / w), Paint()..color = sb.bufferedColor);
    final played = _played;
    canvas.drawRect(seg(0, played), Paint()..color = t.accent);
    if (_chapters && _duration > Duration.zero) {
      final r = 4 * t.scale;
      for (final c in _controller.chapters.value) {
        if (c.start <= Duration.zero) continue;
        final cx = w * timelineFraction(c.start, _duration);
        if (sb.chapterMark == LeafChapterMark.dot) {
          canvas.drawCircle(Offset(cx, cy), r * 0.8 + 1, Paint()..color = const Color(0xB3000000));
          canvas.drawCircle(Offset(cx, cy), r * 0.8, Paint()..color = t.foreground);
          continue;
        }
        final path = Path()
          ..moveTo(cx, cy - r)
          ..lineTo(cx + r, cy)
          ..lineTo(cx, cy + r)
          ..lineTo(cx - r, cy)
          ..close();
        canvas.drawPath(path, Paint()..color = t.foreground);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8
            ..color = const Color(0x8A000000),
        );
      }
    }
    final showKnob = _knob == LeafKnob.always || (_knob == LeafKnob.hover && active);
    if (showKnob) canvas.drawCircle(Offset(w * played, cy), sb.knobSize * t.scale / 2, Paint()..color = t.accent);
  }

  // Inspired by the timeline of uosc (github.com/tomasklaen/uosc, LGPL-2.1,
  // by tomasklaen), by way of sync_relay: the striped unbuffered part, the
  // remaining time and the thin line when hidden come from there. The
  // drawing, geometry and values here are our own.
  void _paintBand(Canvas canvas) {
    final t = _theme;
    final sb = t.seekBar;
    final s = t.scale;
    final v = _revealValue;
    final w = size.width, h = size.height;
    final lw = 2.0 * s;
    final x = (w * _played).clamp(lw / 2, math.max(lw / 2, w - lw / 2)).toDouble();
    canvas.drawRect(Offset.zero & size, Paint()..color = t.bandFill);
    canvas.drawRect(Rect.fromLTRB(0, 0, x, h), Paint()..color = t.accent.withValues(alpha: sb.playedTint));
    if (sb.stripes) _stripes(canvas, w, h, v);
    final chapters = _chapters && _duration > Duration.zero ? _controller.chapters.value : const <LeafChapter>[];
    final cut = Paint()..color = const Color(0x4D000000);
    for (final c in chapters) {
      if (c.start <= Duration.zero) continue;
      final cx = w * timelineFraction(c.start, _duration);
      canvas.drawRect(Rect.fromLTRB(cx - 0.5, 0, cx + 0.5, h), cut);
    }
    if (v > 0) {
      canvas.drawRect(Rect.fromLTRB(x - lw / 2, 0, x + lw / 2, h), Paint()..color = t.foreground.withValues(alpha: v));
      final r = sb.chapterDot * s * v;
      final hovered = _hoverX == null ? null : _dotAt(Offset(_hoverX!, _hoverY));
      for (var i = 0; i < chapters.length; i++) {
        if (chapters[i].start <= Duration.zero) continue;
        final c = Offset(w * timelineFraction(chapters[i].start, _duration), 0);
        final big = i == hovered;
        final radius = big ? r * 1.7 : r;
        canvas.drawCircle(c, radius + 1, Paint()..color = const Color(0xB3000000));
        canvas.drawCircle(c, radius, Paint()..color = big ? t.accent : t.foreground.withValues(alpha: 0.9));
      }
    }
    _rightTimeRect = null;
    final minText = sb.timeFontSize * s;
    final textOpacity = ((h - minText) / (minText / 2)).clamp(0.0, 1.0);
    if (textOpacity > 0) _bandTimes(canvas, w, h, x, textOpacity);
    final hx = _hoverX;
    if (hx != null && v > 0.5) {
      canvas.drawRect(Rect.fromLTRB(hx - 0.5, 0, hx + 0.5, h), Paint()..color = t.foreground.withValues(alpha: 0.45));
    }
  }

  void _stripes(Canvas canvas, double w, double h, double v) {
    final parts = _uncached();
    if (parts.isEmpty) return;
    final s = _theme.scale;
    final period = 7.0 * s;
    final paint = Paint()
      ..color = _theme.foreground.withValues(alpha: 0.12 + 0.22 * (1 - v))
      ..strokeWidth = 1.5 * s;
    for (final (from, to) in parts) {
      final ax = (w * from).floorToDouble(), bx = (w * to).ceilToDouble();
      if (ax >= w || bx <= ax) continue;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(ax, 0, bx, h));
      for (var c = (ax / period).floorToDouble() * period - h; c <= bx; c += period) {
        canvas.drawLine(Offset(c, h), Offset(c + h, 0), paint);
      }
      canvas.restore();
    }
  }

  TextStyle get _timeStyle => TextStyle(
    fontFamily: _fontFamily,
    color: _theme.foreground,
    fontSize: _theme.seekBar.timeFontSize * _theme.scale,
    height: 1,
    fontWeight: FontWeight.w500,
    fontFeatures: const [FontFeature.tabularFigures()],
    shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 3)],
  );

  void _bandTimes(Canvas canvas, double w, double h, double lineX, double opacity) {
    final s = _theme.scale;
    final inset = _theme.seekBar.timeInset * s;
    final style = _timeStyle;
    final fs = style.fontSize!;
    final cy = h / 2;
    final e = _elapsedLabel(), r = _rightLabel(), c = _cacheLabel();
    final ep = e == null ? null : _elapsedText.layout(e, style);
    final rp = r == null ? null : _rightText.layout(r, style);
    void draw(TextPainter p, Offset at) {
      if (opacity >= 1) {
        p.paint(canvas, at);
        return;
      }
      canvas.saveLayer(at & p.size, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
      p.paint(canvas, at);
      canvas.restore();
    }

    if (c != null) {
      final cs = style.copyWith(fontSize: fs * 0.8, color: _theme.foregroundDim);
      final cp = _cacheText.layout(c, cs);
      const margin = 6.0;
      var cx = lineX + margin;
      final minX = inset + margin + (ep?.width ?? 0), maxX = w - inset - margin - (rp?.width ?? 0);
      if (cx < minX) {
        cx = minX;
      } else if (cx + cp.width > maxX) {
        cx = maxX - cp.width;
      }
      draw(cp, Offset(cx, cy - fs * 0.4));
    }
    if (ep != null) draw(ep, Offset(inset, cy - fs / 2));
    if (rp != null) {
      final at = Offset(w - inset - rp.width, cy - fs / 2);
      draw(rp, at);
      _rightTimeRect = at & rp.size;
    }
  }
}
