import 'dart:async';

import 'package:flutter/material.dart';

/// One toast: [text], an optional bold [title] above it, and optional [leading] (icon, avatar, thumbnail) and
/// [trailing] widgets. With [onTap] the toast is clickable (and dismissed after the tap); without it clicks pass
/// through to whatever is underneath.
class LeafToast {
  final int id;
  final String text;
  final String? title;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  const LeafToast({
    required this.id,
    required this.text,
    this.title,
    this.leading,
    this.trailing,
    this.onTap,
  });
}

/// The list of toasts on screen. Make one per app (e.g. in the composition root), give it to a [LeafToastHost],
/// and call [show] from anywhere. Policy (what deserves a toast, sounds, system notifications) stays in the app.
class LeafToastController extends ChangeNotifier {
  final _toasts = <LeafToast>[];
  final _timers = <int, Timer>{};
  var _nextId = 0;

  /// Current toasts, oldest first.
  List<LeafToast> get toasts => List.unmodifiable(_toasts);

  /// Shows a toast and returns its id. It goes away after [duration]; null keeps it until [dismiss].
  int show(
    String text, {
    String? title,
    Widget? leading,
    Widget? trailing,
    Duration? duration = const Duration(seconds: 4),
    VoidCallback? onTap,
  }) {
    final id = _nextId++;
    _toasts.add(LeafToast(id: id, text: text, title: title, leading: leading, trailing: trailing, onTap: onTap));
    if (duration != null) _timers[id] = Timer(duration, () => dismiss(id));
    notifyListeners();
    return id;
  }

  void dismiss(int id) {
    _timers.remove(id)?.cancel();
    final before = _toasts.length;
    _toasts.removeWhere((t) => t.id == id);
    if (_toasts.length != before) notifyListeners();
  }

  void clear() {
    if (_toasts.isEmpty) return;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    _toasts.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

/// Puts [controller]'s toasts in a corner over [child]: each slides and fades in from the nearest side edge, stays
/// until the controller drops it, then slides back out while the gap it leaves closes. The newest sits nearest the
/// screen edge [alignment] points at.
///
/// Typically wraps the whole app: `MaterialApp(builder: (context, child) => LeafToastHost(controller: toasts, child: child!))`.
class LeafToastHost extends StatefulWidget {
  final LeafToastController controller;
  final Widget child;

  /// Corner (or edge) the column sits in.
  final Alignment alignment;

  /// Distance from the window edges.
  final EdgeInsets padding;

  /// At most this many toasts show at once (the newest).
  final int maxVisible;

  /// Gap between toasts.
  final double spacing;

  final Duration animationDuration;
  final Curve curve;

  /// Builds each toast's card; defaults to [LeafToastCard].
  final Widget Function(BuildContext context, LeafToast toast)? cardBuilder;

  const LeafToastHost({
    super.key,
    required this.controller,
    required this.child,
    this.alignment = Alignment.bottomLeft,
    this.padding = const EdgeInsets.all(16),
    this.maxVisible = 6,
    this.spacing = 8,
    this.animationDuration = const Duration(milliseconds: 320),
    this.curve = Curves.fastEaseInToSlowEaseOut,
    this.cardBuilder,
  });

  @override
  State<LeafToastHost> createState() => _LeafToastHostState();
}

class _Shown {
  final LeafToast toast;
  bool leaving = false;
  _Shown(this.toast);
}

class _LeafToastHostState extends State<LeafToastHost> {
  final _shown = <_Shown>[];
  final _timers = <Timer>[];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_sync);
    _sync();
  }

  @override
  void didUpdateWidget(LeafToastHost old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_sync);
      widget.controller.addListener(_sync);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_sync);
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  /// New toasts come in; dropped ones stay a moment as "leaving" so they can animate out.
  void _sync() {
    final live = {for (final t in widget.controller.toasts) t.id: t};
    final known = {for (final s in _shown) s.toast.id};
    final leaving = <_Shown>[];
    setState(() {
      for (final s in _shown) {
        if (!s.leaving && !live.containsKey(s.toast.id)) {
          s.leaving = true;
          leaving.add(s);
        }
      }
      for (final t in widget.controller.toasts) {
        if (!known.contains(t.id)) _shown.add(_Shown(t));
      }
    });
    if (leaving.isEmpty) return;
    _timers.add(Timer(widget.animationDuration, () {
      if (mounted) setState(() => _shown.removeWhere(leaving.contains));
    }));
  }

  Widget _toast(BuildContext context, _Shown s) {
    final toast = s.toast;
    Widget card = widget.cardBuilder?.call(context, toast) ?? LeafToastCard(toast: toast);
    final onTap = toast.onTap;
    if (onTap == null || s.leaving) {
      card = IgnorePointer(child: card);
    } else {
      card = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            onTap();
            widget.controller.dismiss(toast.id);
          },
          child: card,
        ),
      );
    }
    final fromLeft = widget.alignment.x <= 0;
    final dir = fromLeft ? -1.0 : 1.0;
    final duration = widget.animationDuration, curve = widget.curve;
    return TweenAnimationBuilder<double>(
      key: ValueKey(toast.id),
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: curve,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(24 * dir * (1 - v), 0), child: child),
      ),
      // Leaving: slide back out, fade, and collapse the gap.
      child: AnimatedAlign(
        duration: duration,
        curve: curve,
        alignment: fromLeft ? Alignment.topLeft : Alignment.topRight,
        heightFactor: s.leaving ? 0 : 1,
        child: AnimatedSlide(
          duration: duration,
          curve: curve,
          offset: s.leaving ? Offset(0.25 * dir, 0) : Offset.zero,
          child: AnimatedOpacity(
            duration: duration,
            curve: curve,
            opacity: s.leaving ? 0 : 1,
            child: Padding(padding: EdgeInsets.symmetric(vertical: widget.spacing / 2), child: card),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _shown.length <= widget.maxVisible ? _shown : _shown.sublist(_shown.length - widget.maxVisible);
    final top = widget.alignment.y < 0;
    final x = widget.alignment.x;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: SafeArea(
            child: Padding(
              padding: widget.padding,
              child: Align(
                alignment: widget.alignment,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  // Newest nearest the edge: last at the bottom, or first at the top.
                  verticalDirection: top ? VerticalDirection.up : VerticalDirection.down,
                  crossAxisAlignment: x < 0
                      ? CrossAxisAlignment.start
                      : x > 0
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.center,
                  children: [for (final s in visible) _toast(context, s)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The default toast look: a raised, slightly translucent rounded card with an optional leading widget, a bold
/// title, the text (up to three lines) and an optional trailing widget.
class LeafToastCard extends StatelessWidget {
  final LeafToast toast;
  final double maxWidth;
  const LeafToastCard({super.key, required this.toast, this.maxWidth = 380});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = toast.title;
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: EdgeInsets.fromLTRB(toast.leading == null ? 16 : 10, 10, 16, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: title == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
            children: [
              if (toast.leading case final leading?) ...[leading, const SizedBox(width: 12)],
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null) ...[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      toast.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: title == null ? scheme.onSurface : scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (toast.trailing case final trailing?) ...[const SizedBox(width: 12), trailing],
            ],
          ),
        ),
      ),
    );
  }
}

/// A round tinted icon, sized to sit in [LeafToast.leading].
class LeafToastIcon extends StatelessWidget {
  final IconData icon;
  final Color? color;
  const LeafToastIcon(this.icon, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return CircleAvatar(radius: 19, backgroundColor: c.withValues(alpha: 0.15), child: Icon(icon, size: 18, color: c));
  }
}
