import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../leaf_video_adapter.dart';
import '../leaf_video_capabilities.dart';
import 'leaf_menu_entry.dart';
import 'leaf_player_command.dart';
import 'media_math.dart';

/// What the play button shows. Apps with their own play semantics (a watch
/// party's "ready, waiting") supply it through [LeafPlayerActions.playState].
enum LeafPlayState { playing, paused, waiting, ended }

/// The clock's formats; a click on it cycles through the spec's list.
enum LeafTimeFormat {
  /// "6:00 / 24:00".
  elapsedTotal,

  /// "-18:00".
  remaining,

  /// "6:00".
  elapsed,
}

/// The clock text for [format]; "6:00" alone while the duration is unknown.
String leafClockText(Duration position, Duration duration, LeafTimeFormat format) {
  if (duration <= Duration.zero) return formatClock(position);
  return switch (format) {
    LeafTimeFormat.elapsedTotal => '${formatClock(position)} / ${formatClock(duration)}',
    LeafTimeFormat.remaining => '-${formatClock(duration - position < Duration.zero ? Duration.zero : duration - position)}',
    LeafTimeFormat.elapsed => formatClock(position),
  };
}

/// App hooks and content for the controls. Immutable; pass a new one with
/// [LeafPlayerController.updateActions] when something changes.
@immutable
class LeafPlayerActions {
  const LeafPlayerActions({
    this.title,
    this.subtitle,
    this.onBack,
    this.onNext,
    this.onPrevious,
    this.nextLabel,
    this.previousLabel,
    this.onTogglePlay,
    this.playState,
    this.onSeek,
    this.segments,
    this.menuEntries,
    this.seekPreview,
  });

  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onNext;
  final VoidCallback? onPrevious;
  final String? nextLabel;
  final String? previousLabel;

  /// Replaces play/pause (a watch party's ready toggle).
  final VoidCallback? onTogglePlay;

  /// Replaces what the play button shows.
  final ValueListenable<LeafPlayState>? playState;

  /// Routes user seeks through the app (a synced session); the player is
  /// not seeked by the controls then.
  final ValueChanged<Duration>? onSeek;
  final ValueListenable<List<LeafSkipSegment>>? segments;
  final List<LeafMenuEntry> Function()? menuEntries;

  /// A trickplay thumbnail for the seek bar's hover tip.
  final ImageProvider? Function(Duration at)? seekPreview;
}

/// The user's control preferences, owned (and persisted) by the app.
class LeafControlsPrefs extends ChangeNotifier {
  LeafControlsPrefs({
    this._timeFormat = LeafTimeFormat.elapsedTotal,
    Set<String> hidden = const {},
    this._scale = 1.0,
    this._progressLine = true,
  }) : _hidden = Set.unmodifiable(hidden);

  LeafTimeFormat _timeFormat;
  Set<String> _hidden;
  double _scale;
  bool _progressLine;

  LeafTimeFormat get timeFormat => _timeFormat;
  set timeFormat(LeafTimeFormat value) {
    if (value == _timeFormat) return;
    _timeFormat = value;
    notifyListeners();
  }

  /// Control ids the user hid from the bars (they move to the ⋯ menu).
  Set<String> get hidden => _hidden;
  set hidden(Set<String> value) {
    if (setEquals(value, _hidden)) return;
    _hidden = Set.unmodifiable(value);
    notifyListeners();
  }

  /// Bar and button size (1.0 normal, 1.25 large).
  double get scale => _scale;
  set scale(double value) {
    if (value == _scale) return;
    _scale = value;
    notifyListeners();
  }

  /// The thin progress line while the controls are hidden.
  bool get progressLine => _progressLine;
  set progressLine(bool value) {
    if (value == _progressLine) return;
    _progressLine = value;
    notifyListeners();
  }

  Map<String, Object> toJson() => {
    'timeFormat': _timeFormat.name,
    'hidden': _hidden.toList(),
    'scale': _scale,
    'progressLine': _progressLine,
  };

  factory LeafControlsPrefs.fromJson(Map<String, Object?> json) {
    final format = LeafTimeFormat.values.where((f) => f.name == json['timeFormat']).firstOrNull;
    final hidden = json['hidden'];
    final scale = json['scale'];
    final line = json['progressLine'];
    return LeafControlsPrefs(
      timeFormat: format ?? LeafTimeFormat.elapsedTotal,
      hidden: hidden is List ? {for (final h in hidden) h.toString()} : const {},
      scale: scale is num ? scale.toDouble() : 1.0,
      progressLine: line is bool ? line : true,
    );
  }
}

/// The overlay host of a player (`LeafPlayerControls`) as the controller
/// sees it: UI commands go there.
abstract interface class LeafControlsHostHandle {
  /// Handles [command] if it is the host's; false when ignored.
  bool handleUiCommand(LeafPlayerCommand command);
}

/// Whoever performs fullscreen for a player (the player view, or an app).
abstract interface class LeafFullscreenHandle {
  bool get canFullscreen;
  void enterFullscreen();
  void exitFullscreen();
}

/// A seek-by flash ("+20 s"): the sum of the steps in one direction while
/// they keep coming.
@immutable
class LeafSeekFlash {
  const LeafSeekFlash(this.total, this.serial);

  final Duration total;
  final int serial;
}

/// A [ValueListenable] that counts its listeners (for the "no work while
/// hidden" guards) and notifies only on change.
class LeafCountedValue<T> implements ValueListenable<T> {
  LeafCountedValue(this._value);

  final _listeners = <VoidCallback>[];
  T _value;
  bool _disposed = false;

  int get listenerCount => _listeners.length;

  @override
  T get value => _value;

  set value(T next) {
    if (next == _value) return;
    _value = next;
    notify();
  }

  @protected
  void notify() {
    if (_disposed) return;
    for (final l in List.of(_listeners)) {
      if (_listeners.contains(l)) l();
    }
  }

  @override
  void addListener(VoidCallback listener) {
    if (!_disposed) _listeners.add(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void dispose() {
    _disposed = true;
    _listeners.clear();
  }
}

/// The position for the UI, at most once per [interval] (leading and
/// trailing: the last value of a burst always lands). [value] is always the
/// latest raw position. No timer runs while nothing listens.
class LeafThrottledPosition extends LeafCountedValue<Duration> {
  LeafThrottledPosition(super.value, {required this.interval});

  final Duration interval;
  Timer? _cooldown;
  bool _dirty = false;

  bool get debugTimerActive => _cooldown?.isActive ?? false;

  void push(Duration raw) {
    _value = raw;
    if (listenerCount == 0) return;
    if (_cooldown != null) {
      _dirty = true;
      return;
    }
    _emit();
  }

  /// Lands the current value now (seek, play/pause) and lets the next one
  /// through at once.
  void flush() {
    _cooldown?.cancel();
    _cooldown = null;
    _dirty = false;
    if (listenerCount > 0) notify();
  }

  void _emit() {
    _dirty = false;
    notify();
    _cooldown = Timer(interval, _onCooldown);
  }

  void _onCooldown() {
    _cooldown = null;
    if (_dirty && listenerCount > 0) _emit();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (listenerCount == 0) {
      _cooldown?.cancel();
      _cooldown = null;
      _dirty = false;
    }
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    super.dispose();
  }
}

/// One controller per adapter: subscribes to each adapter stream once and
/// exposes throttled listenables, the UI state shared by every control of
/// the player, and a single dispatch, [execute], shared by buttons, keys and
/// gestures.
class LeafPlayerController {
  LeafPlayerController(
    this.adapter, {
    LeafPlayerActions actions = const LeafPlayerActions(),
    LeafControlsPrefs? prefs,
    Duration positionInterval = const Duration(milliseconds: 100),
    this.volumeMax = 100,
    this.volumeStep = 5,
    this.skipFallback,
  }) : _actions = actions,
       prefs = prefs ?? LeafControlsPrefs(),
       _ownsPrefs = prefs == null,
       position = LeafThrottledPosition(adapter.position, interval: positionInterval) {
    final a = adapter;
    _raw = a.position;
    _playing = ValueNotifier(a.isPlaying);
    _duration = ValueNotifier(a.duration);
    _buffered = ValueNotifier(a.buffer);
    _timeFormat = ValueNotifier(this.prefs.timeFormat);
    this.prefs.addListener(_onPrefs);
    _positionSeconds.value = a.position.inSeconds;
    final status = a is HasPlaybackStatus ? a as HasPlaybackStatus : null;
    _buffering = ValueNotifier(status?.isBuffering ?? a.position <= Duration.zero);
    _completed = ValueNotifier(status?.isCompleted ?? false);

    _subs
      ..add(a.positionStream.listen(_onPosition))
      ..add(a.bufferStream.listen(_onBuffer))
      ..add(a.playingStream.listen(_onPlaying))
      ..add(a.readyStream.listen(_onReady))
      ..add(a.errorStream.listen(_onError));
    if (status != null) {
      _subs
        ..add(status.durationStream.listen((d) => _duration.value = d))
        ..add(status.bufferingStream.listen((b) => _buffering.value = b))
        ..add(status.completedStream.listen((c) {
          _completed.value = c;
          _syncPlayState();
        }));
    }
    if (a is HasVolume) {
      final v = a as HasVolume;
      final n = ValueNotifier(v.volume);
      _volume = n;
      _subs.add(v.volumeStream.listen((value) => n.value = value));
    }
    if (a is HasPlaybackRate) {
      final r = a as HasPlaybackRate;
      final n = ValueNotifier(r.rate);
      _rate = n;
      _subs.add(r.rateStream.listen((value) => n.value = value));
    }
    if (a is HasTracks) {
      final t = a as HasTracks;
      final n = ValueNotifier(t.tracks);
      _tracks = n;
      _subs.add(t.tracksStream.listen((value) => n.value = value));
    }
    if (a is HasQualities) {
      final q = a as HasQualities;
      final n = ValueNotifier(q.qualities);
      _qualities = n;
      _subs.add(q.qualitiesStream.listen((value) => n.value = value));
    }
    if (a is HasLooping) {
      final l = a as HasLooping;
      final n = ValueNotifier(l.isLooping);
      _looping = n;
      _subs.add(l.loopingStream.listen((value) => n.value = value));
    }
    if (a is HasPictureInPicture) {
      final p = a as HasPictureInPicture;
      final n = ValueNotifier(false);
      _pip = n;
      _subs.add(p.pipStream.listen((value) => n.value = value));
    }
    if (a is HasVideoSize) {
      final s = a as HasVideoSize;
      final n = ValueNotifier(s.videoSize);
      _videoSize = n;
      _subs.add(s.videoSizeStream.listen((value) => n.value = value));
    }
    if (a is HasChapters) {
      final c = a as HasChapters;
      _chapters.value = c.chapters;
      _subs.add(c.chaptersStream.listen((value) {
        _chapters.value = value;
        _syncMarks();
      }));
    }
    if (a is HasBufferedRanges) {
      final b = a as HasBufferedRanges;
      _ranges = ValueNotifier(b.bufferedRanges);
      _subs.add(b.bufferedRangesStream.listen((value) => _ranges!.value = value));
    }
    _bindActions(actions);
    _syncPlayState();
    _syncMarks();
  }

  final VideoPlayerAdapter adapter;
  final LeafControlsPrefs prefs;
  final bool _ownsPrefs;

  /// The top of the volume range (media_kit: 100; mpv amplifies up to 150).
  final double volumeMax;

  /// One wheel notch or arrow key.
  final double volumeStep;

  /// The fixed skip offered without a better one ("Skip 1:30"); off when
  /// null.
  Duration? skipFallback;

  final _subs = <StreamSubscription<Object?>>[];
  LeafPlayerActions _actions;
  Duration _raw = Duration.zero;
  bool _disposed = false;

  /// The position, at most once per `positionInterval`.
  final LeafThrottledPosition position;
  final _positionSeconds = LeafCountedValue<int>(0);
  final _pendingSeek = ValueNotifier<Duration?>(null);
  Timer? _pendingTimer;
  late final ValueNotifier<bool> _playing;
  late final ValueNotifier<Duration> _duration;
  late final ValueNotifier<Duration> _buffered;
  ValueNotifier<List<LeafTimeRange>>? _ranges;
  late final ValueNotifier<bool> _buffering;
  late final ValueNotifier<bool> _completed;
  final _error = ValueNotifier<Object?>(null);
  final _ownPlayState = ValueNotifier(LeafPlayState.paused);
  ValueNotifier<double>? _volume;
  ValueNotifier<double>? _rate;
  ValueNotifier<LeafTracks>? _tracks;
  ValueNotifier<LeafQualities>? _qualities;
  ValueNotifier<bool>? _looping;
  ValueNotifier<bool>? _pip;
  ValueNotifier<Size?>? _videoSize;
  final _chapters = ValueNotifier<List<LeafChapter>>(const []);
  final _currentChapter = ValueNotifier<int?>(null);
  final _skipOffer = ValueNotifier<LeafSkipOffer?>(null);
  ValueListenable<List<LeafSkipSegment>>? _segments;

  final controlsVisible = ValueNotifier(true);
  final _fullscreen = ValueNotifier(false);
  final _fullscreenAvailable = ValueNotifier(false);
  final infoVisible = ValueNotifier(false);
  late final ValueNotifier<LeafTimeFormat> _timeFormat;

  /// The visible bars' heights, for lifting subtitles or toasts.
  final overlayInsets = ValueNotifier(EdgeInsets.zero);
  final _volumeFlash = ValueNotifier(0);
  final _playFlash = ValueNotifier(0);
  final _seekFlash = ValueNotifier<LeafSeekFlash?>(null);
  double _unmutedVolume = 100;

  final _hosts = <LeafControlsHostHandle>[];
  LeafControlsHostHandle? get _host => _hosts.isEmpty ? null : _hosts.last;
  LeafFullscreenHandle? _fullscreenHandle;

  /// Set by a player view disposed while its fullscreen route is still up:
  /// completes once the route (holding the surface) is gone, so the owner
  /// disposes the adapter and this controller only then.
  Future<void>? pendingTeardown;

  /// The media URL, for the info overlay; see [redactedSource].
  String? source;

  LeafPlayerActions get actions => _actions;

  /// Notifies when [updateActions] passes new actions.
  ValueListenable<LeafPlayerActions> get actionsListenable => _actionsNotifier;
  late final _actionsNotifier = ValueNotifier(_actions);

  /// Shown seconds (the pending seek while there is one): labels listen
  /// here, so they rebuild once a second.
  ValueListenable<int> get positionSeconds => _positionSeconds;

  /// A user seek's target, until the player is within 1.5 s of it (dropped
  /// after 2 s otherwise).
  ValueListenable<Duration?> get pendingSeek => _pendingSeek;
  ValueListenable<bool> get playing => _playing;
  ValueListenable<Duration> get duration => _duration;

  /// The end of the cached range ahead.
  ValueListenable<Duration> get buffered => _buffered;

  /// The cached ranges from [HasBufferedRanges]; null without it (then
  /// `[0, buffered]` is all that is known).
  ValueListenable<List<LeafTimeRange>>? get bufferedRanges => _ranges;
  ValueListenable<bool> get buffering => _buffering;
  ValueListenable<bool> get completed => _completed;
  ValueListenable<Object?> get error => _error;
  ValueListenable<LeafPlayState> get playState => _actions.playState ?? _ownPlayState;
  ValueListenable<double>? get volume => _volume;
  ValueListenable<double>? get rate => _rate;
  ValueListenable<LeafTracks>? get tracks => _tracks;
  ValueListenable<LeafQualities>? get qualities => _qualities;
  ValueListenable<bool>? get looping => _looping;
  ValueListenable<bool>? get pip => _pip;
  ValueListenable<Size?>? get videoSize => _videoSize;
  ValueListenable<List<LeafChapter>> get chapters => _chapters;
  ValueListenable<int?> get currentChapter => _currentChapter;
  ValueListenable<LeafSkipOffer?> get skipOffer => _skipOffer;
  ValueListenable<bool> get fullscreen => _fullscreen;

  /// Whether a fullscreen handler is attached and can act.
  ValueListenable<bool> get fullscreenAvailable => _fullscreenAvailable;
  ValueListenable<LeafTimeFormat> get timeFormat => _timeFormat;

  /// Ticks on each key, wheel or swipe volume step.
  ValueListenable<int> get volumeFlash => _volumeFlash;

  /// Ticks on each user play/pause toggle (the pause indicator).
  ValueListenable<int> get playFlash => _playFlash;

  /// The running seek-by sum ("+20 s"), null once it has faded.
  ValueListenable<LeafSeekFlash?> get seekFlash => _seekFlash;

  /// The raw position (no throttle).
  Duration get rawPosition => _raw;

  /// The position the UI shows: the pending seek while there is one.
  Duration get shownPosition => _pendingSeek.value ?? _raw;

  /// Listeners on [position] and [positionSeconds]; zero while hidden.
  int get debugPositionListeners => position.listenerCount + _positionSeconds.listenerCount;

  bool get hasVolume => _volume != null;

  /// [source] with only the host and the file name: tokens live in query
  /// strings and paths of Jellyfin-style URLs.
  String? get redactedSource {
    final s = source;
    if (s == null) return null;
    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    final name = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    if (uri.host.isEmpty) return name.isEmpty ? null : name;
    return name.isEmpty ? uri.host : '${uri.host}/…/$name';
  }

  void updateActions(LeafPlayerActions actions) {
    if (identical(actions, _actions)) return;
    _unbindActions();
    _actions = actions;
    _bindActions(actions);
    _actionsNotifier.value = actions;
    _syncMarks();
  }

  void _bindActions(LeafPlayerActions actions) {
    _segments = actions.segments?..addListener(_syncMarks);
  }

  void _unbindActions() {
    _segments?.removeListener(_syncMarks);
    _segments = null;
  }

  void _onPrefs() {
    _timeFormat.value = prefs.timeFormat;
  }

  void _onPosition(Duration p) {
    _raw = p;
    final pending = _pendingSeek.value;
    if (pending != null && (p - pending).abs() < const Duration(milliseconds: 1500)) _clearPending();
    position.push(p);
    _positionSeconds.value = shownPosition.inSeconds;
    if (_buffering.value && adapter is! HasPlaybackStatus && p > Duration.zero) _buffering.value = false;
    _pollDuration();
    _syncMarks();
    if (adapter is! HasPlaybackStatus) _syncCompleted();
  }

  void _onBuffer(Duration b) {
    _buffered.value = b;
    _pollDuration();
  }

  void _onPlaying(bool playing) {
    _playing.value = playing;
    position.flush();
    _pollDuration();
    if (adapter is! HasPlaybackStatus) _syncCompleted();
    _syncPlayState();
  }

  void _onReady(void _) {
    _error.value = null;
    if (adapter is! HasPlaybackStatus) _buffering.value = false;
    _pollDuration();
  }

  void _onError(Object error) => _error.value = error;

  void _pollDuration() {
    if (adapter is HasPlaybackStatus) return;
    _duration.value = adapter.duration;
  }

  void _syncCompleted() {
    final d = _duration.value;
    _completed.value = !_playing.value && d > Duration.zero && _raw >= d - const Duration(milliseconds: 300);
    _syncPlayState();
  }

  void _syncPlayState() {
    _ownPlayState.value = _completed.value
        ? LeafPlayState.ended
        : (_playing.value ? LeafPlayState.playing : LeafPlayState.paused);
  }

  void _syncMarks() {
    if (_disposed) return;
    final at = shownPosition;
    final chapters = _chapters.value;
    _currentChapter.value = chapters.isEmpty ? null : chapterIndexAt(chapters, at);
    _skipOffer.value = skipOfferAt(
      position: at,
      duration: _duration.value,
      segments: _segments?.value ?? const [],
      chapters: chapters,
      fallback: skipFallback,
    );
  }

  void _setPending(Duration target) {
    _pendingSeek.value = target;
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(seconds: 2), _clearPending);
    _positionSeconds.value = target.inSeconds;
    position.flush();
  }

  void _clearPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    if (_pendingSeek.value == null) return;
    _pendingSeek.value = null;
    _positionSeconds.value = _raw.inSeconds;
  }

  // ── Attach points ──────────────────────────────────────────────────────

  /// The newest attached host (the fullscreen route's over the inline one)
  /// gets the UI commands.
  void attachControls(LeafControlsHostHandle host) {
    _hosts
      ..remove(host)
      ..add(host);
  }

  void detachControls(LeafControlsHostHandle host) => _hosts.remove(host);

  /// The fullscreen performer; it reports state through [setFullscreen].
  void attachFullscreen(LeafFullscreenHandle handle) {
    if (_disposed) return;
    _fullscreenHandle = handle;
    _fullscreenAvailable.value = handle.canFullscreen;
  }

  void detachFullscreen(LeafFullscreenHandle handle) {
    if (_disposed || !identical(_fullscreenHandle, handle)) return;
    _fullscreenHandle = null;
    _fullscreenAvailable.value = false;
  }

  /// Called by the fullscreen performer.
  void setFullscreen(bool on) {
    if (!_disposed) _fullscreen.value = on;
  }

  /// Re-reads [LeafFullscreenHandle.canFullscreen].
  void refreshFullscreenAvailable() {
    if (!_disposed) _fullscreenAvailable.value = _fullscreenHandle?.canFullscreen ?? false;
  }

  // ── Commands ───────────────────────────────────────────────────────────

  /// Runs [command]; false when nothing handled it (keys then bubble).
  bool execute(LeafPlayerCommand command) {
    if (_disposed) return false;
    switch (command) {
      case LeafTogglePlay():
        togglePlay();
      case LeafPlay():
        _playFlash.value++;
        adapter.play();
      case LeafPause():
        _playFlash.value++;
        adapter.pause();
      case LeafSeekTo(:final target):
        seek(target);
      case LeafSeekBy(:final delta):
        seekBy(delta);
      case LeafSeekToFraction(:final fraction):
        final d = _duration.value;
        if (d <= Duration.zero) return false;
        seek(d * fraction.clamp(0.0, 1.0));
      case LeafStepChapter(:final delta):
        return stepChapter(delta);
      case LeafSeekToChapter(:final index):
        final chapters = _chapters.value;
        if (index < 0 || index >= chapters.length) return false;
        seek(chapters[index].start);
      case LeafSkip():
        return skip();
      case LeafStepVolume(:final steps):
        return stepVolume(steps);
      case LeafSetVolume(volume: final v):
        if (!hasVolume) return false;
        (adapter as HasVolume).setVolume(v.clamp(0.0, volumeMax));
      case LeafToggleMute():
        return toggleMute();
      case LeafSetRate(:final rate):
        return setRate(rate);
      case LeafStepRate(:final delta):
        final r = _rate;
        if (r == null) return false;
        return setRate(((r.value + delta) * 4).round() / 4);
      case LeafResetRate():
        return setRate(1.0);
      case LeafSelectTrack(:final kind, :final id):
        return selectTrack(kind, id);
      case LeafCycleTrack(:final kind, :final includeOff):
        return cycleTrack(kind, includeOff: includeOff);
      case LeafSelectQuality(:final id):
        if (adapter is! HasQualities) return false;
        (adapter as HasQualities).selectQuality(id);
      case LeafToggleLoop():
        final l = _looping;
        if (l == null) return false;
        (adapter as HasLooping).setLooping(!l.value);
      case LeafTogglePip():
        if (adapter is! HasPictureInPicture) return false;
        final p = adapter as HasPictureInPicture;
        if (!p.isPipAvailable) return false;
        unawaited(p.enterPip());
      case LeafToggleFullscreen():
        return toggleFullscreen();
      case LeafEnterFullscreen():
        final h = _fullscreenHandle;
        if (h == null || _fullscreen.value || !h.canFullscreen) return false;
        h.enterFullscreen();
      case LeafExitFullscreen():
        final h = _fullscreenHandle;
        if (h == null || !_fullscreen.value) return false;
        h.exitFullscreen();
      case LeafToggleInfo():
        infoVisible.value = !infoVisible.value;
      case LeafCycleTimeFormat():
        prefs.timeFormat = prefs.timeFormat == LeafTimeFormat.remaining ? LeafTimeFormat.elapsedTotal : LeafTimeFormat.remaining;
      case LeafDismiss():
        if (_host?.handleUiCommand(command) ?? false) return true;
        if (infoVisible.value) {
          infoVisible.value = false;
          return true;
        }
        return execute(const LeafPlayerCommand.exitFullscreen());
      case LeafNext():
        final next = _actions.onNext;
        if (next != null) {
          next();
          return true;
        }
        return _host?.handleUiCommand(command) ?? false;
      case LeafPrevious():
        final previous = _actions.onPrevious;
        if (previous != null) {
          previous();
          return true;
        }
        return _host?.handleUiCommand(command) ?? false;
      case LeafBack():
        final back = _actions.onBack;
        if (back != null) {
          back();
          return true;
        }
        return execute(const LeafPlayerCommand.exitFullscreen());
      case LeafOpenMenu() || LeafToggleControls() || LeafShowControls():
        return _host?.handleUiCommand(command) ?? false;
      case LeafCustomCommand(:final run):
        run();
    }
    return true;
  }

  /// Play/pause (↻ from the start once ended), or the app's own toggle.
  void togglePlay() {
    _playFlash.value++;
    final own = _actions.onTogglePlay;
    if (own != null) {
      own();
      return;
    }
    if (_completed.value) {
      seek(Duration.zero);
      adapter.play();
      return;
    }
    adapter.playOrPause();
  }

  /// A user seek: clamped, shown at once (pending), routed through
  /// [LeafPlayerActions.onSeek] when the app takes seeks.
  void seek(Duration target) {
    final d = _duration.value;
    var t = target < Duration.zero ? Duration.zero : target;
    if (d > Duration.zero && t > d) t = d;
    _setPending(t);
    _syncMarks();
    final own = _actions.onSeek;
    if (own != null) {
      own(t);
    } else {
      adapter.seek(t);
    }
  }

  /// Seeks [delta] from the shown position, so repeated steps add up.
  void seekBy(Duration delta) => seek(shownPosition + delta);

  /// Shows "+20 s" style feedback while steps in one direction keep coming
  /// (double-tap, keys), then fades it.
  void flashSeek(Duration step) {
    final current = _seekFlash.value;
    final same = current != null && current.total.isNegative == step.isNegative && current.total != Duration.zero;
    _seekFlash.value = LeafSeekFlash(same ? current.total + step : step, (current?.serial ?? 0) + 1);
    _seekFlashTimer?.cancel();
    _seekFlashTimer = Timer(const Duration(milliseconds: 700), () => _seekFlash.value = null);
  }

  Timer? _seekFlashTimer;

  bool stepChapter(int delta) {
    final target = chapterStepTarget(_chapters.value, shownPosition, delta);
    if (target == null) return false;
    seek(target);
    return true;
  }

  bool skip() {
    final offer = _skipOffer.value;
    if (offer == null) return false;
    seek(offer.fixed ? shownPosition + (skipFallback ?? Duration.zero) : offer.target);
    return true;
  }

  bool stepVolume(int steps) {
    final v = _volume;
    if (v == null || steps == 0) return false;
    (adapter as HasVolume).setVolume((v.value + steps * volumeStep).clamp(0.0, volumeMax));
    _volumeFlash.value++;
    return true;
  }

  /// Mutes, or restores the level from before muting.
  bool toggleMute() {
    final v = _volume;
    if (v == null) return false;
    final a = adapter as HasVolume;
    if (v.value > 0) {
      _unmutedVolume = v.value;
      a.setVolume(0);
    } else {
      a.setVolume(_unmutedVolume > 0 ? _unmutedVolume.clamp(0.0, volumeMax) : volumeMax);
    }
    _volumeFlash.value++;
    return true;
  }

  bool setRate(double rate) {
    if (adapter is! HasPlaybackRate) return false;
    (adapter as HasPlaybackRate).setRate(rate.clamp(0.25, 4.0));
    return true;
  }

  bool selectTrack(LeafTrackKind kind, String? id) {
    if (adapter is! HasTracks) return false;
    (adapter as HasTracks).selectTrack(kind, id);
    return true;
  }

  /// The next track of [kind] after the selected one, through off when
  /// [includeOff].
  bool cycleTrack(LeafTrackKind kind, {bool includeOff = true}) {
    final t = _tracks;
    if (t == null) return false;
    final ids = <String?>[if (includeOff) null, for (final track in t.value.of(kind)) track.id];
    if (ids.length < 2) return false;
    final at = ids.indexOf(t.value.selected(kind));
    return selectTrack(kind, ids[(at + 1) % ids.length]);
  }

  bool toggleFullscreen() => execute(
    _fullscreen.value ? const LeafPlayerCommand.exitFullscreen() : const LeafPlayerCommand.enterFullscreen(),
  );

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final s in _subs) {
      s.cancel();
    }
    _unbindActions();
    prefs.removeListener(_onPrefs);
    if (_ownsPrefs) prefs.dispose();
    _pendingTimer?.cancel();
    _seekFlashTimer?.cancel();
    position.dispose();
    _positionSeconds.dispose();
    for (final n in <ChangeNotifier?>[
      _pendingSeek,
      _playing,
      _duration,
      _buffered,
      _ranges,
      _buffering,
      _completed,
      _error,
      _ownPlayState,
      _volume,
      _rate,
      _tracks,
      _qualities,
      _looping,
      _pip,
      _videoSize,
      _chapters,
      _currentChapter,
      _skipOffer,
      controlsVisible,
      _fullscreen,
      _fullscreenAvailable,
      infoVisible,
      _timeFormat,
      overlayInsets,
      _volumeFlash,
      _playFlash,
      _seekFlash,
      _actionsNotifier,
    ]) {
      n?.dispose();
    }
  }
}
