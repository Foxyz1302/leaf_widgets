# Controls kit: resume state (2026-10-23)

DESIGN.md (alongside this file) is authoritative. Scope: phases 1–4, opt-in, the legacy controls are never edited here (their changes arrive through perf-audit merges), local only.

## Done
- e6b45d4 (WIP, phase 1 partial), new files only, not exported from the barrel yet:
  - `lib/src/video/leaf_video_capabilities.dart`: the 10 `Has*` abstract mixin classes, plus value types (`LeafTrack`/`LeafTracks`, `LeafChapter`, `LeafTimeRange`, `LeafQuality`/`LeafQualities`, `LeafSkipKind`, `LeafSkipSegment`, `LeafVideoStats`).
  - `lib/src/video/controls/media_math.dart`: ported from sync_relay, plus `skipOfferAt`/`LeafSkipOffer`.
  - `test/video/controls/media_math_test.dart`: 14 tests.
- Deviations so far:
  - `skipOfferAt` is generalised: an app segment > an OP/ED chapter ("Skip <title>" if ≤16 chars) > a fixed fallback (off by default).
  - `LeafSkipOffer` equality ignores the target.
  - `LeafTrack.adapterLabel` is the field; the `label` getter formats it.
  - `chapterIndexAt` returns the list position.

## Next
1. Finish phase 1:
   - `leaf_player_command.dart`: sealed commands with value equality, plus a `dismiss` command for Esc (close menu → panel → info → exit fullscreen).
   - `leaf_player_controller.dart`:
     - timer-throttled position (the trailing value lands; seeks and play/pause flush; no timer without listeners; `debugListenerCount`);
     - `positionSeconds = pendingSeek ?? raw` (the pending seek clears within 1.5 s of the target and drops after 2 s);
     - duration via `HasPlaybackStatus`, else re-read with change detection;
     - without that capability, buffering is true until the first frame;
     - `skipFallback`, the fullscreen attach point, the volume/toggle flash ticks, a redactable `source` URL, `LeafPlayerActions`, `LeafControlsPrefs`.
   - `leaf_controls_visibility.dart`:
     - a timer port of `ControlsFrameState`;
     - a `LeafViewerChrome` bridge as the sole writer of `chrome.hold`, with an `Expando` owner per chrome;
     - `LeafControlsHold`/`LeafControlsHoldRegion`, with microtask-coalesced notifications.
   - `fitBar` as a pure function over `LeafFitItem`.
   - Tests: `player_controller_test`, `visibility_test`.
2. Phase 2:
   - Fades: one 150 ms AnimationController; AnimatedBuilder → Opacity; regions removed after the fade. A `persistent` flag keeps buffering, pauseIndicator and the band mounted.
   - Inside LeafViewer, build controls on the settled page only. The kit owns the only buffering spinner. `minimal` adds buffering at the centre (a deviation).
   - `RenderLeafSeekBar`: paints its own tip, uses an eager recognizer and a MouseTrackerAnnotation, repaints only on ≥1 physical px, caches and disposes its TextPainters.
   - Input: touch through a GestureDetector; mouse through a Listener (click on down) plus a DoubleClickListener port that skips the bars via overlayInsets. Bars sit in ExcludeFocus; the host takes focus on pointer-down.
3. Phase 3:
   - Merge perf-audit FIRST (it brings P2's deferDispose and the scrubber fix).
   - The fullscreen route uses `KeyedSubtree(surfaceKey)`, swapped by one notifier, so the element moves within a single frame.
   - Remove the route after the frame, then dispose the adapter.
   - Cover exemption: use the fullscreen route's `isCurrent`.
   - In kit mode the page never writes `chrome.hold`.
4. Phase 4:
   - Adapter worktrees: `git -C <repo> worktree add ../<repo>-wt/controls-kit -b controls-kit` for video_adapter_media_kit (39b639e) and video_adapter_native (c11c47f), each with an uncommitted pubspec_overrides.yaml pointing at this worktree. Changes stay additive.
   - media_kit 1.2.6: map its streams, `set*Track` (with `.no()` for off), `setPlaylistMode`, and `chapter-list` via NativePlayer `observeProperty`. Put the §6.3 dispose sequencing in the adapter.
   - The native fork has NO chapters API: its tracks are futures, so poll them. leafbooru's adapter goes in as a diff only.
   - Linux demo: a scratch app OUTSIDE example/ (system libmpv + an ffmpeg-made clip with chapters, 2 audio tracks and subtitles).
