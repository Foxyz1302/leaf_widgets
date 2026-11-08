import 'package:flutter/material.dart';

import '../leaf_controls_theme.dart';
import '../leaf_player_command.dart';
import '../leaf_player_controller.dart';
import 'leaf_control.dart';

IconData _playIcon(LeafPlayState s) => switch (s) {
  LeafPlayState.playing => Icons.pause_rounded,
  LeafPlayState.paused => Icons.play_arrow_rounded,
  LeafPlayState.waiting => Icons.check_rounded,
  LeafPlayState.ended => Icons.replay_rounded,
};

String _playText(LeafPlayState s) => switch (s) {
  LeafPlayState.playing => 'Pause',
  LeafPlayState.paused => 'Play',
  LeafPlayState.waiting => 'Waiting',
  LeafPlayState.ended => 'Replay',
};

/// Play / pause / ↻ once ended; accent-filled in the uosc look. Follows
/// `actions.playState` when the app supplies one.
class LeafPlayPauseControl extends LeafControl {
  const LeafPlayPauseControl();

  @override
  String get id => 'playPause';

  @override
  int get priority => 1000;

  @override
  Widget build(BuildContext context, LeafControlContext c) => ValueListenableBuilder<LeafPlayState>(
    valueListenable: c.controller.playState,
    builder: (context, s, _) => Padding(
      padding: EdgeInsets.only(right: c.theme.buttonLook == LeafButtonLook.flat ? 4 * c.theme.scale : 0),
      child: LeafControlButton(
        key: const ValueKey('leaf-control-playPause'),
        icon: _playIcon(s),
        tooltip: c.tip(_playText(s), const LeafPlayerCommand.togglePlay()),
        accent: c.theme.buttonLook == LeafButtonLook.flat,
        big: true,
        onPressed: () => c.controller.execute(const LeafPlayerCommand.togglePlay()),
      ),
    ),
  );
}

/// The large centre button. [whilePaused]: only while not playing (the
/// legacy badge); otherwise with the controls.
class LeafBigPlayControl extends LeafControl {
  const LeafBigPlayControl({this.whilePaused = false});

  final bool whilePaused;

  @override
  String get id => whilePaused ? 'bigPlayWhilePaused' : 'bigPlay';

  @override
  double? estimatedWidth(LeafControlsTheme t) => 72 * t.scale;

  @override
  int get priority => 1000;

  @override
  Widget build(BuildContext context, LeafControlContext c) => ValueListenableBuilder<LeafPlayState>(
    valueListenable: c.controller.playState,
    builder: (context, s, _) {
      if (whilePaused && s == LeafPlayState.playing) return const SizedBox.shrink();
      final t = c.theme;
      final size = 64 * t.scale;
      return LeafTip(
        message: c.tip(_playText(s), const LeafPlayerCommand.togglePlay()),
        child: GestureDetector(
          key: const ValueKey('leaf-control-bigPlay'),
          behavior: HitTestBehavior.opaque,
          onTap: () => c.controller.execute(const LeafPlayerCommand.togglePlay()),
          child: Container(
            width: size,
            height: size,
            margin: EdgeInsets.symmetric(horizontal: 4 * t.scale),
            decoration: const BoxDecoration(color: Color(0x61000000), shape: BoxShape.circle),
            child: Icon(_playIcon(s), size: 40 * t.scale, color: t.foreground),
          ),
        ),
      );
    },
  );
}

/// A ~400 ms ▶ / ❚❚ flash on each user toggle (uosc's
/// `pause_indicator=flash`); ticks only while it flashes.
class LeafPauseIndicatorControl extends LeafControl {
  const LeafPauseIndicatorControl();

  @override
  String get id => 'pauseIndicator';

  @override
  bool get persistent => true;

  @override
  double? estimatedWidth(LeafControlsTheme t) => 0;

  @override
  Widget build(BuildContext context, LeafControlContext c) => _PauseIndicator(controller: c.controller, theme: c.theme);
}

class _PauseIndicator extends StatefulWidget {
  const _PauseIndicator({required this.controller, required this.theme});

  final LeafPlayerController controller;
  final LeafControlsTheme theme;

  @override
  State<_PauseIndicator> createState() => _PauseIndicatorState();
}

class _PauseIndicatorState extends State<_PauseIndicator> with SingleTickerProviderStateMixin {
  late final _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
  bool _flashing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.playFlash.addListener(_flash);
    _anim.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _flashing = false);
    });
  }

  @override
  void didUpdateWidget(_PauseIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.playFlash.removeListener(_flash);
      widget.controller.playFlash.addListener(_flash);
    }
  }

  @override
  void dispose() {
    widget.controller.playFlash.removeListener(_flash);
    _anim.dispose();
    super.dispose();
  }

  void _flash() {
    setState(() => _flashing = true);
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!_flashing) return const SizedBox.shrink();
    final t = widget.theme;
    final playing = !widget.controller.playing.value;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) => Opacity(
          opacity: (1 - _anim.value).clamp(0.0, 1.0),
          child: Transform.scale(scale: 1 + 0.3 * _anim.value, child: child),
        ),
        child: Container(
          key: const ValueKey('leaf-pause-indicator'),
          padding: EdgeInsets.all(16 * t.scale),
          decoration: const BoxDecoration(color: Color(0x61000000), shape: BoxShape.circle),
          child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 40 * t.scale, color: t.foreground),
        ),
      ),
    );
  }
}

/// The spinner while the player buffers (before the first frame without
/// `HasPlaybackStatus`). The kit's only spinner.
class LeafBufferingControl extends LeafControl {
  const LeafBufferingControl();

  @override
  String get id => 'buffering';

  @override
  bool get persistent => true;

  @override
  double? estimatedWidth(LeafControlsTheme t) => 0;

  @override
  Widget build(BuildContext context, LeafControlContext c) => ValueListenableBuilder<bool>(
    valueListenable: c.controller.buffering,
    builder: (context, buffering, _) => buffering
        ? IgnorePointer(
            child: SizedBox.square(
              key: const ValueKey('leaf-buffering'),
              dimension: 40 * c.theme.scale,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: c.theme.foreground),
            ),
          )
        : const SizedBox.shrink(),
  );
}

/// Pages a [LeafViewer] when no app next/previous is set; provided by the
/// controls host inside a viewer.
class LeafViewerPaging extends InheritedWidget {
  const LeafViewerPaging({super.key, required this.canStep, required this.step, required super.child});

  /// Whether a step of [delta] pages anywhere.
  final bool Function(int delta) canStep;
  final void Function(int delta) step;

  static LeafViewerPaging? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LeafViewerPaging>();

  @override
  bool updateShouldNotify(LeafViewerPaging oldWidget) => false;
}

/// Previous / next: the app's ([LeafPlayerActions.onPrevious] /
/// [LeafPlayerActions.onNext], label in the tooltip), else the viewer's
/// pages.
class LeafStepItemControl extends LeafControl {
  const LeafStepItemControl.previous() : forward = false;
  const LeafStepItemControl.next() : forward = true;

  final bool forward;

  @override
  String get id => forward ? 'next' : 'previous';

  @override
  int get priority => 35;

  @override
  Iterable<Listenable> availabilityDeps(LeafPlayerController c) => [c.actionsListenable];

  @override
  bool isAvailable(LeafControlContext c) {
    final a = c.controller.actions;
    return (forward ? a.onNext : a.onPrevious) != null || c.viewerCanPage;
  }

  @override
  Widget build(BuildContext context, LeafControlContext c) {
    final a = c.controller.actions;
    final label = forward ? a.nextLabel : a.previousLabel;
    final text = forward ? 'Next' : 'Previous';
    final command = forward ? const LeafPlayerCommand.next() : const LeafPlayerCommand.previous();
    final paging = (forward ? a.onNext : a.onPrevious) == null ? LeafViewerPaging.maybeOf(context) : null;
    final enabled = paging == null || paging.canStep(forward ? 1 : -1);
    return LeafControlButton(
      key: ValueKey('leaf-control-$id'),
      icon: forward ? Icons.skip_next_rounded : Icons.skip_previous_rounded,
      tooltip: c.tip(label == null ? text : '$text: $label', command),
      onPressed: enabled ? () => c.controller.execute(command) : null,
    );
  }
}

/// ⟲10 / ⟳10: seeks [delta] and flashes the running sum.
class LeafSeekByControl extends LeafControl {
  const LeafSeekByControl(this.delta);

  final Duration delta;

  @override
  String get id => 'seekBy${delta.inSeconds}';

  @override
  int get priority => 30;

  IconData get _icon {
    final back = delta.isNegative;
    return switch (delta.inSeconds.abs()) {
      5 => back ? Icons.replay_5_rounded : Icons.forward_5_rounded,
      10 => back ? Icons.replay_10_rounded : Icons.forward_10_rounded,
      30 => back ? Icons.replay_30_rounded : Icons.forward_30_rounded,
      _ => back ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded,
    };
  }

  @override
  Widget build(BuildContext context, LeafControlContext c) => LeafControlButton(
    key: ValueKey('leaf-control-$id'),
    icon: _icon,
    big: c.slot.name == 'center',
    tooltip: c.tip('${delta.isNegative ? 'Back' : 'Forward'} ${delta.inSeconds.abs()} s', LeafPlayerCommand.seekBy(delta)),
    onPressed: () {
      c.controller.execute(LeafPlayerCommand.seekBy(delta));
      c.controller.flashSeek(delta);
    },
  );
}
