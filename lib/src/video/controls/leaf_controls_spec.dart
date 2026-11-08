import 'package:flutter/foundation.dart';

import 'items/leaf_control.dart';
import 'items/seek_bar.dart';
import 'leaf_controls_layout.dart';
import 'leaf_controls_theme.dart';
import 'leaf_player_keymap.dart';

enum LeafTapAction { toggleControls, togglePlay, none }

enum LeafDoubleTapCenter { togglePlay, toggleFullscreen, none }

enum LeafClickAction { togglePlay, toggleControls, none }

enum LeafDoubleClickAction { toggleFullscreen, none }

/// Touch and mouse gestures on the picture (not on the bars).
@immutable
class LeafGestureSpec {
  const LeafGestureSpec({
    this.tap = LeafTapAction.toggleControls,
    this.doubleTapSeek = const Duration(seconds: 10),
    this.doubleTapSideFraction = 1 / 3,
    this.doubleTapCenter = LeafDoubleTapCenter.togglePlay,
    this.click = LeafClickAction.togglePlay,
    this.doubleClick = LeafDoubleClickAction.toggleFullscreen,
    this.wheelVolume = true,
  });

  final LeafTapAction tap;

  /// Double-tap on the outer sides seeks this far; null turns it off (a
  /// double-tap anywhere then does [doubleTapCenter]).
  final Duration? doubleTapSeek;
  final double doubleTapSideFraction;
  final LeafDoubleTapCenter doubleTapCenter;

  /// A mouse click, acted on at pointer-down.
  final LeafClickAction click;
  final LeafDoubleClickAction doubleClick;

  /// The wheel over the player steps the volume (lists under the mouse
  /// claim it first).
  final bool wheelVolume;

  LeafGestureSpec copyWith({
    LeafTapAction? tap,
    Duration? doubleTapSeek,
    double? doubleTapSideFraction,
    LeafDoubleTapCenter? doubleTapCenter,
    LeafClickAction? click,
    LeafDoubleClickAction? doubleClick,
    bool? wheelVolume,
  }) => LeafGestureSpec(
    tap: tap ?? this.tap,
    doubleTapSeek: doubleTapSeek ?? this.doubleTapSeek,
    doubleTapSideFraction: doubleTapSideFraction ?? this.doubleTapSideFraction,
    doubleTapCenter: doubleTapCenter ?? this.doubleTapCenter,
    click: click ?? this.click,
    doubleClick: doubleClick ?? this.doubleClick,
    wheelVolume: wheelVolume ?? this.wheelVolume,
  );
}

/// When the controls hide on their own.
@immutable
class LeafAutoHide {
  const LeafAutoHide({
    this.delay = const Duration(seconds: 3),
    this.whilePaused = false,
    this.hideCursor = true,
    this.onPointerExit = true,
    this.flashOnCommand = true,
  });

  final Duration delay;

  /// False: a paused video holds the controls up (leaf's default).
  final bool whilePaused;
  final bool hideCursor;
  final bool onPointerExit;

  /// Key seeks show the bars for a moment (volume steps show the readout).
  final bool flashOnCommand;
}

/// A layout with its gestures, keys, auto-hide and look. Use a preset, or
/// `copyWith` / `layout.withSlot(...)` to rearrange one.
@immutable
class LeafControlsSpec {
  const LeafControlsSpec({
    required this.layout,
    this.look = LeafLook.material,
    this.theme,
    this.gestures = const LeafGestureSpec(),
    this.keymap = LeafPlayerKeymap.standard,
    this.autoHide = const LeafAutoHide(),
    this.fullscreen,
  });

  final LeafControlsLayout layout;
  final LeafLook look;

  /// Overrides the resolved theme.
  final LeafControlsTheme? theme;
  final LeafGestureSpec gestures;
  final LeafPlayerKeymap keymap;
  final LeafAutoHide autoHide;

  /// The spec while fullscreen; null: this one.
  final LeafControlsSpec? fullscreen;

  /// The spec for this platform ([adaptive] picks one).
  LeafControlsSpec resolve({required bool desktop}) => this;

  LeafControlsSpec copyWith({
    LeafControlsLayout? layout,
    LeafLook? look,
    LeafControlsTheme? theme,
    LeafGestureSpec? gestures,
    LeafPlayerKeymap? keymap,
    LeafAutoHide? autoHide,
    LeafControlsSpec? fullscreen,
  }) => LeafControlsSpec(
    layout: layout ?? this.layout,
    look: look ?? this.look,
    theme: theme ?? this.theme,
    gestures: gestures ?? this.gestures,
    keymap: keymap ?? this.keymap,
    autoHide: autoHide ?? this.autoHide,
    fullscreen: fullscreen ?? this.fullscreen,
  );

  /// Touch: a tappable centre (previous, big play, next), the clock and
  /// fullscreen below, a line seek bar with an always-on knob at the bottom.
  /// Tap toggles the controls; double-tap the sides ±10 s, the middle plays.
  static const mobile = LeafControlsSpec(
    layout: LeafControlsLayout(slots: _mobileSlots),
    gestures: LeafGestureSpec(click: LeafClickAction.toggleControls, doubleClick: LeafDoubleClickAction.none, wheelVolume: false),
    fullscreen: LeafControlsSpec(
      layout: LeafControlsLayout(
        slots: {
          ..._mobileSlots,
          LeafSlot.topStart: [LeafControl.back, LeafControl.title],
        },
      ),
      gestures: LeafGestureSpec(click: LeafClickAction.toggleControls, doubleClick: LeafDoubleClickAction.none, wheelVolume: false),
    ),
  );

  static const _mobileSlots = <LeafSlot, List<LeafControl>>{
    LeafSlot.center: [LeafControl.previous, LeafControl.bigPlay, LeafControl.next, LeafControl.buffering],
    LeafSlot.bottomStart: [LeafControl.time],
    LeafSlot.bottomEnd: [LeafControl.fullscreen],
    LeafSlot.bottomBelow: [LeafSeekBarControl(knob: LeafKnob.always, hitHeight: 32, chapters: true)],
    LeafSlot.overlay: [LeafControl.seekFeedback, LeafControl.volumeFlash],
  };

  /// Material bars (sync_relay "Standard"): a line seek bar with chapter
  /// marks and a hover tip over a row of round buttons. Click plays,
  /// double-click goes fullscreen, the wheel sets the volume.
  static const desktop = LeafControlsSpec(
    layout: LeafControlsLayout(
      topOnlyInFullscreen: true,
      slots: {
        LeafSlot.topStart: [LeafControl.title],
        LeafSlot.bottomAbove: [LeafSeekBarControl()],
        LeafSlot.bottomStart: _desktopStart,
        LeafSlot.bottomEnd: [LeafControl.fullscreen],
        LeafSlot.center: [LeafControl.buffering, LeafControl.pauseIndicator],
        LeafSlot.overlay: [LeafControl.volumeFlash, LeafControl.seekFeedback],
        LeafSlot.whenHidden: [LeafControl.progressLine],
      },
    ),
  );

  static const _desktopStart = <LeafControl>[
    LeafControl.playPause,
    LeafControl.previous,
    LeafControl.next,
    LeafControl.chapterPrevious,
    LeafControl.chapterNext,
    LeafControl.volume,
    LeafControl.time,
  ];

  /// The uosc look (sync_relay "Minimal"): the desktop items in two glass
  /// capsules, the accent play button, and a thick band timeline with the
  /// times inside that shrinks to a line while hidden.
  static const uosc = LeafControlsSpec(
    look: LeafLook.uosc,
    layout: LeafControlsLayout(
      topOnlyInFullscreen: true,
      capsules: true,
      slots: {
        LeafSlot.topStart: [LeafControl.title],
        LeafSlot.bottomStart: [
          LeafControl.playPause,
          LeafControl.previous,
          LeafControl.next,
          LeafControl.chapterPrevious,
          LeafControl.chapterNext,
          LeafControl.volume,
        ],
        LeafSlot.bottomEnd: [LeafControl.fullscreen],
        LeafSlot.bottomBelow: [
          LeafSeekBarControl(look: LeafSeekBarLook.band, timesInside: true, collapseWhenHidden: true, knob: LeafKnob.never),
        ],
        LeafSlot.center: [LeafControl.buffering, LeafControl.pauseIndicator],
        LeafSlot.overlay: [LeafControl.volumeFlash, LeafControl.seekFeedback],
      },
    ),
  );

  /// Bare (feed tiles, thumbnails strips): a thin line, a big play button
  /// while paused, the progress line while hidden. Tap / click plays; no
  /// keys.
  static const minimal = LeafControlsSpec(
    layout: LeafControlsLayout(
      slots: {
        LeafSlot.bottomBelow: [LeafSeekBarControl(thin: true, hitHeight: 16)],
        LeafSlot.center: [LeafControl.bigPlayWhilePaused, LeafControl.buffering],
        LeafSlot.whenHidden: [LeafControl.progressLine],
      },
    ),
    gestures: LeafGestureSpec(
      tap: LeafTapAction.togglePlay,
      doubleTapSeek: null,
      doubleTapCenter: LeafDoubleTapCenter.none,
      doubleClick: LeafDoubleClickAction.none,
      wheelVolume: false,
    ),
    keymap: LeafPlayerKeymap.none,
  );

  /// Touch → [touch] ([mobile]), desktop → [desktop] ([uosc]).
  static LeafControlsSpec adaptive({LeafControlsSpec desktop = uosc, LeafControlsSpec touch = mobile}) =>
      _AdaptiveSpec(desktop, touch);
}

class _AdaptiveSpec extends LeafControlsSpec {
  _AdaptiveSpec(this.desktopSpec, this.touchSpec) : super(layout: desktopSpec.layout);

  final LeafControlsSpec desktopSpec;
  final LeafControlsSpec touchSpec;

  @override
  LeafControlsSpec resolve({required bool desktop}) => desktop ? desktopSpec : touchSpec;

  @override
  bool operator ==(Object other) => other is _AdaptiveSpec && other.desktopSpec == desktopSpec && other.touchSpec == touchSpec;

  @override
  int get hashCode => Object.hash(desktopSpec, touchSpec);
}
