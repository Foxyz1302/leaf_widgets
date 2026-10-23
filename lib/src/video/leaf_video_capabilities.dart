import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Size;

/// Optional playback state beyond [VideoPlayerAdapter]: a duration stream,
/// buffering and end-of-media. Without it the controls re-read
/// `adapter.duration` on player events and show buffering only before the
/// first frame.
abstract mixin class HasPlaybackStatus {
  Stream<Duration> get durationStream;
  Stream<bool> get bufferingStream;
  bool get isBuffering;
  Stream<bool> get completedStream;
  bool get isCompleted;
}

/// Optional playback speed (1.0 = normal).
abstract mixin class HasPlaybackRate {
  Stream<double> get rateStream;
  double get rate;
  void setRate(double rate);
}

/// Optional video, audio and subtitle track selection.
abstract mixin class HasTracks {
  Stream<LeafTracks> get tracksStream;
  LeafTracks get tracks;

  /// Selects track [id] of [kind]; a null [id] turns the kind off
  /// (subtitles off, no audio).
  void selectTrack(LeafTrackKind kind, String? id);
}

/// Optional chapter list of the open media.
abstract mixin class HasChapters {
  Stream<List<LeafChapter>> get chaptersStream;
  List<LeafChapter> get chapters;
}

/// Optional cached ranges; without it the controls treat
/// `[0, adapter.buffer]` as the only cached range.
abstract mixin class HasBufferedRanges {
  Stream<List<LeafTimeRange>> get bufferedRangesStream;
  List<LeafTimeRange> get bufferedRanges;
}

/// Optional decoded video dimensions (null until known).
abstract mixin class HasVideoSize {
  Stream<Size?> get videoSizeStream;
  Size? get videoSize;
}

/// Optional decoder and cache statistics for the info overlay. Polled about
/// once a second, and only while the overlay is shown.
abstract mixin class HasVideoStats {
  Future<LeafVideoStats> readStats();
}

/// Optional quality variants (HLS/DASH renditions, transcodes).
abstract mixin class HasQualities {
  Stream<LeafQualities> get qualitiesStream;
  LeafQualities get qualities;
  void selectQuality(String id);
}

/// Optional single-item repeat.
abstract mixin class HasLooping {
  Stream<bool> get loopingStream;
  bool get isLooping;
  void setLooping(bool on);
}

/// Optional picture-in-picture. [pipStream] reports whether PiP is active.
abstract mixin class HasPictureInPicture {
  Stream<bool> get pipStream;
  bool get isPipAvailable;
  Future<void> enterPip();
}

enum LeafTrackKind { video, audio, subtitle }

/// One track of the open media. [label] is what menus show: the adapter's
/// own formatting when it passes one, else "title · language · codec
/// channels".
@immutable
class LeafTrack {
  const LeafTrack({
    required this.id,
    required this.kind,
    this.title,
    this.language,
    this.codec,
    this.channels,
    this.isDefault = false,
    this.isForced = false,
    this.isExternal = false,
    String? label,
  }) : adapterLabel = label;

  final String id;
  final LeafTrackKind kind;
  final String? title;
  final String? language;
  final String? codec;

  /// Audio channel count.
  final int? channels;
  final bool isDefault;
  final bool isForced;
  final bool isExternal;

  /// The adapter's own formatting of [label], if it passed one.
  final String? adapterLabel;

  String get label {
    final own = adapterLabel;
    if (own != null && own.isNotEmpty) return own;
    final format = [if (codec != null && codec!.isNotEmpty) codec!.toUpperCase(), ?_channelLayout(channels)].join(' ');
    final parts = [
      if (title != null && title!.isNotEmpty) title!,
      if (language != null && language!.isNotEmpty) language!,
      if (format.isNotEmpty) format,
    ];
    return parts.isEmpty ? 'Track $id' : parts.join(' · ');
  }

  static String? _channelLayout(int? channels) => switch (channels) {
    null || <= 0 => null,
    1 => 'mono',
    2 => '2.0',
    6 => '5.1',
    8 => '7.1',
    final n => '${n}ch',
  };

  @override
  bool operator ==(Object other) =>
      other is LeafTrack &&
      other.id == id &&
      other.kind == kind &&
      other.title == title &&
      other.language == language &&
      other.codec == codec &&
      other.channels == channels &&
      other.isDefault == isDefault &&
      other.isForced == isForced &&
      other.isExternal == isExternal &&
      other.adapterLabel == adapterLabel;

  @override
  int get hashCode => Object.hash(id, kind, title, language, codec, channels, isDefault, isForced, isExternal, adapterLabel);

  @override
  String toString() => 'LeafTrack(${kind.name} $id "$label")';
}

/// The tracks of the open media and the current selection per kind (null:
/// that kind is off or nothing is selected).
@immutable
class LeafTracks {
  const LeafTracks({
    this.video = const [],
    this.audio = const [],
    this.subtitle = const [],
    this.selectedVideo,
    this.selectedAudio,
    this.selectedSubtitle,
  });

  static const empty = LeafTracks();

  final List<LeafTrack> video;
  final List<LeafTrack> audio;
  final List<LeafTrack> subtitle;
  final String? selectedVideo;
  final String? selectedAudio;
  final String? selectedSubtitle;

  List<LeafTrack> of(LeafTrackKind kind) => switch (kind) {
    LeafTrackKind.video => video,
    LeafTrackKind.audio => audio,
    LeafTrackKind.subtitle => subtitle,
  };

  String? selected(LeafTrackKind kind) => switch (kind) {
    LeafTrackKind.video => selectedVideo,
    LeafTrackKind.audio => selectedAudio,
    LeafTrackKind.subtitle => selectedSubtitle,
  };

  @override
  bool operator ==(Object other) =>
      other is LeafTracks &&
      listEquals(other.video, video) &&
      listEquals(other.audio, audio) &&
      listEquals(other.subtitle, subtitle) &&
      other.selectedVideo == selectedVideo &&
      other.selectedAudio == selectedAudio &&
      other.selectedSubtitle == selectedSubtitle;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(video),
    Object.hashAll(audio),
    Object.hashAll(subtitle),
    selectedVideo,
    selectedAudio,
    selectedSubtitle,
  );
}

/// One chapter. [end] is the next chapter's start, or the duration for the
/// last one ([start] while the duration is unknown).
@immutable
class LeafChapter {
  const LeafChapter({required this.index, required this.title, required this.start, required this.end});

  final int index;
  final String title;
  final Duration start;
  final Duration end;

  @override
  bool operator ==(Object other) =>
      other is LeafChapter && other.index == index && other.title == title && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(index, title, start, end);

  @override
  String toString() => 'LeafChapter($index "$title" $start-$end)';
}

@immutable
class LeafTimeRange {
  const LeafTimeRange(this.start, this.end);

  final Duration start;
  final Duration end;

  @override
  bool operator ==(Object other) => other is LeafTimeRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'LeafTimeRange($start-$end)';
}

@immutable
class LeafQuality {
  const LeafQuality({required this.id, required this.label, this.height, this.bitrate, this.isAuto = false});

  final String id;
  final String label;
  final int? height;

  /// Bits per second.
  final int? bitrate;
  final bool isAuto;

  @override
  bool operator ==(Object other) =>
      other is LeafQuality &&
      other.id == id &&
      other.label == label &&
      other.height == height &&
      other.bitrate == bitrate &&
      other.isAuto == isAuto;

  @override
  int get hashCode => Object.hash(id, label, height, bitrate, isAuto);
}

/// The quality variants and the selected one's id.
@immutable
class LeafQualities {
  const LeafQualities({this.options = const [], this.current});

  static const empty = LeafQualities();

  final List<LeafQuality> options;
  final String? current;

  @override
  bool operator ==(Object other) => other is LeafQualities && listEquals(other.options, options) && other.current == current;

  @override
  int get hashCode => Object.hash(Object.hashAll(options), current);
}

enum LeafSkipKind { intro, outro, recap, preview, commercial }

/// A marked range the skip pill offers to jump over (Jellyfin-style media
/// segments, supplied by the app).
@immutable
class LeafSkipSegment {
  const LeafSkipSegment({required this.kind, required this.start, required this.end, this.label});

  final LeafSkipKind kind;
  final Duration start;
  final Duration end;

  /// Overrides the pill's text ("Skip intro").
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is LeafSkipSegment && other.kind == kind && other.start == start && other.end == end && other.label == label;

  @override
  int get hashCode => Object.hash(kind, start, end, label);
}

/// What the info overlay shows from [HasVideoStats.readStats]. Every field is
/// optional; [extra] carries backend-specific lines.
@immutable
class LeafVideoStats {
  const LeafVideoStats({
    this.backend,
    this.videoSize,
    this.displaySize,
    this.containerFps,
    this.renderFps,
    this.displayFps,
    this.videoCodec,
    this.hwdec,
    this.pixelFormat,
    this.colorInfo,
    this.videoBitrate,
    this.audioCodec,
    this.audioChannels,
    this.sampleRate,
    this.audioBitrate,
    this.droppedFrames,
    this.decoderDroppedFrames,
    this.container,
    this.cacheAhead,
    this.cacheBytes,
    this.cacheSpeed,
    this.extra = const {},
  });

  final String? backend;
  final Size? videoSize;
  final Size? displaySize;
  final double? containerFps;
  final double? renderFps;
  final double? displayFps;
  final String? videoCodec;
  final String? hwdec;
  final String? pixelFormat;
  final String? colorInfo;

  /// Bits per second.
  final int? videoBitrate;
  final String? audioCodec;

  /// Channel layout as the backend names it ("stereo", "5.1").
  final String? audioChannels;
  final int? sampleRate;

  /// Bits per second.
  final int? audioBitrate;
  final int? droppedFrames;
  final int? decoderDroppedFrames;
  final String? container;
  final Duration? cacheAhead;
  final int? cacheBytes;

  /// Bytes per second.
  final int? cacheSpeed;
  final Map<String, String> extra;

  @override
  bool operator ==(Object other) =>
      other is LeafVideoStats &&
      other.backend == backend &&
      other.videoSize == videoSize &&
      other.displaySize == displaySize &&
      other.containerFps == containerFps &&
      other.renderFps == renderFps &&
      other.displayFps == displayFps &&
      other.videoCodec == videoCodec &&
      other.hwdec == hwdec &&
      other.pixelFormat == pixelFormat &&
      other.colorInfo == colorInfo &&
      other.videoBitrate == videoBitrate &&
      other.audioCodec == audioCodec &&
      other.audioChannels == audioChannels &&
      other.sampleRate == sampleRate &&
      other.audioBitrate == audioBitrate &&
      other.droppedFrames == droppedFrames &&
      other.decoderDroppedFrames == decoderDroppedFrames &&
      other.container == container &&
      other.cacheAhead == cacheAhead &&
      other.cacheBytes == cacheBytes &&
      other.cacheSpeed == cacheSpeed &&
      mapEquals(other.extra, extra);

  @override
  int get hashCode => Object.hashAll([
    backend,
    videoSize,
    displaySize,
    containerFps,
    renderFps,
    displayFps,
    videoCodec,
    hwdec,
    pixelFormat,
    colorInfo,
    videoBitrate,
    audioCodec,
    audioChannels,
    sampleRate,
    audioBitrate,
    droppedFrames,
    decoderDroppedFrames,
    container,
    cacheAhead,
    cacheBytes,
    cacheSpeed,
    Object.hashAllUnordered(extra.entries.map((e) => Object.hash(e.key, e.value))),
  ]);
}
