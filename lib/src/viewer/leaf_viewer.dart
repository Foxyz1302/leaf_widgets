import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart' show RenderViewportBase;
import 'package:flutter/services.dart';

import 'leaf_viewer_internal.dart';
import 'leaf_zoom_controller.dart';

/// Fullscreen pager with per-page zoom, boundary-aware edge release and a
/// viewer-level dismiss gesture.
///
/// Pages are built by [pageBuilder]. Wrap a page's content in [LeafZoomable]
/// to give it zoom/pan/double-tap; pages without one get paging + dismiss
/// only.
///
/// Gesture arbitration happens in the gesture arena (no raw pointer routing):
/// - [LeafZoomable]'s pan/zoom recognizer claims drags only when the child
///   can actually move (zoomed + a free axis); otherwise the PageView's drag
///   (horizontal) or the dismiss drag (perpendicular) wins — edge-release
/// - the mouse wheel zooms cursor-anchored on all platforms; a plain wheel
///   over a scrollable under the viewer scrolls that scrollable instead
/// - a quick tap outside the active image fires [onTapOutside]
/// - keyboard (when the viewer has focus): the arrows page prev/next,
///   Esc dismisses (via [onDismissed] or pop); disabled with
///   [enableKeyboard]
///
/// Desktop (Windows/Linux/macOS) differs from touch: no mouse drag paging, no
/// drag dismiss and no double-tap ([enableSwipeGestures] forces the touch
/// behaviour anywhere — the close button / wheel / keyboard replace them).
/// When [controlsBuilder] is null on desktop a default control set
/// (previous/next, close, page counter) is shown.
class LeafViewer extends StatefulWidget {
  const LeafViewer({
    super.key,
    required this.pageCount,
    required this.pageBuilder,
    this.pageController,
    this.initialPage = 0,
    this.scrollDirection = Axis.horizontal,
    this.onPageChanged,
    this.dismissEnabled = true,
    this.onDismissed,
    this.onTapOutside,
    this.backgroundBuilder,
    this.controlsBuilder,
    this.enableSwipeGestures,
    this.enableKeyboard = true,
  });

  final int pageCount;
  final Widget Function(BuildContext context, int index) pageBuilder;
  final PageController? pageController;
  final int initialPage;
  final Axis scrollDirection;
  final ValueChanged<int>? onPageChanged;
  final bool dismissEnabled;
  final VoidCallback? onDismissed;
  final VoidCallback? onTapOutside;

  /// Builds the layer behind the pager. Receives the dismiss progress in
  /// `[0, 1]` for backdrop fading.
  final Widget Function(BuildContext context, double progress)? backgroundBuilder;

  /// Builds the chrome overlay on top of the pager (media_kit `controlsBuilder`
  /// style). When null, a default control set is shown on desktop and nothing
  /// on touch platforms.
  final Widget Function(BuildContext context, LeafViewerControls controls)? controlsBuilder;

  /// Force the touch gesture set (swipe paging, drag dismiss, double-tap) on
  /// any platform. Null = platform default (off on desktop, on elsewhere).
  final bool? enableSwipeGestures;

  /// Whether the viewer grabs keyboard focus and handles the arrows for
  /// paging and Esc for dismissal (default true).
  final bool enableKeyboard;

  /// The zoom controller of the currently active page, if any.
  static LeafZoomController? controllerOf(BuildContext context) {
    return LeafViewerScope.maybeOf(context)?.registry.activeController;
  }

  @override
  State<LeafViewer> createState() => _LeafViewerState();
}

/// State passed to [LeafViewer.controlsBuilder].
class LeafViewerControls {
  const LeafViewerControls({required this.pageCount, required this.currentIndex, required this.goToPage});

  final int pageCount;
  final int currentIndex;

  /// Animates to the given page index (clamped by [pageCount]).
  final void Function(int index) goToPage;

  bool get canGoPrevious => currentIndex > 0;
  bool get canGoNext => currentIndex < pageCount - 1;
}

class _LeafViewerState extends State<LeafViewer> with TickerProviderStateMixin implements LeafViewerRegistry {
  late final PageController _pageController;
  late final AnimationController _dismissCtrl;
  final Map<int, LeafZoomController> _controllers = {};
  final ValueNotifier<int> _indexNotifier = ValueNotifier(0);
  final FocusNode _focusNode = FocusNode();

  int _currentIndex = 0;
  bool _dismissing = false;
  Size _viewerSize = Size.zero;

  LeafZoomController? get _activeController => _controllers[_currentIndex];

  bool get _swipeMode => widget.enableSwipeGestures ?? !leafIsDesktopPlatform();

  @override
  bool get swipeGesturesEnabled => _swipeMode;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final horizontal = widget.scrollDirection == Axis.horizontal;
    final prev = horizontal ? LogicalKeyboardKey.arrowLeft : LogicalKeyboardKey.arrowUp;
    final next = horizontal ? LogicalKeyboardKey.arrowRight : LogicalKeyboardKey.arrowDown;
    final key = event.logicalKey;
    if (key == prev) {
      _goToPage(_currentIndex - 1);
      return KeyEventResult.handled;
    }
    if (key == next) {
      _goToPage(_currentIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      if (widget.onDismissed != null) {
        widget.onDismissed!();
      } else {
        Navigator.maybePop(context);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.pageController?.initialPage ?? widget.initialPage;
    _indexNotifier.value = _currentIndex;
    _pageController = widget.pageController ?? PageController(initialPage: _currentIndex);
    _dismissCtrl = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _dismissCtrl.dispose();
    _indexNotifier.dispose();
    if (widget.pageController == null) _pageController.dispose();
    super.dispose();
  }

  // ── Controller registry ─────────────────────────────────────────────────

  @override
  void register(int index, LeafZoomController ctrl) {
    _controllers[index] = ctrl;
  }

  @override
  void unregister(int index, LeafZoomController ctrl) {
    if (_controllers[index] == ctrl) _controllers.remove(index);
  }

  @override
  LeafZoomController? get activeController => _controllers[_currentIndex];

  void _onPageIndexChanged(int index) {
    _currentIndex = index;
    _indexNotifier.value = index;
  }

  void _goToPage(int index) {
    if (index < 0 || index >= widget.pageCount) return;
    _pageController.animateToPage(index, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
  }

  // ── Dismiss ─────────────────────────────────────────────────────────────

  double get _dismissOffset => _dismissCtrl.value;
  double get _dismissExtent => widget.scrollDirection == Axis.horizontal ? _viewerSize.height : _viewerSize.width;
  double get _dismissProgress => _dismissExtent > 0 ? (_dismissOffset.abs() / (_dismissExtent * 0.5)).clamp(0.0, 1.0) : 0.0;

  Offset get _dismissOffsetVector => widget.scrollDirection == Axis.horizontal ? Offset(0, _dismissOffset) : Offset(_dismissOffset, 0);

  void _onDismissStart(DragStartDetails details) {
    _activeController?.cancelGesture();
  }

  void _onDismissUpdate(DragUpdateDetails details) {
    _dismissCtrl.value += widget.scrollDirection == Axis.horizontal ? details.delta.dy : details.delta.dx;
  }

  void _onDismissEnd(DragEndDetails details) {
    _endDismissDrag(details.primaryVelocity ?? 0);
  }

  void _endDismissDrag(double velocity) {
    if (_dismissing || !widget.dismissEnabled) return;
    final offset = _dismissCtrl.value;
    final extent = _dismissExtent;
    if (velocity.abs() > 800 || offset.abs() > extent * 0.25) {
      _dismissing = true;
      final dir = velocity.abs() > 50 ? velocity.sign : (offset.sign == 0 ? 1.0 : offset.sign);
      _dismissCtrl.animateTo(dir * extent * 1.5, duration: const Duration(milliseconds: 200), curve: Curves.easeIn).then((_) {
        if (!mounted) return;
        final onDismissed = widget.onDismissed;
        if (onDismissed != null) {
          onDismissed();
        } else {
          Navigator.maybePop(context);
        }
      });
    } else {
      _dismissCtrl.animateWith(SpringSimulation(const SpringDescription(mass: 1, stiffness: 600, damping: 50), offset, 0, velocity));
    }
  }

  void _onTapUp(TapUpDetails details) {
    final ctrl = _activeController;
    if (ctrl != null && !ctrl.zoomed && !ctrl.imageRect.contains(details.localPosition)) {
      widget.onTapOutside?.call();
    }
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final ctrl = _activeController;
    if (ctrl == null || _viewerSize == Size.zero) return;
    // Plain wheel over a scrollable under the viewer scrolls that scrollable
    // (it registers deeper, so the resolver picks it first); everywhere else,
    // and on Ctrl+wheel or once zoomed, the wheel zooms cursor-anchored.
    if (!HardwareKeyboard.instance.isControlPressed && !ctrl.zoomed) {
      final hit = HitTestResult();
      GestureBinding.instance.hitTestInView(hit, e.position, e.viewId);
      final overScrollable = hit.path.any((entry) =>
          entry.target is RenderViewportBase &&
          (entry.target as RenderViewportBase).axis == Axis.vertical);
      if (overScrollable) return;
    }
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final scroll = event as PointerScrollEvent;
      ctrl.wheelZoom(scroll.scrollDelta.dy, scroll.localPosition);
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final progress = _dismissProgress;
    final behavior = ScrollConfiguration.of(context);
    final horizontal = widget.scrollDirection == Axis.horizontal;
    final desktop = leafIsDesktopPlatform();
    final swipeMode = _swipeMode;
    return Focus(
      focusNode: _focusNode,
      autofocus: widget.enableKeyboard,
      onKeyEvent: widget.enableKeyboard ? _onKeyEvent : null,
      child: LeafViewerScope(
        registry: this,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _viewerSize = constraints.biggest;
            return Stack(
              fit: StackFit.expand,
              children: [
                if (widget.backgroundBuilder != null) widget.backgroundBuilder!(context, progress),
                Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: _onPointerSignal,
                  child: GestureDetector(
                    onVerticalDragStart: horizontal && widget.dismissEnabled && swipeMode ? _onDismissStart : null,
                    onVerticalDragUpdate: horizontal && widget.dismissEnabled && swipeMode ? _onDismissUpdate : null,
                    onVerticalDragEnd: horizontal && widget.dismissEnabled && swipeMode ? _onDismissEnd : null,
                    onHorizontalDragStart: !horizontal && widget.dismissEnabled && swipeMode ? _onDismissStart : null,
                    onHorizontalDragUpdate: !horizontal && widget.dismissEnabled && swipeMode ? _onDismissUpdate : null,
                    onHorizontalDragEnd: !horizontal && widget.dismissEnabled && swipeMode ? _onDismissEnd : null,
                    onTapUp: _onTapUp,
                    child: Transform.translate(
                      offset: _dismissOffsetVector,
                      child: Transform.scale(
                        scale: 1.0 - _dismissProgress * 0.15,
                        child: ScrollConfiguration(
                          behavior: behavior.copyWith(
                            dragDevices: swipeMode ? {...behavior.dragDevices, PointerDeviceKind.mouse} : behavior.dragDevices,
                          ),
                          child: PageView.builder(
                            controller: _pageController,
                            physics: const PageScrollPhysics(),
                            scrollDirection: widget.scrollDirection,
                            // Keep adjacent pages alive so their zoom state
                            // survives swipes (and preloads neighbors).
                            allowImplicitScrolling: true,
                            itemCount: widget.pageCount,
                            onPageChanged: (index) {
                              widget.onPageChanged?.call(index);
                              _onPageIndexChanged(index);
                            },
                            itemBuilder: (context, index) {
                              return LeafPageIndexScope(index: index, child: widget.pageBuilder(context, index));
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.controlsBuilder != null)
                  ValueListenableBuilder<int>(
                    valueListenable: _indexNotifier,
                    builder: (context, index, _) => widget.controlsBuilder!(
                      context,
                      LeafViewerControls(pageCount: widget.pageCount, currentIndex: index, goToPage: _goToPage),
                    ),
                  )
                else if (desktop)
                  ValueListenableBuilder<int>(
                    valueListenable: _indexNotifier,
                    builder: (context, index, _) =>
                        _LeafViewerDefaultControls(controls: LeafViewerControls(pageCount: widget.pageCount, currentIndex: index, goToPage: _goToPage)),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LeafViewerDefaultControls extends StatelessWidget {
  const _LeafViewerDefaultControls({required this.controls});

  final LeafViewerControls controls;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          left: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: _ControlButton(
              icon: Icons.chevron_left,
              onTap: controls.canGoPrevious ? () => controls.goToPage(controls.currentIndex - 1) : null,
            ),
          ),
        ),
        Positioned(
          right: 8,
          top: 0,
          bottom: 0,
          child: Center(
            child: _ControlButton(
              icon: Icons.chevron_right,
              onTap: controls.canGoNext ? () => controls.goToPage(controls.currentIndex + 1) : null,
            ),
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: _ControlButton(icon: Icons.close, onTap: () => Navigator.maybePop(context)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: IgnorePointer(
            child: Text(
              '${controls.currentIndex + 1} / ${controls.pageCount}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]),
            ),
          ),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      tooltip: null,
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.45),
        foregroundColor: Colors.white,
      ),
    );
  }
}
