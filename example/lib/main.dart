import 'package:flutter/material.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

import 'viewer_demo.dart';

void main() {
  runApp(const LeafWidgetsGalleryApp());
}

class LeafWidgetsGalleryApp extends StatelessWidget {
  const LeafWidgetsGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'leaf_widgets gallery',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark),
      ),
      home: const _GalleryHome(),
    );
  }
}

class _GalleryHome extends StatefulWidget {
  const _GalleryHome();

  @override
  State<_GalleryHome> createState() => _GalleryHomeState();
}

class _GalleryHomeState extends State<_GalleryHome> {
  bool _favorited = false;
  bool _swipeEmulation = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('leaf_widgets gallery')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(title: 'AnimatedStar', child: const Row(children: [AnimatedStar(), SizedBox(width: 24), AnimatedStar(size: 36, color: Colors.cyanAccent)])),
          _Section(
            title: 'AnimatedFavoriteButton',
            child: Row(
              children: [
                AnimatedFavoriteButton(isFavorited: _favorited, onChanged: (v) async {
                  await Future<void>.delayed(const Duration(milliseconds: 600));
                  if (!mounted) return false;
                  setState(() => _favorited = v);
                  return true;
                }),
                const SizedBox(width: 24),
                const AnimatedFavoriteButton(),
              ],
            ),
          ),
          _Section(
            title: 'LeafPopover (tap trigger)',
            child: LeafPopover(
              popoverAnchor: Alignment.topCenter,
              childAnchor: Alignment.bottomCenter,
              spacing: 8,
              popoverBuilder: (context, controller) => Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Popover content'),
                      TextButton(onPressed: controller.hide, child: const Text('Close')),
                    ],
                  ),
                ),
              ),
              child: const Chip(label: Text('Open popover')),
            ),
          ),
          _Section(
            title: 'LeafContextMenu (right-click / long-press)',
            child: LeafContextMenu(
              entries: const [
                ContextMenuAction(label: 'Copy', icon: Icons.copy, shortcut: 'Ctrl+C'),
                ContextMenuAction(label: 'Open', icon: Icons.open_in_new),
                ContextMenuDivider(),
                ContextMenuAction(label: 'Delete', icon: Icons.delete, destructive: true),
              ],
              onDismissed: () => debugPrint('menu dismissed'),
              child: Container(
                height: 100,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
                child: const Text('Right-click me'),
              ),
            ),
          ),
          _Section(
            title: 'LeafImage (network + reveal)',
            child: LeafImage(
              image: const NetworkImage('https://picsum.photos/seed/leaf/800/500'),
              height: 220,
              width: double.infinity,
              fit: BoxFit.cover,
              imageBuilder: (context, child) => ClipRRect(borderRadius: BorderRadius.circular(12), child: child),
              revealAnimation: const GradientRevealAnimation(),
              loadingBuilder: (context, progress) => Container(
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
                child: progress > 0
                    ? Center(child: LinearProgressIndicator(value: progress))
                    : const Center(child: CircularProgressIndicator()),
              ),
              errorBuilder: (context, error, retry) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [const Icon(Icons.error_outline), TextButton(onPressed: retry, child: const Text('Retry'))],
                ),
              ),
            ),
          ),
          _Section(
            title: 'LeafViewer (fullscreen feel test)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  icon: const Icon(Icons.fullscreen),
                  label: const Text('Open 3-image viewer'),
                  onPressed: () => openLeafViewerDemo(context, enableSwipeGestures: _swipeEmulation),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Swipe gestures (phone emulation)'),
                  value: _swipeEmulation,
                  onChanged: (v) => setState(() => _swipeEmulation = v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
