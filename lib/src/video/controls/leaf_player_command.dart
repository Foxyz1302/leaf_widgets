import 'package:flutter/foundation.dart';

import '../leaf_video_capabilities.dart';

/// Everything a button, key or gesture can ask of the player, dispatched
/// through `LeafPlayerController.execute`. Value equality, so keymaps can
/// be compared and edited.
@immutable
sealed class LeafPlayerCommand {
  const LeafPlayerCommand();

  const factory LeafPlayerCommand.togglePlay() = LeafTogglePlay;
  const factory LeafPlayerCommand.play() = LeafPlay;
  const factory LeafPlayerCommand.pause() = LeafPause;
  const factory LeafPlayerCommand.seekTo(Duration target) = LeafSeekTo;
  const factory LeafPlayerCommand.seekBy(Duration delta) = LeafSeekBy;
  const factory LeafPlayerCommand.seekToFraction(double fraction) = LeafSeekToFraction;
  const factory LeafPlayerCommand.stepChapter(int delta) = LeafStepChapter;
  const factory LeafPlayerCommand.seekToChapter(int index) = LeafSeekToChapter;
  const factory LeafPlayerCommand.skip() = LeafSkip;
  const factory LeafPlayerCommand.stepVolume(int steps) = LeafStepVolume;
  const factory LeafPlayerCommand.setVolume(double volume) = LeafSetVolume;
  const factory LeafPlayerCommand.toggleMute() = LeafToggleMute;
  const factory LeafPlayerCommand.setRate(double rate) = LeafSetRate;
  const factory LeafPlayerCommand.stepRate(double delta) = LeafStepRate;
  const factory LeafPlayerCommand.resetRate() = LeafResetRate;
  const factory LeafPlayerCommand.selectTrack(LeafTrackKind kind, String? id) = LeafSelectTrack;
  const factory LeafPlayerCommand.cycleTrack(LeafTrackKind kind, {bool includeOff}) = LeafCycleTrack;
  const factory LeafPlayerCommand.selectQuality(String id) = LeafSelectQuality;
  const factory LeafPlayerCommand.toggleLoop() = LeafToggleLoop;
  const factory LeafPlayerCommand.togglePip() = LeafTogglePip;
  const factory LeafPlayerCommand.toggleFullscreen() = LeafToggleFullscreen;
  const factory LeafPlayerCommand.enterFullscreen() = LeafEnterFullscreen;
  const factory LeafPlayerCommand.exitFullscreen() = LeafExitFullscreen;
  const factory LeafPlayerCommand.toggleInfo() = LeafToggleInfo;
  const factory LeafPlayerCommand.cycleTimeFormat() = LeafCycleTimeFormat;
  const factory LeafPlayerCommand.openMenu(String controlId) = LeafOpenMenu;
  const factory LeafPlayerCommand.toggleControls() = LeafToggleControls;
  const factory LeafPlayerCommand.showControls() = LeafShowControls;

  /// Esc: closes the topmost menu, then the panel, then the info overlay,
  /// then leaves fullscreen; unhandled when there is nothing to close.
  const factory LeafPlayerCommand.dismiss() = LeafDismiss;
  const factory LeafPlayerCommand.next() = LeafNext;
  const factory LeafPlayerCommand.previous() = LeafPrevious;
  const factory LeafPlayerCommand.back() = LeafBack;

  /// An app action; equal by [id] only.
  const factory LeafPlayerCommand.custom(String id, VoidCallback run) = LeafCustomCommand;
}

sealed class _Unit extends LeafPlayerCommand {
  const _Unit();

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => '$runtimeType';
}

final class LeafTogglePlay extends _Unit {
  const LeafTogglePlay();
}

final class LeafPlay extends _Unit {
  const LeafPlay();
}

final class LeafPause extends _Unit {
  const LeafPause();
}

final class LeafSkip extends _Unit {
  const LeafSkip();
}

final class LeafToggleMute extends _Unit {
  const LeafToggleMute();
}

final class LeafResetRate extends _Unit {
  const LeafResetRate();
}

final class LeafToggleLoop extends _Unit {
  const LeafToggleLoop();
}

final class LeafTogglePip extends _Unit {
  const LeafTogglePip();
}

final class LeafToggleFullscreen extends _Unit {
  const LeafToggleFullscreen();
}

final class LeafEnterFullscreen extends _Unit {
  const LeafEnterFullscreen();
}

final class LeafExitFullscreen extends _Unit {
  const LeafExitFullscreen();
}

final class LeafToggleInfo extends _Unit {
  const LeafToggleInfo();
}

final class LeafCycleTimeFormat extends _Unit {
  const LeafCycleTimeFormat();
}

final class LeafToggleControls extends _Unit {
  const LeafToggleControls();
}

final class LeafShowControls extends _Unit {
  const LeafShowControls();
}

final class LeafDismiss extends _Unit {
  const LeafDismiss();
}

final class LeafNext extends _Unit {
  const LeafNext();
}

final class LeafPrevious extends _Unit {
  const LeafPrevious();
}

final class LeafBack extends _Unit {
  const LeafBack();
}

sealed class _Valued<T> extends LeafPlayerCommand {
  const _Valued(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other.runtimeType == runtimeType && other is _Valued<T> && other.value == value;

  @override
  int get hashCode => Object.hash(runtimeType, value);

  @override
  String toString() => '$runtimeType($value)';
}

final class LeafSeekTo extends _Valued<Duration> {
  const LeafSeekTo(super.value);

  Duration get target => value;
}

final class LeafSeekBy extends _Valued<Duration> {
  const LeafSeekBy(super.value);

  Duration get delta => value;
}

final class LeafSeekToFraction extends _Valued<double> {
  const LeafSeekToFraction(super.value);

  double get fraction => value;
}

final class LeafStepChapter extends _Valued<int> {
  const LeafStepChapter(super.value);

  int get delta => value;
}

final class LeafSeekToChapter extends _Valued<int> {
  const LeafSeekToChapter(super.value);

  int get index => value;
}

final class LeafStepVolume extends _Valued<int> {
  const LeafStepVolume(super.value);

  int get steps => value;
}

final class LeafSetVolume extends _Valued<double> {
  const LeafSetVolume(super.value);

  double get volume => value;
}

final class LeafSetRate extends _Valued<double> {
  const LeafSetRate(super.value);

  double get rate => value;
}

final class LeafStepRate extends _Valued<double> {
  const LeafStepRate(super.value);

  double get delta => value;
}

final class LeafSelectQuality extends _Valued<String> {
  const LeafSelectQuality(super.value);

  String get id => value;
}

final class LeafOpenMenu extends _Valued<String> {
  const LeafOpenMenu(super.value);

  String get controlId => value;
}

final class LeafSelectTrack extends LeafPlayerCommand {
  const LeafSelectTrack(this.kind, this.id);

  final LeafTrackKind kind;
  final String? id;

  @override
  bool operator ==(Object other) => other is LeafSelectTrack && other.kind == kind && other.id == id;

  @override
  int get hashCode => Object.hash(kind, id);

  @override
  String toString() => 'LeafSelectTrack(${kind.name}, $id)';
}

final class LeafCycleTrack extends LeafPlayerCommand {
  const LeafCycleTrack(this.kind, {this.includeOff = true});

  final LeafTrackKind kind;
  final bool includeOff;

  @override
  bool operator ==(Object other) => other is LeafCycleTrack && other.kind == kind && other.includeOff == includeOff;

  @override
  int get hashCode => Object.hash(kind, includeOff);

  @override
  String toString() => 'LeafCycleTrack(${kind.name}, includeOff: $includeOff)';
}

final class LeafCustomCommand extends LeafPlayerCommand {
  const LeafCustomCommand(this.id, this.run);

  final String id;
  final VoidCallback run;

  @override
  bool operator ==(Object other) => other is LeafCustomCommand && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'LeafCustomCommand($id)';
}
