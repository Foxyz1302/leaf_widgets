import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../viewer/leaf_viewer_internal.dart';
import 'leaf_controls_spec.dart';
import 'leaf_fullscreen.dart';
import 'leaf_player_controller.dart';
import 'leaf_player_controls.dart';
import 'leaf_player_defaults.dart';

/// Hosts a player's surface and its controls, and performs fullscreen.
///
/// Route mode pushes a zero-transition route and moves the live surface
/// element there with a [GlobalKey] (one notifier flips which side builds
/// it, so the move happens within a single frame): the same State, texture
/// and platform view, `load()` never runs again. In-place mode only runs the
/// delegate and switches the controls to the fullscreen spec.
class LeafPlayerView extends StatefulWidget {
  const LeafPlayerView({
    super.key,
    required this.controller,
    required this.surface,
    this.spec,
    this.aspectRatio,
    this.placeholder,
    this.underlay = const [],
    this.fullscreenMode,
    this.fullscreenDelegate,
    this.onRetry,
    this.onFullscreenRoute,
  });

  final LeafPlayerController controller;

  /// The adapter's surface.
  final Widget surface;
  final LeafControlsSpec? spec;
  final double? aspectRatio;

  /// Shown inline while the surface is in the fullscreen route (black when
  /// null).
  final Widget? placeholder;

  /// App layers between the surface and the controls (a thumbnail, danmaku);
  /// built inline and in the fullscreen route.
  final List<Widget> underlay;

  /// Null: [LeafPlayerDefaults.fullscreenMode] ([LeafFullscreenMode.auto]).
  final LeafFullscreenMode? fullscreenMode;

  /// Null: [LeafPlayerDefaults.fullscreenDelegate], else
  /// [LeafFullscreenDelegate.platformDefault].
  final LeafFullscreenDelegate? fullscreenDelegate;

  /// Retry from the fullscreen route's error card.
  final VoidCallback? onRetry;

  /// The fullscreen route came ([active]) or went, or got covered by
  /// another route ([covered]): the page's pause-when-covered policy looks at
  /// that route instead of its own while it is up.
  final void Function(bool active, bool covered)? onFullscreenRoute;

  @override
  State<LeafPlayerView> createState() => _LeafPlayerViewState();
}

class _LeafPlayerViewState extends State<LeafPlayerView> implements LeafFullscreenHandle {
  final _surfaceKey = GlobalKey(debugLabel: 'LeafPlayerView surface');
  final _inRoute = ValueNotifier(false);
  ModalRoute<void>? _route;
  LeafFullscreenMode _mode = LeafFullscreenMode.route;
  LeafFullscreenDelegate _delegate = LeafFullscreenDelegate.none;
  ValueListenable<bool>? _external;
  bool _routeCovered = false;

  LeafPlayerController get _ctrl => widget.controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(LeafPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) oldWidget.controller.detachFullscreen(this);
    _resolve();
  }

  void _resolve() {
    final defaults = LeafPlayerDefaults.maybeOf(context);
    final mode = widget.fullscreenMode ?? defaults?.fullscreenMode ?? LeafFullscreenMode.auto;
    final inViewer = LeafViewerScope.maybeOf(context) != null;
    _mode = mode == LeafFullscreenMode.auto ? (inViewer ? LeafFullscreenMode.inPlace : LeafFullscreenMode.route) : mode;
    _delegate = widget.fullscreenDelegate ?? defaults?.fullscreenDelegate ?? LeafFullscreenDelegate.platformDefault();
    _ctrl.attachFullscreen(this);
  }

  @override
  bool get canFullscreen => switch (_mode) {
    LeafFullscreenMode.route => true,
    LeafFullscreenMode.inPlace => !_delegate.isNone && (leafIsDesktopPlatform() || (widget.aspectRatio ?? 16 / 9) > 1),
    LeafFullscreenMode.disabled || LeafFullscreenMode.auto => false,
  };

  LeafFullscreenRequest get _request =>
      LeafFullscreenRequest(mode: _mode, aspectRatio: widget.aspectRatio, videoSize: _ctrl.videoSize?.value);

  @override
  void enterFullscreen() {
    if (_ctrl.fullscreen.value || !canFullscreen) return;
    _ctrl.setFullscreen(true);
    if (_mode == LeafFullscreenMode.route) {
      final route = PageRouteBuilder<void>(
        opaque: true,
        maintainState: true,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        settings: const RouteSettings(name: 'leaf-fullscreen'),
        pageBuilder: (context, _, _) => _FullscreenBody(view: this),
      );
      _route = route;
      _routeCovered = false;
      unawaited(Navigator.of(context, rootNavigator: true).push(route));
      _inRoute.value = true;
      widget.onFullscreenRoute?.call(true, false);
    }
    _listenExternal();
    unawaited(_delegate.enter(_request));
  }

  @override
  void exitFullscreen() {
    if (!_ctrl.fullscreen.value) return;
    _ctrl.setFullscreen(false);
    _unlistenExternal();
    final route = _route;
    _route = null;
    if (route != null) {
      _inRoute.value = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
        if (mounted) widget.onFullscreenRoute?.call(false, false);
      });
    }
    unawaited(_delegate.exit(_request));
  }

  /// From the route's build: reported after it (the page pauses or resumes
  /// the player, whose listeners must not rebuild mid-build).
  void _onRouteCover(bool covered) {
    if (!mounted || _route == null || covered == _routeCovered) return;
    _routeCovered = covered;
    scheduleMicrotask(() {
      if (mounted && _route != null) widget.onFullscreenRoute?.call(true, covered);
    });
  }

  void _listenExternal() {
    _external = _delegate.externalState?..addListener(_onExternal);
  }

  void _unlistenExternal() {
    _external?.removeListener(_onExternal);
    _external = null;
  }

  void _onExternal() {
    if (_external?.value == false) exitFullscreen();
  }

  @override
  void dispose() {
    _unlistenExternal();
    final route = _route;
    _route = null;
    final inRoute = _inRoute;
    final ctrl = _ctrl;
    // Nothing here may notify: the tree is locked while it unmounts.
    if (route != null) {
      final done = Completer<void>();
      ctrl.pendingTeardown = done.future;
      unawaited(_delegate.exit(_request));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ctrl.setFullscreen(false);
          ctrl.detachFullscreen(this);
          inRoute.dispose();
          done.complete();
        });
        WidgetsBinding.instance.scheduleFrame();
      });
      WidgetsBinding.instance.scheduleFrame();
    } else {
      inRoute.dispose();
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.detachFullscreen(this));
    }
    super.dispose();
  }

  Widget _surfaceSlot() => _slot(_surfaceKey, widget.surface, widget.aspectRatio);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: _inRoute,
          builder: (context, inRoute, _) =>
              inRoute ? (widget.placeholder ?? const ColoredBox(color: Colors.black)) : _surfaceSlot(),
        ),
        ...widget.underlay,
        ValueListenableBuilder<bool>(
          valueListenable: _ctrl.fullscreen,
          builder: (context, full, _) => LeafPlayerControls(
            controller: _ctrl,
            spec: widget.spec,
            isFullscreen: full && _mode == LeafFullscreenMode.inPlace,
          ),
        ),
      ],
    );
  }
}

Widget _slot(GlobalKey key, Widget surface, double? ratio) {
  final s = KeyedSubtree(key: key, child: surface);
  return ratio == null ? s : Center(child: AspectRatio(aspectRatio: ratio, child: s));
}

/// The fullscreen route's page: black, the moved surface, the underlay and
/// the controls in their fullscreen variant. System back exits fullscreen.
class _FullscreenBody extends StatefulWidget {
  const _FullscreenBody({required this.view});

  final _LeafPlayerViewState view;

  @override
  State<_FullscreenBody> createState() => _FullscreenBodyState();
}

class _FullscreenBodyState extends State<_FullscreenBody> {
  late final LeafPlayerController _ctrl = widget.view._ctrl;
  late final LeafControlsSpec? _spec = widget.view.widget.spec;
  late final List<Widget> _underlay = widget.view.widget.underlay;
  late final VoidCallback? _onRetry = widget.view.widget.onRetry;
  late final GlobalKey _key = widget.view._surfaceKey;
  late final ValueNotifier<bool> _inRoute = widget.view._inRoute;
  late Widget _surface = widget.view.widget.surface;
  late final double? _ratio = widget.view.widget.aspectRatio;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    widget.view._onRouteCover(route != null && !route.isCurrent);
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && view.mounted) view.exitFullscreen();
      },
      child: ColoredBox(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: _inRoute,
              builder: (context, inRoute, _) {
                if (!inRoute) return const SizedBox.shrink();
                if (view.mounted) _surface = view.widget.surface;
                return _slot(_key, _surface, _ratio);
              },
            ),
            ..._underlay,
            LeafPlayerControls(controller: _ctrl, spec: _spec, isFullscreen: true),
            ValueListenableBuilder<Object?>(
              valueListenable: _ctrl.error,
              builder: (context, error, _) => error == null || _onRetry == null
                  ? const SizedBox.shrink()
                  : Center(
                      child: Card(
                        color: const Color(0xEB18181C),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.broken_image, color: Colors.white54, size: 32),
                              TextButton(onPressed: _onRetry, child: const Text('Retry')),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
