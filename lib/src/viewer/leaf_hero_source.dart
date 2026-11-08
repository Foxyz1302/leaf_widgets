import 'package:flutter/widgets.dart';

/// The hero tag of the post a [LeafViewer] currently shows, shared with the
/// grid that opened it (Aves' approach to grid ↔ viewer heroes).
///
/// The grid hides exactly the tile whose tag is [value] (see [hide]), so the
/// tile under the viewer is a hole while the viewer is up and the return
/// flight lands into it. The opener sets [value] before pushing and calls
/// [attach] with the pushed route; the viewer updates it on page settle
/// ([LeafViewer.heroSource]); it clears when the route's animation reaches
/// dismissed, i.e. when the return flight has landed.
class LeafHeroSource extends ValueNotifier<Object?> {
  LeafHeroSource() : super(null);

  bool _returning = false;

  /// Whether a viewer opened from here is animating back (its return flight
  /// has not landed yet). Openers ignore taps meanwhile: a re-open would
  /// start a second flight from a tile that is still hidden.
  bool get returning => _returning;

  /// Tracks [route]'s animation: [returning] while it reverses, cleared on
  /// dismissed. Call right after pushing it.
  void attach(Route<Object?> route) {
    final animation = route is TransitionRoute<Object?> ? route.animation : null;
    if (animation == null) return;
    void onStatus(AnimationStatus status) {
      switch (status) {
        case AnimationStatus.reverse:
          _returning = true;
        case AnimationStatus.dismissed:
          _returning = false;
          value = null;
          animation.removeStatusListener(onStatus);
        case AnimationStatus.forward || AnimationStatus.completed:
          _returning = false;
      }
    }

    animation.addStatusListener(onStatus);
  }

  /// [child] hidden (state, size and hero kept) while [tag] is the current
  /// one. Wrap the whole tile, outside its [LeafSourceHero].
  Widget hide(Object tag, Widget child) => ValueListenableBuilder<Object?>(
    valueListenable: this,
    child: child,
    builder: (context, current, child) => Visibility.maintain(visible: current != tag, child: child!),
  );
}

/// A grid-side [Hero] that keeps its child in place during a flight (the
/// default placeholder is an empty box, which would blank and relayout the
/// tile). Pair with [LeafHeroSource.hide].
class LeafSourceHero extends StatelessWidget {
  const LeafSourceHero({super.key, required this.tag, required this.child});

  final Object tag;
  final Widget child;

  @override
  Widget build(BuildContext context) => Hero(tag: tag, placeholderBuilder: (_, _, child) => child, child: child);
}
