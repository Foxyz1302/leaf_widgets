import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../viewer/leaf_chrome.dart';
import '../viewer/leaf_viewer.dart';
import '../viewer/leaf_viewer_internal.dart';
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
  });

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
  /// it only for videos where fullscreen makes sense (landscape ones).
  final VoidCallback? onFullscreenToggle;

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

  @override
  State<LeafVideoPage> createState() => _LeafVideoPageState();
}

class _LeafVideoPageState extends State<LeafVideoPage> with WidgetsBindingObserver {
  VideoPlayerAdapter? _adapter;
  ValueListenable<bool>? _waitForIdle;
  bool _loaded = false;
  bool _failed = false;
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
      if (mounted) setState(() => _ready = true);
    }));
    _subs.add(adapter.errorStream.listen((error) {
      _releaseGate();
      if (!mounted) return;
      setState(() => _failed = true);
      adapter.pause();
    }));
  }

  void _onScrolling() {
    final scrolling = _waitForIdle;
    if (scrolling == null || scrolling.value) return;
    scrolling.removeListener(_onScrolling);
    _waitForIdle = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _adapter != null) return;
      setState(_createAdapter);
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
      setState(() => _failed = true);
      return;
    }
    if (!mounted) return;
    setState(() => _loaded = true);
    if (_active && !_coveredByRoute && !_backgrounded) adapter.play();
  }

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
        _started = true;
        _startLoad();
      }
    }

    // "Something is pushed on top of me" — sheets, pages, dialogs, anything.
    // Route.isCurrent is the only reliable signal: a route's secondaryAnimation
    // is not driven by bottom sheets (ModalBottomSheetRoute.canTransitionFrom
    // only accepts other sheets), so status listeners on it stay silent for
    // the most common cover in gallery apps. _ModalScopeStatus notifies on
    // isCurrent changes, so this re-runs from didChangeDependencies.
    final route = ModalRoute.of(context);
    _setCoveredByRoute(route != null && !route.isCurrent);
  }

  @override
  void didUpdateWidget(LeafVideoPage oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      // owns it from here.
      _chrome?.hold = false;
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
    if (!_active) return;
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
    if (adapter != null) {
      if (widget.deferDispose) {
        if (_loadIssued) adapter.pause();
        _PendingDisposals.instance.add(adapter);
      } else {
        adapter.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.aspectRatio;
    final adapter = _adapter;
    final thumbnail = widget.thumbnail;
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
