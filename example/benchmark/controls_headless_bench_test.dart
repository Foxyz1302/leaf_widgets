import 'package:example/bench/bench_video_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leaf_widgets/leaf_widgets.dart';
// ignore: implementation_imports
import 'package:leaf_widgets/src/video/controls/items/seek_bar.dart' show RenderLeafSeekBar;

import 'bench_probe.dart';

const _presets = {
  'mobile': LeafControlsSpec.mobile,
  'desktop': LeafControlsSpec.desktop,
  'uosc': LeafControlsSpec.uosc,
  'minimal': LeafControlsSpec.minimal,
};

class _Fs implements LeafFullscreenHandle {
  @override
  bool get canFullscreen => true;
  @override
  void enterFullscreen() {}
  @override
  void exitFullscreen() {}
}

int _seekBarPaints(WidgetTester tester) => RenderLeafSeekBar.debugTotalPaints;

Future<void> _settle(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  fullscreenCycleBench();
  for (final MapEntry(key: name, value: spec) in _presets.entries) {
    testWidgets('kit-playing-$name: hidden and visible, position at 30 Hz', (tester) async {
      final desktop = name == 'desktop' || name == 'uosc';
      debugDefaultTargetPlatformOverride = desktop ? TargetPlatform.linux : TargetPlatform.android;
      tester.view.physicalSize = desktop ? const Size(1920, 1080) : const Size(1080, 2400);
      tester.view.devicePixelRatio = desktop ? 1.0 : 3.0;
      final adapter = BenchKitAdapter(seed: 1);
      final controller = LeafPlayerController(adapter, actions: const LeafPlayerActions(title: 'Bench'))..attachFullscreen(_Fs());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(fit: StackFit.expand, children: [adapter.surface, LeafPlayerControls(controller: controller, spec: spec)]),
          ),
        ),
      );
      await tester.runAsync(() => adapter.load(url: 'bench://kit'));
      adapter.play();
      await tester.pump(const Duration(milliseconds: 500));

      final probe = BenchProbe()..install();
      var clockRebuilds = 0;
      probe.onRebuild = (e) {
        if (e.widget is ValueListenableBuilder<int>) clockRebuilds++;
      };
      Future<Map<String, Object>> measure() async {
        const slots = 125;
        var wanted = 0, ticking = 0;
        probe.layoutsBy.clear();
        probe.paintsBy.clear();
        final r = probe.rebuilds, l = probe.layouts, p = probe.paints, sp = _seekBarPaints(tester);
        clockRebuilds = 0;
        for (var i = 0; i < slots; i++) {
          await tester.binding.delayed(const Duration(milliseconds: 16));
          if (tester.binding.hasScheduledFrame) wanted++;
          await tester.pump();
          if (SchedulerBinding.instance.transientCallbackCount > 0) ticking++;
        }
        final secs = slots * 0.016;
        return {
          'framesWantedPerSecond': (wanted / secs).round(),
          'tickingFrames': ticking,
          'rebuildsPerFrame': double.parse(((probe.rebuilds - r) / slots).toStringAsFixed(2)),
          'layoutsPerFrame': double.parse(((probe.layouts - l) / slots).toStringAsFixed(2)),
          'paintsPerFrame': double.parse(((probe.paints - p) / slots).toStringAsFixed(2)),
          'seekBarPaintsPerSecond': ((_seekBarPaints(tester) - sp) / secs).round(),
          'clockRebuildsPerSecond': (clockRebuilds / secs).round(),
          'positionListeners': controller.debugPositionListeners,
          'layoutsBy': {...probe.layoutsBy},
          'paintsBy': {...probe.paintsBy},
        };
      }

      try {
        await _settle(tester, 4000);
        final hiddenOk = !controller.controlsVisible.value;
        final hidden = await measure();
        controller.execute(const LeafPlayerCommand.showControls());
        await _settle(tester, 300);
        final visible = await measure();
        benchReport('kit-playing-$name-hidden', {'hidden': hiddenOk, ...hidden});
        benchReport('kit-playing-$name-visible', visible);
        benchReport('kit-layers-$name', benchLayerCounts(tester.binding.renderViews.first.debugLayer!));
        expect(hiddenOk, isTrue);
        expect(hidden['tickingFrames'], 0);
        expect(hidden['positionListeners'], lessThanOrEqualTo(1));
        expect(visible['tickingFrames'], 0);
        expect(visible['clockRebuildsPerSecond'] as int, lessThanOrEqualTo(2));
        expect(visible['seekBarPaintsPerSecond'] as int, lessThanOrEqualTo(11));
      } finally {
        probe.uninstall();
        adapter.pause();
        await tester.pumpWidget(const SizedBox.shrink());
        controller.dispose();
        adapter.dispose();
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

class _CountingSurface extends StatefulWidget {
  const _CountingSurface(this.child);

  static int inits = 0;
  final Widget child;

  @override
  State<_CountingSurface> createState() => _CountingSurfaceState();
}

class _CountingSurfaceState extends State<_CountingSurface> {
  @override
  void initState() {
    super.initState();
    _CountingSurface.inits++;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SurfaceKitAdapter extends BenchKitAdapter {
  _SurfaceKitAdapter() : super(seed: 3);

  @override
  Widget get surface => _CountingSurface(super.surface);
}

void fullscreenCycleBench() {
  testWidgets('kit-fullscreen-cycle: 10 route cycles move the surface, nothing reloads', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    BenchCounters.reset();
    _CountingSurface.inits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: SizedBox(
              width: 960,
              height: 540,
              child: Builder(
                builder: (context) {
                  BenchCounters.pageBuilds++;
                  return LeafVideoPage(createAdapter: _SurfaceKitAdapter.new, url: 'bench://fs', controls: LeafControlsSpec.uosc);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await _settle(tester, 4000);
    final controller = tester.widget<LeafPlayerControls>(find.byType(LeafPlayerControls)).controller;
    var entered = 0;
    void onFullscreen() {
      if (controller.fullscreen.value) entered++;
    }

    controller.fullscreen.addListener(onFullscreen);
    final before = {...BenchCounters.snapshot(), 'surfaceInits': _CountingSurface.inits};
    final layersBefore = benchLayerCounts(tester.binding.renderViews.first.debugLayer!);
    for (var i = 0; i < 10; i++) {
      controller.execute(const LeafPlayerCommand.enterFullscreen());
      await _settle(tester, 200);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester, 200);
    }
    controller.fullscreen.removeListener(onFullscreen);
    await _settle(tester, 4000);
    final after = {...BenchCounters.snapshot(), 'surfaceInits': _CountingSurface.inits};
    final layersAfter = benchLayerCounts(tester.binding.renderViews.first.debugLayer!);
    final delta = {for (final k in after.keys) k: after[k]! - (before[k] ?? 0)};
    benchReport('kit-fullscreen-cycle', {'entered': entered, 'fullscreenNow': controller.fullscreen.value, 'delta': delta, 'layersBefore': layersBefore, 'layersAfter': layersAfter});
    try {
      expect(entered, 10);
      expect(controller.fullscreen.value, isFalse);
      expect(delta['creates'], 0);
      expect(delta['loads'], 0);
      expect(delta['surfaceInits'], 0);
      expect(delta['pageBuilds'], 0);
      expect(layersAfter, layersBefore);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester, 1000);
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
