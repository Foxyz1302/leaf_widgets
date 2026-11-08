import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../leaf_controls_theme.dart';
import '../leaf_player_command.dart';
import '../leaf_player_controller.dart';
import '../media_math.dart';
import 'leaf_control.dart';

/// Turns wheel deltas into volume steps (sync_relay's port): a mouse notch
/// is one step, smooth-scroll deltas add up to one, mostly-sideways
/// scrolls are none.
class LeafWheelSteps {
  static const _notch = 50.0;
  double _sum = 0;

  static bool vertical(PointerSignalEvent e) =>
      e is PointerScrollEvent && e.scrollDelta.dy != 0 && e.scrollDelta.dy.abs() > e.scrollDelta.dx.abs();

  /// +1 louder (wheel up), -1 quieter, 0 not a step yet.
  int take(PointerScrollEvent e) {
    final dy = e.scrollDelta.dy;
    if (dy.abs() >= _notch) {
      _sum = 0;
      return dy < 0 ? 1 : -1;
    }
    if (_sum != 0 && _sum.sign != dy.sign) _sum = 0;
    _sum += dy;
    if (_sum.abs() < _notch) return 0;
    final step = _sum < 0 ? 1 : -1;
    _sum = 0;
    return step;
  }

  /// Claims [e] when it is a vertical scroll nothing under the mouse
  /// claimed first (a list, a menu), then calls [onStep] per step.
  void handle(PointerSignalEvent e, ValueChanged<int> onStep) {
    if (!vertical(e)) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final step = take(event as PointerScrollEvent);
      if (step != 0) onStep(step);
    });
  }
}

IconData leafVolumeIcon(double volume) =>
    volume <= 0 ? Icons.volume_off_rounded : (volume < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded);

/// A thin volume track over 0..[max]: filled to the volume, the part above
/// 100 in the boost colour with a tick at 100 (only when [max] > 100).
/// Click or drag sets it.
class LeafVolumeBar extends StatelessWidget {
  const LeafVolumeBar({
    super.key,
    required this.volume,
    required this.max,
    required this.onChanged,
    required this.theme,
    this.width = 72,
    this.color,
  });

  final double volume;
  final double max;
  final ValueChanged<double>? onChanged;
  final LeafControlsTheme theme;
  final double width;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    void at(double x) => onChanged?.call((x / width * max).clamp(0.0, max).roundToDouble());
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: onChanged == null ? null : (e) => at(e.localPosition.dx),
      onHorizontalDragUpdate: onChanged == null ? null : (e) => at(e.localPosition.dx),
      child: SizedBox(
        width: width,
        height: 24,
        child: CustomPaint(
          painter: _VolumePainter(volume.clamp(0.0, max), max, color ?? theme.foreground, theme.foregroundDim.withValues(alpha: 0.35), theme.boost),
        ),
      ),
    );
  }
}

class _VolumePainter extends CustomPainter {
  _VolumePainter(this.volume, this.max, this.color, this.track, this.boost);

  final double volume, max;
  final Color color, track, boost;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    double x(double v) => size.width * v / max;
    final line = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), line..color = track);
    if (max > 100) {
      final full = x(100);
      canvas.drawLine(
        Offset(full, y - 5),
        Offset(full, y + 5),
        Paint()
          ..color = track
          ..strokeWidth = 1.5,
      );
    }
    if (volume > 0) canvas.drawLine(Offset(0, y), Offset(x(volume.clamp(0, 100)), y), line..color = color);
    if (volume > 100) canvas.drawLine(Offset(x(100), y), Offset(x(volume), y), line..color = boost);
    canvas.drawCircle(Offset(x(volume), y), 5, Paint()..color = volume > 100 ? boost : color);
  }

  @override
  bool shouldRepaint(_VolumePainter old) =>
      old.volume != volume || old.max != max || old.color != color || old.track != track || old.boost != boost;
}

enum LeafVolumeSlider {
  /// Beside the speaker when the bar has room, else on hover ([fitBar]).
  auto,
  always,
  hover,
  never,
}

/// The speaker (click mutes and restores) and a slider beside it or
/// sliding out on hover; the wheel over it steps the volume (claimed, so
/// the player's own wheel skips it). Needs `HasVolume`.
class LeafVolumeControl extends LeafControl {
  const LeafVolumeControl({this.slider = LeafVolumeSlider.auto});

  final LeafVolumeSlider slider;

  @override
  String get id => 'volume';

  @override
  int get priority => 40;

  @override
  bool isAvailable(LeafControlContext c) => c.controller.volume != null;

  @override
  LeafFitItem fitItem(LeafControlContext c) => LeafFitItem(
    id,
    c.theme.scaledButton,
    priority: priority,
    sliderWidth: slider == LeafVolumeSlider.auto ? c.theme.volumeSliderWidth + 12 : 0,
  );

  @override
  Widget build(BuildContext context, LeafControlContext c) {
    final w = c.theme.volumeSliderWidth;
    final room = switch (slider) {
      LeafVolumeSlider.auto => c.fit.slider,
      LeafVolumeSlider.always => LeafSliderRoom(beside: true, width: w + 12),
      LeafVolumeSlider.hover => LeafSliderRoom(beside: false, width: w + 12),
      LeafVolumeSlider.never => LeafSliderRoom.none,
    };
    final sliderWidth = (room.width - 12).clamp(0.0, w);
    return _Volume(c: c, beside: room.beside, sliderWidth: sliderWidth < 32 ? 0 : sliderWidth);
  }
}

class _Volume extends StatefulWidget {
  const _Volume({required this.c, required this.beside, required this.sliderWidth});

  final LeafControlContext c;
  final bool beside;
  final double sliderWidth;

  @override
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  final _steps = LeafWheelSteps();
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final ctrl = c.controller;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Listener(
        onPointerSignal: (e) => _steps.handle(e, (step) => ctrl.execute(LeafPlayerCommand.stepVolume(step))),
        child: ValueListenableBuilder<double>(
          valueListenable: ctrl.volume!,
          builder: (context, v, _) => Row(
            key: const ValueKey('leaf-control-volume'),
            mainAxisSize: MainAxisSize.min,
            children: [
              LeafControlButton(
                icon: leafVolumeIcon(v),
                color: v > 100 ? c.theme.boost : null,
                tooltip: c.tip('Volume ${v.round()} %', const LeafPlayerCommand.toggleMute()),
                onPressed: () => ctrl.execute(const LeafPlayerCommand.toggleMute()),
              ),
              AnimatedSize(
                key: ValueKey(widget.beside),
                duration: const Duration(milliseconds: 150),
                child: widget.sliderWidth > 0 && (widget.beside || _hover)
                    ? Padding(
                        padding: const EdgeInsets.only(left: 4, right: 8),
                        child: LeafVolumeBar(
                          key: const ValueKey('leaf-volume-bar'),
                          volume: v,
                          max: ctrl.volumeMax,
                          theme: c.theme,
                          color: c.theme.buttonLook == LeafButtonLook.flat ? c.theme.accent : null,
                          width: widget.sliderWidth,
                          onChanged: (value) => ctrl.execute(LeafPlayerCommand.setVolume(value)),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mute only (touch bars).
class LeafMuteControl extends LeafControl {
  const LeafMuteControl();

  @override
  String get id => 'mute';

  @override
  int get priority => 40;

  @override
  bool isAvailable(LeafControlContext c) => c.controller.volume != null;

  @override
  Widget build(BuildContext context, LeafControlContext c) => ValueListenableBuilder<double>(
    valueListenable: c.controller.volume!,
    builder: (context, v, _) => LeafControlButton(
      key: const ValueKey('leaf-control-mute'),
      icon: leafVolumeIcon(v),
      tooltip: c.tip(v <= 0 ? 'Unmute' : 'Mute', const LeafPlayerCommand.toggleMute()),
      onPressed: () => c.controller.execute(const LeafPlayerCommand.toggleMute()),
    ),
  );
}

/// The volume readout for a second after each wheel, key or swipe step,
/// whether the controls are up or not.
class LeafVolumeFlashControl extends LeafControl {
  const LeafVolumeFlashControl();

  @override
  String get id => 'volumeFlash';

  @override
  bool get persistent => true;

  @override
  bool isAvailable(LeafControlContext c) => c.controller.volume != null;

  @override
  Widget build(BuildContext context, LeafControlContext c) => _VolumeFlash(c: c);
}

class _VolumeFlash extends StatefulWidget {
  const _VolumeFlash({required this.c});

  final LeafControlContext c;

  @override
  State<_VolumeFlash> createState() => _VolumeFlashState();
}

class _VolumeFlashState extends State<_VolumeFlash> {
  bool _on = false;
  Timer? _timer;

  LeafPlayerController get _ctrl => widget.c.controller;

  @override
  void initState() {
    super.initState();
    _ctrl.volumeFlash.addListener(_flash);
  }

  @override
  void didUpdateWidget(_VolumeFlash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.c.controller != _ctrl) {
      oldWidget.c.controller.volumeFlash.removeListener(_flash);
      _ctrl.volumeFlash.addListener(_flash);
    }
  }

  @override
  void dispose() {
    _ctrl.volumeFlash.removeListener(_flash);
    _timer?.cancel();
    super.dispose();
  }

  void _flash() {
    setState(() => _on = true);
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), () {
      if (mounted) setState(() => _on = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_on) return const SizedBox.shrink();
    final t = widget.c.theme;
    final max = _ctrl.volumeMax;
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -0.6),
        child: ValueListenableBuilder<double>(
          valueListenable: _ctrl.volume!,
          builder: (context, value, _) {
            final v = value.clamp(0.0, max);
            return DecoratedBox(
              key: const ValueKey('leaf-volume-readout'),
              decoration: BoxDecoration(
                color: t.capsuleFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: t.capsuleBorder, width: 0.5),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 14, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(leafVolumeIcon(v), size: 20, color: v > 100 ? t.boost : t.foreground),
                    const SizedBox(width: 8),
                    LeafVolumeBar(volume: v, max: max, theme: t, onChanged: null, width: 96),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 44,
                      child: Text('${v.round()} %', textAlign: TextAlign.right, style: t.labelStyle.copyWith(fontSize: 13)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
