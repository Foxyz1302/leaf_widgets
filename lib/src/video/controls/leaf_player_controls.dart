import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../viewer/leaf_chrome.dart';
import '../../viewer/leaf_viewer_internal.dart';
import 'items/leaf_control.dart';
import 'items/play_items.dart';
import 'items/volume_items.dart';
import 'leaf_controls_layout.dart';
import 'leaf_controls_spec.dart';
import 'leaf_controls_theme.dart';
import 'leaf_controls_visibility.dart';
import 'leaf_player_command.dart';
import 'leaf_player_controller.dart';
import 'leaf_player_defaults.dart';
import 'media_math.dart';

/// The controls overlay for one player: lays a [LeafControlsSpec] out over
/// the picture, fades its regions with one 150 ms animation (a region is
/// removed once faded out), and owns the keys, the picture's gestures, the
/// wheel and the cursor.
///
/// Inside a [LeafViewer] it builds only on the settled page; on touch, in a
/// chrome-enabled viewer (or with [chrome]), it shows and hides with that
/// chrome.
///
/// Detached (outside the pager, see [LeafDetachedControls]): [picture] false
/// leaves the picture's gestures to the page ([LeafPlayerGestures]) and lets
/// pointers between the controls through.
class LeafPlayerControls extends StatefulWidget {
  const LeafPlayerControls({
    super.key,
    required this.controller,
    this.spec,
    this.isFullscreen = false,
    this.suppress,
    this.holdBy,
    this.picture = true,
    this.chrome,
  });

  final LeafPlayerController controller;

  /// Whether the controls own the picture's taps and double-taps.
  final bool picture;

  /// Shows and hides with this chrome on touch (else the enclosing viewer's).
  final LeafViewerChrome? chrome;

  /// Null: [LeafPlayerDefaults]'s, else [LeafControlsSpec.adaptive].
  final LeafControlsSpec? spec;

  /// Uses the spec's fullscreen variant and the fullscreen-only gestures.
  final bool isFullscreen;

  /// While true the controls are drawn hidden (something takes their place).
  final ValueListenable<bool>? suppress;

  /// Holds the controls up (the mouse on an app's floating widget).
  final LeafControlsHold? holdBy;

  @override
  State<LeafPlayerControls> createState() => _LeafPlayerControlsState();
}

class _LeafPlayerControlsState extends State<LeafPlayerControls>
    with SingleTickerProviderStateMixin
    implements LeafControlsHostHandle {
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 150), value: 1);
  final _focus = FocusNode(debugLabel: 'LeafPlayerControls', skipTraversal: true);
  final _wheel = LeafWheelSteps();
  LeafControlsVisibility? _visibility;
  LeafViewerScope? _viewer;
  int? _pageIndex;
  bool _active = true;
  bool _desktop = false;
  bool _shown = true;
  DateTime? _lastClick;
  Offset? _lastClickAt;
  Offset? _doubleTapAt;
  Widget? _built;

  LeafPlayerController get _ctrl => widget.controller;

  @override
  void initState() {
    super.initState();
    _ctrl.attachControls(this);
    _ctrl.playing.addListener(_onPlaying);
    widget.holdBy?.addListener(_onHoldBy);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _built = null;
    _desktop = leafIsDesktopPlatform();
    final viewer = LeafViewerScope.maybeOf(context);
    final index = LeafPageIndexScope.maybeOf(context);
    if (!identical(viewer, _viewer)) {
      _viewer?.currentIndex.removeListener(_onPage);
      _viewer = viewer;
      _viewer?.currentIndex.addListener(_onPage);
    }
    _pageIndex = index;
    _active = _isActive();
    _ensureVisibility();
  }

  @override
  void didUpdateWidget(LeafPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.detachControls(this);
      oldWidget.controller.playing.removeListener(_onPlaying);
      _ctrl.attachControls(this);
      _ctrl.playing.addListener(_onPlaying);
    }
    if (oldWidget.holdBy != widget.holdBy) {
      oldWidget.holdBy?.removeListener(_onHoldBy);
      _visibility?.hold(oldWidget.holdBy!, false);
      widget.holdBy?.addListener(_onHoldBy);
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.spec != widget.spec ||
        oldWidget.isFullscreen != widget.isFullscreen ||
        oldWidget.suppress != widget.suppress ||
        oldWidget.picture != widget.picture ||
        oldWidget.chrome != widget.chrome) {
      _built = null;
      _ensureVisibility(force: oldWidget.suppress != widget.suppress || oldWidget.spec != widget.spec);
    }
  }

  @override
  void dispose() {
    _ctrl.detachControls(this);
    _ctrl.playing.removeListener(_onPlaying);
    widget.holdBy?.removeListener(_onHoldBy);
    _viewer?.currentIndex.removeListener(_onPage);
    _dropVisibility();
    _fade.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _isActive() {
    final index = _pageIndex;
    final viewer = _viewer;
    return viewer == null || index == null || viewer.currentIndex.value == index;
  }

  void _onPage() {
    final active = _isActive();
    if (active == _active) return;
    setState(() {
      _active = active;
      _built = null;
    });
    final v = _visibility;
    if (v is LeafViewerChromeVisibility) active ? v.activate() : v.deactivate();
    if (active) _takeFocusIfViewerHadIt();
  }

  void _takeFocusIfViewerHadIt() {
    final viewerNode = _viewer?.focusNode;
    final primary = FocusManager.instance.primaryFocus;
    if (viewerNode == null || primary == null) return;
    if (primary == viewerNode || primary.ancestors.contains(viewerNode)) _focus.requestFocus();
  }

  LeafControlsSpec get _baseSpec =>
      (widget.spec ?? LeafPlayerDefaults.maybeOf(context)?.controls ?? LeafControlsSpec.adaptive()).resolve(desktop: _desktop);

  LeafControlsSpec get _spec {
    final base = _baseSpec;
    return widget.isFullscreen ? (base.fullscreen ?? base) : base;
  }

  void _ensureVisibility({bool force = false}) {
    final chrome = widget.chrome ?? _viewer?.chrome;
    final useChrome = chrome != null && !_desktop && !widget.isFullscreen;
    final current = _visibility;
    final fits = useChrome
        ? current is LeafViewerChromeVisibility && current.chrome == chrome
        : current is LeafAutoHideVisibility;
    if (fits && !force) return;
    _dropVisibility();
    final autoHide = _spec.autoHide;
    final next = useChrome
        ? LeafViewerChromeVisibility(chrome)
        : LeafAutoHideVisibility(delay: autoHide.delay, hideOnExit: autoHide.onPointerExit, suppress: widget.suppress);
    _visibility = next;
    next.visible.addListener(_onVisible);
    if (next is LeafViewerChromeVisibility && _active) next.activate();
    _onPlaying();
    _onHoldBy();
    _syncVisible(animate: false);
  }

  void _dropVisibility() {
    final v = _visibility;
    if (v == null) return;
    v.visible.removeListener(_onVisible);
    v.dispose();
    _visibility = null;
  }

  void _onPlaying() {
    final v = _visibility;
    if (v == null) return;
    final whilePaused = _spec.autoHide.whilePaused;
    v.hold(#leafPaused, !whilePaused && !_ctrl.playing.value);
  }

  void _onHoldBy() {
    final h = widget.holdBy;
    if (h != null) _visibility?.hold(h, h.held);
  }

  void _onVisible() => _syncVisible(animate: true);

  void _syncVisible({required bool animate}) {
    final shown = _visibility?.visible.value ?? true;
    _ctrl.controlsVisible.value = shown;
    if (shown == _shown && (animate || _fade.value == (shown ? 1 : 0))) return;
    _shown = shown;
    if (!animate) {
      _fade.value = shown ? 1 : 0;
    } else if (shown) {
      _fade.forward();
    } else {
      _fade.reverse();
    }
  }

  // ── Host commands ──────────────────────────────────────────────────────

  @override
  bool handleUiCommand(LeafPlayerCommand command) {
    final v = _visibility;
    switch (command) {
      case LeafToggleControls():
        v?.toggle();
        return v != null;
      case LeafShowControls():
        v?.wake();
        return v != null;
      case LeafNext() || LeafPrevious():
        final delta = command is LeafNext ? 1 : -1;
        final viewer = _viewer;
        final index = _pageIndex;
        if (viewer == null || index == null || viewer.goToPage == null) return false;
        final target = index + delta;
        if (target < 0 || target >= viewer.pageCount) return false;
        viewer.goToPage!(target);
        return true;
      default:
        return false;
    }
  }

  // ── Input ──────────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    var keymap = _spec.keymap;
    final viewer = _viewer;
    if (viewer != null) keymap = keymap.forViewer(viewer.axis);
    for (final command in keymap.commandsFor(event)) {
      if (!_ctrl.execute(command)) continue;
      if (_spec.autoHide.flashOnCommand && (command is LeafSeekBy || command is LeafStepChapter || command is LeafSeekToFraction)) {
        _visibility?.wake();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_desktop && !_focus.hasFocus) _focus.requestFocus();
  }

  void _onWheel(PointerSignalEvent e) {
    if (!_spec.gestures.wheelVolume || _ctrl.volume == null) return;
    _wheel.handle(e, (step) => _ctrl.execute(LeafPlayerCommand.stepVolume(step)));
  }

  void _onBackgroundDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.mouse || e.buttons != kPrimaryMouseButton) return;
    final g = _spec.gestures;
    switch (g.click) {
      case LeafClickAction.togglePlay:
        _ctrl.execute(const LeafPlayerCommand.togglePlay());
      case LeafClickAction.toggleControls:
        _visibility?.toggle();
      case LeafClickAction.none:
        break;
    }
    final now = DateTime.now();
    final last = _lastClick, at = _lastClickAt;
    if (g.doubleClick == LeafDoubleClickAction.toggleFullscreen &&
        last != null &&
        at != null &&
        now.difference(last) < const Duration(milliseconds: 400) &&
        (e.localPosition - at).distance < 24) {
      _lastClick = null;
      _ctrl.execute(const LeafPlayerCommand.toggleFullscreen());
      return;
    }
    _lastClick = now;
    _lastClickAt = e.localPosition;
  }

  void _onTap() {
    switch (_spec.gestures.tap) {
      case LeafTapAction.toggleControls:
        _visibility?.toggle();
      case LeafTapAction.togglePlay:
        _ctrl.execute(const LeafPlayerCommand.togglePlay());
      case LeafTapAction.none:
        break;
    }
  }

  void _onDoubleTap(double width) {
    final g = _spec.gestures;
    final at = _doubleTapAt;
    final seek = g.doubleTapSeek;
    if (at != null && seek != null && width > 0) {
      final side = width * g.doubleTapSideFraction;
      if (at.dx < side || at.dx > width - side) {
        final step = at.dx < side ? -seek : seek;
        _ctrl.execute(LeafPlayerCommand.seekBy(step));
        _ctrl.flashSeek(step);
        return;
      }
    }
    switch (g.doubleTapCenter) {
      case LeafDoubleTapCenter.togglePlay:
        _ctrl.execute(const LeafPlayerCommand.togglePlay());
      case LeafDoubleTapCenter.toggleFullscreen:
        _ctrl.execute(const LeafPlayerCommand.toggleFullscreen());
      case LeafDoubleTapCenter.none:
        break;
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────

  LeafControlsTheme _resolveTheme(LeafControlsSpec spec) {
    final defaults = LeafPlayerDefaults.maybeOf(context);
    final base =
        spec.theme ??
        defaults?.theme ??
        Theme.of(context).extension<LeafControlsTheme>() ??
        LeafControlsTheme.forLook(spec.look, Theme.of(context).colorScheme);
    return base.copyWith(scale: base.scale * _ctrl.prefs.scale);
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();
    return _built ??= ListenableBuilder(listenable: _ctrl.prefs, builder: (context, _) => _buildControls(context));
  }

  Widget _buildControls(BuildContext context) {
    final spec = _spec;
    final theme = _resolveTheme(spec);
    final viewer = _viewer;
    var keymap = spec.keymap;
    if (viewer != null) keymap = keymap.forViewer(viewer.axis);
    final data = LeafControlContext(
      controller: _ctrl,
      visibility: _visibility!,
      theme: theme,
      spec: spec,
      keymap: keymap,
      reveal: _fade,
      isFullscreen: widget.isFullscreen,
      isTouch: !_desktop,
      viewerCanPage: viewer?.goToPage != null && _pageIndex != null,
    );
    final layout = spec.layout;
    final hidden = _ctrl.prefs.hidden;
    List<LeafControl> items(LeafSlot slot) => [
      for (final c in layout[slot])
        if (!hidden.contains(c.id)) c,
    ];
    final showTop = !layout.topOnlyInFullscreen || widget.isFullscreen;
    final uosc = theme.clusterLook == LeafClusterLook.capsule || layout.capsules;

    Widget fading(Widget child) => _Fade(animation: _fade, shown: _visibility!.visible, child: child);
    Widget whenHidden(Widget child) => _WhenHidden(animation: _fade, child: child);

    final top = showTop
        ? _Bar(
            data: data.inSlot(LeafSlot.topStart),
            start: items(LeafSlot.topStart),
            center: items(LeafSlot.topCenter),
            end: items(LeafSlot.topEnd),
            capsules: false,
            fitted: false,
          )
        : null;
    final centerAll = items(LeafSlot.center);
    final overlayAll = items(LeafSlot.overlay);
    final belowAll = items(LeafSlot.bottomBelow);
    final above = items(LeafSlot.bottomAbove);
    final rowStart = items(LeafSlot.bottomStart), rowCenter = items(LeafSlot.bottomCenter), rowEnd = items(LeafSlot.bottomEnd);
    final hasRow = rowStart.isNotEmpty || rowCenter.isNotEmpty || rowEnd.isNotEmpty;
    final action = items(LeafSlot.action);
    final sideStart = items(LeafSlot.sideStart), sideEnd = items(LeafSlot.sideEnd);
    final whenHiddenItems = items(LeafSlot.whenHidden);
    final s = theme.scale;

    Widget built(LeafControl c, LeafSlot slot) => _Item(control: c, data: data.inSlot(slot));

    final bottomFading = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (action.isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, 8 * s),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [for (final c in action) built(c, LeafSlot.action)]),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: uosc
                ? null
                : LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [theme.barScrimBottom.withValues(alpha: 0), theme.barScrimBottom],
                  ),
          ),
          child: Padding(
            padding: EdgeInsets.only(top: uosc ? 0 : theme.barScrimExtent * s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in above)
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: built(c, LeafSlot.bottomAbove)),
                if (hasRow)
                  Padding(
                    padding: EdgeInsets.fromLTRB(uosc ? 12 : 8, 0, uosc ? 12 : 8, uosc ? 8 * s : 0),
                    child: _Bar(
                      data: data.inSlot(LeafSlot.bottomStart),
                      start: rowStart,
                      center: rowCenter,
                      end: rowEnd,
                      capsules: layout.capsules,
                      fitted: true,
                    ),
                  ),
                for (final c in belowAll)
                  if (!c.persistent) built(c, LeafSlot.bottomBelow),
              ],
            ),
          ),
        ),
      ],
    );

    final picture = LayoutBuilder(
      builder: (context, box) => _Background(
        touchTap: _onTap,
        doubleTap: _spec.gestures.doubleTapSeek != null || _spec.gestures.doubleTapCenter != LeafDoubleTapCenter.none
            ? () => _onDoubleTap(box.maxWidth)
            : null,
        onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
        onMouseDown: _onBackgroundDown,
      ),
    );

    final stack = Stack(
      fit: StackFit.expand,
      children: [
        if (widget.picture) picture,
        if (whenHiddenItems.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: whenHidden(
              Column(mainAxisSize: MainAxisSize.min, children: [for (final c in whenHiddenItems) built(c, LeafSlot.whenHidden)]),
            ),
          ),
        if (centerAll.any((c) => c.persistent))
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [for (final c in centerAll) if (c.persistent) built(c, LeafSlot.center)],
            ),
          ),
        for (final c in overlayAll)
          if (c.persistent) Positioned.fill(child: built(c, LeafSlot.overlay)),
        if (top != null && (items(LeafSlot.topStart).isNotEmpty || items(LeafSlot.topCenter).isNotEmpty || items(LeafSlot.topEnd).isNotEmpty))
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: fading(
              _BarHold(
                visibility: data.visibility,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [theme.barScrimTop, theme.barScrimTop.withValues(alpha: 0)],
                    ),
                  ),
                  child: Padding(padding: EdgeInsets.fromLTRB(8, 8, 8, 24 * s), child: SafeArea(bottom: false, child: top)),
                ),
              ),
            ),
          ),
        if (centerAll.any((c) => !c.persistent))
          Center(
            child: fading(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (final c in centerAll) if (!c.persistent) built(c, LeafSlot.center)],
              ),
            ),
          ),
        if (sideStart.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: fading(Column(mainAxisSize: MainAxisSize.min, children: [for (final c in sideStart) built(c, LeafSlot.sideStart)])),
          ),
        if (sideEnd.isNotEmpty)
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: fading(Column(mainAxisSize: MainAxisSize.min, children: [for (final c in sideEnd) built(c, LeafSlot.sideEnd)])),
          ),
        for (final c in overlayAll)
          if (!c.persistent) Positioned.fill(child: fading(built(c, LeafSlot.overlay))),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: _MeasureHeight(
              onHeight: (h) => _ctrl.overlayInsets.value = _ctrl.overlayInsets.value.copyWith(bottom: h),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  fading(_BarHold(visibility: data.visibility, child: bottomFading)),
                  for (final c in belowAll)
                    if (c.persistent) built(c, LeafSlot.bottomBelow),
                ],
              ),
            ),
          ),
        ),
      ],
    );

    Widget host = LeafPlayerScope(
      data: data,
      child: DefaultTextStyle.merge(
        style: theme.labelStyle,
        child: MediaQuery.withClampedTextScaling(maxScaleFactor: 1.3, child: stack),
      ),
    );
    if (data.viewerCanPage) {
      final v = viewer!;
      host = LeafViewerPaging(
        canStep: (delta) {
          final target = _pageIndex! + delta;
          return target >= 0 && target < v.pageCount;
        },
        step: (delta) => _ctrl.execute(delta > 0 ? const LeafPlayerCommand.next() : const LeafPlayerCommand.previous()),
        child: host,
      );
    }
    return Material(
      type: MaterialType.transparency,
      child: Focus(
        focusNode: _focus,
        autofocus: widget.isFullscreen,
        onKeyEvent: _onKey,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerSignal: _onWheel,
          child: _Cursor(
            visibility: data.visibility,
            hideCursor: spec.autoHide.hideCursor,
            child: host,
          ),
        ),
      ),
    );
  }
}

/// A region that fades with the controls and is removed once faded out.
/// Fully shown it adds no layer: Opacity (and FadeTransition) keep an
/// OpacityLayer even at 1.0, [_FadeBox] does not.
class _Fade extends StatelessWidget {
  const _Fade({required this.animation, required this.shown, required this.child});

  final AnimationController animation;

  /// The target: pointers are ignored as soon as the controls start hiding.
  final ValueListenable<bool> shown;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([animation, shown]),
    child: ExcludeFocus(child: child),
    builder: (context, child) {
      if (animation.value == 0) return const SizedBox.shrink();
      return IgnorePointer(ignoring: !shown.value, child: _FadeBox(opacity: animation.value, child: child));
    },
  );
}

class _FadeBox extends SingleChildRenderObjectWidget {
  const _FadeBox({required this.opacity, super.child});

  final double opacity;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFadeBox(Color.getAlphaFromOpacity(opacity));

  @override
  void updateRenderObject(BuildContext context, _RenderFadeBox renderObject) =>
      renderObject.alpha = Color.getAlphaFromOpacity(opacity);
}

class _RenderFadeBox extends RenderProxyBox {
  _RenderFadeBox(this._alpha);

  int _alpha;

  bool get _partial => _alpha > 0 && _alpha < 255;

  set alpha(int value) {
    if (value == _alpha) return;
    final was = _partial;
    _alpha = value;
    if (was != _partial) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _partial;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null || _alpha == 0) {
      layer = null;
      return;
    }
    if (_alpha == 255) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushOpacity(offset, _alpha, super.paint, oldLayer: layer as OpacityLayer?);
  }
}

/// Mounted only once the controls have faded out.
class _WhenHidden extends StatelessWidget {
  const _WhenHidden({required this.animation, required this.child});

  final AnimationController animation;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) => animation.value == 0 ? child! : const SizedBox.shrink(),
  );
}

/// The pointer on a bar holds the controls up.
class _BarHold extends StatefulWidget {
  const _BarHold({required this.visibility, required this.child});

  final LeafControlsVisibility visibility;
  final Widget child;

  @override
  State<_BarHold> createState() => _BarHoldState();
}

class _BarHoldState extends State<_BarHold> {
  @override
  void didUpdateWidget(_BarHold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visibility != widget.visibility) oldWidget.visibility.hold(this, false);
  }

  @override
  void dispose() {
    widget.visibility.hold(this, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => widget.visibility.hold(this, true),
    onExit: (_) => widget.visibility.hold(this, false),
    child: widget.child,
  );
}

/// Hides the cursor with the controls; real mouse movement wakes them.
class _Cursor extends StatelessWidget {
  const _Cursor({required this.visibility, required this.hideCursor, required this.child});

  final LeafControlsVisibility visibility;
  final bool hideCursor;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: visibility.visible,
    child: child,
    builder: (context, shown, child) => MouseRegion(
      cursor: !shown && hideCursor ? SystemMouseCursors.none : MouseCursor.defer,
      onHover: (e) {
        if (e.kind == PointerDeviceKind.mouse) visibility.pointerMoved(e.position);
      },
      onEnter: (e) {
        if (e.kind == PointerDeviceKind.mouse) visibility.pointerMoved(e.position);
      },
      onExit: (e) {
        if (e.kind == PointerDeviceKind.mouse) visibility.pointerExited();
      },
      child: child,
    ),
  );
}

/// The picture: touch taps through a GestureDetector, mouse clicks on
/// pointer-down (no double-tap delay). Only what no bar covers reaches it.
class _Background extends StatelessWidget {
  const _Background({
    required this.touchTap,
    required this.doubleTap,
    required this.onDoubleTapDown,
    required this.onMouseDown,
  });

  final VoidCallback touchTap;
  final VoidCallback? doubleTap;
  final GestureTapDownCallback onDoubleTapDown;
  final PointerDownEventListener onMouseDown;

  static const _touch = {PointerDeviceKind.touch, PointerDeviceKind.stylus, PointerDeviceKind.invertedStylus, PointerDeviceKind.unknown};

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: onMouseDown,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      supportedDevices: _touch,
      onTap: touchTap,
      onDoubleTapDown: doubleTap == null ? null : onDoubleTapDown,
      onDoubleTap: doubleTap,
      child: const SizedBox.expand(),
    ),
  );
}

/// One item: built once per host build, listening below itself.
class _Item extends StatelessWidget {
  const _Item({required this.control, required this.data});

  final LeafControl control;
  final LeafControlContext data;

  @override
  Widget build(BuildContext context) {
    final deps = control.availabilityDeps(data.controller).toList();
    if (deps.isEmpty) return control.isAvailable(data) ? control.build(context, data) : const SizedBox.shrink();
    return ListenableBuilder(
      listenable: Listenable.merge(deps),
      builder: (context, _) => control.isAvailable(data) ? control.build(context, data) : const SizedBox.shrink(),
    );
  }
}

/// A bar row: start, center and end clusters. [fitted]: fits its width
/// with [fitBar] (re-fitted when the width or an availability changes).
class _Bar extends StatelessWidget {
  const _Bar({
    required this.data,
    required this.start,
    required this.center,
    required this.end,
    required this.capsules,
    required this.fitted,
  });

  final LeafControlContext data;
  final List<LeafControl> start, center, end;
  final bool capsules;
  final bool fitted;

  @override
  Widget build(BuildContext context) {
    final all = [...start, ...center, ...end];
    final c = data.controller;
    final deps = <Listenable>[
      for (final item in all) ...item.availabilityDeps(c),
      if (fitted) ...[c.duration, c.timeFormat],
    ];
    Widget row(BoxConstraints box) {
      bool available(LeafControl item, LeafSlot slot) => item.isAvailable(data.inSlot(slot));
      final s = start.where((i) => available(i, LeafSlot.bottomStart)).toList();
      final m = center.where((i) => available(i, LeafSlot.bottomCenter)).toList();
      final e = end.where((i) => available(i, LeafSlot.bottomEnd)).toList();
      var fit = LeafBarFit(slider: LeafSliderRoom(beside: true, width: data.theme.volumeSliderWidth + 12));
      var shown = {for (final i in [...s, ...m, ...e]) i.id};
      if (fitted && box.maxWidth.isFinite) {
        final t = data.theme;
        final pad = capsules ? 2 * t.capsulePad + 2 : 0.0;
        List<LeafFitItem> fits(List<LeafControl> items, LeafSlot slot) => [
          for (var k = 0; k < items.length; k++)
            () {
              final f = items[k].fitItem(data.inSlot(slot));
              return k == 0 && pad > 0 ? LeafFitItem(f.id, f.width + pad, priority: f.priority, sliderWidth: f.sliderWidth, compactWidth: f.compactWidth == null ? null : f.compactWidth! + pad) : f;
            }(),
        ];
        final result = fitBar(
          start: fits(s, LeafSlot.bottomStart),
          center: fits(m, LeafSlot.bottomCenter),
          end: fits(e, LeafSlot.bottomEnd),
          width: box.maxWidth,
        );
        fit = LeafBarFit(slider: result.slider, compactTime: result.compactTime);
        shown = result.shown;
      }
      List<Widget> cluster(List<LeafControl> items, LeafSlot slot) => [
        for (final i in items)
          if (shown.contains(i.id)) _Item(control: i, data: data.inSlot(slot, fit: fit)),
      ];
      Widget wrap(List<Widget> children) =>
          capsules && children.isNotEmpty ? LeafCapsule(children: children) : Row(mainAxisSize: MainAxisSize.min, children: children);
      if (!fitted) {
        final flexible = s.any((i) => i.estimatedWidth(data.theme) == null);
        return Row(
          children: [
            ...cluster(s, LeafSlot.topStart),
            if (!flexible) const Spacer(),
            ...cluster(m, LeafSlot.topCenter),
            if (m.isNotEmpty) const Spacer(),
            ...cluster(e, LeafSlot.topEnd),
          ],
        );
      }
      return Row(
        children: [
          wrap(cluster(s, LeafSlot.bottomStart)),
          const Spacer(),
          if (m.isNotEmpty) ...[wrap(cluster(m, LeafSlot.bottomCenter)), const Spacer()],
          wrap(cluster(e, LeafSlot.bottomEnd)),
        ],
      );
    }

    // The LayoutBuilder is its items' build scope: the clock's tick relays it
    // out, so it gets tight constraints (the relayout stops there) and its
    // own repaint boundary (the repaint too).
    Widget body() => fitted
        ? RepaintBoundary(
            child: SizedBox(
              height: data.theme.scaledButton + (capsules ? 2 * data.theme.capsulePad : 0),
              child: LayoutBuilder(builder: (context, box) => row(box)),
            ),
          )
        : row(const BoxConstraints());
    if (deps.isEmpty) return body();
    return ListenableBuilder(listenable: Listenable.merge(deps), builder: (context, _) => body());
  }
}

/// Reports its child's height after layout (the bottom bars, for
/// [LeafPlayerController.overlayInsets]).
class _MeasureHeight extends SingleChildRenderObjectWidget {
  const _MeasureHeight({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureHeight(onHeight);

  @override
  void updateRenderObject(BuildContext context, _RenderMeasureHeight renderObject) => renderObject.onHeight = onHeight;
}

class _RenderMeasureHeight extends RenderProxyBox {
  _RenderMeasureHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onHeight(h);
    });
  }
}
