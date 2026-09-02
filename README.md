# leaf_widgets

Leaf UI widgets — zero external dependencies.

- `LeafViewer` — a self-contained, photo_view-style fullscreen viewer:
  clamped zoom + pan, swipe-to-dismiss, double-tap zoom, mouse-wheel zoom,
  native keyboard controls and tap-outside dismissal. Desktop + mobile
  behaviour out of the box.
- `LeafZoomable` — opt-in per-page zoom wrapper for `LeafViewer` (also usable
  standalone); auto-sizes itself from an image's pixel dimensions via
  `LeafZoomable.image`.
- `LeafZoomController` — the zoom/pan state machine behind both (clamped,
  fling, double-tap staging, wheel zoom).
- Plus: `LeafContextMenu`, `LeafPopover`, `LeafImage`, `AnimatedFavoriteButton`,
  `AnimatedStar`.

## Features

- Clamped zoom (1x–maxScale) and pan (corners cannot escape the viewport)
- Edge-release: a drag at a fully zoomed-out, fully clamped position pages or
  dismisses instead of panning (gesture-arena based, no raw pointer routing)
- Mobile: swipe to page, drag perpendicular to dismiss, double-tap zooms
  (1x → contained → 1:1 when dimensions are known)
- Desktop (Windows/Linux/macOS): mouse-wheel zoom (cursor-anchored), no drag
  paging/dismiss/double-tap by default, default on-screen controls
  (previous/next, close, page counter) — or your own via `controlsBuilder`
- Keyboard when focused: ←/→ (or ↑/↓ for vertical paging) + Esc dismiss
  (opt-out with `enableKeyboard: false`)
- Tap outside the active image fires `onTapOutside`
- `LeafZoomable.image`: pixel dimensions extracted from the image stream at
  load time — contained size and 1:1 double-tap step work without passing
  anything (falls back to viewport clamping until decoded)

## Getting started

Add to `pubspec.yaml`:

```yaml
dependencies:
  leaf_widgets:
    path: ../leaf_widgets
```

## Usage

```dart
import 'package:flutter/material.dart';
import 'package:leaf_widgets/leaf_widgets.dart';

class PostViewer extends StatelessWidget {
  const PostViewer({super.key, required this.posts});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LeafViewer(
        pageCount: urls.length,
        onDismissed: () => Navigator.of(context).maybePop(),
        pageBuilder: (context, index) => LeafZoomable.image(
          image: Image.network(
            urls[index],
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                const Center(child: Icon(Icons.broken_image, color: Colors.white38)),
          ),
        ),
      ),
    );
  }
}
```

That is the full viewer: paging, clamped zoom/pan, swipe-dismiss, double-tap
(1:1 included — the pixel dimensions are resolved automatically), wheel zoom,
keyboard, tap-outside, and desktop controls.

### Sizing control

`LeafZoomable` sizes the zoom clamp itself when possible:

- `LeafZoomable.image` resolves the image's pixel dimensions from its stream
  (no second download — the image cache dedupes) and uses them for the
  contained size and the 1:1 stage.
- Plain `LeafZoomable(child: ...)` clamps against the viewport until you pass
  explicit sizes:

```dart
// Contained (fit-to-screen) render size + full-resolution size.
LeafZoomable(
  childSize: myContainedSize,   // optional — defaults to the viewport
  originalSize: myFullSize,     // optional — null disables the 1:1 stage
  child: myWidget,
)
```

### Custom chrome

```dart
LeafViewer(
  pageCount: urls.length,
  controlsBuilder: (context, controls) => Row(
    children: [
      IconButton(
        onPressed: controls.canGoPrevious ? () => controls.goToPage(controls.currentIndex - 1) : null,
        icon: const Icon(Icons.chevron_left),
      ),
      Text('${controls.currentIndex + 1} / ${controls.pageCount}'),
    ],
  ),
  pageBuilder: (context, index) => /* ... */,
)
```

### Platforms

- Touch: swipe paging, perpendicular drag dismiss, double-tap zoom.
- Desktop: wheel zoom, keyboard, default controls; swipe gestures are off
  unless `enableSwipeGestures: true` forces them on.
- `scrollDirection` flips paging to vertical; the dismiss gesture then runs
  along the other axis.

## Additional information

- Example: `example/lib/viewer_demo.dart`
- All viewer code lives in `lib/src/viewer/` — zoom math in
  `leaf_zoom_controller.dart` (property-tested), gesture arbitration in
  `leaf_pan_zoom_recognizer.dart` (ported from photo_view, MIT).
