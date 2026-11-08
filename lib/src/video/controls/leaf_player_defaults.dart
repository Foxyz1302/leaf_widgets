import 'package:flutter/widgets.dart';

import 'leaf_controls_spec.dart';
import 'leaf_controls_theme.dart';
import 'leaf_fullscreen.dart';
import 'leaf_player_controller.dart';

/// App-wide defaults for the controls kit, placed once above the app.
/// [controls] set here switches every `LeafVideoPage` without its own
/// `controlsBuilder` to the kit.
class LeafPlayerDefaults extends InheritedWidget {
  const LeafPlayerDefaults({
    super.key,
    this.controls,
    this.theme,
    this.prefs,
    this.fullscreenDelegate,
    this.fullscreenMode = LeafFullscreenMode.auto,
    required super.child,
  });

  /// The spec for pages that pass none; null keeps the legacy controls.
  final LeafControlsSpec? controls;
  final LeafControlsTheme? theme;

  /// Shared prefs (time format, scale, hidden ids, progress line).
  final LeafControlsPrefs? prefs;

  /// The OS step of fullscreen; null: [LeafFullscreenDelegate.platformDefault].
  final LeafFullscreenDelegate? fullscreenDelegate;
  final LeafFullscreenMode fullscreenMode;

  static LeafPlayerDefaults? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<LeafPlayerDefaults>();

  @override
  bool updateShouldNotify(LeafPlayerDefaults oldWidget) =>
      oldWidget.controls != controls ||
      oldWidget.theme != theme ||
      oldWidget.prefs != prefs ||
      oldWidget.fullscreenDelegate != fullscreenDelegate ||
      oldWidget.fullscreenMode != fullscreenMode;
}
