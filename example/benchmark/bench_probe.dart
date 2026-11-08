import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class BenchProbe {
  int rebuilds = 0;
  int newElements = 0;
  int layouts = 0;
  int paints = 0;
  final _seen = Expando<bool>();
  late DebugPrintCallback _savedPrint;

  /// Paints per render object type.
  final paintsBy = <String, int>{};

  /// Layouts per render object type.
  final layoutsBy = <String, int>{};

  /// Sees every rebuilt element (per-widget counts).
  void Function(Element element)? onRebuild;

  void install() {
    debugOnRebuildDirtyWidget = (element, _) {
      rebuilds++;
      onRebuild?.call(element);
      if (_seen[element] == null) {
        _seen[element] = true;
        newElements++;
      }
    };
    debugOnProfilePaint = (r) {
      paints++;
      final name = r.runtimeType.toString();
      paintsBy[name] = (paintsBy[name] ?? 0) + 1;
    };
    debugPrintLayouts = true;
    _savedPrint = debugPrint;
    final saved = _savedPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.startsWith('Laying out')) {
        layouts++;
        final m = RegExp(r'Laying out .*?(Render\w+)').firstMatch(message);
        final name = m?.group(1) ?? '?';
        layoutsBy[name] = (layoutsBy[name] ?? 0) + 1;
        return;
      }
      saved(message, wrapWidth: wrapWidth);
    };
  }

  void uninstall() {
    debugOnRebuildDirtyWidget = null;
    debugOnProfilePaint = null;
    debugPrintLayouts = false;
    debugPrint = _savedPrint;
  }
}

class BenchPhase {
  BenchPhase(this.name);

  final String name;
  final rebuilds = <int>[];
  final newElements = <int>[];
  final layouts = <int>[];
  final paints = <int>[];
  int tickingFrames = 0;
  Map<String, int> counters = const {};

  static Map<String, num> _dist(List<int> values) {
    if (values.isEmpty) return {'total': 0};
    final sorted = [...values]..sort();
    return {
      'total': values.fold(0, (a, b) => a + b),
      'perFrame': double.parse((values.fold(0, (a, b) => a + b) / values.length).toStringAsFixed(1)),
      'p90': sorted[((sorted.length - 1) * 0.9).round()],
      'max': sorted.last,
    };
  }

  Map<String, Object> toJson() => {
    'frames': rebuilds.length,
    'tickingFrames': tickingFrames,
    'rebuilds': _dist(rebuilds),
    'newElements': _dist(newElements),
    'layouts': _dist(layouts),
    'paints': _dist(paints),
    'counters': counters,
  };
}

void benchReport(String name, Object data) => debugPrint('HEADLESS_BENCH $name ${jsonEncode(data)}');

Map<String, int> benchLayerCounts(Layer root) {
  final counts = <String, int>{};
  void visit(Layer layer) {
    counts.update('all', (v) => v + 1, ifAbsent: () => 1);
    if (layer is ShaderMaskLayer) counts.update('shaderMask', (v) => v + 1, ifAbsent: () => 1);
    if (layer is BackdropFilterLayer) counts.update('backdrop', (v) => v + 1, ifAbsent: () => 1);
    if (layer is OpacityLayer) counts.update('opacity', (v) => v + 1, ifAbsent: () => 1);
    if (layer is ContainerLayer) {
      var child = layer.firstChild;
      while (child != null) {
        visit(child);
        child = child.nextSibling;
      }
    }
  }

  visit(root);
  return counts;
}

