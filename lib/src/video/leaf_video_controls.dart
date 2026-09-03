import 'dart:async';

import 'package:flutter/material.dart';

import '../viewer/leaf_viewer.dart';
import '../viewer/leaf_viewer_internal.dart';
import 'leaf_video_adapter.dart';

enum _SkipDirection { backward, forward }

/// Default touch-first control set for [LeafVideoPage]: double-tap thirds to
/// seek (middle toggles playback), single tap toggles the viewer's chrome,
/// bottom bar with scrubber and a fullscreen slot.
///
/// Visibility is the viewer's chrome state, never owned here — this widget
/// only renders. Outside a chrome-enabled viewer it renders permanently
/// visible and single taps do nothing.
class LeafVideoControls extends StatefulWidget {
  const LeafVideoControls({super.key, required this.adapter, this.skipDuration = const Duration(seconds: 10), this.onFullscreenToggle});

  final VideoPlayerAdapter adapter;
  final Duration skipDuration;

  /// Null hides the fullscreen button.
  final VoidCallback? onFullscreenToggle;

  @override
  State<LeafVideoControls> createState() => _LeafVideoControlsState();
}

class _LeafVideoControlsState extends State<LeafVideoControls> {
  static const _feedbackDuration = Duration(milliseconds: 600);

  Offset? _doubleTapPos;
  Timer? _skipFeedbackTimer;
  _SkipDirection? _skipFeedback;
  Duration? _skipAmount;

  bool get _mobile => !leafIsDesktopPlatform();

  @override
  void dispose() {
    _skipFeedbackTimer?.cancel();
    super.dispose();
  }

  void _handleTap() {
    LeafViewer.chromeOf(context)?.toggle();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPos = details.localPosition;
  }

  void _handleDoubleTap() {
    if (_doubleTapPos == null) return;
    final adapter = widget.adapter;
    if (!_mobile) {
      adapter.playOrPause();
      return;
    }
    final box = context.findRenderObject() as RenderBox;
    final third = box.size.width / 3;
    final x = _doubleTapPos!.dx;
    final skip = widget.skipDuration;

    if (x < third) {
      final target = adapter.position - skip;
      adapter.seek(target < Duration.zero ? Duration.zero : target);
      _accumulate(_SkipDirection.backward, skip);
    } else if (x > third * 2) {
      final target = adapter.position + skip;
      adapter.seek(target > adapter.duration ? adapter.duration : target);
      _accumulate(_SkipDirection.forward, skip);
    } else {
      adapter.playOrPause();
    }
  }

  void _accumulate(_SkipDirection direction, Duration skip) {
    final amount = _skipFeedback == direction ? _skipAmount! + skip : skip;
    _skipFeedbackTimer?.cancel();
    setState(() {
      _skipFeedback = direction;
      _skipAmount = amount;
    });
    _skipFeedbackTimer = Timer(_feedbackDuration, () {
      if (!mounted) return;
      setState(() {
        _skipFeedback = null;
        _skipAmount = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final chrome = LeafViewer.chromeOf(context);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _handleTap,
              onDoubleTapDown: _handleDoubleTapDown,
              onDoubleTap: _handleDoubleTap,
            ),
          ),
          // Bottom bar — fades with the viewer's chrome state. Bottom-anchored
          // with its natural height: inside a StackFit.expand stack a bare
          // child stretches full-screen and eats every gesture meant for the
          // tap detector above it.
          if (chrome != null)
            ValueListenableBuilder<bool>(
              valueListenable: chrome.visibleListenable,
              builder: (context, visible, _) => IgnorePointer(
                ignoring: !visible,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: visible ? 1.0 : 0.0,
                  child: Align(alignment: Alignment.bottomCenter, child: SafeArea(child: _buildBar(context))),
                ),
              ),
            )
          else
            Align(alignment: Alignment.bottomCenter, child: SafeArea(child: _buildBar(context))),
          // Center play badge while paused.
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
          if (_skipFeedback != null && _skipAmount != null)
            IgnorePointer(
              child: Align(
                alignment: _skipFeedback == _SkipDirection.backward ? Alignment.centerLeft : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Container(
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(100)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(_skipFeedback == _SkipDirection.backward ? Icons.fast_rewind : Icons.fast_forward, size: 20),
                        const SizedBox(width: 4),
                        Text('${_skipFeedback == _SkipDirection.forward ? '+' : '-'}${_skipAmount!.inSeconds}s'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Colors.black, Colors.transparent], begin: Alignment.bottomCenter, end: Alignment.topCenter),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 50),
          Row(
            children: [
              Expanded(child: _Scrubber(widget.adapter)),
              StreamBuilder<Duration>(
                stream: widget.adapter.positionStream,
                builder: (context, _) => Text(
                  '${_formatDuration(widget.adapter.position)} / ${_formatDuration(widget.adapter.duration)}',
                  // Tabular digits: every-second width jitter would resize the
                  // scrubber next to it.
                  style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ),
              if (widget.onFullscreenToggle != null) IconButton(icon: const Icon(Icons.fullscreen), onPressed: widget.onFullscreenToggle),
            ],
          ),
        ],
      ),
    );
  }
}

class _Scrubber extends StatefulWidget {
  const _Scrubber(this.adapter);

  final VideoPlayerAdapter adapter;

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  bool _wasPaused = false;

  double _fraction(Duration value) {
    final duration = widget.adapter.duration;
    return duration.inMilliseconds > 0 ? (value.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0) : 0.0;
  }

  void _seekFraction(double fraction) {
    widget.adapter.seek(Duration(milliseconds: (widget.adapter.duration.inMilliseconds * fraction).round()));
  }

  @override
  Widget build(BuildContext context) {
    const height = 6.0;
    const radius = Radius.circular(3);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _seekFraction(details.localPosition.dx / (context.findRenderObject() as RenderBox).size.width),
      onHorizontalDragStart: (_) {
        _wasPaused = !widget.adapter.isPlaying;
        widget.adapter.pause();
      },
      onHorizontalDragUpdate: (details) => _seekFraction(details.localPosition.dx / (context.findRenderObject() as RenderBox).size.width),
      onHorizontalDragEnd: (_) {
        if (!_wasPaused) widget.adapter.play();
      },
      child: SizedBox(
        height: 20,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return SizedBox(
                height: height,
                width: width,
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(radius),
                  child: Stack(
                    children: [
                      Container(color: Colors.white12),
                      StreamBuilder<Duration>(
                        stream: widget.adapter.bufferStream,
                        builder: (context, _) => AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.fastEaseInToSlowEaseOut,
                          width: (_fraction(widget.adapter.buffer) * width).clamp(0.0, width),
                          color: Colors.white30,
                        ),
                      ),
                      StreamBuilder<Duration>(
                        stream: widget.adapter.positionStream,
                        builder: (context, _) => AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          curve: Curves.fastEaseInToSlowEaseOut,
                          width: (_fraction(widget.adapter.position) * width).clamp(0.0, width),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
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
