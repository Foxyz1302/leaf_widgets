import 'package:flutter/material.dart';

/// The two looks over one catalog: Material bars (sync_relay "Standard")
/// and the uosc band with glass capsules (sync_relay "Minimal").
enum LeafLook { material, uosc }

enum LeafButtonLook { round, flat }

enum LeafClusterLook { bare, capsule }

enum LeafChapterMark { diamond, dot }

/// Seek bar tokens.
@immutable
class LeafSeekBarTheme {
  const LeafSeekBarTheme({
    this.lineHeight = 3,
    this.lineHoverHeight = 5,
    this.lineHitHeight = 28,
    this.knobSize = 12,
    this.bandHeight = 36,
    this.bandCollapsedHeight = 3,
    this.playedTint = 0.4,
    this.stripes = true,
    this.chapterMark = LeafChapterMark.diamond,
    this.cacheLabelThreshold = const Duration(seconds: 60),
    this.trackColor = const Color(0x3DFFFFFF),
    this.bufferedColor = const Color(0x3DFFFFFF),
    this.timeFontSize = 15,
    this.timeInset = 12,
    this.chapterDot = 3.5,
  });

  final double lineHeight;
  final double lineHoverHeight;

  /// The line's hit area (the track is centred in it).
  final double lineHitHeight;
  final double knobSize;
  final double bandHeight;
  final double bandCollapsedHeight;

  /// The band's played part: the accent at this alpha.
  final double playedTint;

  /// Diagonal stripes over the band's part not downloaded yet.
  final bool stripes;
  final LeafChapterMark chapterMark;

  /// The band's cache label ("12s") shows while less is buffered ahead.
  final Duration cacheLabelThreshold;
  final Color trackColor;
  final Color bufferedColor;
  final double timeFontSize;
  final double timeInset;
  final double chapterDot;

  LeafSeekBarTheme copyWith({
    double? lineHeight,
    double? lineHoverHeight,
    double? lineHitHeight,
    double? knobSize,
    double? bandHeight,
    double? bandCollapsedHeight,
    double? playedTint,
    bool? stripes,
    LeafChapterMark? chapterMark,
    Duration? cacheLabelThreshold,
    Color? trackColor,
    Color? bufferedColor,
    double? timeFontSize,
    double? timeInset,
    double? chapterDot,
  }) => LeafSeekBarTheme(
    lineHeight: lineHeight ?? this.lineHeight,
    lineHoverHeight: lineHoverHeight ?? this.lineHoverHeight,
    lineHitHeight: lineHitHeight ?? this.lineHitHeight,
    knobSize: knobSize ?? this.knobSize,
    bandHeight: bandHeight ?? this.bandHeight,
    bandCollapsedHeight: bandCollapsedHeight ?? this.bandCollapsedHeight,
    playedTint: playedTint ?? this.playedTint,
    stripes: stripes ?? this.stripes,
    chapterMark: chapterMark ?? this.chapterMark,
    cacheLabelThreshold: cacheLabelThreshold ?? this.cacheLabelThreshold,
    trackColor: trackColor ?? this.trackColor,
    bufferedColor: bufferedColor ?? this.bufferedColor,
    timeFontSize: timeFontSize ?? this.timeFontSize,
    timeInset: timeInset ?? this.timeInset,
    chapterDot: chapterDot ?? this.chapterDot,
  );
}

/// The controls' tokens. Resolves as the spec's theme, then
/// `LeafPlayerDefaults.theme`, then `Theme.extension`, then the look's
/// defaults from the app's `colorScheme` ([LeafControlsTheme.forLook]).
/// Every surface is a solid translucent fill: no blur over the video.
@immutable
class LeafControlsTheme extends ThemeExtension<LeafControlsTheme> {
  const LeafControlsTheme({
    required this.accent,
    this.onAccent = Colors.white,
    this.foreground = Colors.white,
    this.foregroundDim = const Color(0xB3FFFFFF),
    this.disabled = const Color(0x61FFFFFF),
    this.hover = const Color(0x1FFFFFFF),
    this.boost = const Color(0xFFFFB74D),
    this.barScrimTop = const Color(0x99000000),
    this.barScrimBottom = const Color(0xB3000000),
    this.barScrimExtent = 24,
    this.capsuleFill = const Color(0x8C000000),
    this.capsuleBorder = const Color(0x1FFFFFFF),
    this.bandFill = const Color(0xCC0E0E12),
    this.tooltipFill = const Color(0xEB18181C),
    this.panelFill = const Color(0xEB18181C),
    this.scale = 1,
    this.buttonExtent = 48,
    this.iconSize = 24,
    this.playIconSize = 30,
    this.radius = 10,
    this.fontSize = 14,
    this.textStyle,
    this.buttonLook = LeafButtonLook.round,
    this.clusterLook = LeafClusterLook.bare,
    this.capsulePad = 4,
    this.seekBar = const LeafSeekBarTheme(),
    this.fade = const Duration(milliseconds: 150),
    this.volumeSliderWidth = 72,
  });

  /// The look's defaults over [scheme]'s primary.
  factory LeafControlsTheme.forLook(LeafLook look, ColorScheme scheme) => switch (look) {
    LeafLook.material => LeafControlsTheme(accent: scheme.primary, onAccent: scheme.onPrimary),
    LeafLook.uosc => LeafControlsTheme(
      accent: scheme.primary,
      onAccent: scheme.onPrimary,
      buttonExtent: 38,
      iconSize: 22,
      playIconSize: 26,
      fontSize: 13,
      buttonLook: LeafButtonLook.flat,
      clusterLook: LeafClusterLook.capsule,
      seekBar: const LeafSeekBarTheme(chapterMark: LeafChapterMark.dot),
    ),
  };

  final Color accent;
  final Color onAccent;
  final Color foreground;
  final Color foregroundDim;
  final Color disabled;
  final Color hover;

  /// The volume above 100 %.
  final Color boost;
  final Color barScrimTop;
  final Color barScrimBottom;

  /// The scrim's lead above the bottom bar.
  final double barScrimExtent;
  final Color capsuleFill;
  final Color capsuleBorder;
  final Color bandFill;
  final Color tooltipFill;
  final Color panelFill;

  /// Bar and button size (prefs scale multiplies in).
  final double scale;
  final double buttonExtent;
  final double iconSize;
  final double playIconSize;
  final double radius;
  final double fontSize;
  final TextStyle? textStyle;
  final LeafButtonLook buttonLook;
  final LeafClusterLook clusterLook;
  final double capsulePad;
  final LeafSeekBarTheme seekBar;

  /// The controls' fade in and out.
  final Duration fade;
  final double volumeSliderWidth;

  /// The text style for labels at [scale], tabular figures.
  TextStyle get labelStyle => (textStyle ?? const TextStyle()).copyWith(
    color: foreground,
    fontSize: fontSize * scale,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  double get scaledButton => buttonExtent * scale;

  @override
  LeafControlsTheme copyWith({
    Color? accent,
    Color? onAccent,
    Color? foreground,
    Color? foregroundDim,
    Color? disabled,
    Color? hover,
    Color? boost,
    Color? barScrimTop,
    Color? barScrimBottom,
    double? barScrimExtent,
    Color? capsuleFill,
    Color? capsuleBorder,
    Color? bandFill,
    Color? tooltipFill,
    Color? panelFill,
    double? scale,
    double? buttonExtent,
    double? iconSize,
    double? playIconSize,
    double? radius,
    double? fontSize,
    TextStyle? textStyle,
    LeafButtonLook? buttonLook,
    LeafClusterLook? clusterLook,
    double? capsulePad,
    LeafSeekBarTheme? seekBar,
    Duration? fade,
    double? volumeSliderWidth,
  }) => LeafControlsTheme(
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    foreground: foreground ?? this.foreground,
    foregroundDim: foregroundDim ?? this.foregroundDim,
    disabled: disabled ?? this.disabled,
    hover: hover ?? this.hover,
    boost: boost ?? this.boost,
    barScrimTop: barScrimTop ?? this.barScrimTop,
    barScrimBottom: barScrimBottom ?? this.barScrimBottom,
    barScrimExtent: barScrimExtent ?? this.barScrimExtent,
    capsuleFill: capsuleFill ?? this.capsuleFill,
    capsuleBorder: capsuleBorder ?? this.capsuleBorder,
    bandFill: bandFill ?? this.bandFill,
    tooltipFill: tooltipFill ?? this.tooltipFill,
    panelFill: panelFill ?? this.panelFill,
    scale: scale ?? this.scale,
    buttonExtent: buttonExtent ?? this.buttonExtent,
    iconSize: iconSize ?? this.iconSize,
    playIconSize: playIconSize ?? this.playIconSize,
    radius: radius ?? this.radius,
    fontSize: fontSize ?? this.fontSize,
    textStyle: textStyle ?? this.textStyle,
    buttonLook: buttonLook ?? this.buttonLook,
    clusterLook: clusterLook ?? this.clusterLook,
    capsulePad: capsulePad ?? this.capsulePad,
    seekBar: seekBar ?? this.seekBar,
    fade: fade ?? this.fade,
    volumeSliderWidth: volumeSliderWidth ?? this.volumeSliderWidth,
  );

  @override
  LeafControlsTheme lerp(LeafControlsTheme? other, double t) {
    if (other == null) return this;
    return t < 0.5
        ? this
        : other.copyWith(
            accent: Color.lerp(accent, other.accent, t),
            foreground: Color.lerp(foreground, other.foreground, t),
          );
  }
}
