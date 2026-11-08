import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../viewer/leaf_chrome.dart';

/// When the controls are up. Holds keep them up (a seek drag, an open menu,
/// the pointer on a bar, a paused video); [wake] shows them and restarts
/// the hide countdown.
abstract class LeafControlsVisibility {
  ValueListenable<bool> get visible;

  /// Whether anything holds the controls up.
  bool get held;

  void wake();
  void hide();
  void toggle();

  /// [who] holds the controls up ([on]) or lets go. Set-based (each holder
  /// counts once); listeners hear it in a microtask, never during a build.
  void hold(Object who, bool on);

  /// A mouse hover at [position]; only real movement wakes.
  void pointerMoved(Offset position);

  /// The mouse left the player.
  void pointerExited();

  void dispose();
}

/// The kit's own auto-hide (a port of sync_relay's `ControlsFrameState`):
/// hides after [delay] without real mouse movement or a wake, at once when
/// the pointer leaves ([hideOnExit]), never while held. [suppress] draws
/// them hidden while something takes their place.
class LeafAutoHideVisibility implements LeafControlsVisibility {
  LeafAutoHideVisibility({
    this.delay = const Duration(seconds: 3),
    this.hideOnExit = true,
    this.autoHide = true,
    this._suppress,
  }) {
    _suppress?.addListener(_sync);
    _restart();
  }

  final Duration delay;
  final bool hideOnExit;

  /// Off: only [hide]/[toggle] hide them.
  final bool autoHide;
  final ValueListenable<bool>? _suppress;

  final _out = ValueNotifier(true);
  bool _shown = true;
  final _holders = <Object>{};
  bool _held = false;
  bool _queued = false;
  bool _disposed = false;
  Timer? _timer;
  Offset? _last;

  @override
  ValueListenable<bool> get visible => _out;

  @override
  bool get held => _held;

  bool get debugTimerActive => _timer?.isActive ?? false;

  void _sync() {
    if (_disposed) return;
    _out.value = _shown && !(_suppress?.value ?? false);
  }

  void _set(bool shown) {
    _shown = shown;
    _sync();
  }

  @override
  void wake() {
    if (_disposed) return;
    _set(true);
    _restart();
  }

  @override
  void hide() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = null;
    _set(false);
  }

  @override
  void toggle() => _shown ? hide() : wake();

  @override
  void hold(Object who, bool on) {
    if (on ? !_holders.add(who) : !_holders.remove(who)) return;
    if (_queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (_disposed) return;
      final now = _holders.isNotEmpty;
      if (now == _held) return;
      _held = now;
      if (now) {
        _timer?.cancel();
        _timer = null;
        _set(true);
      } else {
        _restart();
      }
    });
  }

  @override
  void pointerMoved(Offset position) {
    final last = _last;
    _last = position;
    if (last != null && (position - last).distance < 0.5) return;
    wake();
  }

  @override
  void pointerExited() {
    _last = null;
    if (!hideOnExit || _held) return;
    hide();
  }

  void _restart() {
    _timer?.cancel();
    _timer = null;
    if (!autoHide || _held || !_shown || _disposed) return;
    _timer = Timer(delay, () {
      _timer = null;
      if (!_held) _set(false);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _suppress?.removeListener(_sync);
    _out.dispose();
  }
}

/// The controls' visibility as a view onto a [LeafViewer]'s chrome (touch,
/// inside a chrome-enabled viewer): every chrome layer reveals together. The
/// active page's bridge is the only writer of [LeafViewerChrome.hold]
/// (`hold = any holder`); an inactive bridge never writes it.
class LeafViewerChromeVisibility implements LeafControlsVisibility {
  LeafViewerChromeVisibility(this.chrome);

  final LeafViewerChrome chrome;

  static final _owner = Expando<LeafViewerChromeVisibility>('LeafViewerChrome.hold owner');

  final _holders = <Object>{};
  bool _queued = false;
  bool _disposed = false;

  /// Whether this bridge writes the chrome's hold.
  bool get isOwner => _owner[chrome] == this;

  /// Takes over the chrome's hold (the page became the settled one).
  void activate() {
    if (_disposed) return;
    _owner[chrome] = this;
    _write();
  }

  /// Lets go of the chrome's hold (the page left the stage).
  void deactivate() {
    if (!isOwner) return;
    _owner[chrome] = null;
    chrome.hold = false;
  }

  @override
  ValueListenable<bool> get visible => chrome.visibleListenable;

  @override
  bool get held => _holders.isNotEmpty;

  @override
  void wake() => chrome.show();

  @override
  void hide() => chrome.hide();

  @override
  void toggle() => chrome.toggle();

  @override
  void hold(Object who, bool on) {
    if (on ? !_holders.add(who) : !_holders.remove(who)) return;
    if (_queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (!_disposed) _write();
    });
  }

  void _write() {
    if (!isOwner) return;
    final on = _holders.isNotEmpty;
    chrome.hold = on;
    if (on) chrome.show();
  }

  @override
  void pointerMoved(Offset position) {}

  @override
  void pointerExited() {}

  @override
  void dispose() {
    deactivate();
    _disposed = true;
  }
}

/// What keeps the controls up besides the mouse on them: the mouse on a
/// floating element over the picture ([LeafControlsHoldRegion]) or an open
/// app popover. Notifies in a microtask, never during a build or dispose.
class LeafControlsHold extends ChangeNotifier {
  final _by = <Object>{};
  bool _told = false;
  bool _queued = false;
  bool _disposed = false;

  bool get held => _told;

  void set(Object who, bool on) {
    if (on ? !_by.add(who) : !_by.remove(who)) return;
    if (_queued) return;
    _queued = true;
    scheduleMicrotask(() {
      _queued = false;
      if (_disposed) return;
      final now = _by.isNotEmpty;
      if (now == _told) return;
      _told = now;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The mouse on [child] holds [hold] while it is there.
class LeafControlsHoldRegion extends StatefulWidget {
  const LeafControlsHoldRegion({super.key, required this.hold, required this.child});

  final LeafControlsHold? hold;
  final Widget child;

  @override
  State<LeafControlsHoldRegion> createState() => _LeafControlsHoldRegionState();
}

class _LeafControlsHoldRegionState extends State<LeafControlsHoldRegion> {
  @override
  void didUpdateWidget(LeafControlsHoldRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hold != widget.hold) oldWidget.hold?.set(this, false);
  }

  @override
  void dispose() {
    widget.hold?.set(this, false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hold = widget.hold;
    if (hold == null) return widget.child;
    return MouseRegion(onEnter: (_) => hold.set(this, true), onExit: (_) => hold.set(this, false), child: widget.child);
  }
}
