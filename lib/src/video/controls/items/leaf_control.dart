import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../leaf_controls_layout.dart';
import '../leaf_controls_spec.dart';
import '../leaf_controls_theme.dart';
import '../leaf_controls_visibility.dart';
import '../leaf_player_command.dart';
import '../leaf_player_controller.dart';
import '../leaf_player_keymap.dart';
import '../media_math.dart';
import 'chapter_items.dart';
import 'flashes.dart';
import 'play_items.dart';
import 'seek_bar.dart';
import 'time_items.dart';
import 'volume_items.dart';
import 'window_items.dart';

/// How a bar fits at its width ([fitBar]), for the items in it.
@immutable
class LeafBarFit {
  const LeafBarFit({this.slider = const LeafSliderRoom(beside: true, width: 72), this.compactTime = false});

  static const roomy = LeafBarFit();

  final LeafSliderRoom slider;
  final bool compactTime;
}

/// Everything a catalog item builds from.
@immutable
class LeafControlContext {
  const LeafControlContext({
    required this.controller,
    required this.visibility,
    required this.theme,
    required this.spec,
    required this.keymap,
    required this.reveal,
    required this.isFullscreen,
    required this.isTouch,
    this.viewerCanPage = false,
    this.slot = LeafSlot.overlay,
    this.fit = LeafBarFit.roomy,
  });

  final LeafPlayerController controller;
  final LeafControlsVisibility visibility;
  final LeafControlsTheme theme;
  final LeafControlsSpec spec;

  /// The active keys (tooltip hints come from here).
  final LeafPlayerKeymap keymap;

  /// The controls' fade, 0 hidden .. 1 shown.
  final Animation<double> reveal;
  final bool isFullscreen;
  final bool isTouch;

  /// Inside a viewer: next/previous page it when the app has none.
  final bool viewerCanPage;
  final LeafSlot slot;
  final LeafBarFit fit;

  LeafControlContext inSlot(LeafSlot slot, {LeafBarFit? fit}) => LeafControlContext(
    controller: controller,
    visibility: visibility,
    theme: theme,
    spec: spec,
    keymap: keymap,
    reveal: reveal,
    isFullscreen: isFullscreen,
    isTouch: isTouch,
    viewerCanPage: viewerCanPage,
    slot: slot,
    fit: fit ?? this.fit,
  );

  /// "Play (Space)".
  String tip(String text, LeafPlayerCommand command) => keymap.tooltip(text, command);
}

/// Gives descendants of the controls host the player's context.
class LeafPlayerScope extends InheritedWidget {
  const LeafPlayerScope({super.key, required this.data, required super.child});

  final LeafControlContext data;

  static LeafControlContext? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LeafPlayerScope>()?.data;

  static LeafControlContext of(BuildContext context) => maybeOf(context)!;

  @override
  bool updateShouldNotify(LeafPlayerScope oldWidget) =>
      oldWidget.data.theme != data.theme ||
      oldWidget.data.isFullscreen != data.isFullscreen ||
      oldWidget.data.keymap != data.keymap ||
      oldWidget.data.controller != data.controller ||
      oldWidget.data.visibility != data.visibility;
}

/// One item of the controls catalog. Items are `const` objects placed into
/// slots by a [LeafControlsLayout]; they build leaf widgets that listen to
/// the controller themselves, so nothing above them rebuilds on ticks.
abstract class LeafControl {
  const LeafControl();

  String get id;

  /// What [isAvailable] reads; the bar re-fits when one notifies.
  Iterable<Listenable> availabilityDeps(LeafPlayerController c) => const [];

  /// False drops the item (a capability missing, nothing to show).
  bool isAvailable(LeafControlContext c) => true;

  /// The width in a bar; null for flexible items.
  double? estimatedWidth(LeafControlsTheme t) => t.scaledButton;

  /// The lowest drops into ⋯ first; 1000 and above never drop.
  int get priority => 50;

  /// Stays mounted while the controls are hidden (it shows itself when it
  /// has something to say: a spinner, a flash, the collapsed band).
  bool get persistent => false;

  LeafFitItem fitItem(LeafControlContext c) => LeafFitItem(id, estimatedWidth(c.theme) ?? 0, priority: priority);

  Widget build(BuildContext context, LeafControlContext c);

  static const playPause = LeafPlayPauseControl();
  static const bigPlay = LeafBigPlayControl();
  static const bigPlayWhilePaused = LeafBigPlayControl(whilePaused: true);
  static const pauseIndicator = LeafPauseIndicatorControl();
  static const buffering = LeafBufferingControl();
  static const previous = LeafStepItemControl.previous();
  static const next = LeafStepItemControl.next();
  static const seekBar = LeafSeekBarControl();
  static const time = LeafTimeControl();
  static const progressLine = LeafProgressLineControl();
  static const chapterPrevious = LeafChapterStepControl.previous();
  static const chapterNext = LeafChapterStepControl.next();
  static const volume = LeafVolumeControl();
  static const mute = LeafMuteControl();
  static const volumeFlash = LeafVolumeFlashControl();
  static const fullscreen = LeafFullscreenControl();
  static const title = LeafTitleControl();
  static const back = LeafBackControl();
  static const seekFeedback = LeafSeekFeedbackControl();
  static const spacer = _SpacerControl();

  static LeafControl seekBy(Duration delta) => LeafSeekByControl(delta);
  static LeafControl gap(double width) => _GapControl(width);

  /// A button that runs [onPressed].
  static LeafControl action({
    required String id,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    ValueListenable<int>? badge,
    ValueListenable<bool>? enabled,
    int priority = 50,
  }) => _ActionControl(id, icon, tooltip, onPressed, badge, enabled, priority);

  /// A button showing [activeIcon] while [value] is true.
  static LeafControl toggle({
    required String id,
    required IconData icon,
    required IconData activeIcon,
    required String tooltip,
    required ValueListenable<bool> value,
    required ValueChanged<bool> onChanged,
    int priority = 50,
  }) => _ToggleControl(id, icon, activeIcon, tooltip, value, onChanged, priority);

  /// The escape hatch: any widget, [width] wide in a bar (null: flexible).
  static LeafControl widget({required String id, required WidgetBuilder builder, double? width, int priority = 50}) =>
      _WidgetControl(id, builder, width, priority);

  /// The built-ins by id, for [LeafControlsLayout.fromIds].
  static const Map<String, LeafControl> catalog = {
    'playPause': playPause,
    'bigPlay': bigPlay,
    'bigPlayWhilePaused': bigPlayWhilePaused,
    'pauseIndicator': pauseIndicator,
    'buffering': buffering,
    'previous': previous,
    'next': next,
    'seekBar': seekBar,
    'time': time,
    'progressLine': progressLine,
    'chapterPrevious': chapterPrevious,
    'chapterNext': chapterNext,
    'volume': volume,
    'mute': mute,
    'volumeFlash': volumeFlash,
    'fullscreen': fullscreen,
    'title': title,
    'back': back,
    'seekFeedback': seekFeedback,
    'spacer': spacer,
  };
}

class _SpacerControl extends LeafControl {
  const _SpacerControl();

  @override
  String get id => 'spacer';

  @override
  double? estimatedWidth(LeafControlsTheme t) => 0;

  @override
  int get priority => 1000;

  @override
  Widget build(BuildContext context, LeafControlContext c) => const Spacer();
}

class _GapControl extends LeafControl {
  const _GapControl(this.width);

  final double width;

  @override
  String get id => 'gap$width';

  @override
  double? estimatedWidth(LeafControlsTheme t) => width * t.scale;

  @override
  int get priority => 1000;

  @override
  Widget build(BuildContext context, LeafControlContext c) => SizedBox(width: width * c.theme.scale);
}

class _ActionControl extends LeafControl {
  const _ActionControl(this.id, this.icon, this.tooltip, this.onPressed, this.badge, this.enabled, this.priority);

  @override
  final String id;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final ValueListenable<int>? badge;
  final ValueListenable<bool>? enabled;
  @override
  final int priority;

  @override
  Widget build(BuildContext context, LeafControlContext c) {
    final listenables = <Listenable>[?badge, ?enabled];
    Widget button() => LeafControlButton(
      key: ValueKey('leaf-control-$id'),
      icon: icon,
      tooltip: tooltip,
      badge: badge?.value,
      onPressed: (enabled?.value ?? true) ? onPressed : null,
    );
    if (listenables.isEmpty) return button();
    return ListenableBuilder(listenable: Listenable.merge(listenables), builder: (context, _) => button());
  }
}

class _ToggleControl extends LeafControl {
  const _ToggleControl(this.id, this.icon, this.activeIcon, this.tooltip, this.value, this.onChanged, this.priority);

  @override
  final String id;
  final IconData icon;
  final IconData activeIcon;
  final String tooltip;
  final ValueListenable<bool> value;
  final ValueChanged<bool> onChanged;
  @override
  final int priority;

  @override
  Widget build(BuildContext context, LeafControlContext c) => ValueListenableBuilder<bool>(
    valueListenable: value,
    builder: (context, on, _) => LeafControlButton(
      key: ValueKey('leaf-control-$id'),
      icon: on ? activeIcon : icon,
      tooltip: tooltip,
      onPressed: () => onChanged(!on),
    ),
  );
}

class _WidgetControl extends LeafControl {
  const _WidgetControl(this.id, this.builder, this.width, this.priority);

  @override
  final String id;
  final WidgetBuilder builder;
  final double? width;
  @override
  final int priority;

  @override
  double? estimatedWidth(LeafControlsTheme t) => width;

  @override
  Widget build(BuildContext context, LeafControlContext c) => builder(context);
}

/// The controls' tooltip: the theme's dark fill, above the control.
class LeafTip extends StatelessWidget {
  const LeafTip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (message.isEmpty) return child;
    final t = LeafPlayerScope.maybeOf(context)?.theme;
    return Tooltip(
      message: message,
      preferBelow: false,
      verticalOffset: 28,
      waitDuration: const Duration(milliseconds: 400),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: t?.tooltipFill ?? const Color(0xEB18181C),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t?.capsuleBorder ?? const Color(0x1FFFFFFF), width: 0.5),
      ),
      textStyle: TextStyle(color: t?.foreground ?? Colors.white, fontSize: 12),
      child: child,
    );
  }
}

/// A control button in the theme's look: round (Material) or flat (uosc, a
/// rounded square that lights on hover). [accent] fills it with the accent
/// (the uosc play button). Never takes focus, so Space stays play.
class LeafControlButton extends StatefulWidget {
  const LeafControlButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.accent = false,
    this.big = false,
    this.badge,
    this.color,
    this.label,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool accent;

  /// The play button's larger icon.
  final bool big;
  final int? badge;
  final Color? color;
  final String? label;

  @override
  State<LeafControlButton> createState() => _LeafControlButtonState();
}

class _LeafControlButtonState extends State<LeafControlButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = LeafPlayerScope.of(context).theme;
    final w = widget;
    final enabled = w.onPressed != null;
    final flat = t.buttonLook == LeafButtonLook.flat;
    final size = t.scaledButton;
    final iconSize = (w.big || w.accent ? t.playIconSize : t.iconSize) * t.scale;
    final fg = !enabled ? t.disabled : (w.accent && flat ? t.onAccent : (w.color ?? t.foreground));
    final Color bg;
    if (w.accent && flat) {
      bg = _hover ? Color.lerp(t.accent, Colors.white, 0.18)! : t.accent;
    } else {
      bg = _hover && enabled ? t.hover : Colors.transparent;
    }
    final badge = w.badge;
    final icon = Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(w.icon, color: fg, size: iconSize),
        if (badge != null && badge > 0)
          Positioned(
            right: -7,
            top: -5,
            child: Container(
              key: const ValueKey('leaf-badge'),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(999)),
              child: Text(
                '$badge',
                style: TextStyle(color: t.onAccent, fontSize: 9, height: 1.35, fontWeight: FontWeight.w700),
              ),
            ),
          ),
      ],
    );
    final round = !flat || w.accent;
    return LeafTip(
      message: w.tooltip,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: w.onPressed,
          child: Semantics(
            button: true,
            enabled: enabled,
            label: w.tooltip,
            child: Container(
              height: size,
              constraints: BoxConstraints(minWidth: size),
              padding: EdgeInsets.symmetric(horizontal: w.label == null ? 0 : 10 * t.scale),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(round && w.label == null ? size / 2 : t.radius * t.scale),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  if (w.label != null) ...[
                    SizedBox(width: 6 * t.scale),
                    Text(w.label!, style: t.labelStyle.copyWith(color: fg)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A glass capsule (a solid translucent fill, no blur) around a row of
/// buttons: the uosc look's clusters.
class LeafCapsule extends StatelessWidget {
  const LeafCapsule({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = LeafPlayerScope.of(context).theme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.capsuleFill,
        borderRadius: BorderRadius.circular(t.radius * t.scale + t.capsulePad),
        border: Border.all(color: t.capsuleBorder, width: 0.5),
      ),
      child: Padding(
        padding: EdgeInsets.all(t.capsulePad),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 2, children: children),
      ),
    );
  }
}
