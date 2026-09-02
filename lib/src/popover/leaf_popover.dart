import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LeafPopoverController
// ─────────────────────────────────────────────────────────────────────────────

/// Controls the visibility of an [LeafPopover] programmatically.
///
/// Pass an instance to [LeafPopover.controller]. The controller is also passed to
/// the `popoverBuilder` so the popover content can dismiss itself.
class LeafPopoverController {
  bool _isShowing = false;

  /// Whether the popover is currently showing.
  bool get isShowing => _isShowing;

  /// Callbacks wired by the owning [LeafPopover] state.
  void Function()? _onShow;
  void Function()? _onHide;

  /// Show the popover.
  void show() {
    if (!_isShowing) {
      _isShowing = true;
      _onShow?.call();
    }
  }

  /// Hide the popover.
  void hide() {
    if (_isShowing) {
      _isShowing = false;
      _onHide?.call();
    }
  }

  /// Toggle visibility.
  void toggle() {
    if (_isShowing) {
      hide();
    } else {
      show();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LeafPopover
// ─────────────────────────────────────────────────────────────────────────────

/// A Material-styled popover that shows arbitrary content anchored to a child.
///
/// On tap of [child], the content built by [popoverBuilder] is displayed in an
/// anchored overlay. Tap outside or press Escape to dismiss.
///
/// The [popoverBuilder] receives the [LeafPopoverController] so the popover
/// content can dismiss itself (e.g. a close button inside the popover).
///
/// Pass an optional [controller] for external show/hide control. If omitted,
/// the popover manages visibility internally.
///
/// ```dart
/// LeafPopover(
///   popoverAnchor: Alignment.topCenter,
///   childAnchor: Alignment.bottomCenter,
///   spacing: 4,
///   popoverBuilder: (context, controller) => Card(
///     child: Padding(
///       padding: EdgeInsets.all(16),
///       child: Text('Popover content'),
///     ),
///   ),
///   child: TextButton(onPressed: null, child: Text('Open')),
/// )
/// ```
class LeafPopover extends StatefulWidget {
  /// Builder for the popover overlay content.
  ///
  /// Receives the [LeafPopoverController] so the popover content can call
  /// `controller.hide()` to dismiss itself.
  final Widget Function(BuildContext context, LeafPopoverController controller) popoverBuilder;

  /// The trigger widget. Tapping it toggles the popover.
  final Widget child;

  /// Anchor point on the popover itself. Defaults to [Alignment.topCenter].
  ///
  /// Together with [childAnchor] this controls where the popover appears
  /// relative to the child. For example with the default values the popover
  /// appears centered above the child.
  final AlignmentGeometry popoverAnchor;

  /// Anchor point on the child. Defaults to [Alignment.bottomCenter].
  ///
  /// Together with [popoverAnchor] this controls where the popover appears
  /// relative to the child. For example with the default values the popover
  /// appears centered above the child, positioned just below the child.
  final AlignmentGeometry childAnchor;

  /// Gap between the child edge and the popover edge. Defaults to 4.
  final double spacing;

  /// Optional external controller for programmatic show/hide.
  ///
  /// If omitted, the popover creates its own internal controller. Either way
  /// the controller is passed to [popoverBuilder] for self-dismiss.
  final LeafPopoverController? controller;

  /// Called when the popover is dismissed.
  final VoidCallback? onDismissed;

  const LeafPopover({
    required this.popoverBuilder,
    required this.child,
    this.popoverAnchor = Alignment.topCenter,
    this.childAnchor = Alignment.bottomCenter,
    this.spacing = 4,
    this.controller,
    this.onDismissed,
    super.key,
  });

  @override
  State<LeafPopover> createState() => _LeafPopoverState();
}

class _LeafPopoverState extends State<LeafPopover> {
  final _overlayController = OverlayPortalController();
  final _childKey = GlobalKey();
  final _fallbackController = LeafPopoverController();

  late final LeafPopoverController _controller;
  Offset? _childGlobalPosition;
  Size? _childSize;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? _fallbackController;
    _controller._onShow = _show;
    _controller._onHide = _hide;
  }

  @override
  void dispose() {
    // Unwire callbacks so the controller doesn't call into disposed state.
    if (!identical(_controller, _fallbackController)) {
      _controller._onShow = null;
      _controller._onHide = null;
    }
    _fallbackController._onShow = null;
    _fallbackController._onHide = null;
    super.dispose();
  }

  void _show() {
    if (_overlayController.isShowing) return;
    final renderBox = _childKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;

    _childGlobalPosition = renderBox.localToGlobal(Offset.zero);
    _childSize = renderBox.size;
    setState(() {});
    _overlayController.show();
  }

  void _hide() {
    _overlayController.hide();
    widget.onDismissed?.call();
  }

  void _onChildTap() {
    _controller.toggle();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (_) {
        if (_childGlobalPosition == null || _childSize == null) {
          return const SizedBox.shrink();
        }
        return _PopoverOverlay(
          childGlobalPosition: _childGlobalPosition!,
          childSize: _childSize!,
          popoverAnchor: widget.popoverAnchor,
          childAnchor: widget.childAnchor,
          spacing: widget.spacing,
          popoverBuilder: widget.popoverBuilder,
          controller: _controller,
          onDismiss: () => _controller.hide(),
        );
      },
      child: GestureDetector(
        onTap: _onChildTap,
        behavior: HitTestBehavior.translucent,
        child: KeyedSubtree(key: _childKey, child: widget.child),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PopoverOverlay
// ─────────────────────────────────────────────────────────────────────────────

class _PopoverOverlay extends StatefulWidget {
  final Offset childGlobalPosition;
  final Size childSize;
  final AlignmentGeometry popoverAnchor;
  final AlignmentGeometry childAnchor;
  final double spacing;
  final Widget Function(BuildContext context, LeafPopoverController controller) popoverBuilder;
  final LeafPopoverController controller;
  final VoidCallback onDismiss;

  const _PopoverOverlay({
    required this.childGlobalPosition,
    required this.childSize,
    required this.popoverAnchor,
    required this.childAnchor,
    required this.spacing,
    required this.popoverBuilder,
    required this.controller,
    required this.onDismiss,
  });

  @override
  State<_PopoverOverlay> createState() => _PopoverOverlayState();
}

class _PopoverOverlayState extends State<_PopoverOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  /// Key on the popover content so we can measure its actual size for
  /// positioning.
  final _menuKey = GlobalKey();

  /// Adjusted position after overflow detection.
  Offset? _adjustedPos;

  /// Whether the exit animation is running.
  bool _dismissing = false;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(duration: const Duration(milliseconds: 100), vsync: this);

    _fade = CurvedAnimation(parent: _animCtrl, curve: Curves.linear);
    _scale = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);

    _animCtrl.addStatusListener(_onStatusChanged);
    _animCtrl.forward();

    // Measure and adjust position after first layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => _adjustPosition());
  }

  @override
  void dispose() {
    _animCtrl.removeStatusListener(_onStatusChanged);
    _animCtrl.dispose();
    super.dispose();
  }

  void _onStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _dismissing) {
      widget.onDismiss();
    }
  }

  // ── positioning ───────────────────────────────────────────────────────────

  /// Compute the desired popover position given its size.
  ///
  /// Pass [Size.zero] for a rough estimate before measurement.
  Offset _computeDesiredPosition(Size popoverSize) {
    final dir = Directionality.of(context);
    final childAnchor = widget.childAnchor.resolve(dir);
    final popoverAnchor = widget.popoverAnchor.resolve(dir);

    // Offset from top-left of each rect to the anchor point.
    final childOffset = Offset(widget.childSize.width / 2 * (childAnchor.x + 1), widget.childSize.height / 2 * (childAnchor.y + 1));
    final popoverOffset = Offset(popoverSize.width / 2 * (popoverAnchor.x + 1), popoverSize.height / 2 * (popoverAnchor.y + 1));

    // Base position: the childAnchor point on the child aligns with the
    // popoverAnchor point on the popover.
    final baseX = widget.childGlobalPosition.dx + childOffset.dx - popoverOffset.dx;
    final baseY = widget.childGlobalPosition.dy + childOffset.dy - popoverOffset.dy;

    // Spacing pushes the popover further away from the child, in the direction
    // normal to the anchored edge.
    final spacingDirX = (childAnchor.x - popoverAnchor.x).sign;
    final spacingDirY = (childAnchor.y - popoverAnchor.y).sign;

    return Offset(baseX + spacingDirX * widget.spacing, baseY + spacingDirY * widget.spacing);
  }

  void _adjustPosition() {
    final menuBox = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (menuBox == null || !menuBox.hasSize) return;

    final menuSize = menuBox.size;
    final mediaQuery = MediaQuery.of(context);
    final screen = mediaQuery.size;
    final padding = mediaQuery.padding;

    var pos = _computeDesiredPosition(menuSize);

    // Horizontal overflow → slide left.
    if (pos.dx + menuSize.width > screen.width - padding.right) {
      pos = Offset(screen.width - menuSize.width - padding.right, pos.dy);
    }
    // Vertical overflow → slide up.
    if (pos.dy + menuSize.height > screen.height - padding.bottom) {
      pos = Offset(pos.dx, screen.height - menuSize.height - padding.bottom);
    }

    // Edge clamping (positive padding only).
    pos = Offset(
      pos.dx.clamp(padding.left, screen.width - menuSize.width - padding.right),
      pos.dy.clamp(padding.top, screen.height - menuSize.height - padding.bottom),
    );

    if (_adjustedPos == null || _adjustedPos! != pos) {
      setState(() => _adjustedPos = pos);
    }
  }

  // ── dismiss ───────────────────────────────────────────────────────────────

  void _dismiss() {
    if (_dismissing) return;
    _dismissing = true;
    _animCtrl.reverse();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Use a rough estimate (popover at Size.zero) for the initial frame before
    // _adjustPosition runs. The entrance animation starts at opacity 0.0 /
    // scale 0.93, so the flash is imperceptible.
    final pos = _adjustedPos ?? _computeDesiredPosition(Size.zero);

    return Stack(
      children: [
        // Invisible barrier catching all pointer events. Menu items (above in
        // the stack) take priority via their own gesture absorption.
        Positioned.fill(
          child: Listener(
            onPointerDown: (_) => _dismiss(),
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),
        // The popover content itself.
        Positioned(
          left: pos.dx,
          top: pos.dy,
          child: Material(
            type: MaterialType.transparency,
            child: CallbackShortcuts(
              bindings: {const SingleActivator(LogicalKeyboardKey.escape): _dismiss},
              child: FocusScope(
                child: FadeTransition(
                  opacity: Tween<double>(begin: 0, end: 1).animate(_fade),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.93, end: 1).animate(_scale),
                    child: KeyedSubtree(key: _menuKey, child: widget.popoverBuilder(context, widget.controller)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
