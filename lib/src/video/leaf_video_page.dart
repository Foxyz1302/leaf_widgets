import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../viewer/leaf_chrome.dart';
import '../viewer/leaf_viewer.dart';
import '../viewer/leaf_viewer_internal.dart';
import 'controls/leaf_controls_spec.dart';
import 'controls/leaf_fullscreen.dart';
import 'controls/leaf_player_controller.dart';
import 'controls/leaf_player_defaults.dart';
import 'controls/leaf_player_view.dart';
import 'first_frame_gate.dart';
import 'leaf_desktop_video_controls.dart';
import 'leaf_video_adapter.dart';
import 'leaf_video_controls.dart';

/// A video page for a [LeafViewer]: owns the full player lifecycle so host
/// apps don't rewrite it per project.
///
/// Playback gating — the part every app gets wrong:
/// - built as a neighbour page → loads and buffers, stays paused (prebuffer);
///   inside a [LeafViewer] neighbours take turns, one first-frame decode at a
///   time, after the settled page
/// - becomes the settled page → loads at once if it was still waiting, plays
/// - stops being it, or the route gets covered, or the app backgrounds → pauses
/// - uncovers / returns → resumes only if it was playing before; re-activating
///   (swiping back) always resumes, TikTok-style
///
/// Chrome policy on a chrome-enabled viewer: while paused, chrome is held up
/// (and shown on the pause transition); while playing, the viewer's auto-hide
/// timer runs.
///
/// Controls: the legacy [LeafVideoControls] / [LeafDesktopVideoControls]
/// unless [controls] is set, or [controlsBuilder] is null and a
/// [LeafPlayerDefaults] above sets one; then the controls kit (a
/// [LeafPlayerView] with real fullscreen) takes over, and the kit owns the
/// chrome hold and the spinner.
class LeafVideoPage extends StatefulWidget {
  const LeafVideoPage({
    super.key,
    required this.createAdapter,
    required this.url,
    this.headers,
    this.aspectRatio,
    this.thumbnail,
    this.controlsBuilder,
    this.skipDuration = const Duration(seconds: 10),
    this.onFullscreenToggle,
    this.deferWhileScrolling = false,
    this.deferDispose = false,
    this.controls,
    this.actions,
    this.fullscreenDelegate,
    this.fullscreenMode,
    this.detachedControls = false,
    this.onController,
  }) : assert(controls == null || controlsBuilder == null, 'Pass either controls (the kit) or controlsBuilder, not both');

  /// Creates the (unloaded) adapter. Called once per page state; the page owns
  /// and disposes it. Route by codec here — the closure can capture the post.
  final VideoPlayerAdapter Function() createAdapter;

  final String url;
  final Map<String, String>? headers;

  /// Video aspect ratio; when set, the surface and thumbnail are centered at
  /// that ratio while gestures keep working across the whole page.
  final double? aspectRatio;

  /// Shown until [VideoPlayerAdapter.readyStream] fires.
  final Widget? thumbnail;

  /// Defaults to [LeafVideoControls] on mobile, [LeafDesktopVideoControls]
  /// on desktop.
  final Widget Function(BuildContext context, VideoPlayerAdapter adapter)? controlsBuilder;
  final Duration skipDuration;

  /// Passed through to the default controls; null hides the button. Provide
  /// it only for videos where fullscreen makes sense (landscape ones). With
  /// the kit and no [fullscreenDelegate], it becomes the in-place delegate
  /// (called on enter and on exit).
  final VoidCallback? onFullscreenToggle;

  /// The controls kit's spec; switches this page to the kit.
  final LeafControlsSpec? controls;

  /// The kit's app hooks (title, next/previous, play and seek overrides).
  final LeafPlayerActions? actions;

  /// The kit's OS fullscreen step.
  final LeafFullscreenDelegate? fullscreenDelegate;
  final LeafFullscreenMode? fullscreenMode;

  /// Inside a [LeafViewer], a page first built while the pager is scrolling
  /// creates and loads its player only after the pager has come to rest,
  /// instead of inside the swipe's frames; pages a multi-page jump only
  /// passes never create one. Until then the page shows its [thumbnail].
  /// Off by default.
  final bool deferWhileScrolling;

  /// When the page goes away (e.g. it drops out of the viewer's cache during
  /// or at the end of a swipe), pause the player at once but dispose it at
  /// the end of the first frame after which no other frame is scheduled (at
  /// most a second later), so the dispose never delays a frame that is
  /// already on its way. A page that comes back meanwhile and gets the same
  /// adapter from [createAdapter] keeps it; the app going to the background
  /// disposes whatever is still pending. Off by default.
  final bool deferDispose;

  /// With the kit: the page draws the surface and the picture's gestures only
  /// and hands its controller out through [onController], for controls drawn
  /// outside the pager ([LeafDetachedControls]) that stay put while pages
  /// slide or dismiss.
  final bool detachedControls;

  /// The kit's controller came (`attached`) or is going (`!attached`; the
  /// page disposes it and the adapter one frame later, so a layer holding it
  /// rebuilds without it first). Called after a frame, never during a build.
  final void Function(LeafPlayerController controller, bool attached)? onController;

  @override
  State<LeafVideoPage> createState() => _LeafVideoPageState();
}

class _LeafVideoPageState extends State<LeafVideoPage> with WidgetsBindingObserver {
  VideoPlayerAdapter? _adapter;
  ValueListenable<bool>? _waitForIdle;
  bool _loaded = false;
  bool _failed = false;
  Duration? _failedAt;
  bool _ready = false;
  bool _started = false;
  bool _loadIssued = false;
  bool _holdsGate = false;

  bool _active = true;
  bool _coveredByRoute = false;
  bool _backgrounded = false;
  bool _wasCovered = false;
  bool _wasPlayingBeforeCover = false;

  LeafViewerChrome? _chrome;
  LeafPlayerController? _kit;
  LeafControlsSpec? _kitSpec;
  bool _pageCovered = false;
  bool _fullscreenRoute = false;
  bool _fullscreenRouteCovered = false;
  FirstFrameGate? _gate;
  int? _pageIndex;
  ValueListenable<int>? _currentIndex;
  final _subs = <StreamSubscription<void>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!widget.deferWhileScrolling) _createAdapter();
  }

  void _createAdapter() {
    final adapter = widget.createAdapter();
    _PendingDisposals.instance.reclaim(adapter);
    _adapter = adapter;
    _subs.add(adapter.playingStream.listen(_onPlayingChanged));
    _subs.add(adapter.readyStream.listen((_) {
      _releaseGate();
      if (mounted) {
        setState(() {
          _ready = true;
          _failed = false;
        });
      }
    }));
    _subs.add(adapter.errorStream.listen((error) {
      _releaseGate();
      if (!mounted) return;
      _failedAt = adapter.position;
      setState(() => _failed = true);
    }));
    _subs.add(adapter.positionStream.listen(_onPosition));
  }

  void _onPosition(Duration position) {
    if (!_failed || !mounted) return;
    final failedAt = _failedAt;
    if (failedAt != null && position <= failedAt) return;
    setState(() => _failed = false);
  }

  void _onScrolling() {
    final scrolling = _waitForIdle;
    if (scrolling == null || scrolling.value) return;
    scrolling.removeListener(_onScrolling);
    _waitForIdle = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _adapter != null) return;
      setState(() {
        _createAdapter();
        _syncKit();
      });
      _started = true;
      _startLoad();
    });
  }

  void _startLoad() {
    final gate = _gate;
    if (gate == null || _active) {
      if (gate != null && gate.activeCount < gate.maxConcurrent) {
        gate.enter();
        _holdsGate = true;
      }
      _load();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _loadIssued) return;
      gate.enter().then((_) {
        if (!mounted || _loadIssued) {
          gate.exit();
          return;
        }
        _holdsGate = true;
        _load();
      });
    });
  }

  void _releaseGate() {
    if (!_holdsGate) return;
    _holdsGate = false;
    _gate?.exit();
  }

  Future<void> _load() async {
    final adapter = _adapter!;
    _loadIssued = true;
    try {
      final loading = adapter.load(url: widget.url, headers: widget.headers);
      if (!_active) adapter.pause();
      await loading;
    } catch (error) {
      _releaseGate();
      if (!mounted) return;
      _failedAt = adapter.position;
      setState(() => _failed = true);
      return;
    }
    if (!mounted) return;
    setState(() => _loaded = true);
    if (_active && !_coveredByRoute && !_backgrounded) adapter.play();
  }

  void _syncKit() {
    final defaults = LeafPlayerDefaults.maybeOf(context);
    final spec = widget.controls ?? (widget.controlsBuilder == null ? defaults?.controls : null);
    _kitSpec = spec;
    final adapter = _adapter;
    if (spec == null) {
      if (_kit != null && _kit!.pendingTeardown == null && !_kit!.fullscreen.value) {
        _kit!.dispose();
        _kit = null;
      }
      return;
    }
    if (adapter == null || _kit != null) return;
    final kit = _kit = LeafPlayerController(adapter, actions: widget.actions ?? const LeafPlayerActions(), prefs: defaults?.prefs)
      ..source = widget.url;
    final notify = widget.onController;
    if (notify != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(_kit, kit)) notify(kit, true);
      });
    }
  }

  void _onFullscreenRoute(bool active, bool covered) {
    _fullscreenRoute = active;
    _fullscreenRouteCovered = covered;
    if (!active && mounted) {
      final route = ModalRoute.of(context);
      _pageCovered = route != null && !route.isCurrent;
    }
    _applyCover();
  }

  void _applyCover() => _setCoveredByRoute(_fullscreenRoute ? _fullscreenRouteCovered : _pageCovered);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chrome = LeafViewer.chromeOf(context);
    _gate = LeafViewerScope.maybeOf(context)?.firstFrameGate;
    _pageIndex = LeafPageIndexScope.maybeOf(context);

    final currentIndex = LeafViewer.currentIndexListOf(context);
    if (!identical(currentIndex, _currentIndex)) {
      _currentIndex?.removeListener(_onIndexChanged);
      _currentIndex = currentIndex;
      _currentIndex?.addListener(_onIndexChanged);
      _evaluateActive();
    }
    if (!_started) {
      final scrolling = _adapter == null && _pageIndex != null ? Scrollable.maybeOf(context)?.position.isScrollingNotifier : null;
      if (scrolling != null && scrolling.value) {
        if (!identical(scrolling, _waitForIdle)) {
          _waitForIdle?.removeListener(_onScrolling);
          _waitForIdle = scrolling..addListener(_onScrolling);
        }
      } else {
        if (_adapter == null) _createAdapter();
        _syncKit();
        _started = true;
        _startLoad();
      }
    }
    _syncKit();

    // "Something is pushed on top of me" — sheets, pages, dialogs, anything.
    // Route.isCurrent is the only reliable signal: a route's secondaryAnimation
    // is not driven by bottom sheets (ModalBottomSheetRoute.canTransitionFrom
    // only accepts other sheets), so status listeners on it stay silent for
    // the most common cover in gallery apps. _ModalScopeStatus notifies on
    // isCurrent changes, so this re-runs from didChangeDependencies.
    final route = ModalRoute.of(context);
    _pageCovered = route != null && !route.isCurrent;
    _applyCover();
  }

  @override
  void didUpdateWidget(LeafVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncKit();
    final actions = widget.actions;
    if (actions != oldWidget.actions) _kit?.updateActions(actions ?? const LeafPlayerActions());
    _kit?.source = widget.url;
    if (oldWidget.url != widget.url || !mapEquals(oldWidget.headers, widget.headers)) {
      _loaded = false;
      _ready = false;
      _failed = false;
      setState(() {});
      if (_started) _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backgrounded = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    _updateCovered();
  }

  void _setCoveredByRoute(bool covered) {
    if (_coveredByRoute == covered) return;
    _coveredByRoute = covered;
    _updateCovered();
  }

  void _onIndexChanged() => _evaluateActive();

  void _evaluateActive() {
    final index = _pageIndex;
    final active = index == null || (_currentIndex?.value == index);
    if (active == _active) return;
    _active = active;
    if (!active) {
      // Release hold for the page leaving the stage; the active page's policy
      // owns it from here. With the kit, its viewer bridge does.
      if (_kit == null) _chrome?.hold = false;
      if (_loadIssued) _adapter!.pause();
    } else if (!_loadIssued) {
      if (_started) _load();
    } else if (_loaded && !_failed && !_coveredByRoute && !_backgrounded) {
      _adapter!.play();
    }
  }

  void _updateCovered() {
    final covered = _coveredByRoute || _backgrounded;
    if (covered) {
      if (_wasCovered) return;
      _wasPlayingBeforeCover = _loadIssued && _adapter!.isPlaying;
      if (_loadIssued) _adapter!.pause();
    } else {
      if (!_wasCovered) return;
      if (_wasPlayingBeforeCover && _active && _loaded && !_failed) _adapter!.play();
    }
    _wasCovered = covered;
  }

  void _onPlayingChanged(bool playing) {
    if (!_active || _kit != null) return;
    final chrome = _chrome;
    if (chrome == null) return;
    if (playing) {
      chrome.hold = false;
    } else {
      chrome.hold = true;
      chrome.show();
    }
  }

  Future<void> _retry() async {
    setState(() => _failed = false);
    await _load();
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _currentIndex?.removeListener(_onIndexChanged);
    _waitForIdle?.removeListener(_onScrolling);
    WidgetsBinding.instance.removeObserver(this);
    _releaseGate();
    final adapter = _adapter;
    final kit = _kit;
    final teardown = kit?.pendingTeardown;
    if (teardown != null) {
      // The fullscreen route still holds the surface: dispose once it is gone.
      if (_loadIssued && adapter != null) scheduleMicrotask(adapter.pause);
      final notify = widget.onController;
      if (notify != null) WidgetsBinding.instance.addPostFrameCallback((_) => notify(kit!, false));
      teardown.then((_) {
        kit!.dispose();
        adapter?.dispose();
      });
    } else if (kit != null && widget.onController != null) {
      // A layer outside the page holds the controller: it lets go first.
      final notify = widget.onController!;
      final deferDispose = widget.deferDispose;
      if (_loadIssued && adapter != null) adapter.pause();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notify(kit, false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          kit.dispose();
          if (adapter == null) return;
          deferDispose ? _PendingDisposals.instance.add(adapter) : adapter.dispose();
        });
        WidgetsBinding.instance.scheduleFrame();
      });
      WidgetsBinding.instance.scheduleFrame();
    } else {
      kit?.dispose();
      if (adapter != null) {
        if (widget.deferDispose) {
          if (_loadIssued) adapter.pause();
          _PendingDisposals.instance.add(adapter);
        } else {
          adapter.dispose();
        }
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.aspectRatio;
    final adapter = _adapter;
    final thumbnail = widget.thumbnail;
    final kit = _kit;
    if (kit != null && adapter != null) return _buildKit(kit, adapter, ratio, thumbnail);
    final Widget surface;
    final Widget controls;
    if (adapter == null) {
      surface = const SizedBox.shrink();
      controls = const SizedBox.shrink();
    } else {
      surface = ratio != null ? Center(child: AspectRatio(aspectRatio: ratio, child: adapter.surface)) : adapter.surface;
      controls =
          widget.controlsBuilder?.call(context, adapter) ??
          (leafIsDesktopPlatform()
              ? LeafDesktopVideoControls(adapter: adapter, onFullscreenToggle: widget.onFullscreenToggle)
              : LeafVideoControls(adapter: adapter, skipDuration: widget.skipDuration, onFullscreenToggle: widget.onFullscreenToggle));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        surface,
        if (!_ready && thumbnail != null)
          IgnorePointer(
            child: ratio != null ? Center(child: AspectRatio(aspectRatio: ratio, child: thumbnail)) : Center(child: thumbnail),
          ),
        if (!_loaded && !_failed && !_ready && thumbnail == null)
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        Positioned.fill(child: controls),
        if (_failed)
          ColoredBox(
            color: Colors.black54,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image, color: Colors.white38, size: 40),
                const SizedBox(height: 8),
                TextButton(onPressed: _retry, child: const Text('Tap to retry', style: TextStyle(color: Colors.white38))),
              ],
            ),
          ),
      ],
    );
  }
}

extension on _LeafVideoPageState {
  Widget _buildKit(LeafPlayerController kit, VideoPlayerAdapter adapter, double? ratio, Widget? thumbnail) {
    final toggle = widget.onFullscreenToggle;
    final legacyDelegate = widget.fullscreenDelegate == null && toggle != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        LeafPlayerView(
          controller: kit,
          surface: adapter.surface,
          spec: _kitSpec,
          aspectRatio: ratio,
          placeholder: thumbnail == null
              ? null
              : ColoredBox(
                  color: Colors.black,
                  child: ratio != null ? Center(child: AspectRatio(aspectRatio: ratio, child: thumbnail)) : Center(child: thumbnail),
                ),
          underlay: [
            if (!_ready && thumbnail != null)
              IgnorePointer(
                child: ratio != null ? Center(child: AspectRatio(aspectRatio: ratio, child: thumbnail)) : Center(child: thumbnail),
              ),
          ],
          fullscreenMode: legacyDelegate && (widget.fullscreenMode ?? LeafFullscreenMode.auto) == LeafFullscreenMode.auto
              ? LeafFullscreenMode.inPlace
              : widget.fullscreenMode,
          fullscreenDelegate: legacyDelegate
              ? LeafFullscreenDelegate.callbacks(onEnter: (_) => toggle(), onExit: (_) => toggle())
              : widget.fullscreenDelegate,
          onRetry: _retry,
          onFullscreenRoute: _onFullscreenRoute,
          detachedControls: widget.detachedControls,
        ),
        if (_failed)
          ColoredBox(
            color: Colors.black54,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.broken_image, color: Colors.white38, size: 40),
                const SizedBox(height: 8),
                TextButton(onPressed: _retry, child: const Text('Tap to retry', style: TextStyle(color: Colors.white38))),
              ],
            ),
          ),
      ],
    );
  }
}

class _PendingDisposals with WidgetsBindingObserver {
  _PendingDisposals._();

  static final instance = _PendingDisposals._();

  static const _maxWait = Duration(seconds: 1);

  final _adapters = <VideoPlayerAdapter>{};
  bool _waiting = false;
  Duration? _since;

  void add(VideoPlayerAdapter adapter) {
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.idle) {
      adapter.dispose();
      return;
    }
    if (_adapters.isEmpty) WidgetsBinding.instance.addObserver(this);
    _adapters.add(adapter);
    _waitForFrameEnd();
  }

  void reclaim(VideoPlayerAdapter adapter) {
    if (_adapters.remove(adapter) && _adapters.isEmpty) _reset();
  }

  void _waitForFrameEnd() {
    if (_waiting) return;
    _waiting = true;
    SchedulerBinding.instance.addPostFrameCallback(_onFrameEnd);
  }

  void _onFrameEnd(Duration timeStamp) {
    _waiting = false;
    if (_adapters.isEmpty) return;
    final since = _since ??= timeStamp;
    if (SchedulerBinding.instance.hasScheduledFrame && timeStamp - since < _maxWait) {
      _waitForFrameEnd();
      return;
    }
    _flush();
  }

  void _flush() {
    final adapters = _adapters.toList();
    _reset();
    for (final adapter in adapters) {
      adapter.dispose();
    }
  }

  void _reset() {
    _adapters.clear();
    _since = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden || state == AppLifecycleState.detached) _flush();
  }
}
