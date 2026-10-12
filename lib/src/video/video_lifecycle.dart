import 'package:flutter/widgets.dart';

/// Pauses a playing child when the app backgrounds or the route is covered
/// (pushed route, dialog, sheet, menu), and asks to resume when it returns.
///
/// Player-agnostic: drives plain callbacks, so custom viewers that don't use
/// [LeafVideoPage] can share the policy. Cover detection uses
/// [ModalRoute.isCurrent] (no [RouteObserver] setup needed); background uses
/// [AppLifecycleState.paused] and [AppLifecycleState.hidden].
/// Callbacks fire post-frame, so they may call `setState` on ancestors.
class VideoLifecycleGuard extends StatefulWidget {
  const VideoLifecycleGuard({
    super.key,
    required this.child,
    required this.isPlaying,
    this.onPause,
    this.onResume,
  });

  final Widget child;

  /// Current playing state. The guard only pauses (and later resumes) while
  /// this is true; an idle child gets no calls.
  final bool isPlaying;

  /// Called once when coverage/background starts while [isPlaying].
  final VoidCallback? onPause;

  /// Called once when fully uncovered/returned, and only if [onPause] fired.
  /// May be left null for pause-only consumers (play stays a tap away).
  final VoidCallback? onResume;

  @override
  State<VideoLifecycleGuard> createState() => _VideoLifecycleGuardState();
}

class _VideoLifecycleGuardState extends State<VideoLifecycleGuard> with WidgetsBindingObserver {
  bool _covered = false;
  bool _backgrounded = false;
  bool _holding = false;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _setCovered(route != null && !route.isCurrent);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _backgrounded = state == AppLifecycleState.paused || state == AppLifecycleState.hidden;
    _evaluate();
  }

  void _setCovered(bool covered) {
    if (_covered == covered) return;
    _covered = covered;
    _evaluate();
  }

  void _evaluate() {
    final held = _covered || _backgrounded;
    if (held == _holding) return;
    _holding = held;
    if (held) {
      if (widget.isPlaying) {
        _wasPlaying = true;
        _deliver(widget.onPause);
      }
    } else if (_wasPlaying) {
      _wasPlaying = false;
      _deliver(widget.onResume);
    }
  }

  void _deliver(VoidCallback? callback) {
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
