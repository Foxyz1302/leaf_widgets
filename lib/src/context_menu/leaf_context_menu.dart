import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data types
// ─────────────────────────────────────────────────────────────────────────────

/// Base class for entries in a [LeafContextMenu].
sealed class ContextMenuEntry {
  const ContextMenuEntry();
}

/// A tappable menu action.
///
/// Layout: `[icon] label [shortcut]` with an optional subtitle below the label.
class ContextMenuAction extends ContextMenuEntry {
  /// Label text. Required.
  final String label;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional subtitle shown below the label.
  final String? subtitle;

  /// Optional shortcut hint shown right-aligned (e.g. `Ctrl+C`).
  final String? shortcut;

  /// Called when the action is tapped.
  final VoidCallback? onTap;

  /// Whether the action is interactive. Defaults to true.
  final bool enabled;

  /// When true the label and icon are rendered in the error colour.
  final bool destructive;

  const ContextMenuAction({
    required this.label,
    this.icon,
    this.subtitle,
    this.shortcut,
    this.onTap,
    this.enabled = true,
    this.destructive = false,
  });
}

/// A visual separator between groups of actions.
class ContextMenuDivider extends ContextMenuEntry {
  const ContextMenuDivider();
}

/// A menu action that runs an async [task] and reports its progress and
/// result in place, inside the menu item.
///
/// While the task runs the item's icon becomes a spinner and its label
/// switches to [runningLabel] (with a thin determinate progress bar when the
/// task reports progress via [task]'s callback); the rest of the menu is
/// locked (other items disabled, outside taps and Escape ignored) until the
/// task completes. On success the item shows a check + [doneLabel] for
/// [doneDuration], on failure an error icon + [errorLabel] for
/// [errorDuration]; then the menu dismisses itself.
class ContextMenuAsyncAction extends ContextMenuAction {
  /// The async task. [onProgress] reports 0..1 when the total is known;
  /// never calling it keeps the spinner indeterminate.
  final Future<void> Function(ValueChanged<double>? onProgress) task;

  /// Label shown while [task] runs.
  final String runningLabel;

  /// Label shown briefly on success.
  final String doneLabel;

  /// Label shown briefly on failure.
  final String errorLabel;

  /// How long the success state stays visible before the menu dismisses.
  final Duration doneDuration;

  /// How long the error state stays visible before the menu dismisses.
  final Duration errorDuration;

  /// Called with the task's error + stack trace when it throws. The error is
  /// always debugPrinted regardless.
  final void Function(Object error, StackTrace stackTrace)? onError;

  const ContextMenuAsyncAction({
    required super.label,
    required this.task,
    super.icon,
    super.subtitle,
    super.shortcut,
    super.enabled,
    super.destructive,
    this.runningLabel = 'Copying…',
    this.doneLabel = 'Copied',
    this.errorLabel = 'Failed',
    this.doneDuration = const Duration(milliseconds: 700),
    this.errorDuration = const Duration(milliseconds: 1400),
    this.onError,
  }) : super(onTap: null);
}

// ─────────────────────────────────────────────────────────────────────────────
// LeafContextMenu
// ─────────────────────────────────────────────────────────────────────────────

/// A Material-styled context menu that opens on right-click (desktop) or
/// long-press (touch).
///
/// Usage:
/// ```dart
/// LeafContextMenu(
///   entries: [
///     const ContextMenuAction(label: 'Copy', icon: Icons.copy, onTap: _onCopy),
///     const ContextMenuDivider(),
///     const ContextMenuAction(label: 'Delete', icon: Icons.delete, destructive: true, onTap: _onDelete),
///   ],
///   child: MyWidget(...),
/// )
/// ```
class LeafContextMenu extends StatefulWidget {
  /// The menu entries ([ContextMenuAction]s and [ContextMenuDivider]s).
  final List<ContextMenuEntry> entries;

  /// The widget that acts as the trigger area.
  final Widget child;

  /// Optional callback fired when the menu is dismissed (by action, outside
  /// tap, or Escape).
  final VoidCallback? onDismissed;

  const LeafContextMenu({required this.entries, required this.child, this.onDismissed, super.key});

  @override
  State<LeafContextMenu> createState() => _LeafContextMenuState();
}

class _LeafContextMenuState extends State<LeafContextMenu> {
  final _overlayController = OverlayPortalController();
  Offset? _globalPosition;

  // ── helpers ───────────────────────────────────────────────────────────────

  static bool get _isTouchDevice =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.fuchsia;

  void _showAtGlobal(Offset globalPosition) {
    _globalPosition = globalPosition;
    setState(() {});
    _overlayController.show();
  }

  void _hide() {
    _globalPosition = null;
    _overlayController.hide();
    widget.onDismissed?.call();
  }

  void _onPrimaryTap(PointerEvent e) {
    // Hide only when the menu is already visible and a primary click happens
    // on the trigger (acts as a toggle-off).
    if (_overlayController.isShowing) {
      _hide();
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    Widget child = widget.child;

    // Right-click (desktop) / secondary button.
    child = Listener(
      onPointerDown: (e) {
        if (e.buttons & kSecondaryButton != 0) {
          _showAtGlobal(e.position);
        } else if (e.buttons & kPrimaryButton != 0) {
          _onPrimaryTap(e);
        }
      },
      child: child,
    );

    // Long-press (touch).
    if (_isTouchDevice) {
      child = GestureDetector(
        onLongPressStart: (details) => _showAtGlobal(details.globalPosition),
        behavior: HitTestBehavior.translucent,
        child: child,
      );
    }

    return OverlayPortal(
      controller: _overlayController,
      overlayChildBuilder: (_) {
        if (_globalPosition == null) {
          return const SizedBox.shrink();
        }
        return _ContextMenuOverlay(globalPosition: _globalPosition!, entries: widget.entries, onDismiss: _hide);
      },
      child: child,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ContextMenuOverlay
// ─────────────────────────────────────────────────────────────────────────────

class _ContextMenuOverlay extends StatefulWidget {
  final Offset globalPosition;
  final List<ContextMenuEntry> entries;
  final VoidCallback onDismiss;

  const _ContextMenuOverlay({required this.globalPosition, required this.entries, required this.onDismiss});

  @override
  State<_ContextMenuOverlay> createState() => _ContextMenuOverlayState();
}

class _ContextMenuOverlayState extends State<_ContextMenuOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  /// Key attached to the menu Card so we can measure its actual size.
  final _menuKey = GlobalKey();

  /// Adjusted position after overflow detection.
  Offset? _adjustedPos;

  /// Whether the exit animation is running.
  bool _dismissing = false;

  /// Whether an async action is currently running. While true, outside taps
  /// and Escape are ignored and all other items are disabled.
  bool _busy = false;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _animCtrl = AnimationController(duration: const Duration(milliseconds: 100), vsync: this);

    _fade = CurvedAnimation(parent: _animCtrl, curve: Curves.linear);
    _scale = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);

    _animCtrl.addStatusListener(_onStatusChanged);
    // Start entrance.
    _animCtrl.forward();

    // Measure and adjust position after first frame.
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

  void _adjustPosition() {
    final menuBox = _menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (menuBox == null || !menuBox.hasSize) return;

    final menuSize = menuBox.size;
    final mediaQuery = MediaQuery.of(context);
    final screen = mediaQuery.size;
    final padding = mediaQuery.padding;

    var x = widget.globalPosition.dx;
    var y = widget.globalPosition.dy;

    // Horizontal flip.
    if (x + menuSize.width > screen.width) {
      x = screen.width - menuSize.width - padding.right;
    }
    // Vertical flip.
    if (y + menuSize.height > screen.height) {
      y = screen.height - menuSize.height - padding.bottom;
    }

    // Ensure minimum edge padding.
    x = x.clamp(padding.left, screen.width - menuSize.width - padding.right);
    y = y.clamp(padding.top, screen.height - menuSize.height - padding.bottom);

    if (_adjustedPos == null || _adjustedPos!.dx != x || _adjustedPos!.dy != y) {
      setState(() => _adjustedPos = Offset(x, y));
    }
  }

  void _setBusy(bool busy) {
    if (_busy != busy) setState(() => _busy = busy);
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
    final pos = _adjustedPos ?? widget.globalPosition;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Stack(
      children: [
        // Invisible barrier. Listener catches ALL pointer events (left,
        // right, middle click). Menu items (above in the stack) take
        // priority via InkWell gesture absorption. Ignored while an async
        // action is running so its feedback isn't cut short.
        Positioned.fill(
          child: Listener(
            onPointerDown: (_) {
              if (!_busy) _dismiss();
            },
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),
        // The menu itself.
        Positioned(
          left: pos.dx,
          top: pos.dy,
          child: Material(
            type: MaterialType.transparency,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  if (!_busy) _dismiss();
                },
              },
              child: FocusScope(
                child: FadeTransition(
                  opacity: Tween<double>(begin: 0, end: 1).animate(_fade),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.93, end: 1).animate(_scale),
                    child: Card(
                      key: _menuKey,
                      margin: EdgeInsets.zero,
                      elevation: 8,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      color: cs.surfaceContainerHighest,
                      surfaceTintColor: Colors.transparent,
                      clipBehavior: Clip.antiAlias,
                      child: IntrinsicWidth(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _buildEntries(theme),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildEntries(ThemeData theme) {
    final children = <Widget>[];
    for (final entry in widget.entries) {
      switch (entry) {
        case ContextMenuAction action:
          children.add(_ContextMenuActionWidget(
            action: action,
            busy: _busy,
            onBusyChanged: _setBusy,
            onDismiss: _dismiss,
          ));
        case ContextMenuDivider _:
          children.add(Divider(height: 1, thickness: 1, color: theme.dividerColor));
      }
    }
    return children;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ContextMenuActionWidget
// ─────────────────────────────────────────────────────────────────────────────

enum _AsyncActionState { idle, running, done, error }

class _ContextMenuActionWidget extends StatefulWidget {
  final ContextMenuAction action;

  /// Whether some async action is currently running (this one or another).
  /// While true, this item is disabled.
  final bool busy;

  final ValueChanged<bool> onBusyChanged;

  /// Dismisses the menu (with its exit animation).
  final VoidCallback onDismiss;

  const _ContextMenuActionWidget({
    required this.action,
    required this.busy,
    required this.onBusyChanged,
    required this.onDismiss,
  });

  @override
  State<_ContextMenuActionWidget> createState() => _ContextMenuActionWidgetState();
}

class _ContextMenuActionWidgetState extends State<_ContextMenuActionWidget> {
  _AsyncActionState _state = _AsyncActionState.idle;
  double? _progress;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  ContextMenuAsyncAction? get _async =>
      widget.action is ContextMenuAsyncAction ? widget.action as ContextMenuAsyncAction : null;

  Future<void> _runAsync() async {
    final async = _async!;
    if (_state == _AsyncActionState.running) return;
    _timer?.cancel();
    setState(() {
      _state = _AsyncActionState.running;
      _progress = null;
    });
    widget.onBusyChanged(true);
    try {
      await async.task((p) {
        if (mounted) setState(() => _progress = p.clamp(0.0, 1.0));
      });
      if (!mounted) return;
      setState(() => _state = _AsyncActionState.done);
      widget.onBusyChanged(false);
      _timer = Timer(async.doneDuration, widget.onDismiss);
    } catch (e, st) {
      debugPrint('ContextMenuAsyncAction "${async.label}" failed: $e\n$st');
      if (!mounted) return;
      setState(() => _state = _AsyncActionState.error);
      widget.onBusyChanged(false);
      _timer = Timer(async.errorDuration, widget.onDismiss);
      async.onError?.call(e, st);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = theme.textTheme;
    final action = widget.action;
    final async = _async;
    final running = async != null && _state == _AsyncActionState.running;
    final done = async != null && _state == _AsyncActionState.done;
    final failed = async != null && _state == _AsyncActionState.error;
    final interactive = action.enabled && !widget.busy;

    final foreground = failed
        ? cs.error
        : running
            ? cs.onSurface
            : done
                ? cs.onSurface
                : action.destructive
                    ? cs.error
                    : interactive
                        ? cs.onSurface
                        : cs.onSurface.withValues(alpha: 0.38);

    final label = running
        ? async.runningLabel
        : done
            ? async.doneLabel
            : failed
                ? async.errorLabel
                : action.label;

    final VoidCallback? onTap = async != null
        ? (_state == _AsyncActionState.running ? null : interactive ? _runAsync : null)
        : (interactive
            ? () {
                action.onTap?.call();
                widget.onDismiss();
              }
            : null);

    final leading = switch ((running, done, failed)) {
      (true, _, _) => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      (_, true, _) => const Icon(Icons.check, size: 18, color: Color(0xFF7CF29C)),
      (_, _, true) => Icon(Icons.error_outline, size: 18, color: cs.error),
      _ => action.icon == null ? null : Icon(action.icon, size: 18, color: foreground),
    };

    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading, const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: text.bodyLarge?.copyWith(color: foreground)),
                      if (action.subtitle != null)
                        Text(action.subtitle!, style: text.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.6))),
                    ],
                  ),
                ),
                if (action.shortcut != null) ...[
                  const SizedBox(width: 24),
                  Text(action.shortcut!, style: text.bodySmall?.copyWith(color: cs.onSurface.withValues(alpha: 0.5))),
                ],
              ],
            ),
          ),
          if (running && _progress != null)
            LinearProgressIndicator(
              value: _progress,
              minHeight: 2,
              color: cs.primary,
              backgroundColor: cs.surfaceContainerHighest,
            ),
        ],
      ),
    );
  }
}
