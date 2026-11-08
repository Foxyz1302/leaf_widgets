import 'package:flutter/material.dart';

import '../leaf_controls_theme.dart';
import '../leaf_player_command.dart';
import '../leaf_player_controller.dart';
import '../media_math.dart';
import '../smooth_position.dart';
import 'leaf_control.dart';
import 'seek_bar.dart';

/// The clock: "6:00 / 24:00" or "-18:00" (the prefs' format; a click
/// switches), elapsed only when the bar is tight. A fixed-width box at its
/// widest text with its own repaint boundary, rebuilt once a second of the
/// smoothed position (the seek bar's, so the two agree).
class LeafTimeControl extends LeafControl {
  const LeafTimeControl();

  @override
  String get id => 'time';

  @override
  int get priority => 1000;

  static double widthOf(String text, LeafControlsTheme t) {
    final p = TextPainter(text: TextSpan(text: text, style: t.labelStyle), textDirection: TextDirection.ltr)..layout();
    final w = p.width;
    p.dispose();
    return (w + 20 * t.scale).ceilToDouble();
  }

  static String _widest(Duration d, LeafTimeFormat f) => leafClockText(d, d, f);

  @override
  LeafFitItem fitItem(LeafControlContext c) {
    final d = c.controller.duration.value;
    final full = widthOf(_widest(d, c.controller.timeFormat.value), c.theme);
    return LeafFitItem(id, full, priority: priority, compactWidth: widthOf(_widest(d, LeafTimeFormat.elapsed), c.theme));
  }

  @override
  double? estimatedWidth(LeafControlsTheme t) => null;

  @override
  Widget build(BuildContext context, LeafControlContext c) => _Clock(c: c, compact: c.fit.compactTime);
}

class _Clock extends StatelessWidget {
  const _Clock({required this.c, required this.compact});

  final LeafControlContext c;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final ctrl = c.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([ctrl.duration, ctrl.timeFormat]),
      builder: (context, _) {
        final d = ctrl.duration.value;
        final format = compact ? LeafTimeFormat.elapsed : ctrl.timeFormat.value;
        final width = LeafTimeControl.widthOf(LeafTimeControl._widest(d, format), c.theme);
        return LeafTip(
          message: compact ? '' : 'Elapsed / remaining (click to switch)',
          child: GestureDetector(
            key: const ValueKey('leaf-control-time'),
            behavior: HitTestBehavior.opaque,
            onTap: compact || d <= Duration.zero ? null : () => ctrl.execute(const LeafPlayerCommand.cycleTimeFormat()),
            child: MouseRegion(
              cursor: compact ? MouseCursor.defer : SystemMouseCursors.click,
              child: SizedBox(
                width: width,
                height: c.theme.scaledButton,
                child: RepaintBoundary(
                  child: Center(
                    child: _SmoothSeconds(
                      controller: ctrl,
                      builder: (context, secs) => Text(
                        leafClockText(Duration(seconds: secs), d, format),
                        maxLines: 1,
                        softWrap: false,
                        textDirection: TextDirection.ltr,
                        style: c.theme.labelStyle,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Rebuilds [builder] when the whole second of the controller's smoothed
/// position changes.
class _SmoothSeconds extends StatefulWidget {
  const _SmoothSeconds({required this.controller, required this.builder});

  final LeafPlayerController controller;
  final Widget Function(BuildContext context, int seconds) builder;

  @override
  State<_SmoothSeconds> createState() => _SmoothSecondsState();
}

class _SmoothSecondsState extends State<_SmoothSeconds> {
  late LeafSmoothPosition _smooth;
  late int _secs;

  static double _stepMs() => 1000;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    _smooth = LeafSmoothPosition.of(widget.controller)
      ..want(this, _stepMs)
      ..addListener(_onTick);
    _secs = _smooth.value.inSeconds;
  }

  void _detach() {
    _smooth
      ..removeListener(_onTick)
      ..release(this);
  }

  @override
  void didUpdateWidget(_SmoothSeconds oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) return;
    _detach();
    _attach();
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  void _onTick() {
    final secs = _smooth.value.inSeconds;
    if (secs != _secs) setState(() => _secs = secs);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _secs);
}

/// A 2 px progress line while the controls are hidden (prefs can switch it
/// off); paints only when it moves a physical pixel.
class LeafProgressLineControl extends LeafControl {
  const LeafProgressLineControl();

  @override
  String get id => 'progressLine';

  @override
  double? estimatedWidth(LeafControlsTheme t) => null;

  @override
  Widget build(BuildContext context, LeafControlContext c) => ListenableBuilder(
    listenable: c.controller.prefs,
    builder: (context, _) => !c.controller.prefs.progressLine
        ? const SizedBox.shrink()
        : IgnorePointer(
            child: LeafSeekBar(
              key: const ValueKey('leaf-progress-line'),
              controller: c.controller,
              theme: c.theme.copyWith(seekBar: c.theme.seekBar.copyWith(trackColor: const Color(0x00000000))),
              thin: true,
              knob: LeafKnob.never,
              chapters: false,
              hoverTip: false,
              interactive: false,
              hitHeight: 2 / c.theme.scale,
            ),
          ),
  );
}
