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
- Plus: `LeafContextMenu`, `LeafPopover`, `LeafToasts`, `LeafImage`, `AnimatedFavoriteButton`,
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

## Toasts

`LeafToastController` holds the toasts; `LeafToastHost` shows them in a corner over the app. Each slides and fades
in from the side, stays for its duration, then slides out while the gap closes. Plain toasts let clicks through;
ones with `onTap` take the click and dismiss. The app keeps the policy (what deserves a toast).

```dart
final toasts = LeafToastController();

MaterialApp(
  builder: (context, child) => LeafToastHost(controller: toasts, alignment: Alignment.bottomLeft, child: child!),
  home: const HomePage(),
);

toasts.show('Load order sorted', leading: const LeafToastIcon(Icons.sort));
toasts.show('Bob: hi', title: 'Chat', duration: null, onTap: openChat); // stays until clicked or dismissed
```

`maxVisible`, `spacing`, `padding`, `animationDuration`, `curve` and `cardBuilder` (default `LeafToastCard`) tune it.

## Additional information

- Example: `example/lib/viewer_demo.dart`
- All viewer code lives in `lib/src/viewer/` — zoom math in
  `leaf_zoom_controller.dart` (property-tested), gesture arbitration in
  `leaf_pan_zoom_recognizer.dart` (ported from photo_view, MIT).

## Video

Player-agnostic video kit — the app picks an engine by implementing one
~80-line adapter; page, lifecycle, and controls come free.

- `VideoPlayerAdapter` (`lib/src/video/leaf_video_adapter.dart`) — the only
  seam: `surface`, `load(url, headers)`, play/pause/seek, position/buffer/
  playing/ready/error streams + sync getters, `dispose()`. Implementations
  live outside this package so it stays dependency-free. The `HasVolume`
  mixin adds volume for adapters that support it; controls show volume UI
  only then.
- `LeafVideoPage` — owns the full lifecycle: neighbor pages preload paused,
  settled page autoplays, route-cover/background pause with
  resume-if-was-playing, error/retry, thumbnail until `readyStream`. Works
  standalone (always-active, permanent controls), but single-active gating
  needs a `LeafViewer` ancestor. `controlsBuilder` defaults to touch
  controls on mobile, desktop controls on desktop.
- `LeafVideoControls` — touch-first: double-tap thirds seek, tap toggles
  chrome, scrubber + time + fullscreen slot.
- `LeafDesktopVideoControls` — click toggles (immediate `onTapDown`, since
  `onTap` would wait out the double-tap timeout on every click),
  double-click fullscreen, self-hiding bar + cursor, hover time bubble,
  volume slider when `HasVolume`.
- `LeafScrubber` — shared scrubber (buffer/position tracks, tap-to-seek,
  drag-to-scrub, optional knob + hover preview); public for custom bars.
- `VideoLifecycleGuard` — background + route-cover pause for custom viewers
  that don't use `LeafVideoPage`. Callback-driven (`isPlaying`/`onPause`/
  `onResume`, `onResume` nullable for pause-only consumers). Cover detection
  via `ModalRoute.isCurrent` (no `RouteObserver` needed); callbacks fire
  post-frame so they may call ancestor `setState`.
- `FirstFrameGate` — caps concurrent first-frame decodes across feed tiles
  (default 2). `await enter()` before opening media, `exit()` on frame,
  playback start, or dispose. Pure logic, headless-tested.

Thumbnail is always app-provided (`thumbnail:` slot) — BlurHash, API
preview, or nothing (spinner). Volume persistence, engine toggles, and the
concrete adapters are app-side (see `video_adapter_media_kit`).

Tests: `test/video/` runs fake-adapter widget tests (gating, retry,
thumbnail-drop, cover flow, guard, desktop controls, gate). Fake-timer
note: pump a duration after taps — gesture deadlines don't advance alone.
