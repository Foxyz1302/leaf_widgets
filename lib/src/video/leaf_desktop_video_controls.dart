import 'dart:async';

import 'package:flutter/material.dart';

import 'leaf_scrubber.dart';
import 'leaf_video_adapter.dart';

/// Desktop control set for [LeafVideoPage]: single click anywhere toggles
/// playback, double-click goes fullscreen, the bar hides itself after
/// [hideDelay] of inactivity (and while the cursor is off the video),
/// the scrubber shows a hover time bubble before anything is clicked, and
/// volume appears only when the adapter implements [HasVolume].
///
/// Visibility is owned here, not by any viewer chrome.
class LeafDesktopVideoControls extends StatefulWidget {
  const LeafDesktopVideoControls({super.key, required this.adapter, this.onFullscreenToggle, this.hideDelay = const Duration(seconds: 3)});

  final VideoPlayerAdapter adapter;

  /// Null hides the fullscreen button and makes double-click a no-op.
  final VoidCallback? onFullscreenToggle;

  /// Idle time while playing after which the bar (and cursor) hide.
  final Duration hideDelay;

  @override
  State<LeafDesktopVideoControls> createState() => _LeafDesktopVideoControlsState();
}

class _LeafDesktopVideoControlsState extends State<LeafDesktopVideoControls> {
  bool _visible = true;
  Timer? _hideTimer;
  StreamSubscription<bool>? _playingSub;
  double _mutedVolume = 100;

  @override
  void initState() {
    super.initState();
    _playingSub = widget.adapter.playingStream.listen(_onPlayingChanged);
    if (widget.adapter.isPlaying) _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _playingSub?.cancel();
    super.dispose();
  }

  void _onPlayingChanged(bool playing) {
    if (playing) {
      _scheduleHide();
    } else {
      _show();
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(widget.hideDelay, () {
      if (!mounted || !widget.adapter.isPlaying) return;
      setState(() => _visible = false);
    });
  }

  void _show() {
    _hideTimer?.cancel();
    if (mounted && !_visible) setState(() => _visible = true);
  }

  void _userActivity() {
    _show();
    if (widget.adapter.isPlaying) _scheduleHide();
  }

  void _hideForExit() {
    _hideTimer?.cancel();
    if (mounted && _visible && widget.adapter.isPlaying) setState(() => _visible = false);
  }

  void _toggleFullscreen() => widget.onFullscreenToggle?.call();

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: MouseRegion(
        cursor: _visible ? SystemMouseCursors.basic : SystemMouseCursors.none,
        onEnter: (_) => _userActivity(),
        onHover: (_) => _userActivity(),
        onExit: (_) => _hideForExit(),
        child: Stack(
          children: [
            Positioned.fill(
              // onTapDown, not onTap: with onDoubleTap set, onTap would wait
              // out the double-tap timeout on every click. A double-click
              // then toggles twice (net zero) plus fullscreen.
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) => widget.adapter.playOrPause(),
                onDoubleTap: _toggleFullscreen,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: IgnorePointer(
                  ignoring: !_visible,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _visible ? 1.0 : 0.0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: _buildBar(context),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: IgnorePointer(
                child: StreamBuilder<bool>(
                  stream: widget.adapter.playingStream,
                  initialData: widget.adapter.isPlaying,
                  builder: (context, snapshot) {
                    final playing = snapshot.data ?? true;
                    return AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.fastEaseInToSlowEaseOut,
                      opacity: playing ? 0 : 1,
                      child: Container(
                        decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(100)),
                        padding: const EdgeInsets.all(20),
                        child: const Icon(Icons.play_arrow, size: 40),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    final volume = widget.adapter is HasVolume ? widget.adapter as HasVolume : null;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Colors.black, Colors.transparent], begin: Alignment.bottomCenter, end: Alignment.topCenter),
      ),
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LeafScrubber(widget.adapter, knob: true, hoverPreview: true),
          Row(
            children: [
              StreamBuilder<bool>(
                stream: widget.adapter.playingStream,
                initialData: widget.adapter.isPlaying,
                builder: (context, snapshot) => IconButton(
                  icon: Icon((snapshot.data ?? false) ? Icons.pause : Icons.play_arrow),
                  onPressed: widget.adapter.playOrPause,
                ),
              ),
              if (volume != null) ...[
                StreamBuilder<double>(
                  stream: volume.volumeStream,
                  initialData: volume.volume,
                  builder: (context, snapshot) {
                    final level = snapshot.data ?? 0;
                    return IconButton(
                      icon: Icon(level <= 0 ? Icons.volume_off : (level < 50 ? Icons.volume_down : Icons.volume_up)),
                      onPressed: () {
                        if (volume.volume > 0) {
                          _mutedVolume = volume.volume;
                          volume.setVolume(0);
                        } else {
                          volume.setVolume(_mutedVolume);
                        }
                      },
                    );
                  },
                ),
                SizedBox(
                  width: 100,
                  child: StreamBuilder<double>(
                    stream: volume.volumeStream,
                    initialData: volume.volume,
                    builder: (context, snapshot) => Slider(
                      value: (snapshot.data ?? 0).clamp(0.0, 100.0),
                      min: 0,
                      max: 100,
                      onChanged: volume.setVolume,
                    ),
                  ),
                ),
              ],
              StreamBuilder<Duration>(
                stream: widget.adapter.positionStream,
                builder: (context, _) => Text(
                  '${_formatDuration(widget.adapter.position)} / ${_formatDuration(widget.adapter.duration)}',
                  style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
              const Spacer(),
              if (widget.onFullscreenToggle != null) IconButton(icon: const Icon(Icons.fullscreen), onPressed: widget.onFullscreenToggle),
            ],
          ),
        ],
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
