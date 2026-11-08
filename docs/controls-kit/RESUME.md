# Controls kit: resume state (2026-11-08)

DESIGN.md (alongside this file) is authoritative. Scope: phases 1–4, opt-in, the legacy controls are never edited here. Branch `controls-kit`, master (902bbe0) merged in.

## Done
- Phase 1 (6924337): `LeafPlayerCommand`, `LeafPlayerController` (throttled position, pending seek, capability listenables, actions, prefs), `LeafAutoHideVisibility` / `LeafViewerChromeVisibility` / `LeafControlsHold(Region)`, `fitBar`.
- Phase 2 (1f91790): `LeafPlayerControls` host, catalog items (play/bigPlay/pauseIndicator/buffering/previous/next/seekBy/seekBar line+band/time/progressLine/chapter steps/volume/mute/volumeFlash/fullscreen/title/back/seekFeedback + generic action/toggle/widget/spacer/gap), layout + 5 presets, theme, keymap (standard/mpv/youtube), demo page (`example/lib/video_controls_demo.dart`), `example/benchmark/controls_headless_bench_test.dart`.
- Phase 3: `LeafPlayerView` (route fullscreen moving the surface by GlobalKey, in-place mode), `LeafFullscreenDelegate` (+ callbacks, none, platformDefault, `LeafSystemFullscreenDelegate`), `LeafPlayerDefaults`, `LeafVideoPage(controls:, actions:, fullscreenDelegate:, fullscreenMode:)`, cover exemption, viewer bridge, viewer-key exclusion, focus on activation, next/prev paging the viewer.
- Linux check (media_kit, 1 player, volume 0, scratch app `/home/foxyz/.claude/jobs/9f255c64/tmp/leaf-controls/mk_fs`): 3 fullscreen cycles, 1 create, 1 load, same texture id, playback advancing in and out.

## Deviations from DESIGN
- PgUp = next chapter, PgDn = previous (mpv, as sync_relay now does); DESIGN had them the other way.
- `Opacity` keeps an OpacityLayer even at 1.0 on this SDK (RenderOpacity is a repaint boundary whenever alpha > 0), so regions fade through a private layerless `_FadeBox`.
- The fitted bar row is a tight, repaint-isolated LayoutBuilder: a LayoutBuilder is its descendants' build scope, so the clock's 1 Hz tick otherwise relaid out the whole bottom bar.
- `LeafControl.isAvailable` takes the `LeafControlContext` (fullscreen, viewer paging), not the controller.
- Presets carry only phase 1–3 items; subtitles / audio / speed / settings / skip / info / rateFlash join in phase 4. Items `fitBar` drops are hidden; the ⋯ menu that lists them is phase 4.
- `LeafGestureSpec` has no phase-5 fields yet (long-press rate, swipes); `LeafPlayerDefaults` has no brightness delegate; it lives in its own file.
- With the kit, `onFullscreenToggle` (no delegate) also picks in-place mode when the mode is auto.
- The controller keeps a stack of attached hosts (the fullscreen route's over the inline one) and a `pendingTeardown` future: a page disposed while fullscreen disposes its controller and adapter only after the route is gone.
- Unknown aspect ratio counts as landscape for the in-place availability rule.

## Next (phase 4)
- In-player menus (`LeafPlayerMenu`, never a route), the settings root, ⋯ overflow for `fitBar`'s dropped and `prefs.hidden` items; `LeafControl.menu` / `.panel`, `LeafPanelSection`.
- Items: subtitles, audioTracks, quality, speed, chapters list, loop, skip pill, info overlay (+ `readStats` 1 Hz only while shown), rateFlash; add them to the presets.
- Adapter worktrees (`video_adapter_media_kit` 39b639e, `video_adapter_native` c11c47f) with uncommitted `pubspec_overrides.yaml` pointing here: media_kit status/rate/tracks/chapters (`observeProperty('chapter-list')`)/video size/stats/looping, and the §6.3 dispose sequencing. Native fork: no chapters API, tracks are futures (poll).
- Tests from §5.3 still open: menus_test, info_overlay_test, skip_test.
