import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../viewer/leaf_chrome.dart';
import '../../viewer/leaf_viewer_internal.dart';
import 'leaf_controls_spec.dart';
import 'leaf_player_command.dart';
import 'leaf_player_controller.dart';
import 'leaf_player_controls.dart';
import 'leaf_player_defaults.dart';

/// A player's controls drawn outside its page: an app layer that stays put
/// while the pages slide renders the current page's [controller] (null: none).
/// A new controller fades in over [fadeIn]; the page keeps the picture's
/// gestures ([LeafPlayerGestures], see [LeafVideoPage.detachedControls]).
class LeafDetachedControls extends StatelessWidget {
  const LeafDetachedControls({
    super.key,
    required this.controller,
    this.spec,
    this.chrome,
    this.fadeIn = const Duration(milliseconds: 180),
  });

  final ValueListenable<LeafPlayerController?> controller;
  final LeafControlsSpec? spec;

  /// Shows and hides with this chrome on touch, outside fullscreen.
  final LeafViewerChrome? chrome;
  final Duration fadeIn;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<LeafPlayerController?>(
    valueListenable: controller,
    builder: (context, ctrl, _) {
      if (ctrl == null) return const SizedBox.shrink();
      return TweenAnimationBuilder<double>(
        key: ObjectKey(ctrl),
        tween: Tween(begin: 0, end: 1),
        duration: fadeIn,
        builder: (context, t, child) => Opacity(opacity: t, child: child),
        child: ValueListenableBuilder<bool>(
          valueListenable: ctrl.fullscreen,
          builder: (context, full, _) => LeafPlayerControls(controller: ctrl, spec: spec, chrome: chrome, picture: false, isFullscreen: full),
        ),
      );
    },
  );
}

/// The picture's touch gestures for a player whose controls are drawn
/// elsewhere: tap and double-tap act per the spec's [LeafGestureSpec] through
/// [controller] (a tap toggles whichever controls host is attached).
class LeafPlayerGestures extends StatefulWidget {
  const LeafPlayerGestures({super.key, required this.controller, this.spec, this.isFullscreen = false});

  final LeafPlayerController controller;
  final LeafControlsSpec? spec;
  final bool isFullscreen;

  @override
  State<LeafPlayerGestures> createState() => _LeafPlayerGesturesState();
}

class _LeafPlayerGesturesState extends State<LeafPlayerGestures> {
  Offset? _doubleTapAt;

  LeafGestureSpec get _gestures {
    final base = (widget.spec ?? LeafPlayerDefaults.maybeOf(context)?.controls ?? LeafControlsSpec.adaptive())
        .resolve(desktop: leafIsDesktopPlatform());
    return (widget.isFullscreen ? (base.fullscreen ?? base) : base).gestures;
  }

  void _onTap() {
    final ctrl = widget.controller;
    switch (_gestures.tap) {
      case LeafTapAction.toggleControls:
        ctrl.execute(const LeafPlayerCommand.toggleControls());
      case LeafTapAction.togglePlay:
        ctrl.execute(const LeafPlayerCommand.togglePlay());
      case LeafTapAction.none:
        break;
    }
  }

  void _onDoubleTap(double width) {
    final ctrl = widget.controller;
    final g = _gestures;
    final at = _doubleTapAt;
    final seek = g.doubleTapSeek;
    if (at != null && seek != null && width > 0) {
      final side = width * g.doubleTapSideFraction;
      if (at.dx < side || at.dx > width - side) {
        final step = at.dx < side ? -seek : seek;
        ctrl.execute(LeafPlayerCommand.seekBy(step));
        ctrl.flashSeek(step);
        return;
      }
    }
    switch (g.doubleTapCenter) {
      case LeafDoubleTapCenter.togglePlay:
        ctrl.execute(const LeafPlayerCommand.togglePlay());
      case LeafDoubleTapCenter.toggleFullscreen:
        ctrl.execute(const LeafPlayerCommand.toggleFullscreen());
      case LeafDoubleTapCenter.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = _gestures;
    final doubleTap = g.doubleTapSeek != null || g.doubleTapCenter != LeafDoubleTapCenter.none;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _onTap,
        onDoubleTapDown: doubleTap ? (d) => _doubleTapAt = d.localPosition : null,
        onDoubleTap: doubleTap ? () => _onDoubleTap(box.maxWidth) : null,
        child: const SizedBox.expand(),
      ),
    );
  }
}
