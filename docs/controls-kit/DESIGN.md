# Modular video controls kit for leaf_widgets: design (read-only, no code changed)

**Sources read:**
- sync_relay: `/mnt/torrents/G_drive_backup/.Projects/SoyDev/Flutter/sync_relay_project/apps/desktop/lib/src/controls/` (15 files, 3,699 lines) and the tests that cover it. From the playback side I read only the interface it calls: `playback/media_marks.dart`, the signals in `playback/playback_controller.dart`, and `SkipPill` in `screens/session/player_controls.dart`. I read nothing about chat, relay, Jellyfin, auth or settings.
- leaf_widgets: the `perf-audit` branch via `git show`. **The branch moved while I was reading** (head is now `6994a0c`: `deferWhileScrolling`, adapter created lazily). The design is based on `6994a0c`.
- The audit report, `/home/foxyz/.claude/jobs/9f255c64/tmp/leaf-audit/REPORT.md`.
- Adoption context: `video_adapter_media_kit`, leafbooru's `native_player_adapter.dart` and `post_view.dart`, kemono's viewer screen, comfy_client's `media_viewer.dart`.

## 0. Decisions at a glance

**Opt-in, legacy untouched.**
- The kit is enabled with `LeafVideoPage(controls: …)`, or once per app with a `LeafPlayerDefaults` widget at the root.
- The legacy `LeafVideoControls`, `LeafDesktopVideoControls` and `LeafScrubber` stay byte-identical.
- The default flips to the kit only after you've confirmed it on device (section 8).

**Adapter: no changes to the base.**
- `VideoPlayerAdapter` and `HasVolume` don't change.
- New features come in through new optional `Has*` interfaces. When an adapter lacks one, the items that need it disappear. Every existing adapter keeps compiling.

**One controller per adapter.**
- `LeafPlayerController` subscribes to each adapter stream once.
- It exposes throttled `ValueListenable`s and a single dispatch, `execute(LeafPlayerCommand)`, shared by buttons, keys and gestures.

**Declarative layout.**
- `LeafControlsLayout` maps 15 slots to `LeafControl` catalog items.
- `LeafControlsSpec` bundles a layout with gestures, keymap, auto-hide and look.
- Presets: `mobile`, `desktop`, `uosc`, `minimal`, and `adaptive` (touch → mobile, desktop → uosc).

**Fullscreen.**
- Default mode is a zero-transition Dart route. It moves the existing surface element there with a GlobalKey, so the same State, texture and platform view survive, with no re-open.
- Inside a `LeafViewer` it works in place instead: no route, only the OS step.
- The OS/window step goes through `LeafFullscreenDelegate`. A SystemChrome delegate for Android/iOS is built in; window_manager stays app-side.

**Menus, panels and the info overlay render inside the player, never as routes.**
- They don't trigger `LeafVideoPage`'s pause-when-covered policy.
- They come along into fullscreen automatically.

---

## 1. sync_relay inventory

### 1.1 How its layout and prefs model works

**`model/controls_layout.dart`**
- Two closed enums: `BarControl` (12 values) and `ControlAction` (11).
- Fixed order. Left: play, previous, next, chapterPrev, chapterNext, volume, time. Right: subtitles, audio, settings, chat, fullscreen.
- Pure functions of a `ControlsSnapshot` (everything except position) plus the user's hidden set: `barControls`, `menuActions`, `controlEnabled`, `controlIcon`, `controlTooltip` (key hints baked into the strings), `clockText`.

**`model/controls_model.dart`** (`PlayerControlsModel`)
- Wraps `SessionCoordinator` signals: position, duration, buffered, chapters, tracks, volume, skipOffer.
- Computes the party play state (playing / ready-waiting / paused / finished) and the snapshot.
- Owns `panelOpen`, `menusOpen` and the `volumeFlash` trigger, plus every action.
- Position is deliberately kept out of the snapshot. The upstream `PlaybackController` already emits it in 250 ms steps.

**`model/controls_prefs.dart`**
- `ControlsSkin {standard, minimal}`, where minimal is the uosc look.
- `TimeDisplay {elapsed, remaining}`.
- `ControlsSize {1.0, 1.25}`.
- `OptionalControl {chapters, subtitles, audio, chat}`: hidden ones move into the top bar's ⋯ menu.

**Hosting.** `session_controls.dart` picks a skin. `frame.dart` (`ControlsFrame`) owns visibility for both skins.

### 1.2 Features

| # | Feature | Generic? | Verdict |
|---|---|---|---|
| 1 | Two looks over one model: Standard (Material) and Minimal (uosc band) | yes | port as `LeafLook.material` / `.uosc` |
| 2 | Bar order spec; drops what doesn't apply (no episode → no prev/next; no chapters → no chapter buttons); play first, fullscreen last | idea yes, enum closed | rework into an open catalog with `isAvailable` |
| 3 | User-hidden buttons move into the ⋯ menu | yes | `LeafControlsPrefs.hidden` → overflow/settings menu |
| 4 | ⋯ "Video and session" menu: change video, copy link, reload, skip 1:30, chapters, subtitles, audio, chat, mark all ready, mark a problem, leave | chapters/subs/audio/skip yes, rest app | generic entries built in; app entries via `LeafPlayerActions.menuEntries` |
| 5 | Enable/dim rules, state icons, tooltips with key hints | yes | port; hints generated from the keymap |
| 6 | Party play button: ✓ = ready and waiting, ↻ = finished | app | hooks `actions.playState` + `onTogglePlay` |
| 7 | Clock "6:00 / 24:00" ↔ "-18:00", click toggles, tabular figures, width reserved | yes | port (`LeafTimeFormat`) |
| 8 | Controls size Normal / Large (×1.25) | yes | `theme.scale` / prefs |
| 9 | Progress line while hidden (2 px in Standard; band collapses to 3 px in Minimal), switchable | yes | `progressLine` item / band `collapseWhenHidden` |
| 10 | Standard seek bar: buffered, hover fill, played, chapter diamonds (not at 0), knob on hover/drag, tip with chapter title over time, seeks on every drag move and on release | yes | port the look, rework the rendering |
| 11 | uosc band timeline (details below the table) | yes | port math and look, rework the rendering |
| 12 | Glass capsules, flat rounded buttons, accent-filled play button, count badges, dark tooltips | yes | port |
| 13 | Volume (details below the table) | yes | port as is, with a `max` parameter |
| 14 | Volume readout flash (~1 s) after wheel/key steps anywhere: controls up or hidden, windowed or fullscreen | yes | port, without blur |
| 15 | Audio and subtitle menus (subtitles start with Off), mpv's selection checked, count badges | yes (mpv label formatting stays app-side) | port onto in-player menus |
| 16 | Chapter list with start-time hints, current one checked; PgUp/PgDn with mpv's 5 s back threshold | yes | port |
| 17 | Previous/next episode with labels in tooltips ("Up next" wins) | button yes, data app | port the button; data via actions |
| 18 | Skip pill: Skip OP/ED from Jellyfin segments, else from OP/ED-titled chapters; "Skip 1:30" fallback (media > 20 min, first 6 min, no chapters) | logic yes, segment source app | port the logic; segments via actions; fallback opt-in |
| 19 | Auto-hide frame (details below the table) | yes | port as is |
| 20 | Buttons excluded from focus, so Space stays play | yes | port |
| 21 | Player panel: 312 px column docked right, stays open across hide/show, foldable sections remembered per run, Esc/× closes | host yes, content app | port the host + `LeafPanelSection` |
| 22 | Panel content: Anime4K shaders, hwdec, sub scale, lift subtitles, screen-res, design, size, bar buttons | app (mpv + AppSettings) | not ported; plugs into the panel |
| 23 | Top bar: NowPlayingTitle (cover/title/episode), Up next popover, ⋯, collapse/exit fullscreen, window buttons | content app | `title`/`back` built in; the rest via `LeafControl.widget` |
| 24 | Chat button with unread badge, quick chat that suppresses the controls, danmaku, party avatars, toasts above the bar | app | plug points in 3.16 |

Details for rows 11, 13 and 19:
- **uosc band (11):**
  - Accent-tinted played part, a white position line, and diagonal stripes over the not-yet-cached part.
  - Chapter cut lines plus dots on the top edge; a hovered dot grows and pressing it jumps to that chapter.
  - Elapsed time on the left and total-or-remaining on the right, inside the band; pressing the right one toggles it.
  - A "12s" cache label while less than 60 s is buffered ahead.
  - Hover line and tip; 120 ms collapse animation.
  - A pending seek is shown until the player catches up (2 s cap).
- **Volume (13):**
  - The speaker mutes and restores.
  - The slider stays out when there's room, otherwise slides out on hover (`volumeSliderRoom`).
  - The wheel steps 5 %: a notch is one step, smooth deltas accumulate, sideways scrolls are ignored, and lists under the mouse claim the scroll first.
  - Range 0–150 with an amber boost above 100 and a tick at 100.
- **Auto-hide frame (19):**
  - Hides after 3 s, wakes only on real mouse movement, hides on pointer exit, hides the cursor.
  - Holds: seek drag, open menu, hold regions over floating widgets. Also `suppress` and a `shown` notifier.
  - Double-click detection sits outside the gesture arena and ignores the bars.

Shortcuts implied by the tooltips: Space, ←/→ nudge, Shift+→ skip 1:30, PgUp/PgDn, `<` `>` or Shift+P/N, M, ↑/↓ and the wheel for volume, F, Esc, Tab (chat), Ctrl+R, Ctrl+Shift+B, Ctrl+1…6 / Ctrl+0 (shaders). The key handler itself lives in the shell, which was out of scope.

### 1.3 Quality

**Port nearly as is:**
- `controls_probe.dart` (`ControlsHold` with microtask-coalesced notifications, `ControlsHoldRegion`).
- `ControlsFrameState` logic and `DoubleClickListener`.
- `volume.dart`: `WheelSteps`, `VolumeWheel`, `VolumeFlash`, `VolumeBar` painter, `VolumeControl`, `volumeSliderRoom`.
- `MinimalButton` and `MinimalCapsule`.
- The timeline math: `uncachedFrom`, `cacheLabel`, `minimalBandSize`, pending-seek settle, chapter-dot reach.
- The pure functions in `media_marks.dart`: `formatClock`, `chapterIndexAt`, `chapterStepTarget`, `skipOfferAt`, `isOpeningTitle`/`isEndingTitle`, `chaptersFromStarts`.
- Keep the uosc LGPL-2.1 attribution comment from `timeline.dart` on the band painter.

**Needs rework:**
- **The model** is tied to `SessionCoordinator`, the signals package and `AppSettings` singletons.
- **The layout** is closed enums: adding a control means editing switches in 4 files.
- **Standard skin:** the hidden bars stay mounted (AnimatedOpacity at 0), so the seek bar and clock keep rebuilding at 4 Hz while hidden.
- **`MinimalTimelinePainter`:** `shouldRepaint` always returns true, and every paint creates TextPainters that are never disposed (`_text`, and `_onRightTime` on each press). The band rebuilds on every position update.
- **`ChapterSeekBar`:** a Stack of Containers, with a `setState` on every hover move.
- **Glass:**
  - `FloatingPill` rests at 0.45 opacity over `AppGlass.pill`, a BackdropFilter blur. While the pill is shown, that's a permanent saveLayer plus a blur over the video.
  - `VolumeReadout` and `PlayerPanel` also blur over the video.
- **Menus** go through the app's `showAppMenu`.

### 1.4 Tests to port as kit tests

- **`controls_model_test`:**
  - Bar order and hidden items moving to the ⋯ menu.
  - Drawn order left to right.
  - Volume slider wide vs. narrow, and on hover.
  - ⚙ toggles the panel.
  - Hidden progress line in both skins.
- **`minimal_controls_test`:**
  - Timeline math and painter values.
  - Hover tip (title above time, tip above the band), chapter-dot jump, right-time toggle.
  - Collapsed band is inert.
  - Press/drag/release seeks, and the pending seek holds the target.
  - Frame hide/wake, drag hold, menu hold, double-click not on the bars.
  - Badges, mute/restore, wheel stepping, lists claiming the wheel first.
- **`player_controls_test`:** seek bar marks and hover, drag seeks, skip pill, track and chapter menu items.
- **`volume_readout_test`:** the wheel-anywhere readout.
- **`player_status_test`:** the "no overflow at widths" idea.

---

## 2. leaf today (`perf-audit` @ `6994a0c`)

**Adapter.**
- `VideoPlayerAdapter` has:
  - `surface` and `load(url, headers)`;
  - position, buffer, playing, ready and error streams;
  - getters for position, duration, buffer and isPlaying;
  - `play`, `pause`, `playOrPause`, `seek`, `dispose`.
- `HasVolume` (an `abstract mixin class`; MediaKitAdapter `implements` it) has `volumeStream`, `volume`, `setVolume`.
- There is no duration stream, rate, tracks, chapters, buffering/ended state, video size or stats.

**`LeafVideoPage`.**
- Owns the adapter, now created lazily (`deferWhileScrolling`).
- Owns the policy: prebuffer neighbours, the first-frame gate, play when settled, pause when covered by any route or when the app backgrounds, resume rules.
- Owns the viewer-chrome hold while paused, plus thumbnail / spinner / retry.
- Parameters: `controlsBuilder(context, adapter)`, `aspectRatio`, `skipDuration`, `onFullscreenToggle` (a bare callback).

**`LeafVideoControls` (touch).**
- A tap toggles the viewer chrome.
- Double-tap on the outer thirds seeks ±10 s with accumulating "+20s" feedback; the middle toggles play.
- Bottom bar: a private `_Scrubber`, time as "mm:ss / mm:ss", and a fullscreen button.
- A center play badge shows while paused. There's no tappable pause button.
- `_ChromeFade` drops the bar after it fades out.

**`LeafDesktopVideoControls`.**
- A click toggles play (on pointer down); double-click calls the fullscreen callback.
- Auto-hides after 3 s, only while playing; hides on pointer exit, along with the cursor; the bar is dropped after the fade.
- Bar: `LeafScrubber(knob, hoverPreview)`, play/pause, mute plus a 0–100 Slider when `HasVolume`, time, fullscreen.

**Viewer.**
- `LeafViewerChrome`: one reveal state for every layer; `hold` (a single bool) suppresses auto-hide; auto-hide on touch only.
- `LeafChrome` is a passive layer that fades with it.
- The viewer's Focus handles bare arrows (paging) and Esc (dismiss).
- `LeafPopover` and `LeafContextMenu` are OverlayPortal-based, not routes.

**Gaps.** No tracks or subtitles, speed, chapters, keyboard control of the video, real fullscreen, info, menus, theming (colours are hard-coded), title/back, next/prev, loop, PiP, buffering or ended state, or volume on mobile.

**Perf after the audit.**
- Hidden bars are dropped; the scrubber has its own RepaintBoundary.
- But both scrubbers still drive an `AnimatedContainer` from every position event (150 ms / 400 ms). With events every ~33 ms, a visible bar on a playing video asks for a frame on every vsync.

---

## 3. The kit API

All new code is in `lib/src/video/controls/` plus `lib/src/video/leaf_video_capabilities.dart`. Flutter only (material, services, gestures, rendering).

### 3.1 Object model

```
VideoPlayerAdapter (+ optional Has*)
   └─ LeafPlayerController            one per adapter: listenables + execute(command) + UI state
        ├─ LeafPlayerView              surface host: aspect ratio, GlobalKey surface, fullscreen route, placeholder
        │    └─ LeafPlayerControls     overlay host: regions, fades, focus/keymap, gestures, menus/panels
        │         └─ LeafPlayerScope   InheritedWidget → controller, visibility, theme, spec, isFullscreen, host
        └─ LeafControlsVisibility      auto-hide + holds (or a bridge onto LeafViewerChrome)
LeafPlayerDefaults (app root)          default spec, theme, prefs, fullscreen and brightness delegates
```

### 3.2 Adapter capabilities: `leaf_video_capabilities.dart`

All optional, detected with `adapter is HasX`, and all `abstract mixin class` so adapters can `with` or `implements` them.

```dart
abstract mixin class HasPlaybackStatus { Stream<Duration> get durationStream; Stream<bool> get bufferingStream; bool get isBuffering; Stream<bool> get completedStream; bool get isCompleted; }
abstract mixin class HasPlaybackRate   { Stream<double> get rateStream; double get rate; void setRate(double rate); }
abstract mixin class HasTracks         { Stream<LeafTracks> get tracksStream; LeafTracks get tracks; void selectTrack(LeafTrackKind kind, String? id); } // null id = off
abstract mixin class HasChapters       { Stream<List<LeafChapter>> get chaptersStream; List<LeafChapter> get chapters; }
abstract mixin class HasBufferedRanges { Stream<List<LeafTimeRange>> get bufferedRangesStream; List<LeafTimeRange> get bufferedRanges; }
abstract mixin class HasVideoSize      { Stream<Size?> get videoSizeStream; Size? get videoSize; }
abstract mixin class HasVideoStats     { Future<LeafVideoStats> readStats(); } // polled at 1 Hz, only while the info overlay shows
abstract mixin class HasQualities      { Stream<LeafQualities> get qualitiesStream; LeafQualities get qualities; void selectQuality(String id); }
abstract mixin class HasLooping        { Stream<bool> get loopingStream; bool get isLooping; void setLooping(bool on); }
abstract mixin class HasPictureInPicture { Stream<bool> get pipStream; bool get isPipAvailable; Future<void> enterPip(); }
```

**Value types** (immutable, value equality):
- `LeafTrackKind {video, audio, subtitle}`
- `LeafTrack {id, kind, title, language, codec, channels, isDefault, isForced, isExternal, label}`: `label` is formatted by the adapter; the default is "title · language · codec channels".
- `LeafTracks {video, audio, subtitle, selectedVideo, selectedAudio, selectedSubtitle; static empty}`
- `LeafChapter {index, title, start, end}`
- `LeafTimeRange {start, end}`
- `LeafQualities {options, current}` and `LeafQuality {id, label, height, bitrate, isAuto}`
- `LeafSkipKind {intro, outro, recap, preview, commercial}` and `LeafSkipSegment {kind, start, end, label}`
- `LeafVideoStats`, all fields nullable:
  - Player and video: `backend`, `videoSize`, `displaySize`, `containerFps`, `renderFps`, `displayFps`, `videoCodec`, `hwdec`, `pixelFormat`, `colorInfo`, `videoBitrate`.
  - Audio: `audioCodec`, `audioChannels`, `sampleRate`, `audioBitrate`.
  - Frames and container: `droppedFrames`, `decoderDroppedFrames`, `container`.
  - Cache: `cacheAhead`, `cacheBytes`, `cacheSpeed`.
  - `extra` (a `Map<String, String>` of backend-specific lines).

Every stream maps onto media_kit 1.2.6:
- `stream.duration`, `stream.buffering`, `stream.completed`, `stream.rate` / `setRate`.
- `stream.tracks` / `stream.track` / `set*Track` (with `SubtitleTrack.no()` for off).
- `stream.width` / `stream.height` / `stream.videoParams` / `stream.audioParams`, and `setPlaylistMode`.
- `getProperty` for `hwdec-current`, `estimated-vf-fps`, `frame-drop-count`, `demuxer-cache-duration` and `cache-speed`, and `observeProperty('chapter-list')`.
- sync_relay's `parseChapterList` moves into `video_adapter_media_kit`.

The native fork exposes `speedStream`, `chaptersStream`, `qualitiesStream`, `isPipAvailableStream` and `videoSizeStream`.

### 3.3 `LeafPlayerController` (`controls/leaf_player_controller.dart`)

```dart
LeafPlayerController(VideoPlayerAdapter adapter, {
  LeafPlayerActions actions = const LeafPlayerActions(),
  LeafControlsPrefs? prefs,
  Duration positionInterval = const Duration(milliseconds: 100),
});
```

**Player state** (all `ValueListenable`):
- Playback: `playing`, `buffering`, `completed`, `duration`, `error`.
- `position`: throttled to `positionInterval`. Timer-based, so it behaves under fake async. The trailing value always lands. Seeks and play/pause changes flush immediately. No timer runs while it has no listeners, and `value` always returns the latest raw position.
- `positionSeconds` (int): notifies only when the displayed second changes. Labels use this.
- `pendingSeek` (`Duration?`): a drag or press target, shown until the player is within 1.5 s of it; dropped after 2 s otherwise.
- Buffer: `buffered` (end), `bufferedRanges` (from the capability, else `[0, buffer]`).
- Capability state, null when the capability is absent: `volume`, `rate`, `tracks`, `qualities`, `looping`, `pip`, `videoSize`.
- Chapters and skips: `chapters` (empty without the capability); `currentChapter` and `skipOffer` notify only on change.
- Duration comes from `HasPlaybackStatus` when present. Otherwise the getter is re-read on each player event and change-detected.

**UI state shared by every control of this player:**
- `controlsVisible`, `fullscreen`, `infoVisible`.
- `timeFormat` (from prefs).
- `overlayInsets`: a `ValueListenable<EdgeInsets>` with the visible bars' heights, for lifting subtitles or toasts.

**Commands:**
- `execute(LeafPlayerCommand)` is the single entry point. Thin wrappers exist: `togglePlay()`, `seek()`, `seekBy()`, `stepVolume()`, `toggleMute()` (remembers the pre-mute level, as both apps do), `setRate()`, `selectTrack()`, `stepChapter()`, `skip()`, `toggleFullscreen()`.
- `updateActions(actions)`; `dispose()` cancels the subscriptions.

**Hooks for app overrides:**
- `actions.onTogglePlay` / `actions.playState` replace the play semantics (watch party).
- `actions.onSeek` routes user seeks through the app (sync relay).

`LeafPlayerActions` (immutable; passed again when it changes):
- Display: `title`, `subtitle`.
- Navigation: `onBack`, `onNext`, `onPrevious`, `nextLabel`, `previousLabel`.
- Overrides: `onTogglePlay`, `playState` (`ValueListenable<LeafPlayState>`: playing / paused / waiting / ended), `onSeek`.
- Content: `segments` (`ValueListenable<List<LeafSkipSegment>>`), `menuEntries` (a `List<LeafMenuEntry> Function()`), `seekPreview` (an `ImageProvider? Function(Duration)` for trickplay).

`LeafControlsPrefs` (a ChangeNotifier owned by the app):
- `timeFormat`, `hidden` (`Set<String>`), `scale` (1.0 / 1.25), `progressLine` (bool).
- `onChanged` so the app can persist, plus `toJson` / `fromJson`.

### 3.4 Commands (`controls/leaf_player_command.dart`)

A sealed `LeafPlayerCommand` with const factories:
- Playback: `togglePlay`, `play`, `pause`.
- Seeking: `seekTo(d)`, `seekBy(d)`, `seekToFraction(f)`, `stepChapter(n)`, `seekToChapter(i)`, `skip` (the current offer, else the fixed fallback if enabled).
- Volume: `stepVolume(n)`, `setVolume(v)`, `toggleMute`.
- Rate: `setRate(r)`, `stepRate(d)`, `resetRate`.
- Tracks and quality: `selectTrack(kind, id)`, `cycleTrack(kind, includeOff)`, `selectQuality(id)`.
- Toggles: `toggleLoop`, `togglePip`.
- Fullscreen: `toggleFullscreen`, `enterFullscreen`, `exitFullscreen`.
- UI: `toggleInfo`, `cycleTimeFormat`, `openMenu(controlId)`, `toggleControls`, `showControls`.
- Navigation: `next`, `previous`, `back`.
- `custom(id, VoidCallback)`.

UI commands are forwarded to the attached `LeafPlayerControls`.

### 3.5 Catalog: `LeafControl`

Each item is a `const` object with static shorthands such as `LeafControl.playPause`. Base contract:

```dart
abstract class LeafControl {
  const LeafControl();
  String get id;
  Iterable<Listenable> availabilityDeps(LeafPlayerController c) => const [];
  bool isAvailable(LeafPlayerController c) => true;
  double? estimatedWidth(LeafControlsTheme t) => t.buttonExtent; // null = flexible
  int get priority => 50;                                        // lowest overflows first
  LeafMenuEntry? menuEntry(LeafMenuContext c) => null;           // how it appears in ⚙/⋯
  Widget build(BuildContext context, LeafControlContext c);
}
```

`LeafControlContext` gives an item: `controller`, `visibility`, `theme`, `slot`, `isFullscreen`, `keymap` (for tooltip hints) and `host` (`openMenu`, `openPanel`, `closeTop`, `flash`).

| id | Default slot | Needs | Behaviour |
|---|---|---|---|
| `playPause` | bottomStart | — | play / pause / ↻ when ended; accent-filled in uosc; honours `actions.playState` |
| `bigPlay` | center | — | large button; option `whilePaused` (legacy badge) or always-with-controls |
| `pauseIndicator` | center | — | ~400 ms ▶/❚❚ flash on toggle (uosc `pause_indicator=flash`) |
| `buffering` | center | `HasPlaybackStatus` (else only before the first frame) | spinner |
| `previous` / `next` | bottomStart | `actions.onPrevious`/`onNext`, else viewer paging | tooltip with the label |
| `LeafControl.seekBy(d)` | center (mobile) | — | ⟲10 / ⟳10 |
| `seekBar` (`LeafSeekBarControl{look: line\|band, knob: never\|hover\|always, chapters, hoverTip, collapseWhenHidden, timesInside}`) | bottomAbove (line) / bottomBelow (band) | optional `HasChapters`, `HasBufferedRanges`, `actions.seekPreview` | everything in rows 10 and 11 of 1.2 |
| `time` (`LeafTimeControl{formats, style}`) | bottomStart | — | click cycles the formats; fixed-width box |
| `progressLine` | whenHidden | — | 2 px line, gated by `prefs.progressLine` |
| `chapterPrevious` / `chapterNext` | bottomStart | `HasChapters` with data | PgUp/PgDn, mpv 5 s rule |
| `chapters` | menu | `HasChapters` | list with start hints, current one checked |
| `skip` (`LeafSkipControl{fallback: Duration?}`) | action | chapters and/or `actions.segments` | Skip OP/ED/intro/recap; fallback off by default |
| `volume` (`LeafVolumeControl{max = 100, slider: auto\|always\|hover\|never, wheel}`) | bottomStart | `HasVolume` | sync_relay port, boost above 100 |
| `mute` | bottomEnd (mobile) | `HasVolume` | mute only |
| `volumeFlash` | overlay | `HasVolume` | readout for 1 s after wheel/key/swipe steps |
| `subtitles` / `audioTracks` | bottomEnd + menu | `HasTracks` | menus; optional count badge |
| `quality` | bottomEnd / menu | `HasQualities` | Auto + variants |
| `speed` (`LeafSpeedControl{rates}`) | bottomEnd / menu | `HasPlaybackRate` | label "1.5×"; default rates 0.25 to 3 |
| `loop` | menu | `HasLooping` | toggle |
| `pip` | bottomEnd | `HasPictureInPicture` | enter PiP |
| `fullscreen` | bottomEnd | the resolved mode must change something (3.13) | icon follows state |
| `info` / `infoOverlay` | menu / overlay | optional `HasVideoStats` | 3.14 |
| `settings` | bottomEnd | — | root menu: Speed ▸, Subtitles ▸, Audio ▸, Quality ▸, Chapters ▸, Loop ✓, Time ▸, Stats ✓, app entries, overflowed items |
| `overflow` | added to bottomEnd automatically | only when something overflowed or is hidden and there is no `settings` | ⋯ |
| `title` / `back` | topStart | `actions.title`; `actions.onBack`, or exits fullscreen | ellipsized title + subtitle |
| `seekFeedback`, `rateFlash` | overlay | — / rate | "−10 s / +20 s" bubbles (legacy port); "2×" while long-pressing |

Generic items, so apps configure rather than write widgets:
- `LeafControl.action(id, icon, tooltip, onPressed, {badge: ValueListenable<int>?, enabled, shortcut})`
- `LeafControl.toggle(id, icon, activeIcon, value, onChanged)`
- `LeafControl.menu(id, icon, tooltip, entries)`
- `LeafControl.panel(id, icon, tooltip, builder)`
- `LeafControl.widget(id, builder)`, the escape hatch
- `LeafControl.spacer`, `LeafControl.gap(w)`

`LeafControl.catalog` is a `Map<String, LeafControl>` of the built-ins, used by `fromIds` (3.6).

### 3.6 Slots and layout (`controls/leaf_controls_layout.dart`)

```dart
enum LeafSlot { topStart, topCenter, topEnd, center, sideStart, sideEnd,
  bottomAbove, bottomStart, bottomCenter, bottomEnd, bottomBelow, action, overlay, whenHidden, menu }

@immutable class LeafControlsLayout {
  const LeafControlsLayout({ /* one List<LeafControl> per slot, default const [] */,
    this.topOnlyInFullscreen = false, this.capsules = false });
  LeafControlsLayout withSlot(LeafSlot slot, List<LeafControl> items);
  LeafControlsLayout without(Set<String> ids);
  LeafControlsLayout insertAfter(String id, LeafControl item);   // + insertBefore
  static LeafControlsLayout fromIds(Map<LeafSlot, List<String>> ids, {Map<String, LeafControl> extra = const {}});
  Map<LeafSlot, List<String>> toIds();
}

@immutable class LeafControlsSpec {
  const LeafControlsSpec({required this.layout, this.look = LeafLook.material, this.theme,
    this.gestures = const LeafGestureSpec(), this.keymap = LeafPlayerKeymap.standard,
    this.autoHide = const LeafAutoHide(), this.fullscreen /* spec used while fullscreen; null = this */});
  static const LeafControlsSpec mobile, desktop, uosc, minimal;
  static LeafControlsSpec adaptive({LeafControlsSpec desktop = uosc, LeafControlsSpec touch = mobile});
  LeafControlsSpec copyWith({...});
}
```

**Fitting** is a pure function, `fitBar(start, center, end, width, theme)`, so it unit-tests without widgets. It runs in a bar-level LayoutBuilder, which recomputes only when the width changes. When the bar is too narrow, it gives up room in this order:
1. The volume slider switches to slide-out on hover (sync_relay's rule).
2. The time label compacts to elapsed only.
3. Items drop into ⋯ by ascending `priority`.

Ultrawide: bars and the seek bar span the full width, with clusters at start, center and end.

### 3.7 Presets

**`mobile`** (touch; matches the legacy behaviour plus a tappable play button)
- topEnd: subtitles, settings.
- center: previous, big playPause, next, buffering.
- bottomStart: time. bottomEnd: fullscreen.
- bottomBelow: seekBar (line; knob always; 32 px hit area; tip only while dragging).
- action: skip. overlay: seekFeedback, volumeFlash, rateFlash, infoOverlay.
- Gestures: tap toggles the controls; double-tap the sides ±10 s; double-tap the middle plays/pauses. Swipe volume and brightness, and horizontal scrub, only in fullscreen.
- Fullscreen variant adds topStart: back, title.

**`desktop`** (Material; sync_relay "Standard")
- top: title, shown only in fullscreen.
- bottomAbove: seekBar (line; knob on hover; chapters; hover tip).
- bottomStart: playPause, previous, next, chapterPrevious, chapterNext, volume, time.
- bottomEnd: subtitles, audioTracks, speed, settings, fullscreen.
- center: buffering, pauseIndicator. action: skip. overlay: volumeFlash, seekFeedback, infoOverlay. whenHidden: progressLine.
- Mouse: click plays/pauses, double-click toggles fullscreen, the wheel sets volume.

**`uosc`** (sync_relay "Minimal")
- Same items as desktop, with `capsules: true`.
- Accent play button in the start capsule (previous, next, chapterPrevious, chapterNext, volume). End capsule: subtitles, audioTracks, speed, settings, fullscreen.
- bottomBelow: seekBar (band; times inside; `collapseWhenHidden`). This replaces both `time` and `progressLine`.
- Look: uosc.

**`minimal`** (bare: feed tiles, comfy_client strips)
- bottomBelow: seekBar (thin 2 px line, no knob, no tip). center: bigPlay(whilePaused). whenHidden: progressLine.
- Tap/click plays/pauses; no keymap.
- Name clash: sync_relay's "Minimal" skin is the kit's **`uosc`** preset, not this one.

**`adaptive`**: touch → `mobile`, desktop → `uosc`.

### 3.8 Theme (`controls/leaf_controls_theme.dart`)

`LeafControlsTheme extends ThemeExtension`. It resolves as `spec.theme` → `LeafPlayerDefaults.theme` → `Theme.extension` → the look's defaults built from `colorScheme`.

Tokens:
- Colours: `accent` (primary), `foreground`, `foregroundDim`, `disabled`, `hover`, `boost`.
- Bars: `barScrimTop`, `barScrimBottom`, `barScrimExtent`.
- Surfaces: `capsuleFill`, `capsuleBorder`, `bandFill`, `tooltipFill`, `panelFill`.
- Sizes: `scale`, `buttonExtent`, `iconSize`, `radius`, `fontSize`, `textStyle`.
- Looks: `buttonLook {round, flat}`, `clusterLook {bare, capsule}`.
- `seekBar` (`LeafSeekBarTheme`): line track height and hover height, band height and collapsed height, `playedTint`, `stripes`, `chapterMark {diamond, dot}`, `cacheLabelThreshold`.
- Motion: `fade` (150 ms), `transition {fade, slide, none}`.

| | `LeafLook.uosc` (from MinimalStyle) | `LeafLook.material` (from Standard) |
|---|---|---|
| Buttons | 38 px flat, radius 10, icon 22; play 26 on an accent circle | 48 px round IconButtons, icon 24, play 30 |
| Clusters | capsules 0x8C000000, border 0x1FFFFFFF 0.5, pad 4 | bare |
| Seek bar | band 0xCC0E0E12, 36 px (3 px collapsed); tint 0.4; 2 px white position line; stripes on a 7 px period; chapter dots r3.5 (×1.7 on hover); times 15 w500, inset 12 | track 3 px (5 on hover); buffered and hover white24; diamond chapter marks 8 px; knob 12 |
| Tooltip / tip | 0xEB18181C, radius 8 | Material default / black at 0.8 |
| Bar scrim | top gradient 0x99000000 → 0 over ~96 px | top 72 px; bottom 0 → 0xB3000000 with a 24 px lead |
| Other | — | volume slider 72 px; boost colour 0xFFFFB74D |

The bars clamp text scaling to at most 1.3. The seek bar and time labels are always left-to-right; clusters use start/end and so mirror in RTL.

### 3.9 Visibility and auto-hide (`controls/leaf_controls_visibility.dart`)

`LeafControlsVisibility` is a port of `ControlsFrameState`:
- `visible` (listenable); `wake()`, `hide()`, `toggle()`.
- `hold(Object who, bool on)`: set-based, notifications coalesced in a microtask.
- `suppress` (a `ValueListenable<bool>` input).
- Wakes only when the mouse really moved (more than 0.5 px); hides immediately on pointer exit; hides the cursor.

`LeafAutoHide` options:
- `delay = 3 s`; `whilePaused = false` (paused holds the controls up, as leaf does today); `hideCursor = true`; `onPointerExit = true`.
- `flashOnCommand`: key-driven seeks and volume steps briefly show the bars or the readout.
- `reveal {movement, proximity}`: proximity is uosc-style per-region reveal near the top and bottom edges, phase 5.

Built-in holds: seek drag, an open menu or panel, the pointer over a bar, a hovered `LeafControlsHoldRegion` (port), and paused.

**Viewer bridge.** On touch, inside a chrome-enabled `LeafViewer`, the visibility is an adapter onto `LeafViewerChrome`. `wake`, `hide` and `toggle` map to `show`, `hide` and `toggle`. The kit becomes the **only** writer of `chrome.hold` (`hold = holds.isNotEmpty`), and only the active page's bridge writes it. In kit mode, LeafVideoPage's "paused → hold" goes through the bridge. Without that, a playing event would release the hold while a menu is open. On desktop the kit owns its own visibility, as `LeafDesktopVideoControls` does today.

### 3.10 Gestures (`controls/leaf_player_gestures.dart`)

`LeafGestureSpec`:
- `tap {toggleControls, togglePlay, none}`.
- `doubleTapSeek = 10 s` (null turns it off); `doubleTapSideFraction = 1/3`; `doubleTapCenter {togglePlay, toggleFullscreen}`.
- `longPressRate` (null by default; 2.0 when enabled).
- `swipeVolume`, `swipeBrightness`, `horizontalScrub`, each `{never, fullscreen, always}`.
- Mouse: `click {togglePlay, toggleControls, none}`, `doubleClick {toggleFullscreen, none}` (the `DoubleClickListener` port: outside the arena, skips the bars using `overlayInsets`), `wheelVolume` (the `WheelSteps` port, claimed through `pointerSignalResolver`).

Rules:
- Inside a `LeafViewer` with swipe gestures, `always` is downgraded to `fullscreen`, because those drags belong to paging and dismiss.
- Brightness needs an app-supplied `LeafBrightnessDelegate` (`get`/`set`/`reset`); real screen brightness needs a plugin. Without one, the gesture is off.
- The seek bar wins the gesture arena on pointer-down, so a drag that starts on the bar never pages or dismisses the viewer.
- Bar backgrounds let taps through on touch and absorb clicks on desktop, matching the legacy behaviour.

### 3.11 Keyboard (`controls/leaf_player_keymap.dart`)

`LeafPlayerKeymap(List<LeafKeyBinding>)`:
- `LeafKeyBinding(key | character, {shift, control, alt, meta}, command)` has value equality, so bindings can be edited and compared. Symbols use `CharacterActivator`.
- Presets: `standard`, `mpv`, `youtube`. Editing: `merge`, `without`. `hintFor(command)` supplies tooltip text.
- It runs from a `Focus.onKeyEvent` on the controls host and returns `ignored` for keys it doesn't use in the current state.
- Buttons never take focus (`ExcludeFocus`).

| Keys | Command |
|---|---|
| Space, K | togglePlay |
| ← / → | seekBy ∓5 s |
| Shift+← / Shift+→ | seekBy ∓1 s |
| J / L | seekBy ∓10 s |
| ↑ / ↓ | stepVolume ±1 (5 %) |
| M | toggleMute |
| F | toggleFullscreen |
| Esc | close the topmost menu → panel → info; else exitFullscreen; else ignored (bubbles to the viewer) |
| PgUp / PgDn | stepChapter ∓1 |
| Shift+P / Shift+N, `<` / `>` | previous / next |
| `[` / `]`, Backspace | rate ∓0.25, reset |
| I | toggleInfo |
| C | cycle subtitles, including Off |
| S | skip the current offer |
| Shift+L | toggleLoop |
| 0–9 | seekToFraction(n/10) |
| Home | seekTo 0 |

Inside a viewer:
- Bare ←/→ (or ↑/↓ for vertical viewers) are dropped from the kit's map, so paging keeps them.
- Shift+arrows and J/L still seek, because the kit's Focus is deeper and handles them first.
- On becoming the settled page, the kit takes focus only if the primary focus is already inside the same viewer. It never steals focus from text fields.

### 3.12 Menus and panel (`controls/items/menus.dart`, `panel.dart`)

`LeafMenuEntry {id, label, hint, icon, checked, enabled, submenu (a builder), onSelected, keepOpen}`.

Menus render **inside the player's Stack**: never a route, never `showMenu`.
- Desktop: anchored above the button, clamped to the player, scrollable, with a search field above 12 items.
- Touch: a bottom panel inside the player, at most 60 % of its height, over a static scrim whose colour animates (no Opacity layer).
- Navigation: ↑/↓, Enter, Esc, type-to-search. An open menu holds the controls up.

The panel is the `PlayerPanel` host port: docked to the end (312 px on desktop, bottom sheet on touch), stays open across hide/show, closes on Esc or ×. `LeafPanelSection` gives foldable sections whose fold state is remembered per run. The app supplies the content.

### 3.13 Fullscreen (`controls/leaf_fullscreen.dart`, `leaf_player_view.dart`)

`enum LeafFullscreenMode { auto, route, inPlace, disabled }`. `auto` resolves to `inPlace` inside a `LeafViewer` (already a full-screen route) and to `route` everywhere else.

**Route mode, enter:**
1. `fullscreen` becomes true.
2. Push `LeafFullscreenRoute` on the root navigator: opaque, zero transitions, black.
3. In the next frame, the route builds `KeyedSubtree(key: view.surfaceKey, child: adapter.surface)`. The framework's `_retakeInactiveElement` takes the live element from the inline slot. I checked this path in `/opt/flutter/.../framework.dart`. The inline slot rebuilds in the same frame to a black placeholder or the thumbnail.
4. Result: the same `Video` / `NativeVideoPlayer` State, texture id and platform view; `load()` is never called again.
5. `delegate.enter(request)`.

**Route mode, exit:**
1. `fullscreen` becomes false: the route drops the key and the inline slot takes the element back in the same frame.
2. `delegate.exit()`.
3. Remove the route.
4. System back goes through `PopScope(canPop: false)` → exit, so this order always holds. Esc does the same through `exitFullscreen`.
5. If the page is disposed while fullscreen, the view removes the route synchronously before the adapter is disposed.

**Cover policy.** `LeafVideoPage` ignores its own fullscreen route while `fullscreen` is true. The route reports its own `isCurrent`, so a dialog pushed over fullscreen pauses and resumes exactly as it does today.

**The route renders:** the surface, the app's `underlay` layers, and `LeafPlayerControls(spec.fullscreen ?? spec, isFullscreen: true)`. That enables fullscreen-only gestures and the full keymap. A small error card offers Retry, which calls the page's retry hook.

**In-place mode:** no route, only the delegate. The controls switch to the `spec.fullscreen` variant where they are.

**Delegates:**

```dart
abstract class LeafFullscreenDelegate {
  const LeafFullscreenDelegate();
  Future<void> enter(LeafFullscreenRequest r);   // r: aspectRatio, videoSize, mode
  Future<void> exit(LeafFullscreenRequest r);
  ValueListenable<bool>? get externalState => null;   // OS left fullscreen by itself → kit exits
  const factory LeafFullscreenDelegate.callbacks({onEnter, onExit, externalState}) = _CallbackDelegate;
  static const LeafFullscreenDelegate none = _NoopDelegate();
  static LeafFullscreenDelegate platformDefault();    // Android/iOS → system, else none
}
class LeafSystemFullscreenDelegate extends LeafFullscreenDelegate {
  const LeafSystemFullscreenDelegate({this.immersive = true, this.lockLandscape = true,
    this.restoreUiMode = SystemUiMode.edgeToEdge, this.restoreOrientations = const []});
}
// App side, desktop, about 4 lines:
LeafFullscreenDelegate.callbacks(onEnter: (_) => windowManager.setFullScreen(true), onExit: (_) => windowManager.setFullScreen(false));
```

**When the fullscreen button shows:**
- Route mode: always, unless disabled.
- In-place mode: only if the delegate isn't `none`, and on touch only for landscape video (aspect ratio > 1). That is leafbooru's current rule.

**Fallback, only if on-device testing shows the native fork's platform-view mode can't be moved:** an optional `HasFullscreenSurface { Widget buildFullscreenSurface(); }`, so that adapter can use the fork's `isFullscreenContext` path.

### 3.14 Info overlay (`controls/items/info_overlay.dart`)

- Top-start panel on a solid translucent fill. Toggled by I, the `info` item or the settings menu. It stays up while the controls hide, like mpv's toggled stats.
- **Sections:**
  - Video: codec, W×H and display size, container fps / render fps, hwdec, pixel format, colour, bitrate, dropped frames.
  - Audio: codec, channels, sample rate, bitrate.
  - Playback: position/duration, rate, volume, buffering.
  - Cache: seconds ahead, bytes, speed.
  - Player: backend plus the adapter's `extra` lines.
  - Keys: generated from the active keymap.
- `readStats()` runs on a 1 Hz Timer **only while the overlay is mounted**.
- Without `HasVideoStats`, it shows what the controller knows (duration, position, buffer, rate, volume, video size, selected tracks).
- The source line shows only the host and file name, never the query string, because tokens appear in Jellyfin-style URLs.
- A Copy button (Clipboard) for bug reports.

### 3.15 How the audit's lessons are built in

**No per-frame repaints from position:**
- The controller throttles `position` to at most 10 Hz; labels listen to `positionSeconds` (1 Hz).
- `RenderLeafSeekBar` is a custom RenderBox that is its own repaint boundary.
  - It subscribes to the controller in `attach`/`detach` and calls `markNeedsPaint` only when the played x moves by at least 1 physical pixel.
  - Its TextPainters are cached, re-laid out only when the string changes, and disposed.
  - `shouldRepaint` compares fields.
- The clock sits in a fixed-width box with its own RepaintBoundary.
- Nothing uses an implicit animation driven by position.

**Hidden controls don't tick or keep layers:**
- A region is removed from the tree when its fade finishes.
- While hidden, the position listenable has zero listeners and its timer doesn't run.
- The only exceptions are items listed under `whenHidden` (progress line, collapsed band), the toggled info overlay, and the skip pill's offer grace period.

**No full-overlay Opacity, no BackdropFilter, small gradients:**
- The host owns one AnimationController, which ticks only during the 150 ms transitions.
- Each region fades with `Opacity` inside an `AnimatedBuilder`. That's deliberately not `FadeTransition`: RenderAnimatedOpacity keeps an OpacityLayer even at alpha 255, while `Opacity` at 1.0 has no layer.
- Every glass surface is a solid translucent fill. Scrims are gradient bands the height of their bar.

**No rebuild cascades:**
- The host returns the identical child widget while its inputs are unchanged, so a page rebuild stops at the host.
- Listeners are attached to leaf widgets only.
- A fullscreen toggle rebuilds only the surface slot.
- `LeafVideoPage` keeps its lifecycle-only `setState`; `LeafViewer` is untouched.

The guard tests and bench budgets for each of these are in section 5.

### 3.16 Where sync_relay's app-specific parts would plug in (nothing ported)

| sync_relay feature | Plug point |
|---|---|
| Party play button: ready ✓ / waiting / finished; Space = ready | `actions.playState` + `actions.onTogglePlay` |
| Seeks broadcast to everyone (user-seek path) | `actions.onSeek` |
| Chat button with unread badge, Tab | `LeafControl.action(id: 'chat', badge: unread, shortcut: Tab)` |
| ⋯ session actions (change video, copy link, reload, mark ready, mark problem, leave) | `actions.menuEntries` (Ctrl+R etc. via `keymap.merge(custom…)`) |
| Player panel (shaders, hwdec, sub scale, danmaku look) | `LeafControl.panel(builder: …)` with `LeafPanelSection` |
| NowPlayingTitle with cover, Up next popover, window buttons, collapse to mini player | `LeafControl.widget` in topEnd; `back` with `actions.onBack` |
| Danmaku, party avatars | `LeafPlayerView.underlay`; follow `controller.controlsVisible` |
| Quick chat box suppressing the controls; floating pills holding them | `LeafPlayerControls.suppress`; `LeafControlsHoldRegion` |
| Lift subtitles above the bar; toasts above the bar | `controller.overlayInsets` |
| Jellyfin segments | `actions.segments`; fixed 1:30 via `LeafSkipControl(fallback: 90 s)` |

---

## 4. Backward compatibility

**Decision: opt-in alongside the legacy widgets.** Not a reimplementation behind them.

What stays as is:
- `VideoPlayerAdapter`, `HasVolume`, `LeafVideoControls`, `LeafDesktopVideoControls` and `LeafScrubber`: unchanged.
- `LeafVideoPage` gains only optional parameters: `controls`, `actions`, `fullscreenDelegate`, `fullscreenMode`.

Which controls a page gets:
- **Kit:** when `controls` is set, or when `controlsBuilder` is null and `LeafPlayerDefaults.controls` exists.
- **Legacy:** otherwise.
- Passing both `controls` and `controlsBuilder` asserts.

Legacy parameters in kit mode:
- `skipDuration` is ignored (the spec has the value).
- `onFullscreenToggle`, when no delegate is given, becomes the in-place delegate: `callbacks(onEnter: toggle, onExit: toggle)`. leafbooru's rotation keeps working unchanged.

Why opt-in:
1. Switching the implementation would silently change the look and behaviour in kemono and leafbooru before you've confirmed it. Examples: the time format "00:30" vs "0:30", and the new center buttons on touch.
2. The legacy tests pin private structure: an `AnimatedOpacity` whose child is a `GestureDetector`, `find.byType(LeafScrubber)`, a `Slider` for volume, "00:00 / 01:00". The audit's regression tests guard the legacy path too. Forcing the kit to imitate those would warp it.
3. The audit agent is editing exactly these files. The kit lives in new files, so no merge conflicts.

Flip later (phase 6, after you've confirmed it on device):
- `LeafVideoPage`'s fallback becomes `LeafControlsSpec.adaptive()`.
- The legacy classes get `@Deprecated` and stay compiling until a version bump.

---

## 5. File plan, phases, tests, adoption

### 5.1 Files

All paths are under `/mnt/torrents/G_drive_backup/.Projects/SoyDev/Flutter/leaf_widgets/`.

```
lib/src/video/leaf_video_capabilities.dart        Has* interfaces + value types
lib/src/video/leaf_video_page.dart                 (+ controls/actions/fullscreen params, kit path via LeafPlayerView)
lib/src/video/controls/
  media_math.dart                  formatClock (compact "1:05", "1:02:03"), chapterIndexAt, chapterStepTarget,
                                   skipOfferAt, isOpening/EndingTitle, uncachedFrom, cacheLabel, bandSize, fitBar
  leaf_player_controller.dart      controller, throttled notifiers, LeafPlayerActions, LeafControlsPrefs
  leaf_player_command.dart         sealed commands
  leaf_controls_visibility.dart    visibility, holds, LeafControlsHold(+Region), viewer-chrome bridge
  leaf_controls_layout.dart        LeafSlot, LeafControlsLayout, editing helpers, fromIds/toIds
  leaf_controls_spec.dart          LeafControlsSpec + presets, LeafAutoHide, LeafPlayerDefaults
  leaf_controls_theme.dart         LeafControlsTheme, LeafLook, LeafSeekBarTheme
  leaf_player_keymap.dart          LeafKeyBinding, LeafPlayerKeymap presets
  leaf_player_gestures.dart        LeafGestureSpec, tap/double-tap/long-press/swipe/wheel/double-click
  leaf_player_controls.dart        overlay host (regions, fades, focus, open stack), LeafPlayerScope
  leaf_player_view.dart            surface host + fullscreen route
  leaf_fullscreen.dart             LeafFullscreenMode, delegates, LeafSystemFullscreenDelegate
  items/leaf_control.dart          base, catalog, generic action/toggle/menu/panel/widget/spacer/gap
  items/play_items.dart            playPause, bigPlay, pauseIndicator, buffering, previous/next, seekBy, loop
  items/seek_bar.dart              LeafSeekBar + RenderLeafSeekBar (line and band painters), tip
  items/time_items.dart            time, progressLine
  items/volume_items.dart          volume, mute, volumeFlash (WheelSteps port)
  items/track_items.dart           subtitles, audioTracks, quality, speed
  items/chapter_items.dart         chapterPrevious/Next, chapters
  items/skip_items.dart            skip pill
  items/window_items.dart          fullscreen, pip, title, back, settings, overflow
  items/info_overlay.dart          info + overlay
  items/menus.dart                 LeafMenuEntry, LeafPlayerMenu (in-player, keyboard, search)
  items/panel.dart                 LeafPlayerPanel host, LeafPanelSection
  items/flashes.dart               seekFeedback, rateFlash
lib/src/viewer/leaf_viewer_internal.dart  (+ LeafViewerScope.axis and .goToPage, internal; updateShouldNotify stays false)
lib/leaf_widgets.dart                     exports the public kit classes; render objects and menu internals stay private
example/lib/video_controls_demo.dart      feel-test: preset switcher, fake adapter with chapters/tracks/stats, width presets
```

### 5.2 Phases

**Phases 1–2** touch only new files, so they can start before the perf-audit merge. **Phase 3** waits for the merge.

1. **Foundations, no UI.** Capabilities, `media_math`, controller, commands, visibility and hold.
2. **Host, core catalog and looks.**
   - `LeafPlayerControls` with regions, fades, drop-after-fade, keymap and basic gestures.
   - Layout, fitting, presets (all five), theme.
   - Items: playPause, bigPlay, pauseIndicator, buffering, seekBar (line + band), time, progressLine, volume + wheel + flash, mute, previous/next, seekBy, title/back, the generic items, and the fullscreen button (callback for now).
   - Demo page and benchmarks.
   - Usable on its own at this point, over any surface.
3. **Page integration and fullscreen.**
   - `LeafPlayerView`, the fullscreen route and in-place mode, delegates, `LeafPlayerDefaults`.
   - LeafVideoPage parameters, cover exemption, viewer-chrome bridge, viewer-key exclusion (adds `axis` to `LeafViewerScope`), focus on activation, next/prev paging the viewer (adds `goToPage`).
   - Device checks: media_kit on Linux, and the native fork on Android in both texture and platform-view modes.
4. **Menus, tracks, info.**
   - In-player menus, the settings root menu and overflow; subtitles, audio, quality, speed, chapters, loop, chapter step, skip pill, info overlay.
   - App-side adapters:
     - `video_adapter_media_kit`: rate, tracks, chapters, playback status, video size, stats, looping.
     - leafbooru's `NativePlayerAdapter`: rate, chapters, qualities, PiP, video size.
5. **Mobile and uosc extras.** Swipe volume and brightness, long-press rate, fullscreen scrub, docked panel, PiP item, uosc proximity reveal and a vertical side volume bar, `overlayInsets`.
6. **Adoption, then the flip.** The flip happens after you confirm.

### 5.3 Widget tests (`test/video/controls/`; the existing tests stay unchanged)

- **`media_math_test`:** the ported sync_relay math (clock, chapter index/step, skip offers including the chaptered and fixed cases, OP/ED titles, uncached, cache label, band size). Plus `fitBar` wide/narrow/volume-modes/priorities.
- **`player_controller_test`:**
  - Throttle: 30 Hz in gives at most 10 Hz out; the trailing value lands; seek and pause flush; no timer without listeners.
  - `positionSeconds`; duration from stream vs. polling; pending-seek catch-up and the 2 s revert.
  - `currentChapter` and `skipOffer` notify only on change.
  - Volume step, mute/restore, clamp to max; rate step/reset; track cycling including Off; action overrides; dispose.
- **`visibility_test`:** the frame tests ported (delay, real movement, exit, cursor, drag/menu/region holds, suppress), paused hold, the bridge being the only writer of `chrome.hold`, an inactive page releasing it.
- **`layout_test`:** preset contents, `withSlot` / `without` / `insertAfter`, `fromIds` ↔ `toIds` round trip, hidden → overflow, missing capability → removed, availability flipping when tracks appear.
- **`player_controls_test`:**
  - Every preset at 320 / 360 / 412 / 800 / 1280 / 1920 / 2560 / 3440 px without overflow; drawn order matches the layout.
  - Hidden: no `LeafSeekBar`, `debugPositionListeners == 0`, `transientCallbackCount == 0`.
  - No `BackdropFilter` in any preset; no OpacityLayer once settled.
  - A page rebuild doesn't rebuild the host's subtree.
- **`seek_bar_test`:**
  - Ported marks, hover tip (title over time, above the bar), throttled drag seeks plus release, pending hold, chapter-dot jump, right-time toggle, collapsed band inert.
  - Paints only on a pixel change; no ancestor layout on ticks.
  - A drag on the bar inside `LeafViewer` doesn't page.
- **`volume_test`:** the ported volume tests plus the 1 s flash.
- **`keymap_test`:** every binding; the Esc stack order; viewer paging keys untouched; Space doesn't trigger buttons; focus is taken only when the viewer had it.
- **`gestures_test`:** double-tap zones and accumulation, tap toggling the viewer chrome, double-click not on the bars, long-press rate restore, swipe only in fullscreen.
- **`menus_test`:** ported track/chapter items, speed and quality, settings root composition with overflow, keyboard navigation and search, menu holds the controls, **no route pushed and the adapter's pause count unchanged**.
- **`fullscreen_test`:**
  - Route mode: a stateful fake surface shows 1 initState and 0 disposes across 5 cycles; adapter creates and loads unchanged; the page doesn't pause; back and Esc exit; the delegate is called once per enter/exit; disposing the page pops the route.
  - In-place mode: no route.
  - Availability rules; a dialog over fullscreen pauses and resumes.
- **`info_overlay_test`:** `readStats` at 1 Hz only while visible (0 when closed), fallback fields, URL redaction.
- **`skip_test`:** offers, labels, the grace period while hidden, the S key.

### 5.4 Headless benchmarks (`example/benchmark/`)

Plan: move `_Probe` / `_Phase` into `bench_probe.dart`, then add `controls_headless_bench_test.dart`. Also add a stateful `BenchSurface` and capability mixins on `BenchVideoAdapter`.

| Scenario | Measures | Budget |
|---|---|---|
| `kit-playing-{preset}-{hidden,visible}` (position at 30 Hz) | frames wanted/s, ticking frames, rebuilds/layouts/paints per frame, seek-bar paints/s, clock rebuilds/s, position listeners | hidden: 0 ticking, 0 rebuilds, 0 layouts, 0 listeners (desktop/uosc progress line: 1 listener, paints only on pixel changes). Visible: 0 ticking, clock ≤ 1/s, seek bar ≤ 10/s, no layouts outside the clock box |
| `kit-swipe-workload` (the existing workload with `controls: mobile`) | the same per-phase table as the audit | pageBuilds, creates and loads equal to legacy; rebuilds, layouts and paints ≤ legacy + 10 %. If neighbour-page controls break this, build them only on the settled page |
| `kit-fullscreen-cycle` (10 route cycles) | creates, loads, surface initState, pageBuilds, layer counts | all 0 extra; layers identical before and after |
| `kit-layers` | `_layerCounts` plus `BackdropFilterLayer` | settled: 0 backdrop, 0 opacity layers |
| `kit-menu-open` | plays/pauses | unchanged |
| `kit-info-overlay` | `readStats` calls/s | 0 hidden, about 1 visible |

### 5.5 What each app changes

- **kemono_browser_project** (media_kit, viewer):
  - Wrap the app once in `LeafPlayerDefaults(controls: LeafControlsSpec.adaptive())`. The adapter capabilities arrive with the shared `video_adapter_media_kit` update.
  - True OS fullscreen on desktop needs window_manager plus the 4-line delegate. Without it, the fullscreen button hides inside the viewer, because nothing would change.
- **leafbooru** (native fork, Android viewer): `LeafVideoPage(controls: LeafControlsSpec.mobile, onFullscreenToggle: …)`. The existing landscape-rotation callback becomes the in-place delegate; nothing else changes.
- **comfy_client:**
  - Replace `_VideoPage`'s raw `Video(controller:)` with `LeafVideoPage(createAdapter: () => MediaKitAdapter(loop: true), url: …, controls: LeafControlsSpec.adaptive(), fullscreenMode: inPlace or disabled)`. Its viewer already covers the window.
  - It needs the `video_adapter_media_kit` path dependency.
  - **Do the teardown fix from section 6 first.**
- **sync_relay:** no migration needed; section 3.16 shows the plug points if you ever want it.

---

## 6. Problems spotted while reading

1. **`LeafVideoPage` pauses for any route that covers it**, popup menus and dialogs included. That's why the kit's menus can't be routes, and why its own fullscreen route needs the exemption.
2. **The legacy scrubbers restart an `AnimatedContainer` on every position event.** A visible bar on a playing video requests a frame on every vsync, and the audit didn't address that state. A separate small legacy fix would be swapping it for a plain sized box. Your call.
3. **`MediaKitAdapter.dispose` disposes the Player immediately.** comfy_client's own player code documents a SEGV from disposing mid-open or mid-decode (CUVID/EGL) and sequences pause → wait → dispose. Port that sequencing into the adapter before comfy_client adopts `LeafVideoPage`.
4. **`NativePlayerAdapter`'s `playingStream`, `readyStream` and `errorStream` build a new mapped broadcast stream on every getter call.** Harmless today, but the kit adds subscribers; cache them in fields.
5. **sync_relay perf issues (1.3) aren't ported as they are:** hidden Standard bars stay mounted, the timeline painter repaints unconditionally and leaks TextPainters, and the pill, readout and panel blur over the video.
6. **Name clash:** sync_relay's "Minimal" skin = the kit's `uosc` preset.
7. **Only sync_relay has window_manager.** kemono and comfy_client get full-window, not OS, fullscreen on desktop until they add it.

## 7. Assumptions (cheap to change)

- `adaptive` uses the uosc look on desktop.
- Every desktop preset keeps click = play/pause, as leaf does today, rather than mpv's no-op click.
- Inside viewers, bare arrows stay paging; seek with J/L and Shift+arrows.
- New time format is compact "6:00 / 24:00"; legacy keeps "06:00". Before the duration is known, show elapsed only.
- Volume max defaults to 100 (media_kit's scale); the boost colour appears only when an app sets max above 100.
- Position UI rate defaults to 10 Hz.
- The skip fallback (1:30) is off by default.
- Brightness swipe and desktop PiP stay delegate-only.
- Web is not a target.
- Proximity reveal waits until phase 5.

## 8. Blocking question

Nothing blocks phases 1–5. One decision gates phase 6:

**After you've confirmed the kit on device, should `LeafVideoPage` default to it, with `LeafVideoControls` and `LeafDesktopVideoControls` marked `@Deprecated`?** My recommendation is yes. Until then it stays opt-in through `controls:` or `LeafPlayerDefaults`, so no app changes look by surprise.
