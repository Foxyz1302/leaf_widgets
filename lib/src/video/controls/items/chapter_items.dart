import 'package:flutter/material.dart';

import '../leaf_player_command.dart';
import '../leaf_player_controller.dart';
import 'leaf_control.dart';

/// Previous / next chapter (PgDn / PgUp, mpv's 5 s back rule); shown only
/// when the media has chapters.
class LeafChapterStepControl extends LeafControl {
  const LeafChapterStepControl.previous() : forward = false;
  const LeafChapterStepControl.next() : forward = true;

  final bool forward;

  @override
  String get id => forward ? 'chapterNext' : 'chapterPrevious';

  @override
  int get priority => 20;

  @override
  Iterable<Listenable> availabilityDeps(LeafPlayerController c) => [c.chapters];

  @override
  bool isAvailable(LeafControlContext c) => c.controller.chapters.value.isNotEmpty;

  @override
  Widget build(BuildContext context, LeafControlContext c) {
    final command = LeafPlayerCommand.stepChapter(forward ? 1 : -1);
    return LeafControlButton(
      key: ValueKey('leaf-control-$id'),
      icon: forward ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
      tooltip: c.tip(forward ? 'Next chapter' : 'Previous chapter', command),
      onPressed: () => c.controller.execute(command),
    );
  }
}
