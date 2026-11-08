import 'package:flutter/material.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

import 'demo/demo_kit_adapter.dart';

/// Feel-test for the controls kit: preset switcher, width presets and a fake
/// player with chapters, volume, rate and cached ranges.
class VideoControlsDemoPage extends StatefulWidget {
  const VideoControlsDemoPage({super.key});

  @override
  State<VideoControlsDemoPage> createState() => _VideoControlsDemoPageState();
}

class _VideoControlsDemoPageState extends State<VideoControlsDemoPage> {
  static final _presets = <String, LeafControlsSpec>{
    'adaptive': LeafControlsSpec.adaptive(),
    'mobile': LeafControlsSpec.mobile,
    'desktop': LeafControlsSpec.desktop,
    'uosc': LeafControlsSpec.uosc,
    'minimal': LeafControlsSpec.minimal,
  };
  static const _widths = <String, double?>{'360': 360, '800': 800, '1280': 1280, 'fill': null};

  String _preset = 'adaptive';
  String _width = 'fill';
  int _generation = 0;
  final _prefs = LeafControlsPrefs();

  @override
  void dispose() {
    _prefs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = _widths[_width];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Video controls kit'),
        actions: [
          IconButton(
            tooltip: 'Reload the player',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _generation++),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<String>(
                  segments: [for (final p in _presets.keys) ButtonSegment(value: p, label: Text(p))],
                  selected: {_preset},
                  onSelectionChanged: (s) => setState(() => _preset = s.first),
                ),
                SegmentedButton<String>(
                  segments: [for (final w in _widths.keys) ButtonSegment(value: w, label: Text(w))],
                  selected: {_width},
                  onSelectionChanged: (s) => setState(() => _width = s.first),
                ),
                ListenableBuilder(
                  listenable: _prefs,
                  builder: (context, _) => FilterChip(
                    label: const Text('Large'),
                    selected: _prefs.scale > 1,
                    onSelected: (on) => _prefs.scale = on ? 1.25 : 1.0,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: SizedBox(
                width: width,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: _DemoPlayer(key: ValueKey(_generation), spec: _presets[_preset]!, prefs: _prefs),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoPlayer extends StatefulWidget {
  const _DemoPlayer({super.key, required this.spec, required this.prefs});

  final LeafControlsSpec spec;
  final LeafControlsPrefs prefs;

  @override
  State<_DemoPlayer> createState() => _DemoPlayerState();
}

class _DemoPlayerState extends State<_DemoPlayer> implements LeafFullscreenHandle {
  final _adapter = DemoKitAdapter();
  late final _controller = LeafPlayerController(
    _adapter,
    prefs: widget.prefs,
    actions: const LeafPlayerActions(title: 'Demo episode', subtitle: 'S01E01 · a painted fake player'),
  );

  @override
  void initState() {
    super.initState();
    _controller.attachFullscreen(this);
    _controller.fullscreen.addListener(_rebuild);
    _adapter.load(url: 'demo://episode').then((_) => _adapter.play());
  }

  void _rebuild() => setState(() {});

  @override
  bool get canFullscreen => true;

  @override
  void enterFullscreen() => _controller.setFullscreen(true);

  @override
  void exitFullscreen() => _controller.setFullscreen(false);

  @override
  void dispose() {
    _controller.dispose();
    _adapter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      _adapter.surface,
      LeafPlayerControls(controller: _controller, spec: widget.spec, isFullscreen: _controller.fullscreen.value),
    ],
  );
}
