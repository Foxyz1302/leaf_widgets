import 'dart:async';

import 'package:flutter/material.dart';

/// Status of the async task shown by [LeafAsyncChip].
enum LeafAsyncStatus { idle, running, done, error }

/// Overlay chip that reports the progress and result of an async task.
///
/// Trigger the task imperatively via `GlobalKey<LeafAsyncChipState>` and
/// `LeafAsyncChipState.run()`. While the task runs a spinner pill is shown
/// over [child] (determinate when the task reports progress, indeterminate
/// otherwise); on success it pops into a check + [doneLabel] pill that
/// auto-resets after [doneDuration]; on failure it shows an error pill for
/// [errorDuration], logs the error, and forwards it to [onError].
class LeafAsyncChip extends StatefulWidget {
  /// The widget the overlay renders on top of.
  final Widget child;

  /// Label shown next to the spinner while the task runs.
  final String runningLabel;

  /// Label shown next to the check when the task completes. Can be overridden
  /// per-run via [LeafAsyncChipState.run].
  final String doneLabel;

  /// Label shown when the task throws.
  final String errorLabel;

  /// How long the success pill stays visible before resetting to idle.
  final Duration doneDuration;

  /// How long the error pill stays visible before resetting to idle.
  final Duration errorDuration;

  /// Called with the task's error + stack trace when it throws. The error is
  /// always debugPrinted regardless.
  final void Function(Object error, StackTrace stackTrace)? onError;

  const LeafAsyncChip({
    super.key,
    required this.child,
    this.runningLabel = 'Working…',
    this.doneLabel = 'Done',
    this.errorLabel = 'Failed',
    this.doneDuration = const Duration(milliseconds: 1200),
    this.errorDuration = const Duration(milliseconds: 3000),
    this.onError,
  });

  @override
  State<LeafAsyncChip> createState() => LeafAsyncChipState();
}

class LeafAsyncChipState extends State<LeafAsyncChip> {
  LeafAsyncStatus _status = LeafAsyncStatus.idle;
  double? _progress;
  String _doneLabel = '';
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Runs [task], showing the running → done/error overlay. Ignores the call
  /// while a task is already running. [doneLabel] overrides the widget's
  /// default label for this run; [resultLabel] turns the task's result into
  /// the label instead ("12 moved"), when it returns a non-empty string.
  Future<void> run<T>({
    required Future<T> Function(ValueChanged<double>? onProgress) task,
    String? doneLabel,
    String? Function(T result)? resultLabel,
  }) async {
    if (_status == LeafAsyncStatus.running) return;
    _timer?.cancel();
    setState(() {
      _status = LeafAsyncStatus.running;
      _progress = null;
      _doneLabel = doneLabel ?? widget.doneLabel;
    });
    try {
      final result = await task((p) {
        if (mounted) setState(() => _progress = p.clamp(0.0, 1.0));
      });
      if (!mounted) return;
      setState(() {
        _status = LeafAsyncStatus.done;
        if (resultLabel?.call(result) case final label? when label.isNotEmpty) _doneLabel = label;
      });
      _timer = Timer(widget.doneDuration, _reset);
    } catch (e, st) {
      debugPrint('LeafAsyncChip: task failed: $e\n$st');
      if (!mounted) return;
      setState(() => _status = LeafAsyncStatus.error);
      _timer = Timer(widget.errorDuration, _reset);
      widget.onError?.call(e, st);
    }
  }

  void _reset() {
    if (mounted) setState(() => _status = LeafAsyncStatus.idle);
  }

  @override
  Widget build(BuildContext context) {
    // The pill floats over the child without taking part in layout: a label wider than the child (a small button)
    // overflows it instead of resizing it and nudging the surrounding layout.
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (_status != LeafAsyncStatus.idle)
          Positioned.fill(
            child: IgnorePointer(
              child: OverflowBox(
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(
                      scale: Tween<double>(
                        begin: 0.6,
                        end: 1.0,
                      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
                      child: child,
                    ),
                  ),
                  child: _Pill(key: ValueKey(_status), status: _status, progress: _progress, label: _label),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String get _label => switch (_status) {
    LeafAsyncStatus.running => widget.runningLabel,
    LeafAsyncStatus.done => _doneLabel,
    LeafAsyncStatus.error => widget.errorLabel,
    LeafAsyncStatus.idle => '',
  };
}

class _Pill extends StatelessWidget {
  final LeafAsyncStatus status;
  final double? progress;
  final String label;

  const _Pill({super.key, required this.status, required this.progress, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          switch (status) {
            LeafAsyncStatus.running => SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, value: progress, color: Colors.white),
            ),
            LeafAsyncStatus.done => const Icon(Icons.check, size: 16, color: Color(0xFF7CF29C)),
            LeafAsyncStatus.error => const Icon(Icons.error_outline, size: 16, color: Color(0xFFFF6B6B)),
            LeafAsyncStatus.idle => const SizedBox.shrink(),
          },
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
