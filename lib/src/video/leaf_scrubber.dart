import 'package:flutter/material.dart';

import 'leaf_video_adapter.dart';
import 'scrubber_progress.dart';

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

class _LeafScrubberState extends State<LeafScrubber> with SingleTickerProviderStateMixin {
  late final ScrubberProgress _progress;
  bool _wasPaused = false;
  bool _dragging = false;
  double? _hoverFraction;

  @override
  void initState() {
    super.initState();
    _progress = ScrubberProgress(widget.adapter, this);
  }

  @override
  void didUpdateWidget(LeafScrubber oldWidget) {
    super.didUpdateWidget(oldWidget);
    _progress.adapter = widget.adapter;
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
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

    Widget track = RepaintBoundary(
      child: SizedBox(
        width: double.infinity,
        height: 22 + trackHeight,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final totalMs = widget.adapter.duration.inMilliseconds.toDouble();
            final hover = _hoverFraction;
            _progress.extent = width * MediaQuery.devicePixelRatioOf(context);
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
                  child: RepaintBoundary(
                    child: CustomPaint(
                      painter: ScrubberTrackPainter(_progress, playedColor: Theme.of(context).colorScheme.primary, knob: widget.knob),
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
        _progress.dragging = true;
        widget.adapter.pause();
        setState(() => _dragging = true);
      },
      onHorizontalDragUpdate: (details) =>
          _seekFraction(_dxToFraction(details.localPosition, (context.findRenderObject() as RenderBox).size.width)),
      onHorizontalDragEnd: (_) {
        _progress.dragging = false;
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
