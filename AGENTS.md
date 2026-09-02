# AGENTS.md — leaf_widgets

## Overview

Reusable Flutter UI widgets with **zero external dependencies** (pure `flutter`). Extracted from the Kemono Browser app (`S:\G_drive_backup\.Projects\SoyDev\Flutter\kemono_browser_project`) — that repo's AGENTS.md has the app-side context, and its `docs/photo-view-evaluation.md` is the **design bible** for the viewer: findings 1–12 from a photo_view feel-test, locked decisions in §6, and the package-extraction rationale in §6.1. Read it before touching the viewer.

Current contents:

| Widget | File | Notes |
|--------|------|-------|
| `LeafViewer` | `lib/src/viewer/leaf_viewer.dart` | Fullscreen pager: per-page zoom, edge-release, dismiss, desktop controls |
| `LeafZoomable` | `lib/src/viewer/leaf_zoomable.dart` | Per-page opt-in zoom wrapper (pages without it: paging + dismiss only) |
| `LeafZoomController` | `lib/src/viewer/leaf_zoom_controller.dart` | Pure math + animation state, `ChangeNotifier` |
| `LeafPanZoomRecognizer` | `lib/src/viewer/leaf_pan_zoom_recognizer.dart` | Arena pan/zoom recognizer (photo_view port) |
| `LeafViewerScope`/`LeafPageIndexScope`/`LeafViewerRegistry` | `lib/src/viewer/leaf_viewer_internal.dart` | Internal plumbing, **not** exported from the barrel |
| `LeafContextMenu` | `lib/src/context_menu/leaf_context_menu.dart` | Right-click / long-press menu |
| `LeafPopover` | `lib/src/popover/leaf_popover.dart` | Anchored overlay popover |
| `LeafImage` | `lib/src/image/leaf_image.dart` | Image widget: reveal animations, skeleton, retry |
| `AnimatedFavoriteButton` / `AnimatedStar` | `lib/src/misc/` | Async-aware heart toggle / spinning star |

## Commands

```bash
flutter analyze          # package must stay at zero issues
flutter test             # full suite
flutter test test/viewer # viewer subset (controller + widget tests)
cd example && flutter run -d windows   # feel-test harness (gallery + 3-image viewer demo)
cd example && flutter test
```

Convention: analyze + test on every change to the package (unlike the app, the package is small and the loop is cheap). No commit unless asked.

## LeafViewer API

```dart
LeafViewer(
  pageCount, pageBuilder,
  pageController?, initialPage, scrollDirection,
  onPageChanged,                 // external page-change notification
  dismissEnabled, onDismissed,   // onDismissed == null → Navigator.maybePop(context)
  onTapOutside,                  // quick tap outside the active image at 1×
  backgroundBuilder,             // (context, dismissProgress) → backdrop layer
  controlsBuilder,               // media_kit-style chrome slot
  enableSwipeGestures,           // null = platform default; true = phone emulation anywhere
)
```

`controlsBuilder(context, LeafViewerControls)` receives `pageCount`, `currentIndex`, `canGoPrevious/Next`, `goToPage(index)` (animated). When null: a default control set (prev/next chevrons, close, counter) renders **on desktop only**.

`LeafZoomable(child, childSize, originalSize?, maxScale, enabled)` — `childSize` is the contained (fit-to-screen) size, `originalSize` enables the 1:1 double-tap step. `enabled: false` renders content without zoom (until an image loads).

## Gesture architecture (how it works and why)

**The arbitration lives in the gesture arena — never in ScrollPhysics.** `Scrollable.setCanDrag` **removes the drag recognizer entirely** when physics is `NeverScrollableScrollPhysics` (`scrollable.dart`, `_gestureRecognizers = {}`), so a PageView with locked physics never tracks the in-flight pointer. Mid-drag physics unlocking is therefore impossible. Do not reintroduce physics-locking for paging control.

The flow:

1. Each `LeafZoomable` registers a `LeafPanZoomRecognizer` (extends `ScaleGestureRecognizer`, ported from photo_view's `PhotoViewGestureRecognizer`). On the **first non-zero move** it resolves immediately:
   - `controller.shouldClaim(fingerDelta)` (`shouldMoveX || shouldMoveY` — the LoliSnatcher `Axis.values` port) → `acceptGesture` → pan/pinch callbacks drive the controller
   - otherwise → `resolve(rejected)` → the arena hands the gesture to the PageView's drag (horizontal) or the viewer's dismiss drag (perpendicular) — **this is the edge-release behaviour**: a drag starting at a fully clamped position pages/dismisses instead of panning
2. `shouldClaim` is false at 1× (the child fits → `HitCorners(true,true)` → blocked), so at 1× every drag goes to the pager/dismiss.
3. Dismiss is viewer-level (LoliSnatcher pattern): the whole PageView translates + scales, the backdrop fades with progress. Thresholds: velocity > 800 px/s **or** offset > 25% of the perpendicular extent → fly-off to `dir * extent * 1.5` (200 ms easeIn) → `onDismissed ?? Navigator.maybePop`; otherwise spring back (`SpringDescription(mass 1, stiffness 600, damping 50)`). Progress = `|offset| / (extent * 0.5)`.
4. Wheel zooms from **any** scale (user decision: no wheel-paging), cursor-anchored: `scale * (1 - scrollDy * 0.001)` clamped `[1, maxScale]`.
5. Once a pan is claimed it stays claimed (sticky) — mid-drag clamp→page transitions do **not** exist (same as photo_view; they never existed in the app either).

### Desktop mode

Windows/Linux/macOS (auto-detected, `leafIsDesktopPlatform()`): no mouse drag paging, no drag dismiss, no double-tap — the wheel zooms, the default controls page, the close button closes. Mouse-drag **panning when zoomed stays** (recognizer-based, device-agnostic). `enableSwipeGestures: true` forces the full touch set anywhere (mouse paging + dismiss + double-tap) for phone emulation.

## Ported math (photo_view 0.15.0, MIT)

Source-verified against the installed package in the pub cache (`photo_view-0.15.0/lib/...`):

| Piece | Where | Notes |
|-------|-------|-------|
| Corners/clamp | `photo_view_controller_delegate.dart` `cornersX/Y`/`clampPosition` | Our model: scale relative to contained (1.0 = resting); position in screen px. Property-tested against photo_view's formulas |
| HitCornersDetector | `photo_view_hit_corners.dart` | Ported verbatim (private `_HitCorners`/`_shouldMoveAxis`) |
| Double-tap cycle | `photo_view.dart` `defaultScaleStateCycle` + `nextScaleState` | 1× → covered → 1:1 → 1×, with the no-op-skip loop; zoom-in targets the **tap point**, zoom-out animates to `(1.0, zero)` |
| Contained/covered | `src/utils/photo_view_utils.dart` | `min`/`max` of viewport/child ratios |

**Deliberately NOT ported** (evaluation findings 2/3/9/11): the friction-tail animations (`AnimationController.fling(velocity: 0.4)`), the fixed +100 px pan glide, center-targeted double-tap. Replaced by: our velocity-proportional fling (Ticker, friction 0.92/frame, `v/60` per frame, stop < 5, trigger > 300 px/s, tap-to-stop), 200 ms easeOut Matrix4Tween zoom animation, tap-point anchoring, and cancel-and-snap-to-1× on gesture interrupt. Rotation not ported (YAGNI).

## Critical gotchas (hard-won — read before changing anything)

1. **Never physics-lock the PageView** — see above. The arena recognizer is load-bearing.
2. **The recognizer must resolve on the first non-zero move** — otherwise `ScaleGestureRecognizer._advanceStateMachine` auto-accepts at `kPanSlop` (36 px) and can win the arena tie-break against the PageView's 18 px accept on large per-event deltas (fast flicks, tests), swallowing the drag.
3. **After `resolve(rejected)`, skip `super.handleEvent`** — the base asserts `_state != ready` on subsequent events.
4. **Never `setState` the viewer on page changes** — `PageView.builder` re-invokes `itemBuilder` on rebuild → new `ImageProvider` instances → `ImageCache` identity-key misses → re-downloads → **black flash**. The page index lives in a `ValueNotifier` (`_indexNotifier`); only the controls listen. There is a regression test asserting pageBuilder is not re-invoked for existing pages.
5. **`allowImplicitScrolling: true` is required** — default cache extent 0 disposes neighbor pages, destroying per-page zoom state on swipe.
6. **`shouldClaim` sign convention** — public API takes raw finger delta; negated internally to photo_view's `move = initialFocalPoint - currentFocalPoint` convention. The corner-block matrix tests depend on this.
7. **`onDismissed` defaults to `Navigator.maybePop`** — standalone dismissals close the route; the app passes its own for custom cleanup.
8. **`_indexNotifier` + `_currentIndex`**: keep both in sync (`_onPageIndexChanged`). The registry's `activeController` reads `_currentIndex` (event-time); the notifier drives UI only.

## Testing conventions

- Controller math: plain `test()` with `TestVSync()` (no binding needed for pure math). Animation/fling tests: `testWidgets`.
- **Ticker pattern**: `pump()` (zero duration — starts the ticker, elapsed 0) *then* `pump(duration)`. A single timed pump only starts the ticker.
- **Fling tests**: pump a frame loop (16 ms steps) until it stops, and never end a test with a running fling/ticker.
- **`debugDefaultTargetPlatformOverride` must be reset inside the test body** (last line) — the binding's invariant check runs before any `tearDown`/`addTearDown`.
- Taps start the `DoubleTapGestureRecognizer`'s 40 ms countdown — flush with `pump(350 ms)` or the test fails on pending timers.
- `Offset.toString()` rounds to 1 decimal — use `closeTo`, not exact equality, for float-derived values.
- `pumpAndSettle` never settles with perpetual animations on screen (the example gallery's `AnimatedStar`); use fixed pumps there.
- Widget tests drive gestures with `tester.startGesture` / `moveBy` / `timedDrag`; the slow-drag helper (~8 px steps, 200 ms pumps) keeps per-event deltas realistic (see gotcha 2).

## References & inspirations

- **Design bible**: `kemono_browser_project/docs/photo-view-evaluation.md` — findings 1–12 (zoom feel, double-tap, fling, single-axis scope flaw, wheel, mouse dragDevices, phone findings, lag), §5 LoliSnatcher architecture, §6 locked decisions, §6.1 package layout
- **photo_view** (upstream, MIT): `https://github.com/bluefireteam/photo_view`, installed at `C:\Users\timka\AppData\Local\Pub\Cache\hosted\pub.dev\photo_view-0.15.0\lib\` — `photo_view_gallery.dart`, `src/core/photo_view_gesture_detector.dart`, `src/core/photo_view_hit_corners.dart`, `src/core/photo_view_core.dart`, `src/controller/photo_view_controller_delegate.dart`, `src/utils/photo_view_utils.dart`, `src/photo_view_scale_state.dart`
- **LoliSnatcher** (architecture): `https://github.com/NO-ob/LoliSnatcher_Droid` — `lib/src/pages/gallery_view_page.dart` (local copy: `C:\Users\timka\AppData\Local\Temp\loli_gallery_view_page.dart`): viewer-level dismiss, `dismissProgress` mapping, videos as dumb children. Their photo_view fork (`github.com/NANI-SORE/photo_view` @ `410b4c2`) is the `Axis.values` both-axes validation — our `shouldClaim` is that rule in recognizer form
- **Flutter internals** (this SDK, `Z:\.Programs\flutter`): `scrollable.dart` `setCanDrag` (drag recognizer removal), `gestures/scale.dart` `_advanceStateMachine` (36 px auto-accept), `painting/image_stream.dart` `reportError` (error routing to listeners), `widgets/image.dart` listener wiring, `scroll_configuration.dart` `_kTouchLikeDeviceTypes` (mouse removed from default dragDevices in 3.47)
- **media_kit**: `controlsBuilder` inspiration for `LeafViewer.controlsBuilder`
- **The app**: `kemono_browser_project/lib/src/screens/fullscreen_image_viewer_screen.dart` — the `_ZoomableMixin` this viewer replaces (parameters ported: slop 12 px, fling 300, dismiss 800/25%, spring params); integration is still pending there

## Status & known future work

- Package 0.0.1, `publish_to: none`, git repo initialized — no commits made by the agent
- **App integration pending**: replace `_ZoomableMixin` + the 4 page types' gesture code with `LeafViewer`, delete `_ZoomableMixin`/`_ZoomReporter`/video dismiss copies, remove `photo_view` dep + demo screen
- Decode-size cap for huge images (51 MP, evaluation finding 12) — test on phone after integration
- Trackpad pinch (PointerPanZoomEvent) works through the base recognizer but is untested on hardware
- Example's `_HeaderImageProvider` has value equality so recreated pages reuse the cache; the app's `KemonoImageProvider` must keep stable instances across rebuilds (create once in `initState`, like `_FullscreenPage` does)
