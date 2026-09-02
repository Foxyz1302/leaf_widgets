import 'package:flutter/widgets.dart';

/// Player-agnostic contract between [LeafVideoPage]/[LeafVideoControls] and
/// whichever player the host app wires in (a Media3 wrapper, media_kit, ...).
/// This is the only seam that knows a player exists; implementations live
/// app-side so the package stays dependency-free.
abstract class VideoPlayerAdapter {
  /// The player's rendering surface, inserted into the page's stack.
  Widget get surface;

  /// Loads [url]. Completes when the player may start playback; throws on
  /// load failure. Safe to call before the surface is laid out.
  Future<void> load({required String url, Map<String, String>? headers});

  Stream<Duration> get positionStream;
  Stream<Duration> get bufferStream;
  Stream<bool> get playingStream;

  /// Fires when the first frame is actually rendered — the safe signal to
  /// drop the thumbnail (a `loaded` state is not; it precedes the first
  /// frame and produces a black flash).
  Stream<void> get readyStream;

  /// Fires on playback errors after a successful [load].
  Stream<Object> get errorStream;

  Duration get position;
  Duration get duration;
  Duration get buffer;
  bool get isPlaying;

  void play();
  void pause();
  void playOrPause();
  void seek(Duration target);

  /// Releases the underlying player. The adapter is unusable afterwards.
  void dispose();
}
