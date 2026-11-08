import 'package:flutter/material.dart';

import '../leaf_controls_theme.dart';
import '../leaf_player_controller.dart';
import 'leaf_control.dart';

/// "−10 s" / "+20 s" bubbles on the side being seeked (double-tap, the
/// seek buttons), summing while the steps keep coming.
class LeafSeekFeedbackControl extends LeafControl {
  const LeafSeekFeedbackControl();

  @override
  String get id => 'seekFeedback';

  @override
  bool get persistent => true;

  @override
  double? estimatedWidth(LeafControlsTheme t) => 0;

  @override
  Widget build(BuildContext context, LeafControlContext c) => IgnorePointer(
    child: ValueListenableBuilder<LeafSeekFlash?>(
      valueListenable: c.controller.seekFlash,
      builder: (context, flash, _) {
        if (flash == null) return const SizedBox.shrink();
        final back = flash.total.isNegative;
        final t = c.theme;
        return Align(
          alignment: Alignment(back ? -0.6 : 0.6, 0),
          child: Container(
            key: const ValueKey('leaf-seek-feedback'),
            padding: EdgeInsets.symmetric(horizontal: 14 * t.scale, vertical: 8 * t.scale),
            decoration: BoxDecoration(color: const Color(0x8A000000), borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(back ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded, color: t.foreground, size: 20 * t.scale),
                SizedBox(width: 6 * t.scale),
                Text('${back ? '−' : '+'}${flash.total.inSeconds.abs()} s', style: t.labelStyle),
              ],
            ),
          ),
        );
      },
    ),
  );
}
