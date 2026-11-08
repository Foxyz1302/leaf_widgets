import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Axis;

import '../leaf_video_capabilities.dart';
import 'leaf_player_command.dart';

/// One key binding: a [key] (with modifiers) or a typed [character] ("<",
/// "[": the layout decides which keys type it, so Shift is not checked).
@immutable
class LeafKeyBinding {
  const LeafKeyBinding(
    LogicalKeyboardKey this.key,
    this.command, {
    this.shift = false,
    this.control = false,
    this.alt = false,
    this.meta = false,
  }) : character = null;

  const LeafKeyBinding.character(String this.character, this.command, {this.control = false, this.alt = false, this.meta = false})
    : key = null,
      shift = false;

  final LogicalKeyboardKey? key;
  final String? character;
  final bool shift;
  final bool control;
  final bool alt;
  final bool meta;
  final LeafPlayerCommand command;

  bool get isBareArrow =>
      key != null &&
      !shift &&
      !control &&
      !alt &&
      !meta &&
      {
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowUp,
        LogicalKeyboardKey.arrowDown,
      }.contains(key);

  bool matches(KeyEvent event, HardwareKeyboard keyboard) {
    if (keyboard.isControlPressed != control || keyboard.isAltPressed != alt || keyboard.isMetaPressed != meta) return false;
    final c = character;
    if (c != null) return event.character == c;
    return event.logicalKey == key && keyboard.isShiftPressed == shift;
  }

  /// "Shift+→", "Space", "<".
  String get label {
    final c = character;
    final name = c ?? _keyName(key!);
    return [if (control) 'Ctrl', if (alt) 'Alt', if (meta) 'Meta', if (shift) 'Shift', name].join('+');
  }

  static String _keyName(LogicalKeyboardKey k) => switch (k) {
    LogicalKeyboardKey.space => 'Space',
    LogicalKeyboardKey.arrowLeft => '←',
    LogicalKeyboardKey.arrowRight => '→',
    LogicalKeyboardKey.arrowUp => '↑',
    LogicalKeyboardKey.arrowDown => '↓',
    LogicalKeyboardKey.pageUp => 'PgUp',
    LogicalKeyboardKey.pageDown => 'PgDn',
    LogicalKeyboardKey.escape => 'Esc',
    LogicalKeyboardKey.backspace => 'Backspace',
    LogicalKeyboardKey.home => 'Home',
    _ => k.keyLabel.length == 1 ? k.keyLabel.toUpperCase() : k.keyLabel,
  };

  @override
  bool operator ==(Object other) =>
      other is LeafKeyBinding &&
      other.key == key &&
      other.character == character &&
      other.shift == shift &&
      other.control == control &&
      other.alt == alt &&
      other.meta == meta &&
      other.command == command;

  @override
  int get hashCode => Object.hash(key, character, shift, control, alt, meta, command);

  @override
  String toString() => 'LeafKeyBinding($label → $command)';
}

/// The player's keys. Runs from the controls host's Focus; keys it does not
/// bind, or whose command does nothing right now, bubble on.
@immutable
class LeafPlayerKeymap {
  const LeafPlayerKeymap(this.bindings);

  final List<LeafKeyBinding> bindings;

  static const none = LeafPlayerKeymap([]);

  /// The kit's default (DESIGN §3.11; PgUp/PgDn as in mpv).
  static const standard = LeafPlayerKeymap([
    LeafKeyBinding(LogicalKeyboardKey.space, LeafTogglePlay()),
    LeafKeyBinding(LogicalKeyboardKey.keyK, LeafTogglePlay()),
    LeafKeyBinding(LogicalKeyboardKey.arrowLeft, LeafSeekBy(Duration(seconds: -5))),
    LeafKeyBinding(LogicalKeyboardKey.arrowRight, LeafSeekBy(Duration(seconds: 5))),
    LeafKeyBinding(LogicalKeyboardKey.arrowLeft, LeafSeekBy(Duration(seconds: -1)), shift: true),
    LeafKeyBinding(LogicalKeyboardKey.arrowRight, LeafSeekBy(Duration(seconds: 1)), shift: true),
    LeafKeyBinding(LogicalKeyboardKey.keyJ, LeafSeekBy(Duration(seconds: -10))),
    LeafKeyBinding(LogicalKeyboardKey.keyL, LeafSeekBy(Duration(seconds: 10))),
    LeafKeyBinding(LogicalKeyboardKey.arrowUp, LeafStepVolume(1)),
    LeafKeyBinding(LogicalKeyboardKey.arrowDown, LeafStepVolume(-1)),
    LeafKeyBinding(LogicalKeyboardKey.keyM, LeafToggleMute()),
    LeafKeyBinding(LogicalKeyboardKey.keyF, LeafToggleFullscreen()),
    LeafKeyBinding(LogicalKeyboardKey.escape, LeafDismiss()),
    LeafKeyBinding(LogicalKeyboardKey.pageUp, LeafStepChapter(1)),
    LeafKeyBinding(LogicalKeyboardKey.pageDown, LeafStepChapter(-1)),
    LeafKeyBinding(LogicalKeyboardKey.keyP, LeafPrevious(), shift: true),
    LeafKeyBinding(LogicalKeyboardKey.keyN, LeafNext(), shift: true),
    LeafKeyBinding.character('<', LeafPrevious()),
    LeafKeyBinding.character('>', LeafNext()),
    LeafKeyBinding.character('[', LeafStepRate(-0.25)),
    LeafKeyBinding.character(']', LeafStepRate(0.25)),
    LeafKeyBinding(LogicalKeyboardKey.backspace, LeafResetRate()),
    LeafKeyBinding(LogicalKeyboardKey.keyI, LeafToggleInfo()),
    LeafKeyBinding(LogicalKeyboardKey.keyC, LeafCycleTrack(LeafTrackKind.subtitle)),
    LeafKeyBinding(LogicalKeyboardKey.keyS, LeafSkip()),
    LeafKeyBinding(LogicalKeyboardKey.keyL, LeafToggleLoop(), shift: true),
    LeafKeyBinding(LogicalKeyboardKey.digit0, LeafSeekToFraction(0)),
    LeafKeyBinding(LogicalKeyboardKey.digit1, LeafSeekToFraction(0.1)),
    LeafKeyBinding(LogicalKeyboardKey.digit2, LeafSeekToFraction(0.2)),
    LeafKeyBinding(LogicalKeyboardKey.digit3, LeafSeekToFraction(0.3)),
    LeafKeyBinding(LogicalKeyboardKey.digit4, LeafSeekToFraction(0.4)),
    LeafKeyBinding(LogicalKeyboardKey.digit5, LeafSeekToFraction(0.5)),
    LeafKeyBinding(LogicalKeyboardKey.digit6, LeafSeekToFraction(0.6)),
    LeafKeyBinding(LogicalKeyboardKey.digit7, LeafSeekToFraction(0.7)),
    LeafKeyBinding(LogicalKeyboardKey.digit8, LeafSeekToFraction(0.8)),
    LeafKeyBinding(LogicalKeyboardKey.digit9, LeafSeekToFraction(0.9)),
    LeafKeyBinding(LogicalKeyboardKey.home, LeafSeekTo(Duration.zero)),
  ]);

  /// mpv's defaults where they map: ↑/↓ seek a minute, 9/0 volume, `j`
  /// subtitles, `L` loop.
  static const mpv = LeafPlayerKeymap([
    LeafKeyBinding(LogicalKeyboardKey.space, LeafTogglePlay()),
    LeafKeyBinding(LogicalKeyboardKey.keyP, LeafTogglePlay()),
    LeafKeyBinding(LogicalKeyboardKey.arrowLeft, LeafSeekBy(Duration(seconds: -5))),
    LeafKeyBinding(LogicalKeyboardKey.arrowRight, LeafSeekBy(Duration(seconds: 5))),
    LeafKeyBinding(LogicalKeyboardKey.arrowLeft, LeafSeekBy(Duration(seconds: -1)), shift: true),
    LeafKeyBinding(LogicalKeyboardKey.arrowRight, LeafSeekBy(Duration(seconds: 1)), shift: true),
    LeafKeyBinding(LogicalKeyboardKey.arrowUp, LeafSeekBy(Duration(seconds: 60))),
    LeafKeyBinding(LogicalKeyboardKey.arrowDown, LeafSeekBy(Duration(seconds: -60))),
    LeafKeyBinding.character('9', LeafStepVolume(-1)),
    LeafKeyBinding.character('0', LeafStepVolume(1)),
    LeafKeyBinding(LogicalKeyboardKey.keyM, LeafToggleMute()),
    LeafKeyBinding(LogicalKeyboardKey.keyF, LeafToggleFullscreen()),
    LeafKeyBinding(LogicalKeyboardKey.escape, LeafDismiss()),
    LeafKeyBinding(LogicalKeyboardKey.pageUp, LeafStepChapter(1)),
    LeafKeyBinding(LogicalKeyboardKey.pageDown, LeafStepChapter(-1)),
    LeafKeyBinding.character('<', LeafPrevious()),
    LeafKeyBinding.character('>', LeafNext()),
    LeafKeyBinding.character('[', LeafStepRate(-0.25)),
    LeafKeyBinding.character(']', LeafStepRate(0.25)),
    LeafKeyBinding(LogicalKeyboardKey.backspace, LeafResetRate()),
    LeafKeyBinding(LogicalKeyboardKey.keyI, LeafToggleInfo()),
    LeafKeyBinding(LogicalKeyboardKey.keyJ, LeafCycleTrack(LeafTrackKind.subtitle)),
    LeafKeyBinding(LogicalKeyboardKey.keyL, LeafToggleLoop(), shift: true),
  ]);

  /// YouTube's: k/Space, j/l 10 s, ←/→ 5 s, ↑/↓ volume, c captions, 0–9.
  static const youtube = LeafPlayerKeymap([
    LeafKeyBinding(LogicalKeyboardKey.space, LeafTogglePlay()),
    LeafKeyBinding(LogicalKeyboardKey.keyK, LeafTogglePlay()),
    LeafKeyBinding(LogicalKeyboardKey.keyJ, LeafSeekBy(Duration(seconds: -10))),
    LeafKeyBinding(LogicalKeyboardKey.keyL, LeafSeekBy(Duration(seconds: 10))),
    LeafKeyBinding(LogicalKeyboardKey.arrowLeft, LeafSeekBy(Duration(seconds: -5))),
    LeafKeyBinding(LogicalKeyboardKey.arrowRight, LeafSeekBy(Duration(seconds: 5))),
    LeafKeyBinding(LogicalKeyboardKey.arrowUp, LeafStepVolume(1)),
    LeafKeyBinding(LogicalKeyboardKey.arrowDown, LeafStepVolume(-1)),
    LeafKeyBinding(LogicalKeyboardKey.keyM, LeafToggleMute()),
    LeafKeyBinding(LogicalKeyboardKey.keyF, LeafToggleFullscreen()),
    LeafKeyBinding(LogicalKeyboardKey.escape, LeafDismiss()),
    LeafKeyBinding(LogicalKeyboardKey.keyC, LeafCycleTrack(LeafTrackKind.subtitle)),
    LeafKeyBinding(LogicalKeyboardKey.keyN, LeafNext(), shift: true),
    LeafKeyBinding(LogicalKeyboardKey.keyP, LeafPrevious(), shift: true),
    LeafKeyBinding.character('<', LeafStepRate(-0.25)),
    LeafKeyBinding.character('>', LeafStepRate(0.25)),
    LeafKeyBinding(LogicalKeyboardKey.digit0, LeafSeekToFraction(0)),
    LeafKeyBinding(LogicalKeyboardKey.digit1, LeafSeekToFraction(0.1)),
    LeafKeyBinding(LogicalKeyboardKey.digit2, LeafSeekToFraction(0.2)),
    LeafKeyBinding(LogicalKeyboardKey.digit3, LeafSeekToFraction(0.3)),
    LeafKeyBinding(LogicalKeyboardKey.digit4, LeafSeekToFraction(0.4)),
    LeafKeyBinding(LogicalKeyboardKey.digit5, LeafSeekToFraction(0.5)),
    LeafKeyBinding(LogicalKeyboardKey.digit6, LeafSeekToFraction(0.6)),
    LeafKeyBinding(LogicalKeyboardKey.digit7, LeafSeekToFraction(0.7)),
    LeafKeyBinding(LogicalKeyboardKey.digit8, LeafSeekToFraction(0.8)),
    LeafKeyBinding(LogicalKeyboardKey.digit9, LeafSeekToFraction(0.9)),
    LeafKeyBinding(LogicalKeyboardKey.home, LeafSeekTo(Duration.zero)),
  ]);

  /// [extra] first, so it overrides the bindings it shares keys with.
  LeafPlayerKeymap merge(List<LeafKeyBinding> extra) => LeafPlayerKeymap([...extra, ...bindings]);

  LeafPlayerKeymap without(bool Function(LeafKeyBinding binding) test) =>
      LeafPlayerKeymap([for (final b in bindings) if (!test(b)) b]);

  /// Inside a viewer: the bare arrows along its [axis] page it.
  LeafPlayerKeymap forViewer(Axis axis) => without(
    (b) =>
        b.isBareArrow &&
        (axis == Axis.horizontal
            ? (b.key == LogicalKeyboardKey.arrowLeft || b.key == LogicalKeyboardKey.arrowRight)
            : (b.key == LogicalKeyboardKey.arrowUp || b.key == LogicalKeyboardKey.arrowDown)),
  );

  /// The commands bound to [event], first match first.
  Iterable<LeafPlayerCommand> commandsFor(KeyEvent event, [HardwareKeyboard? keyboard]) sync* {
    final k = keyboard ?? HardwareKeyboard.instance;
    for (final b in bindings) {
      if (b.matches(event, k)) yield b.command;
    }
  }

  /// "Space", "F": the first key bound to [command], for tooltips.
  String? hintFor(LeafPlayerCommand command) {
    for (final b in bindings) {
      if (b.command == command) return b.label;
    }
    return null;
  }

  /// "Play (Space)".
  String tooltip(String text, LeafPlayerCommand command) {
    final hint = hintFor(command);
    return hint == null ? text : '$text ($hint)';
  }

  @override
  bool operator ==(Object other) => other is LeafPlayerKeymap && listEquals(other.bindings, bindings);

  @override
  int get hashCode => Object.hashAll(bindings);
}
