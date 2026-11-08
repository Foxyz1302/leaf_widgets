import 'package:flutter/foundation.dart';

import 'items/leaf_control.dart';

/// Where an item goes.
enum LeafSlot {
  topStart,
  topCenter,
  topEnd,
  center,
  sideStart,
  sideEnd,

  /// Spans the bottom bar above its row (the line seek bar).
  bottomAbove,
  bottomStart,
  bottomCenter,
  bottomEnd,

  /// Spans the bottom bar below its row (the uosc band).
  bottomBelow,

  /// Above the bottom bar at its end (the skip pill).
  action,

  /// Free-floating over the player, mounted while the controls show and
  /// while hidden for persistent items (flashes, readouts).
  overlay,

  /// Mounted only while the controls are hidden (the progress line).
  whenHidden,

  /// Only in the ⚙ / ⋯ menus.
  menu,
}

/// Slots → catalog items. Immutable; edit with [withSlot], [without],
/// [insertAfter] and [insertBefore].
@immutable
class LeafControlsLayout {
  const LeafControlsLayout({
    this.slots = const {},
    this.topOnlyInFullscreen = false,
    this.capsules = false,
  });

  final Map<LeafSlot, List<LeafControl>> slots;

  /// The top bar only shows in fullscreen.
  final bool topOnlyInFullscreen;

  /// The bottom row's start and end clusters sit in glass capsules (uosc).
  final bool capsules;

  List<LeafControl> operator [](LeafSlot slot) => slots[slot] ?? const [];

  Iterable<LeafControl> get all => slots.values.expand((items) => items);

  LeafControlsLayout copyWith({Map<LeafSlot, List<LeafControl>>? slots, bool? topOnlyInFullscreen, bool? capsules}) =>
      LeafControlsLayout(
        slots: slots ?? this.slots,
        topOnlyInFullscreen: topOnlyInFullscreen ?? this.topOnlyInFullscreen,
        capsules: capsules ?? this.capsules,
      );

  LeafControlsLayout withSlot(LeafSlot slot, List<LeafControl> items) =>
      copyWith(slots: {...slots, slot: List.unmodifiable(items)});

  LeafControlsLayout without(Set<String> ids) => copyWith(
    slots: {
      for (final e in slots.entries) e.key: List.unmodifiable(e.value.where((c) => !ids.contains(c.id))),
    },
  );

  LeafControlsLayout _insert(String id, LeafControl item, int offset) => copyWith(
    slots: {
      for (final e in slots.entries)
        e.key: List.unmodifiable([
          for (final c in e.value) ...[
            if (c.id == id && offset == 0) item,
            c,
            if (c.id == id && offset == 1) item,
          ],
        ]),
    },
  );

  /// [item] after every item with [id].
  LeafControlsLayout insertAfter(String id, LeafControl item) => _insert(id, item, 1);

  LeafControlsLayout insertBefore(String id, LeafControl item) => _insert(id, item, 0);

  /// A layout from catalog ids (persisted user layouts); unknown ids are
  /// skipped. [extra] adds app items by id.
  static LeafControlsLayout fromIds(
    Map<LeafSlot, List<String>> ids, {
    Map<String, LeafControl> extra = const {},
    bool topOnlyInFullscreen = false,
    bool capsules = false,
  }) {
    final known = {...LeafControl.catalog, ...extra};
    return LeafControlsLayout(
      slots: {
        for (final e in ids.entries) e.key: List.unmodifiable([for (final id in e.value) ?known[id]]),
      },
      topOnlyInFullscreen: topOnlyInFullscreen,
      capsules: capsules,
    );
  }

  Map<LeafSlot, List<String>> toIds() => {
    for (final e in slots.entries)
      if (e.value.isNotEmpty) e.key: [for (final c in e.value) c.id],
  };
}
