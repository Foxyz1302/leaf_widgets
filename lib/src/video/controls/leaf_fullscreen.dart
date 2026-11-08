import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// How a player goes fullscreen.
enum LeafFullscreenMode {
  /// [inPlace] inside a `LeafViewer` (already a full-screen route), [route]
  /// everywhere else.
  auto,

  /// A zero-transition route the live surface moves into (same State,
  /// texture and platform view: no re-open).
  route,

  /// No route: only the delegate's OS step; the controls switch to the
  /// fullscreen spec where they are.
  inPlace,
  disabled,
}

/// What the delegate is told on enter / exit.
@immutable
class LeafFullscreenRequest {
  const LeafFullscreenRequest({required this.mode, this.aspectRatio, this.videoSize});

  /// The resolved mode ([LeafFullscreenMode.route] or [LeafFullscreenMode.inPlace]).
  final LeafFullscreenMode mode;
  final double? aspectRatio;
  final Size? videoSize;
}

/// The OS / window step of fullscreen (immersive mode and rotation on
/// phones, the window on desktop). The kit's route or in-place switch
/// happens either way; the delegate makes it real fullscreen.
abstract class LeafFullscreenDelegate {
  const LeafFullscreenDelegate();

  Future<void> enter(LeafFullscreenRequest request);
  Future<void> exit(LeafFullscreenRequest request);

  /// The OS left fullscreen by itself (true → false): the kit exits too.
  ValueListenable<bool>? get externalState => null;

  /// Whether this delegate does anything (in-place fullscreen without one
  /// would change nothing, so its button hides).
  bool get isNone => false;

  /// App callbacks; e.g. on desktop with window_manager:
  /// `LeafFullscreenDelegate.callbacks(onEnter: (_) => windowManager.setFullScreen(true), onExit: (_) => windowManager.setFullScreen(false))`.
  const factory LeafFullscreenDelegate.callbacks({
    FutureOr<void> Function(LeafFullscreenRequest request)? onEnter,
    FutureOr<void> Function(LeafFullscreenRequest request)? onExit,
    ValueListenable<bool>? externalState,
  }) = _CallbackDelegate;

  static const LeafFullscreenDelegate none = _NoopDelegate();

  /// Android / iOS: [LeafSystemFullscreenDelegate]; elsewhere [none].
  static LeafFullscreenDelegate platformDefault() {
    if (kIsWeb) return none;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => const LeafSystemFullscreenDelegate(),
      _ => none,
    };
  }
}

class _CallbackDelegate extends LeafFullscreenDelegate {
  const _CallbackDelegate({this.onEnter, this.onExit, ValueListenable<bool>? externalState}) : _external = externalState;

  final FutureOr<void> Function(LeafFullscreenRequest request)? onEnter;
  final FutureOr<void> Function(LeafFullscreenRequest request)? onExit;
  final ValueListenable<bool>? _external;

  @override
  ValueListenable<bool>? get externalState => _external;

  @override
  Future<void> enter(LeafFullscreenRequest request) async => await onEnter?.call(request);

  @override
  Future<void> exit(LeafFullscreenRequest request) async => await onExit?.call(request);
}

class _NoopDelegate extends LeafFullscreenDelegate {
  const _NoopDelegate();

  @override
  bool get isNone => true;

  @override
  Future<void> enter(LeafFullscreenRequest request) async {}

  @override
  Future<void> exit(LeafFullscreenRequest request) async {}
}

/// Phones: immersive system UI and, for landscape video, landscape
/// orientations while fullscreen; restored on exit.
class LeafSystemFullscreenDelegate extends LeafFullscreenDelegate {
  const LeafSystemFullscreenDelegate({
    this.immersive = true,
    this.lockLandscape = true,
    this.restoreUiMode = SystemUiMode.edgeToEdge,
    this.restoreOrientations = const [],
  });

  final bool immersive;

  /// Landscape only for video wider than tall (or of unknown shape).
  final bool lockLandscape;
  final SystemUiMode restoreUiMode;

  /// Empty: every orientation.
  final List<DeviceOrientation> restoreOrientations;

  @override
  Future<void> enter(LeafFullscreenRequest request) async {
    if (immersive) await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final ratio = request.aspectRatio ?? 16 / 9;
    if (lockLandscape && ratio > 1) {
      await SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
  }

  @override
  Future<void> exit(LeafFullscreenRequest request) async {
    if (immersive) await SystemChrome.setEnabledSystemUIMode(restoreUiMode);
    if (lockLandscape) await SystemChrome.setPreferredOrientations(restoreOrientations);
  }
}
