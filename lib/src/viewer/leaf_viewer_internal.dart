import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'leaf_zoom_controller.dart';

/// Whether the current platform is a desktop OS. Desktop viewers swap swipe
/// gestures for controls: no mouse paging, no drag dismiss, no double-tap.
bool leafIsDesktopPlatform() {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

/// Internal: registry contract between [LeafViewer] and [LeafZoomable].
/// Not exported from the package barrel.
abstract class LeafViewerRegistry {
  void register(int index, LeafZoomController ctrl);
  void unregister(int index, LeafZoomController ctrl);
  LeafZoomController? get activeController;

  /// Whether the touch gesture set (double-tap etc.) is active.
  bool get swipeGesturesEnabled;
}

/// Internal: registry scope shared between [LeafViewer] and [LeafZoomable].
class LeafViewerScope extends InheritedWidget {
  const LeafViewerScope({required this.registry, super.key, required super.child});

  final LeafViewerRegistry registry;

  static LeafViewerScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LeafViewerScope>();
  }

  @override
  bool updateShouldNotify(LeafViewerScope oldWidget) => false;
}

/// Internal: provides a page's index to [LeafZoomable] so it can register its
/// controller with the viewer.
class LeafPageIndexScope extends InheritedWidget {
  const LeafPageIndexScope({required this.index, super.key, required super.child});

  final int index;

  static int? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<LeafPageIndexScope>()?.index;
  }

  @override
  bool updateShouldNotify(LeafPageIndexScope oldWidget) => oldWidget.index != index;
}
