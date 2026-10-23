import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Reveal Animation Interface
// ═══════════════════════════════════════════════════════════════════════════════

/// Pluggable reveal effect that plays when an image finishes loading.
///
/// Implementors own an [AnimationController] with the given [duration] and
/// return the wrapped [child] from [build].
abstract class LeafRevealAnimation {
  const LeafRevealAnimation();

  /// How long the reveal animation takes.
  Duration get duration;

  /// Wrap [child] (the loaded image) with the reveal effect.
  ///
  /// [controller] is pre-configured with [duration] and will be
  /// `.forward()`-ed by [LeafImage] when the first frame arrives.
  Widget build(BuildContext context, Widget child, AnimationController controller);
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Built-in Animations
// ═══════════════════════════════════════════════════════════════════════════════

/// Sweeps a gradient mask across the image from left-to-right (or top-to-bottom).
class GradientRevealAnimation extends LeafRevealAnimation {
  /// Direction of the sweep.
  final Axis direction;

  /// Width of the gradient transition zone as a fraction of the image width.
  final double window;

  /// Final position of the trailing gradient stop (1.0 = fully revealed).
  final double finalStop2;

  @override
  final Duration duration;

  /// Animation curve.
  final Curve curve;

  const GradientRevealAnimation({
    this.direction = Axis.horizontal,
    this.window = 0.3,
    this.finalStop2 = 1.3,
    this.duration = const Duration(milliseconds: 400),
    this.curve = Curves.fastLinearToSlowEaseIn,
  });

  @override
  Widget build(BuildContext context, Widget child, AnimationController controller) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final t = controller.value;
        final startStop1 = -window;
        final startStop2 = 0.0;
        final stop1 = lerpDouble(startStop1, finalStop2 - window, t)!;
        final stop2 = lerpDouble(startStop2, finalStop2, t)!;
        return _RevealMask(
          gradient: stop1 >= 1.0
              ? null
              : LinearGradient(
                  begin: direction == Axis.horizontal ? Alignment.centerLeft : Alignment.topCenter,
                  end: direction == Axis.horizontal ? Alignment.centerRight : Alignment.bottomCenter,
                  colors: const [Colors.white, Colors.transparent],
                  stops: [stop1, stop2],
                ),
          child: child!,
        );
      },
      child: child,
    );
  }
}

class _RevealMask extends SingleChildRenderObjectWidget {
  const _RevealMask({required this.gradient, required super.child});

  final Gradient? gradient;

  @override
  _RenderRevealMask createRenderObject(BuildContext context) => _RenderRevealMask(gradient);

  @override
  void updateRenderObject(BuildContext context, _RenderRevealMask renderObject) => renderObject.gradient = gradient;
}

class _RenderRevealMask extends RenderProxyBox {
  _RenderRevealMask(this._gradient);

  Gradient? _gradient;

  set gradient(Gradient? value) {
    if (value == _gradient) return;
    final wasMasking = _gradient != null;
    _gradient = value;
    if (wasMasking != (value != null)) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _gradient != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final gradient = _gradient;
    if (child == null || gradient == null) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    final mask = layer is ShaderMaskLayer ? layer! as ShaderMaskLayer : ShaderMaskLayer();
    mask
      ..shader = gradient.createShader(Offset.zero & size)
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    layer = mask;
    context.pushLayer(mask, super.paint, offset);
  }
}

/// Simple opacity fade-in.
class FadeRevealAnimation extends LeafRevealAnimation {
  @override
  final Duration duration;
  final Curve curve;

  const FadeRevealAnimation({this.duration = const Duration(milliseconds: 300), this.curve = Curves.easeIn});

  @override
  Widget build(BuildContext context, Widget child, AnimationController controller) {
    return FadeTransition(
      opacity: controller.drive(CurveTween(curve: curve)),
      child: child,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  LeafImage
// ═══════════════════════════════════════════════════════════════════════════════

/// Configurable image widget with pluggable reveal animations, built-in
/// interactivity, loading skeleton support, and one-tap retry on error.
///
/// Wraps Flutter's [Image] and manages its three builders internally so you
/// never have to write `Stack` + `Material` + `InkWell` + `loadingBuilder` +
/// `errorBuilder` yourself.
///
/// ```dart
/// LeafImage(
///   image: KemonoImageProvider(url, creatorId: id, postId: pid),
///   fit: BoxFit.cover,
///   loadingBuilder: (ctx, progress) => SkeletonTile(progress: progress),
///   onTap: () => FullscreenImageViewerScreen.open(...),
///   revealAnimation: const GradientRevealAnimation(),
/// )
/// ```
class LeafImage extends StatefulWidget {
  // ── Required ──────────────────────────────────────────────────────────────

  /// The source image.
  final ImageProvider image;

  // ── Standard Image passthrough ────────────────────────────────────────────

  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final FilterQuality filterQuality;

  // ── Loading ───────────────────────────────────────────────────────────────

  /// Called with a [progress] value in `[0.0, 1.0]` while the image downloads.
  ///
  /// This is the right place for loading skeletons — the skeleton fills the
  /// same layout space the final image will occupy.
  ///
  /// When `null`, no custom loading state is shown and Flutter's default
  /// behaviour applies.
  final Widget Function(BuildContext context, double progress)? loadingBuilder;

  // ── Error ─────────────────────────────────────────────────────────────────

  /// Called when the image fails to load.
  ///
  /// The [retry] callback bumps an internal key so the image reloads from
  /// scratch.
  ///
  /// When `null`, a default grey box with a refresh icon is shown.
  final Widget Function(BuildContext context, Object error, VoidCallback retry)? errorBuilder;

  // ── Reveal ────────────────────────────────────────────────────────────────

  /// Animation that plays once when the first image frame is decoded.
  ///
  /// Defaults to [GradientRevealAnimation] when `null`.
  final LeafRevealAnimation? revealAnimation;

  // ── Decoration ────────────────────────────────────────────────────────────

  /// Wraps the loaded image (e.g. with [ClipRRect] or [DecoratedBox]).
  ///
  /// This runs **before** the reveal animation, so the clip applies to both
  /// the image and its reveal effect.
  final Widget Function(BuildContext context, Widget child)? imageBuilder;

  // ── Interactivity ─────────────────────────────────────────────────────────

  /// Tapping the loaded image area.
  ///
  /// Applying a handler wraps the image in a transparent [Material] +
  /// [InkWell] so you get the standard ripple/splash behaviour without
  /// needing an external `Stack`.
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  /// Called when the image fails to load.
  final void Function(Object error, StackTrace? stack)? onError;

  // ── Semantics ─────────────────────────────────────────────────────────────

  final String? semanticLabel;
  final bool excludeFromSemantics;

  // ── Gapless playback ──────────────────────────────────────────────────────

  /// If `true`, keeps showing the old image while a new [image] provider loads.
  final bool gaplessPlayback;

  // ──────────────────────────────────────────────────────────────────────────

  const LeafImage({
    super.key,
    required this.image,
    this.fit,
    this.alignment = Alignment.center,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.filterQuality = FilterQuality.low,
    this.loadingBuilder,
    this.errorBuilder,
    this.revealAnimation = const GradientRevealAnimation(),
    this.imageBuilder,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onError,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.gaplessPlayback = false,
  });

  @override
  State<LeafImage> createState() => _LeafImageState();
}

class _LeafImageState extends State<LeafImage> with SingleTickerProviderStateMixin {
  late final AnimationController _revealController;
  int _retryKey = 0;
  bool _imageReady = false;
  bool _wasSync = false;
  bool _revealStarted = false;

  // ── Lifecycle ───────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(duration: widget.revealAnimation?.duration ?? Duration.zero, vsync: this);
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(LeafImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image ||
        oldWidget.cacheWidth != widget.cacheWidth ||
        oldWidget.cacheHeight != widget.cacheHeight) {
      _retryKey = 0;
      _imageReady = false;
      _wasSync = false;
      _revealStarted = false;
      _revealController
        ..reset()
        ..duration = widget.revealAnimation?.duration ?? Duration.zero;
    }
  }

  // ── Retry ────────────────────────────────────────────────────────────────

  void _handleRetry() {
    setState(() {
      _retryKey++;
      _imageReady = false;
      _wasSync = false;
      _revealStarted = false;
      _revealController.reset();
    });
  }

  void _startReveal(bool wasSync) {
    if (_revealStarted) return;
    _revealStarted = true;
    _wasSync = wasSync;

    if (wasSync) {
      _revealController.value = 1.0;
    } else {
      _revealController.forward();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  bool get _hasTapHandler =>
      widget.onTap != null || widget.onDoubleTap != null || widget.onLongPress != null || widget.onSecondaryTap != null;

  /// Wraps the rendered image with decoration → reveal animation.
  /// Interactivity is applied at the outermost layer in [build] so it's
  /// present even during loading and error states.
  Widget _wrapLoaded(Widget child) {
    // 1. Custom decoration (ClipRRect, border, etc.)
    if (widget.imageBuilder != null) {
      child = widget.imageBuilder!(context, child);
    }

    // 2. Reveal animation (null = disabled)
    if (widget.revealAnimation != null && !_wasSync) {
      child = widget.revealAnimation!.build(context, child, _revealController);
    }

    return child;
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final imageInkwell = _hasTapHandler
        ? Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                onDoubleTap: widget.onDoubleTap,
                onLongPress: widget.onLongPress,
                onSecondaryTap: widget.onSecondaryTap,
              ),
            ),
          )
        : null;
    final effectiveImage = (widget.cacheWidth != null || widget.cacheHeight != null)
        ? ResizeImage.resizeIfNeeded(widget.cacheWidth, widget.cacheHeight, widget.image)
        : widget.image;
    Widget imageWidget = Image(
      key: ValueKey('leaf_$_retryKey'),
      image: effectiveImage,
      fit: widget.fit,
      alignment: widget.alignment,
      width: widget.width,
      height: widget.height,
      filterQuality: widget.filterQuality,
      gaplessPlayback: widget.gaplessPlayback,
      semanticLabel: widget.semanticLabel,
      excludeFromSemantics: widget.excludeFromSemantics,
      loadingBuilder: imageInkwell != null
          ? (context, child, loadingProgress) {
              return Stack(children: [_loadingBuilder(context, child, loadingProgress), imageInkwell]);
            }
          : (widget.loadingBuilder != null ? _loadingBuilder : null),
      frameBuilder: _frameBuilder,
      errorBuilder: (context, error, stackTrace) {
        final errorContent = _errorBuilder(context, error, stackTrace);
        if (imageInkwell == null) return errorContent;
        return SizedBox.expand(child: Stack(children: [imageInkwell, errorContent]));
      },
    );

    return SizedBox(width: widget.width, height: widget.height, child: imageWidget);
  }

  Widget _loadingBuilder(BuildContext context, Widget child, ImageChunkEvent? progress) {
    if (_imageReady || progress == null) {
      // Already decoded or download complete — pass through to frameBuilder
      return child;
    }

    if (widget.loadingBuilder == null) {
      // No custom skeleton — show the default placeholder
      return child;
    }

    final p = progress.expectedTotalBytes != null ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes! : 0.0;

    return widget.loadingBuilder!(context, p);
  }

  Widget _frameBuilder(BuildContext context, Widget child, int? frame, bool wasSynchronouslyLoaded) {
    if (frame != null) {
      // First frame decoded
      _imageReady = true;
      _startReveal(wasSynchronouslyLoaded);
      return _wrapLoaded(child);
    }
    return child;
  }

  Widget _errorBuilder(BuildContext context, Object error, StackTrace? stackTrace) {
    widget.onError?.call(error, stackTrace);

    if (widget.errorBuilder != null) {
      return widget.errorBuilder!(context, error, _handleRetry);
    }

    return _defaultError();
  }

  Widget _defaultError() {
    return Container(
      color: Colors.grey.shade800,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          const Icon(Icons.image_not_supported, color: Colors.white38),
          IconButton.outlined(icon: const Icon(Icons.refresh), onPressed: _handleRetry),
        ],
      ),
    );
  }
}
