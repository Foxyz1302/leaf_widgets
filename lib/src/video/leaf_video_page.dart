import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../viewer/leaf_chrome.dart';
import '../viewer/leaf_viewer.dart';
import '../viewer/leaf_viewer_internal.dart';
import 'leaf_desktop_video_controls.dart';
import 'leaf_video_adapter.dart';
import 'leaf_video_controls.dart';

/// A video page for a [LeafViewer]: owns the full player lifecycle so host
/// apps don't rewrite it per project.
///
/// Playback gating — the part every app gets wrong:
/// - built as a neighbour page → loads and buffers, stays paused (prebuffer)
/// - becomes the settled page → plays
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

  @override
  State<LeafVideoPage> createState() => _LeafVideoPageState();
}

class _LeafVideoPageState extends State<LeafVideoPage> with WidgetsBindingObserver {
  late final VideoPlayerAdapter _adapter;
  bool _loaded = false;
  bool _failed = false;
  bool _ready = false;

  bool _active = true;
  bool _coveredByRoute = false;
  bool _backgrounded = false;
  bool _wasCovered = false;
  bool _wasPlayingBeforeCover = false;

  LeafViewerChrome? _chrome;
  int? _pageIndex;
  ValueListenable<int>? _currentIndex;
  final _subs = <StreamSubscription<void>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _adapter = widget.createAdapter();
    _subs.add(_adapter.playingStream.listen(_onPlayingChanged));
    _subs.add(_adapter.readyStream.listen((_) {
      if (mounted) setState(() => _ready = true);
    }));
    _subs.add(_adapter.errorStream.listen((error) {
      if (!mounted) return;
      setState(() => _failed = true);
      _adapter.pause();
    }));
    _load();
  }

  Future<void> _load() async {
    try {
      await _adapter.load(url: widget.url, headers: widget.headers);
    } catch (error) {
      if (!mounted) return;
      setState(() => _failed = true);
      return;
    }
    if (!mounted) return;
    setState(() => _loaded = true);
    if (_active && !_coveredByRoute && !_backgrounded) _adapter.play();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chrome = LeafViewer.chromeOf(context);
    _pageIndex = LeafPageIndexScope.maybeOf(context);

    final currentIndex = LeafViewer.currentIndexListOf(context);
    if (!identical(currentIndex, _currentIndex)) {
      _currentIndex?.removeListener(_onIndexChanged);
      _currentIndex = currentIndex;
      _currentIndex?.addListener(_onIndexChanged);
      _evaluateActive();
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
    if (oldWidget.url != widget.url || oldWidget.headers != widget.headers) {
      _loaded = false;
      _ready = false;
      _failed = false;
      setState(() {});
      _load();
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
      _adapter.pause();
    } else if (_loaded && !_failed && !_coveredByRoute && !_backgrounded) {
      _adapter.play();
    }
  }

  void _updateCovered() {
    final covered = _coveredByRoute || _backgrounded;
    if (covered) {
      if (_wasCovered) return;
      _wasPlayingBeforeCover = _adapter.isPlaying;
      _adapter.pause();
    } else {
      if (!_wasCovered) return;
      if (_wasPlayingBeforeCover && _active && _loaded && !_failed) _adapter.play();
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
    WidgetsBinding.instance.removeObserver(this);
    _adapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.aspectRatio;
    final surface = ratio != null ? Center(child: AspectRatio(aspectRatio: ratio, child: _adapter.surface)) : _adapter.surface;
    final thumbnail = widget.thumbnail;
    final controls =
        widget.controlsBuilder?.call(context, _adapter) ??
        (leafIsDesktopPlatform()
            ? LeafDesktopVideoControls(adapter: _adapter, onFullscreenToggle: widget.onFullscreenToggle)
            : LeafVideoControls(adapter: _adapter, skipDuration: widget.skipDuration, onFullscreenToggle: widget.onFullscreenToggle));

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
