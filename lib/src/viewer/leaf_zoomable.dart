import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'leaf_pan_zoom_recognizer.dart';
import 'leaf_viewer_internal.dart';
import 'leaf_zoom_controller.dart';

/// Opt-in per-page zoom wrapper for [LeafViewer].
///
/// Wrap a page's content to give it zoom/pan/double-tap behaviour. Pages
/// without a [LeafZoomable] only get paging and dismiss.
///
/// [childSize] is the contained (fit-to-screen) render size of the child.
/// Optional: when null the zoom clamps against the viewport (always works,
/// slightly loose for letterboxed images). [originalSize] is the
/// full-resolution size of the child and enables the 1:1 double-tap step;
/// when null that step is skipped.
///
/// Use [LeafZoomable.image] to render a plain image: its pixel dimensions
/// are extracted from the image stream at load time, so both the contained
/// size and the 1:1 step work without passing anything.
///
/// Set [enabled] to false to render content without zoom (e.g. until the
/// image has loaded).
class LeafZoomable extends StatefulWidget {
  const LeafZoomable({
    super.key,
    required this.child,
    this.childSize,
    this.originalSize,
    this.maxScale = 5.0,
    this.enabled = true,
    this.onTap,
    this.onZoomChanged,
  }) : image = null;

  const LeafZoomable.image({
    super.key,
    required Image image,
    this.maxScale = 5.0,
    this.enabled = true,
    this.onTap,
    this.onZoomChanged,
  })  : child = image,
        childSize = null,
        originalSize = null,
        image = image;

  final Widget child;
  final Size? childSize;
  final Size? originalSize;

  /// Non-null when created via [LeafZoomable.image]: the image's pixel
  /// dimensions are resolved from its stream to size the zoom correctly.
  final Image? image;

  final double maxScale;
  final bool enabled;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onZoomChanged;

  /// The contained (letterboxed) size of [source] inside [viewport].
  static Size containSize(Size viewport, Size source) {
    final ratio = source.width / source.height;
    if (viewport.width / viewport.height > ratio) {
      return Size(viewport.height * ratio, viewport.height);
    }
    return Size(viewport.width, viewport.width / ratio);
  }

  @override
  State<LeafZoomable> createState() => _LeafZoomableState();
}

class _LeafZoomableState extends State<LeafZoomable> with TickerProviderStateMixin {
  late final LeafZoomController _controller;
  int? _index;
  LeafViewerRegistry? _registry;
  double _scaleBefore = 1.0;
  Offset _prevFocal = Offset.zero;

  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  Size? _decodedSize;
  bool _imageResolved = false;
  bool _lastZoomed = false;

  void _notifyZoom() {
    final zoomed = _controller.zoomed;
    if (zoomed == _lastZoomed) return;
    _lastZoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
  }

  @override
  void initState() {
    super.initState();
    _controller = LeafZoomController(maxScale: widget.maxScale, vsync: this)
      ..onZoomLimit = () => HapticFeedback.mediumImpact();
    _lastZoomed = _controller.zoomed;
    _controller.addListener(_notifyZoom);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final index = LeafPageIndexScope.maybeOf(context);
    final registry = LeafViewerScope.maybeOf(context)?.registry;
    if (index != _index || registry != _registry) {
      _unregister();
      _index = index;
      _registry = registry;
      _register();
    }
    if (widget.image != null && !_imageResolved) {
      _imageResolved = true;
      _resolveImageDimensions();
    }
  }

  @override
  void didUpdateWidget(LeafZoomable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.maxScale != widget.maxScale) {
      _controller.updateLayout(viewport: _controller.viewport, childSize: _controller.childSize, originalSize: _controller.originalSize);
    }
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        _register();
      } else {
        _unregister();
      }
    }
  }

  void _register() {
    final index = _index;
    if (index == null || !widget.enabled) return;
    _registry?.register(index, _controller);
  }

  void _unregister() {
    final index = _index;
    if (index == null) return;
    _registry?.unregister(index, _controller);
  }

  void _resolveImageDimensions() {
    final image = widget.image!;
    final stream = image.image.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
      info.dispose();
      if (!mounted || size == _decodedSize) return;
      setState(() => _decodedSize = size);
    });
    stream.addListener(listener);
    _imageStream = stream;
    _imageListener = listener;
  }

  @override
  void dispose() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _unregister();
    _controller.removeListener(_notifyZoom);
    _controller.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails details) {
    _controller.cancelGesture();
    _scaleBefore = _controller.scale;
    _prevFocal = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final newScale = _scaleBefore * details.scale;
    _controller.scaleUpdate(newScale, _prevFocal, details.localFocalPoint);
    _prevFocal = details.localFocalPoint;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if ((_controller.scale - _scaleBefore).abs() < 0.001) {
      final v = details.velocity.pixelsPerSecond;
      if (v.distance > 300) _controller.startFling(v);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!widget.enabled) return;
    // Ctrl+scroll always zooms; plain scroll also zooms once zoomed (so the
    // wheel can zoom back out). Otherwise the event passes through to the
    // enclosing scrollable.
    if (!HardwareKeyboard.instance.isControlPressed && !_controller.zoomed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final scroll = event as PointerScrollEvent;
      _controller.wheelZoom(scroll.scrollDelta.dy, scroll.localPosition);
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = constraints.biggest;
        final decoded = _decodedSize;
        final contained = widget.childSize ??
            (decoded != null ? LeafZoomable.containSize(viewport, decoded) : viewport);
        final original = widget.originalSize ?? decoded;
        final content = Center(
          child: SizedBox(
            width: contained.width,
            height: contained.height,
            child: widget.child,
          ),
        );
        if (!widget.enabled) return content;
        _controller.updateLayout(viewport: viewport, childSize: contained, originalSize: original);
        return ListenableBuilder(
          listenable: _controller,
          builder: (context, _) {
            final transform = Matrix4.identity()
              ..setEntry(0, 3, _controller.position.dx)
              ..setEntry(1, 3, _controller.position.dy)
              ..setEntry(0, 0, _controller.scale)
              ..setEntry(1, 1, _controller.scale);
            final gestures = <Type, GestureRecognizerFactory>{
              LeafPanZoomRecognizer: GestureRecognizerFactoryWithHandlers<LeafPanZoomRecognizer>(
                () => LeafPanZoomRecognizer(shouldClaim: _controller.shouldClaim, debugOwner: this),
                (instance) => instance
                  ..onStart = _onScaleStart
                  ..onUpdate = _onScaleUpdate
                  ..onEnd = _onScaleEnd,
              ),
            };
            if (LeafViewerScope.maybeOf(context)?.registry.swipeGesturesEnabled ?? true) {
              gestures[DoubleTapGestureRecognizer] = GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
                () => DoubleTapGestureRecognizer(debugOwner: this),
                (instance) => instance.onDoubleTapDown = (details) => _controller.doubleTap(details.localPosition),
              );
            }
            final chrome = LeafViewerScope.maybeOf(context)?.chrome;
            final tapCallback = widget.onTap ?? chrome?.toggle;
            if (tapCallback != null) {
              gestures[TapGestureRecognizer] = GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                () => TapGestureRecognizer(debugOwner: this),
                (instance) => instance.onTap = tapCallback,
              );
            }
            return Listener(
              onPointerSignal: _onPointerSignal,
              child: RawGestureDetector(
                behavior: HitTestBehavior.translucent,
                gestures: gestures,
                child: Transform(transform: transform, alignment: Alignment.center, child: content),
              ),
            );
          },
        );
      },
    );
  }
}
