import 'package:flutter/widgets.dart';

/// One entry of a player menu (the ⚙ root, ⋯, a track list). App entries
/// come in through `LeafPlayerActions.menuEntries`.
@immutable
class LeafMenuEntry {
  const LeafMenuEntry({
    required this.id,
    required this.label,
    this.hint,
    this.icon,
    this.checked,
    this.enabled = true,
    this.submenu,
    this.onSelected,
    this.keepOpen = false,
  });

  final String id;
  final String label;

  /// Secondary text at the end (a start time, a key, the current value).
  final String? hint;
  final IconData? icon;

  /// Null: not a checkable entry.
  final bool? checked;
  final bool enabled;
  final List<LeafMenuEntry> Function()? submenu;
  final VoidCallback? onSelected;

  /// Selecting it leaves the menu open (toggles).
  final bool keepOpen;
}
