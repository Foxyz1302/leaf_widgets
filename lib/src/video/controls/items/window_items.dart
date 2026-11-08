import 'package:flutter/material.dart';

import '../leaf_controls_theme.dart';
import '../leaf_player_command.dart';
import '../leaf_player_controller.dart';
import 'leaf_control.dart';

/// Enters / leaves fullscreen; shown while something can perform it (the
/// player view, or an app's handler).
class LeafFullscreenControl extends LeafControl {
  const LeafFullscreenControl();

  @override
  String get id => 'fullscreen';

  @override
  int get priority => 1000;

  @override
  Iterable<Listenable> availabilityDeps(LeafPlayerController c) => [c.fullscreenAvailable];

  @override
  bool isAvailable(LeafControlContext c) => c.controller.fullscreenAvailable.value || c.isFullscreen;

  @override
  Widget build(BuildContext context, LeafControlContext c) => ValueListenableBuilder<bool>(
    valueListenable: c.controller.fullscreen,
    builder: (context, full, _) => LeafControlButton(
      key: const ValueKey('leaf-control-fullscreen'),
      icon: full ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
      tooltip: c.tip(full ? 'Exit fullscreen' : 'Fullscreen', const LeafPlayerCommand.toggleFullscreen()),
      onPressed: () => c.controller.execute(const LeafPlayerCommand.toggleFullscreen()),
    ),
  );
}

/// The title and subtitle from the actions, ellipsized.
class LeafTitleControl extends LeafControl {
  const LeafTitleControl();

  @override
  String get id => 'title';

  @override
  double? estimatedWidth(LeafControlsTheme t) => null;

  @override
  Iterable<Listenable> availabilityDeps(LeafPlayerController c) => [c.actionsListenable];

  @override
  bool isAvailable(LeafControlContext c) => (c.controller.actions.title ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context, LeafControlContext c) {
    final a = c.controller.actions;
    final t = c.theme;
    return Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8 * t.scale),
        child: Column(
          key: const ValueKey('leaf-control-title'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              a.title!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.labelStyle.copyWith(fontSize: 16 * t.scale, fontWeight: FontWeight.w600),
            ),
            if ((a.subtitle ?? '').isNotEmpty)
              Text(
                a.subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.labelStyle.copyWith(color: t.foregroundDim, fontSize: 13 * t.scale),
              ),
          ],
        ),
      ),
    );
  }
}

/// Back: the app's `actions.onBack`, else leaves fullscreen.
class LeafBackControl extends LeafControl {
  const LeafBackControl();

  @override
  String get id => 'back';

  @override
  int get priority => 1000;

  @override
  Iterable<Listenable> availabilityDeps(LeafPlayerController c) => [c.actionsListenable];

  @override
  bool isAvailable(LeafControlContext c) => c.controller.actions.onBack != null || c.isFullscreen;

  @override
  Widget build(BuildContext context, LeafControlContext c) => LeafControlButton(
    key: const ValueKey('leaf-control-back'),
    icon: Icons.arrow_back_rounded,
    tooltip: 'Back',
    onPressed: () => c.controller.execute(const LeafPlayerCommand.back()),
  );
}
