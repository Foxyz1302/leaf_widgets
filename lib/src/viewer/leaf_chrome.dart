import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'leaf_viewer_internal.dart';

/// Reveal state for everything that hides/shows on tap inside a [LeafViewer]:
/// video controls, post action rails, the viewer's own paging chrome.
///
/// One state, one timer. The auto-hide timer runs whenever chrome is visible
/// and not held — [hold] only *suppresses* hiding (e.g. a paused video keeps
/// controls up); it never shows anything and never cancels hiding while
/// playing. Media pages drive [hold]; passive layers just listen.
class LeafViewerChrome {
  LeafViewerChrome({this.hideDelay = const Duration(seconds: 3), this.autoHide = true}) {
    // Chrome starts visible — arm the hide timer right away, or entry state
    // would never auto-hide until the first tap.
    _restartTimer();
  }

  /// How long chrome stays up before auto-hiding while not held.
  final Duration hideDelay;

  /// Whether chrome auto-hides at all (off on desktop — hiding there is
  /// tap-driven only).
  final bool autoHide;

  final ValueNotifier<bool> _visible = ValueNotifier<bool>(true);
  bool _hold = false;
  Timer? _timer;

  ValueListenable<bool> get visibleListenable => _visible;
  bool get visible => _visible.value;

  void toggle() => _visible.value ? hide() : show();

  void show() {
    _visible.value = true;
    _restartTimer();
  }

  void hide() {
    _visible.value = false;
    _cancelTimer();
  }

  /// While held, the auto-hide timer is suppressed. Releasing restarts it.
  set hold(bool value) {
    if (_hold == value) return;
    _hold = value;
    value ? _cancelTimer() : _restartTimer();
  }

  void _restartTimer() {
    _cancelTimer();
    if (!autoHide || _hold || !_visible.value) return;
    _timer = Timer(hideDelay, () => _visible.value = false);
  }

  void _cancelTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _cancelTimer();
    _visible.dispose();
  }
}

/// A passive chrome layer: fades with the viewer's reveal state and stops
/// receiving pointers while hidden. Taps outside of actual controls pass
/// through to the media underneath.
///
/// Outside a chrome-enabled [LeafViewer] the layer renders permanently
/// visible.
class LeafChrome extends StatelessWidget {
  const LeafChrome({super.key, required this.builder, this.duration = const Duration(milliseconds: 200)});

  final WidgetBuilder builder;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final chrome = LeafViewerScope.maybeOf(context)?.chrome;
    if (chrome == null) return builder(context);
    return ValueListenableBuilder<bool>(
      valueListenable: chrome.visibleListenable,
      builder: (context, visible, _) => IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(duration: duration, opacity: visible ? 1.0 : 0.0, child: builder(context)),
      ),
    );
  }
}
