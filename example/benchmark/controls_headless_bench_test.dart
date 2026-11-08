import 'package:example/bench/bench_video_adapter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
