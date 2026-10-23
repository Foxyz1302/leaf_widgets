import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
/// A large [LeafZoomable.image] is decoded at half resolution while it is
/// shown at 1x, when half still covers the display in both orientations and
/// the image is drawn with mipmaps ([FilterQuality.medium], or
/// [FilterQuality.high] under Impeller): mipmapped sampling reads that half
/// level anyway, so the 1x picture is the same at a quarter of the memory.
/// Zooming in loads the full resolution and swaps it in once decoded;
/// settling back at 1x returns to the half-size decode. Set
/// [decodeFullResolution] to always decode at full resolution.
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
  })  : image = null,
        decodeFullResolution = false;

  const LeafZoomable.image({
    super.key,
    required Image image,
    this.maxScale = 5.0,
    this.enabled = true,
    this.onTap,
    this.onZoomChanged,
    this.decodeFullResolution = false,
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

  /// Decode [image] at full resolution also at 1x (see the class docs).
  final bool decodeFullResolution;

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
  ImageProvider? _baseImage;
  Size? _decodedSize;
  bool _baseReduced = false;
  ImageStream? _fullStream;
  ImageStreamListener? _fullListener;
  bool _fullReady = false;
  bool _levelCheckScheduled = false;
  bool _lastZoomed = false;

  void _notifyZoom() {
    final zoomed = _controller.zoomed;
    if (zoomed == _lastZoomed) return;
    _lastZoomed = zoomed;
    widget.onZoomChanged?.call(zoomed);
    if (_baseReduced) _scheduleLevelCheck();
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
    if (widget.image != null) _resolveBase();
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
    if (widget.image?.image != oldWidget.image?.image) {
      _stopImageDimensions();
      _stopFull();
      _baseImage = null;
      _decodedSize = null;
      _baseReduced = false;
      _fullReady = false;
    }
    if (widget.image != null) _resolveBase();
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

  ImageProvider _baseFor(Image image) {
    final source = image.image;
    if (widget.decodeFullResolution ||
        image.runtimeType != Image ||
        source is ResizeImage ||
        image.centerSlice != null ||
        image.repeat != ImageRepeat.noRepeat ||
        image.fit == BoxFit.none) {
      return source;
    }
    final mipmapped = image.filterQuality == FilterQuality.medium ||
        (image.filterQuality == FilterQuality.high && ui.ImageFilter.isShaderFilterSupported);
    final display = View.maybeOf(context)?.display.size;
    if (!mipmapped || display == null || display.isEmpty) return source;
    return _HalfImage(source, Size(math.max(display.width, display.height), math.min(display.width, display.height)));
  }

  void _resolveBase() {
    final base = _baseFor(widget.image!);
    if (base == _baseImage) return;
    _stopImageDimensions();
    _baseImage = base;
    final stream = base.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      final decoded = Size(info.image.width.toDouble(), info.image.height.toDouble());
      info.dispose();
      final completer = stream.completer;
      final size = (completer == null ? null : _sourceSizes[completer]?.size) ?? decoded;
      final reduced = size.width > decoded.width;
      if (!mounted || (size == _decodedSize && reduced == _baseReduced)) return;
      setState(() {
        _decodedSize = size;
        _baseReduced = reduced;
      });
      if (reduced) _scheduleLevelCheck();
    });
    stream.addListener(listener);
    _imageStream = stream;
    _imageListener = listener;
  }

  void _stopImageDimensions() {
    final stream = _imageStream, listener = _imageListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _imageStream = null;
    _imageListener = null;
  }

  void _scheduleLevelCheck() {
    if (_levelCheckScheduled) return;
    _levelCheckScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _levelCheckScheduled = false;
      if (mounted) _updateLevel();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _updateLevel() {
    final image = widget.image;
    final wantFull = image != null && _baseReduced && _controller.zoomed;
    if (wantFull && _fullStream == null) {
      final stream = image.image.resolve(createLocalImageConfiguration(context));
      final listener = ImageStreamListener(
        (info, _) {
          info.dispose();
          if (!mounted || _fullReady || _fullStream != stream) return;
          setState(() => _fullReady = true);
        },
        onError: (error, stackTrace) {},
      );
      _fullStream = stream;
      _fullListener = listener;
      stream.addListener(listener);
    } else if (!wantFull && _fullStream != null) {
      _stopFull();
      if (_fullReady) setState(() => _fullReady = false);
    }
  }

  void _stopFull() {
    final stream = _fullStream, listener = _fullListener;
    if (stream != null && listener != null) stream.removeListener(listener);
    _fullStream = null;
    _fullListener = null;
  }

  static Image _withImage(Image image, ImageProvider provider) => Image(
        key: image.key,
        image: provider,
        frameBuilder: image.frameBuilder,
        loadingBuilder: image.loadingBuilder,
        errorBuilder: image.errorBuilder,
        semanticLabel: image.semanticLabel,
        excludeFromSemantics: image.excludeFromSemantics,
        width: image.width,
        height: image.height,
        color: image.color,
        opacity: image.opacity,
        colorBlendMode: image.colorBlendMode,
        fit: image.fit,
        alignment: image.alignment,
        repeat: image.repeat,
        centerSlice: image.centerSlice,
        matchTextDirection: image.matchTextDirection,
        gaplessPlayback: image.gaplessPlayback,
        isAntiAlias: image.isAntiAlias,
        filterQuality: image.filterQuality,
      );

  @override
  void dispose() {
    _stopImageDimensions();
    _stopFull();
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
        final image = widget.image, base = _baseImage;
        final shown = image == null || base == null || _fullReady || identical(base, image.image) ? widget.child : _withImage(image, base);
        final content = Center(
          child: SizedBox(
            width: contained.width,
            height: contained.height,
            child: shown,
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

class _SourceSize {
  Size? size;
}

final _sourceSizes = Expando<_SourceSize>();

@immutable
class _HalfImageKey {
  const _HalfImageKey(this.sourceKey, this.display);

  final Object sourceKey;
  final Size display;

  @override
  bool operator ==(Object other) => other is _HalfImageKey && other.sourceKey == sourceKey && other.display == display;

  @override
  int get hashCode => Object.hash(sourceKey, display);
}

class _HalfImage extends ImageProvider<_HalfImageKey> {
  const _HalfImage(this.source, this.display);

  final ImageProvider source;
  final Size display;

  @override
  Future<_HalfImageKey> obtainKey(ImageConfiguration configuration) {
    Completer<_HalfImageKey>? completer;
    SynchronousFuture<_HalfImageKey>? result;
    source.obtainKey(configuration).then((key) {
      if (completer == null) {
        result = SynchronousFuture(_HalfImageKey(key, display));
      } else {
        completer.complete(_HalfImageKey(key, display));
      }
    });
    if (result != null) return result!;
    completer = Completer<_HalfImageKey>();
    return completer.future;
  }

  @override
  ImageStreamCompleter loadImage(_HalfImageKey key, ImageDecoderCallback decode) {
    final sourceSize = _SourceSize();
    Future<ui.Codec> decodeHalf(ui.ImmutableBuffer buffer, {ui.TargetImageSizeCallback? getTargetSize}) {
      return decode(
        buffer,
        getTargetSize: (width, height) {
          sourceSize.size = Size(width.toDouble(), height.toDouble());
          return getTargetSize?.call(width, height) ?? _targetSize(width, height);
        },
      );
    }

    final completer = source.loadImage(key.sourceKey, decodeHalf);
    _sourceSizes[completer] = sourceSize;
    completer.addEphemeralErrorListener((error, stackTrace) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  ui.TargetImageSize _targetSize(int width, int height) {
    final source = Size(width.toDouble(), height.toDouble());
    final upright = LeafZoomable.containSize(display, source);
    final turned = LeafZoomable.containSize(display.flipped, source);
    final shown = Size(math.max(upright.width, turned.width), math.max(upright.height, turned.height));
    if (width >= 2 * shown.width && height >= 2 * shown.height) {
      return ui.TargetImageSize(width: (width / 2).round(), height: (height / 2).round());
    }
    return ui.TargetImageSize(width: width, height: height);
  }

  @override
  bool operator ==(Object other) => other is _HalfImage && other.source == source && other.display == display;

  @override
  int get hashCode => Object.hash(source, display);
}
