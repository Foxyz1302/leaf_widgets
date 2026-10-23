import 'package:flutter/material.dart';

import 'leaf_video_adapter.dart';

/// Shared scrubber: buffered + position tracks, tap-to-seek, drag-to-scrub
/// (pauses during the drag, resumes after when it was playing).
///
/// With [knob] the position gets an always-visible handle (desktop
/// affordance). With [hoverPreview] a time bubble follows the cursor before
/// anything is clicked.
class LeafScrubber extends StatefulWidget {
  const LeafScrubber(this.adapter, {super.key, this.knob = false, this.hoverPreview = false});

  final VideoPlayerAdapter adapter;

  /// Always-visible position handle (desktop affordance).
  final bool knob;

  /// Time bubble following the cursor before anything is clicked (desktop).
  final bool hoverPreview;

  @override
  State<LeafScrubber> createState() => _LeafScrubberState();
}

class _LeafScrubberState extends State<LeafScrubber> {
  bool _wasPaused = false;
  bool _dragging = false;
  double? _hoverFraction;

  double _fraction(Duration value, double totalMs) {
    return totalMs > 0 ? (value.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;
  }

  void _seekFraction(double fraction) {
    final totalMs = widget.adapter.duration.inMilliseconds;
    widget.adapter.seek(Duration(milliseconds: (totalMs * fraction.clamp(0.0, 1.0)).round()));
  }

  double _dxToFraction(Offset localPosition, double width) {
    return width > 0 ? (localPosition.dx / width).clamp(0.0, 1.0) : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final trackHeight = (_dragging || _hoverFraction != null) ? 6.0 : 4.0;
    const radius = Radius.circular(3);

    Widget track = RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        height: 22 + trackHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final totalMs = widget.adapter.duration.inMilliseconds.toDouble();
            final hover = _hoverFraction;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 22,
                  width: width,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (widget.hoverPreview && hover != null && !_dragging)
                        Positioned(
                          left: (hover * width).clamp(24.0, width - 24.0) - 24.0,
                          bottom: 0,
                          child: Container(
                            width: 48,
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              _formatDuration(Duration(milliseconds: (totalMs * hover).round())),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: trackHeight,
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
                            width: (_fraction(widget.adapter.buffer, totalMs) * width).clamp(0.0, width),
                            color: Colors.white30,
                          ),
                        ),
                        StreamBuilder<Duration>(
                          stream: widget.adapter.positionStream,
                          builder: (context, _) {
                            final positionWidth = (_fraction(widget.adapter.position, totalMs) * width).clamp(0.0, width);
                            return Stack(
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  curve: Curves.fastEaseInToSlowEaseOut,
                                  width: positionWidth,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                if (widget.knob)
                                  Positioned(
                                    left: (positionWidth - 6).clamp(0.0, width - 12),
                                    top: 0,
                                    bottom: 0,
                                    child: const Center(
                                      child: SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                          child: SizedBox.expand(),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    track = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) => _seekFraction(_dxToFraction(details.localPosition, (context.findRenderObject() as RenderBox).size.width)),
      onHorizontalDragStart: (_) {
        _wasPaused = !widget.adapter.isPlaying;
        widget.adapter.pause();
        setState(() => _dragging = true);
      },
      onHorizontalDragUpdate: (details) =>
          _seekFraction(_dxToFraction(details.localPosition, (context.findRenderObject() as RenderBox).size.width)),
      onHorizontalDragEnd: (_) {
        setState(() => _dragging = false);
        if (!_wasPaused) widget.adapter.play();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: track,
      ),
    );

    if (!widget.hoverPreview) return track;
    return MouseRegion(
      onHover: (event) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        setState(() => _hoverFraction = _dxToFraction(event.localPosition, box.size.width));
      },
      onExit: (_) {
        if (mounted) setState(() => _hoverFraction = null);
      },
      child: track,
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}
