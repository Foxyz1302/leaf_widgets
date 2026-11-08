# Post browser core: design (working doc)

Status: proposal, nothing built. Read-only audit of three apps and three shared
packages, done 2026-11-09. Code wins over this doc; where it disagrees, the doc
is stale.

**What was read**

| Repo | Branch / state |
|---|---|
| `leafbooru` | `main` (4dac888) via `git show`, and the `sheet-sketch` working tree (f1a8e7a plus whatever another agent had uncommitted at read time) |
| `pixiv_app` | `main` (0abeb3a) |
| `kemono_browser_project` | `main` working tree (has uncommitted work per its `docs/state.md`) |
| `leaf_widgets` | `master` (902bbe0) and `controls-kit` (805b68c, incl. `docs/controls-kit/`) |
| `.shared/fox_utils` | `main` (3af98f8) |
| `video_adapter_media_kit` | `master` |

Content safety (leafbooru `CLAUDE.md`, applies to all three apps): this doc
was written from code, schemas and docs only. It names no posts, tags,
creators or live URLs, and the design below carries the rule into the core
(section 5.11).

Abbreviations: **LB** leafbooru, **PX** pixiv_app, **KB** kemono_browser_project,
**LW** leaf_widgets, **FU** fox_utils, **VA** video_adapter_media_kit.

---

## 0. Headline findings

1. **Three apps, three viewers, three caches, three error stories.** PX has its
   own outer + inner `ExtendedPageView` pager and does not import `leaf_widgets`
   at all (it's in `pubspec.yaml`, zero imports). KB uses `LeafViewer` only
   inside one post's files; posts open as a dialog. LB `sheet-sketch` is the
   furthest along: `LeafViewer` + hero + teleporting minimap + PX-style
   reversed post page.
2. **The same idea is already re-ported by hand.** LB `post_minimap.dart` says
   "pixiv_app's PostMinimap"; LB `post_page.dart` says "laid out like
   pixiv_app's reversed detail page"; PX `docs/caching.md` says its cache is
   "same shape as the niggabooru neighbor project but NOT copied 1:1"; KB and
   LB carry near-identical `DioFileService` / `ImageCacheService` /
   `*ImageProvider` files. That is exactly the cost the user wants gone.
3. **The best version of each piece lives in a different app** (table in
   section 5). Nobody has all of them; every app is missing something another
   app already solved.
4. **No app handles 429 or rate limits.** KB's server asks for ≤ 1 req/s and
   ≤ 5 concurrent downloads; it is a `Now` TODO, unimplemented. LB and PX
   have nothing.
5. **Bugs and flaws to fix regardless of the core** (flagged, not touched):
   - LB `booru/sankaku.dart` `authenticate()` `debugPrint`s the access token.
   - LB Gelbooru puts `api_key`/`user_id` in the query string, and LB/PX log
     raw exceptions whose text can include the request URL → credentials and
     content in logs. KB's `safeUri` (host + path only) is the fix.
   - KB `RetryInterceptor` retries with a bare `Dio()`: no UA, no cookie, no
     interceptors (and swallows each attempt's error). Its retries of
     download-host requests go out with the default Dart UA instead of the
     identity UA, and auth-gated retries go out logged out.
   - KB `restoreSession()` blocks `runApp()` on a network login (its own TODO).
   - LB `CachedBooruImage` removes the disk file on *any* error, including
     decode errors; PX documents this as a trap (corrupt file → loop) and keeps
     the disk file.
   - LB and KB cancel a shared download when one image listener goes away
     (KB TODO "Cancel-vs-shared-download"); PX's per-URL request-seq guard
     fixes the token-race half of it.
   - FU `dio_exceptions.dart` is not exported from the barrel, so nobody can
     use it; its messages are generic and emoji-laden.
   - Credentials are plain Hive strings in all three (KB password, Sankaku
     password, Gelbooru key, PX cookie jar). Accepted as "personal app" in PX;
     never decided for the others (open question Q7).
6. **APIs are under-used** (section 8). The biggest wins already sit in client
   code with no UI: LB autocomplete (both boorus), PX search / ranking /
   follow feed / bookmarks / comments, KB global post search, linked accounts,
   comments, revisions.

---

## 1. Goals and principles

- **One design.** A gesture, a layout, a loading state or an error is decided
  once, in the core, and every app gets it. Apps only supply what the API
  forces to differ.
- **Thumb zone.** Everything the hand needs while browsing sits in the bottom
  third: actions, minimap, close, search entry, feed switch. Top of the screen
  is for content and read-only info. (LB sheet-sketch's bottom panel and PX's
  `reverseDetails` mode are the reference.)
- **Sketch-first.** New UI lands in one app as a sketch (LB `sheet-sketch` is
  the model), the user feels it on device, and only then moves into the core.
  The core never grows features no app has felt.
- **1:1 gestures.** Content follows the finger exactly; release decides by
  distance *and* velocity; nothing jumps. Pager, dismiss, pull-to-close,
  details reveal, minimap follow and hero return are all continuous. The arena
  rules in `leaf_widgets/AGENTS.md` (never physics-lock, resolve on first move)
  stay the law.
- **No duplicated UI.** One grid tile, one viewer page, one action button, one
  load-more footer, one error view. If two screens need it, it's a core widget.
- **Capabilities, not `if (source is X)`.** The core asks what a source *can*
  do and hides what it can't. No app-name checks in core code.
- **Content-safe by construction.** Logs and diagnostics never carry URLs with
  query strings, tags, titles or names (section 5.11).
- **Manual paging.** "Load more" footer that appends de-duplicated items
  (settled in PX `docs/roadmap.md`, LB does the same). KB's page numbers are
  the exception (section 5.1).

---

## 2. Package structure

### 2.1 Decision: a new package `leaf_browser` on top of `leaf_widgets`

`leaf_widgets` has a hard rule: **zero external dependencies** (its
`AGENTS.md`, `pubspec.yaml`, and the extraction rationale in KB
`docs/photo-view-evaluation.md` §6.1). The core needs dio, signals, hive_ce,
flutter_cache_manager and waterfall_flow. So the core cannot live inside
`leaf_widgets` without breaking that rule.

```
leaf_widgets            pure Flutter UI, zero deps (unchanged rule)
   ▲
video_adapter_media_kit media_kit adapter (unchanged; optional for apps)
   ▲ (injected, not depended on)
leaf_browser            NEW: Source contract, models, net, cache, stores,
   ▲                    feed/viewer/details/search/settings screens
   │      fox_utils     platform plugins only (clipboard, Android files, drop)
   │        ▲
app (leafbooru, pixiv_app, kemono_browser_project): sources + app-only parts
```

- `leaf_browser` depends on `leaf_widgets`, `fox_utils`, `dio`, `signals`,
  `hive_ce`, `flutter_cache_manager`, `waterfall_flow`, `url_launcher`.
- It does **not** depend on media_kit. Video comes in through
  `BrowserConfig.videoAdapterFactory` (a `VideoPlayerAdapter Function()`), so
  PX (no video today) doesn't pull libmpv. LB and KB pass `MediaKitAdapter`.
- Repo: `leaf_browser`, same layout and conventions as `leaf_widgets`
  (barrel, `lib/src/<system>/`, `docs/`, example app with a fixtures source).

### 2.2 What goes where

**Into `leaf_widgets` (pure Flutter, reusable outside browsers):**

| Piece | From | Notes |
|---|---|---|
| `LeafMinimap` | LB `post_minimap.dart` (sheet-sketch) + PX `inner_minimap.dart` | Takes `itemCount`, `thumbBuilder`, fractional `ValueListenable<double>`, `onJump`. Absolute follow (PX gotcha). |
| Teleport jump | LB `post_view.dart` `_teleport` / `_goTo` | Becomes `LeafViewerControls.jumpToPage(i)`: one-page animation with the target standing in, then a silent jump. Replaces PX `traversal_guard.dart`. |
| `LeafPinchLift` | LB `post_page.dart` `PinchLift` + `_TwoFingerScale` | Instagram-style lift for non-zoomable layouts. |
| `LeafAsyncButton` | LB `post_sheet.dart` `PostActionButton` | idle → running → done/failed → idle; icon + kit-bar variants. LW already has `LeafAsyncChip`; merge the two. |
| `LeafLoadMoreFooter` | LB `search_view.dart` `LoadMoreFooter` | On `ValueListenable`s (not signals) to stay zero-dep. |
| Waterfall follow math | LB `waterfall_layout.dart` `waterfallFollowOffset` | Pure function; the grid wrapper lives in `leaf_browser` (needs waterfall_flow). |
| Byte/count formatting | LB `_formatBytes` ×2, `formatCount`, `formatFileSize`; FU `formatBytes`; PX/KB local copies | One `leaf_format.dart`. |
| Controls kit | LW `controls-kit` branch | Merge to master first (it's a prerequisite, section 7). |

**Into `leaf_browser`:** everything in sections 3–5.

**Out of `fox_utils`:**

| File | Fate |
|---|---|
| `dio_exceptions.dart` | Delete. Replaced by `leaf_browser` `NetError` (typed, redacted, user message + debug text). It is unexported today, so nothing breaks. |
| `random_utils.dart` `formatBytes`, `BytesFormatter`, `NullableProgress01` | Move to `leaf_widgets` `leaf_format.dart`. The rest (`GradientText`, clippers, color utils, date extensions) stays or goes per user (Q10). |
| `error_window.dart` | Superseded by `leaf_browser` diagnostics sheet. |
| `clipboard_x.dart`, `android_files.dart`, `desktop_drop_x.dart`, vendor/ | **Stay.** Platform channels belong here. |
| `Calculator` in the barrel | Template leftover; delete. |

New in FU (proposal): `AndroidFiles.saveFromPath(path, …)` that streams a
file into MediaStore instead of taking the whole file as `Uint8List`. LB's
`downloadPost` reads the whole video into memory to save it today.

---

## 3. The `Source` interface

One `Source` per site (Gelbooru, Sankaku, pixiv, kemono-style). A source is a
plain Dart class owning its `Dio`, parsing, URL rules and auth. The core never
sees wire JSON.

```dart
abstract class Source {
  SourceId get id;                       // 'gelbooru', 'sankaku', 'pixiv', 'pawchive'
  String get name;
  SourceCaps get caps;                   // what the UI may offer (3.2)
  HostPolicy get hosts;                  // UA/Referer/limits per host (5.10)

  // Lists
  List<FeedSpec> get feeds;              // named entry feeds (3.3)
  Future<PostPage> list(FeedRequest req);          // feed, search, creator, related, family…

  // One post
  Future<Post> post(PostRef ref);                  // hydrate (detail fields)
  Future<List<Media>> media(PostRef ref);          // all pages/files, in order
  Future<Media> refreshMedia(Media m, Object error); // signed-URL renewal; throws if not applicable

  // Lookup
  Future<List<TagSuggestion>> suggest(String text);  // caps.autocomplete
  Future<Creator> creator(CreatorRef ref);           // caps.creatorPage

  // Optional delegates (null = not offered)
  AuthDelegate? get auth;
  FavoritesDelegate? get favorites;      // post favorites / bookmarks
  FollowsDelegate? get follows;          // creator follow / favorite creator
  CommentsDelegate? get comments;

  // Image/video requests
  MediaRequest requestFor(Uri url);      // headers + cache key + cache class
}
```

### 3.1 Paging

Every list is a `FeedRequest` + opaque cursor. Sources pick the cursor type;
the core never does arithmetic on it.

```dart
sealed class Cursor {}
class PageCursor   extends Cursor { final int page; }          // Gelbooru pid (0-based), Sankaku legacy (1-based)
class OffsetCursor extends Cursor { final int offset; }        // KB ?o= (50 per page)
class KeysetCursor extends Cursor { final String next; }       // Sankaku /posts/keyset meta.next
class IdQueueCursor extends Cursor { final List<String> ids; } // PX recommend nextIds; PX artist ID windows
class SampleCursor extends Cursor {}                           // PX discovery: same call, new sample, dedup-append

class FeedRequest {
  final FeedKind kind;        // feed(FeedSpec) | search(Query) | creator(CreatorRef) | related(PostRef) | family(PostRef) | favorites | follows
  final Cursor? cursor;       // null = first page
  final int? limit;
}

class PostPage {
  final List<Post> items;
  final Cursor? next;         // null = exhausted
  final int? total;           // only when the API states it (Gelbooru @attributes.count, PX search total, KB scraped)
  final List<Tag> relatedTags;// PX search relatedTags; empty elsewhere
}
```

The core's `FeedController` (section 5.1) owns dedup by `post.id`, the
generation counter against stale responses (LB `_searchGen`), and the rule
"`next == null` or zero new items → exhausted" (LB `hasMore` + PX "No new
works").

Fixes this absorbs: LB `SearchResult.hasMore(postsPerPage)` guesses from page
size; Sankaku's client sends both `page` and `next` to the keyset route; PX
artist contexts keep `orderIds` + windows by hand in `detail_screen.dart`.

### 3.2 Capability flags

```dart
class SourceCaps {
  final Set<Cap> flags;
  final Set<TagKind> tagKinds;      // which kinds the source can type (Gelbooru needs a lookup)
  final PagingStyle paging;         // loadMore | numberedPages (KB) — 5.1
  final bool exactTotals;
  final Duration? signedUrlTtl;     // KB temp_url ≈ 6 h; null = URLs are stable
}

enum Cap {
  tagSearch, autocomplete, tagTypes, negativeTags, sortMetaTags,
  creatorPage, creatorSearchLocal,       // KB: 89K creator index searched on device
  related, postFamily,                   // booru parent/children
  multiMedia,                            // >1 media per post (PX pages, KB attachments)
  video, animatedImage, ugoira, archives, htmlBody,
  comments, favoritePost, followCreator, newSinceLastVisit,
  ratingFilter,                          // PX mode all/safe/r18, booru rating:
  dimensionsInList,                      // list items carry w/h (masonry possible)
}
```

UI rule: a capability absent → its button/section/setting is not built (not
disabled). Example: `postFamily` off → no "Related" family row; `comments`
off → no comments section.

### 3.3 Named feeds

`List<FeedSpec>` is what the feed switcher shows. Each has an id, label, icon,
optional modes (rating), and whether it needs auth.

| Source | Feeds (today → proposed) |
|---|---|
| Gelbooru | search only → search, plus saved searches as feeds |
| Sankaku | search only → search, saved searches |
| pixiv | discovery (all/safe/r18) → + following latest, ranking (daily…, incl. r18), search |
| kemono | creator list (home), creator posts → + recent posts (`/posts?o=&q=`), favorite creators with "new", favorite posts |

### 3.4 Auth

```dart
abstract class AuthDelegate {
  AuthKind get kind;          // apiKey (Gelbooru: user id + key) | password→token (Sankaku)
                              // | password→cookie (KB) | pastedCookie (PX PHPSESSID → full jar)
  List<AuthField> get fields; // labels + obscure flags → generic login form
  ReadonlySignal<AuthState> get state;  // loggedOut | restoring | loggedIn | failed(reason)
  Future<void> login(Map<String, String> values);
  Future<void> restore();     // from SessionStore; MUST NOT block runApp
  Future<void> logout();
  Future<bool> recover();     // called by the auth interceptor on 401/302 (KB re-login)
}
```

### 3.5 Rate limits

Declared, not coded per call:

```dart
class HostPolicy {
  final Map<String, HostRule> rules;   // by host pattern
}
class HostRule {
  final String? userAgent;       // KB: identity UA, NEVER a browser UA on download hosts
  final String? referer;         // PX: per-call override still possible (artwork / user / ranking)
  final double? requestsPerSecond; // KB download hosts: 1
  final int? maxConcurrent;      // KB download hosts: 5
  final bool retryOn429 = true;  // honour Retry-After, back off otherwise
}
```

---

## 4. Shared models

Plain immutable Dart classes in `leaf_browser` (no dart_mappable in the core:
the sources parse wire JSON with whatever they use today; PX and KB keep their
mappable DTOs and map them to core models).

```dart
class Post {
  final SourceId source;
  final String id;
  final String? title;
  final CreatorRef? creator;           // id + name + avatar when the list item has them
  final List<Tag> tags;
  final DateTime? date;
  final Thumb thumb;                   // url + aspect (null aspect → square/cover tile)
  final MediaSummary media;            // kind + count, enough for badges and pre-sizing pagers
  final Rating rating;                 // general | sensitive | explicit | unknown
  final PostStats stats;               // score, favorites, bookmarks, views, comments — all nullable
  final bool? favorited;               // when the API says (PX bookmarkData, KB favorites index)
  final Uri? webUrl;                   // "open in browser", "copy link"
  final String? text;                  // description / HTML body (htmlBody cap says which)
  final PostExt? ext;                  // source-only data; the core never reads it
}

class Media {
  final MediaKind kind;                // image | animated | video | ugoira | archive | file
  final MediaVariants urls;            // thumb, sample, original (any may be null)
  final int? width, height, bytes;
  final Duration? duration;
  final String? fileName;
  final DateTime? expiresAt;           // signed URLs (KB temp_url), drives refreshMedia
  final MediaAvailability availability;// available | temporary | previewOnly (KB three states)
}

class Creator {
  final SourceId source; final String id; final String name;
  final Uri? avatar, banner;
  final String? service;               // KB: patreon/fanbox/…; null elsewhere
  final bool? followed;
  final DateTime? updatedAt;           // KB "new since last visit"
  final int? postCount;
  final CreatorExt? ext;
}

class Tag {
  final String name;
  final TagKind kind;                  // artist, character, copyright, general, meta, other
  final int? count;
  final String? translation;           // PX tag translations
}
```

Source extensions (in the app, `sealed`/`final class … extends PostExt`):

| App | `PostExt` fields |
|---|---|
| LB | `md5`, `parentId`, `hasChildren`, `sourceUrl`, `status`, `fileExt`, Sankaku `voteCount`, `raw` (fixtures need it) |
| PX | `illustType`, `xRestrict`, `aiType`, `bookStyle`, `pageCount`, `isBookmarkable`, `bookmarkData` |
| KB | `service`, `hasFull`, `previewState`, `embed`, `attachments` (raw `FileInfo`s), `substring` |

`MediaKind.ugoira` and `.archive` are rendered by app-registered
`MediaRenderer`s (5.4); the core only knows they exist.

---

## 5. Shared systems

For each: what each app does now → chosen design → what stays source-specific.

### 5.1 Grid / feed

| | Now |
|---|---|
| LB | `search_view.dart` `_PostGrid`: `SliverWaterfallFlow`, 2 columns on phone / 280 max extent desktop, aspect from w/h, `ResizeImage` 280 dp thumbs, animated files stay static (`gridThumbnail`), `LoadMoreFooter`, `Search` class with signals + gen counter + cursor. Grid follows the viewer (`_follow` + `waterfallFollowOffset`) and hides the hero tile (`LeafHeroSource`). Tiles: tag badges, info chips. |
| PX | `feed_screen.dart`: waterfall with user tile width 140–480 persisted (`WebSession.tileWidth`), `gridThumbUrl` rewrite for aspect-true thumbs, `minTileAspect` clamp, `TileBadge` (pages/ugoira), `RefreshIndicator`, "Load more (N shown)" footer, `FeedStore` signals. No hero, no follow. |
| KB | `creator_posts_screen.dart`: `SliverGrid` with `FixedHeightGridDelegate` (height 200, max extent 900), text+banner cards, `PostPaginator` numbered pages with total scraped from HTML. `home_screen.dart`: creator grid. `JustifiedImageGrid` for files inside a post. |

**Chosen:** `BrowserGrid` = LB grid mechanics (waterfall, follow, hero source,
static animated thumbs, `ResizeImage` decode) + PX tile-width setting and
refresh + PX `minTileAspect` clamp + one `PostTile` with a badge slot. Driven
by `FeedController` (LB `Search` generalized: signals `items`, `loading`,
`loadingMore`, `error`, `moreError`, `exhausted`, `total`; gen counter; dedup).

Why: LB's follow + hero is the only grid that keeps your place when you come
back from the viewer; PX's width control is the user's stated preference
(wishlist "choose grid item width like niggabooru").

**Source-specific:** thumb URL choice (PX `gridThumbUrl` rewrite, LB
preferSample, KB thumbnail host), badges content (`PostTile.badges` built from
`MediaSummary` + an app hook), KB card tiles when `dimensionsInList` is false
(post cards with title/date are the KB browsing unit; masonry needs sizes KB
lists don't carry). KB numbered pages: keep as `PagingStyle.numberedPages`
only if the user still wants it (Q4) — its `docs/state.md` says "Pages, not
load-more — for now".

### 5.2 Viewer / pager, minimap, dismiss, hero

| | Now |
|---|---|
| LB main | `post_view.dart`: `LeafViewer` (both-way dismiss, chrome on, page counter off), load-more as last page, `onPageSettled` → grid follow, `LeafViewerHero`, info button → `showModalBottomSheet`. Immersive system UI with cover detection. |
| LB sheet-sketch | `post_view.dart` + `post_page.dart` + `post_minimap.dart`: `LeafViewer(dismissEnabled: false)`; each page is a reversed `CustomScrollView` (media at the bottom, details above, dragging down reveals details 1:1); pull up past the media closes (`_PullCloseScrollPhysics`, 15 % or −700 px/s); minimap + action row pinned at the bottom, fading with close progress; minimap jumps teleport; hero from grid tile; double-tap opens a separate zoom view; two-finger `PinchLift`. |
| PX | `detail_screen.dart` outer `PageController` + `detail_page.dart` inner `ExtendedPageView` for multi-page; nested-drag handoff (`resolveEndVelocity`, 12 % commit), conditional keep-alive (OOM fix), neighbor prefetch of JSON + thumbs + one adjacent full, `PostMinimap` with absolute follow, `TraversalGuard` for distant jumps, artist window contexts with ±24 growth cells, optional reversed layout. No zoom (removed), no dismiss, no hero (`MaterialPageRoute`). |
| KB | `fullscreen_image_viewer_screen.dart`: `LeafViewer` over one post's files only (images `LeafZoomable`, videos `LeafVideoPage`, archive entries), size-gate pill, preview fallback, signed-URL refresh on 403. Posts themselves: `PostDetailDialog`, no paging between posts. `image_viewer_screen.dart` `MyImageViewerScreen` looks dead (no callers). |

**Chosen:** `PostViewer` = LB sheet-sketch structure, with these pieces:

- Outer pager: `LeafViewer` over the `FeedController`'s list (+ load-more page
  at the end, as LB). `dismissEnabled: false`; closing is the page's own pull
  (sheet-sketch) — one close gesture, not two. Requires LW `controls-kit`
  (hero source, `onSwipeUp`, dismiss progress).
- Page: `PostPage` = reversed scroll, media at the bottom, `PostDetails`
  sections above (5.3). Thumb zone: minimap + action row pinned at the bottom.
- Multi-media posts (PX pages, KB files): an inner horizontal pager inside the
  media slot, with PX's handoff to the outer pager (`resolveEndVelocity`,
  lazy held drag). This is the hardest port (section 7 risks). Pre-size the
  inner pager from `MediaSummary.count` so placeholder swipes work before the
  media list arrives (PX gotcha).
- Minimap: `LeafMinimap` with LB teleport jumps. PX's `TraversalGuard` goes.
- Hero: `LeafHeroSource` + `LeafViewerHero`, thumbnail-only child for videos
  (LB comment: a player inside the hero flight builds a second player).
- Zoom: double-tap → `LeafZoomable` full view (sheet-sketch `openZoomView`);
  pinch on the page → `LeafPinchLift`. Inline zoom inside the reversed scroll
  was the arena fight that made PX remove zoom; the separate view avoids it.
- Prefetch policy (PX): neighbors' JSON + thumbs sequentially, then one
  adjacent full; never a burst. Keep-alive only for active ± 1.
- System UI: LB's immersive + covered-route handling.
- Contexts (PX `docs/contexts.md`): a viewer browses the list it was opened
  from; cross-links push a new context. Keep as a core rule.

**Source-specific:** media rendering per kind (ugoira, archive pages),
KB's size gate and preview-only states (via `MediaAvailability`), PX artist
windows (an `IdQueueCursor` list with `total` known up front — the
"n / N" label comes from `PostPage.total`).

### 5.3 Details / post page

| | Now |
|---|---|
| LB sheet-sketch | `post_sheet.dart` `PostDetails`: sections "More like this" (quick-search chips for top artist/character/copyright tags), tag groups by kind with colors, facts table, source link, related family (parent + children thumbnails opening a new viewer). |
| LB main | `PostDetailsSheet` modal bottom sheet. |
| PX | `detail_page.dart`: author header (avatar from list, upgraded by `userFull`), "More from this artist" strip with ±N growth, tags web-style (`#tag` + gray translation, not tappable), related grid with `nextIds` load-more in a tinted card, chrome/bar with author. |
| KB | `PostDetailDialog`: banner, title, HTML body (`flutter_widget_from_html`), attachments split images/other, archive tiles (download → browse), favorite button, flag dialog. |

**Chosen:** `PostDetails` = list of `DetailSection`s built from capabilities,
in LB's reversed-sliver form:

1. Creator row (PX author header): avatar, name, follow button (`follows`),
   tap → creator page. KB and Sankaku have creators; Gelbooru: artist-kind
   tags stand in (tap → search).
2. Actions are *not* here — they're in the bottom row (5.5).
3. Title + text (`htmlBody` → HTML renderer, else plain).
4. Tags grouped by kind (LB), with translation (PX), tap → new search context,
   long-press → copy / add to query / exclude.
5. Facts (LB facts table, from `PostStats` + media info).
6. Creator strip "More from this creator" (PX), hidden in creator contexts.
7. Family (LB `postFamily`) / Related grid (PX `related`) — same widget,
   different `FeedRequest`.
8. Comments (`comments` cap; collapsed, loads on expand).
9. Files list for non-media attachments (KB): archives, other files.

**Source-specific:** section *content* comes from the model; only KB's
archive tile + browser and the flag dialog are app widgets plugged in via
`DetailSection.custom`.

### 5.4 Video

| | Now |
|---|---|
| LB | `video/playback_lab.dart` `LabVideoPage` wrapping `LeafVideoPage` + kit controls (`controls-kit`), MediaKit adapter, hold-for-2×, stats overlay, options panel; 4 hardware decoders; media_kit fork pin. |
| KB | `LeafVideoPage` + `MediaKitAdapter` (volume persisted) with legacy controls, identity UA + Referer headers. |
| PX | No video. Ugoira = `ugoira_player.dart`: zip range-reads via koni_archive, exact frame delays, frontier hold, 2-entry session store, minimal one-line bar. |

**Chosen:** `LeafVideoPage` with the controls kit (`LeafControlsSpec.mobile`
adapted like LB `_videoControls`), adapter from `BrowserConfig`. Hold-for-2×
and the rate flash move from LB's lab into the kit (it's on the kit's phase 4
list as `rateFlash` / long-press rate). Volume persistence (KB) becomes a
core setting. The playback lab and stats overlay stay LB debug tools.

**Source-specific:** request headers (via `requestFor`), HLS (KB `temp_url`
playlists — unhandled today), ugoira renderer (PX app, registered as a
`MediaRenderer` for `MediaKind.ugoira`; the session store and zip cache class
move with it).

### 5.5 Save / copy / download / share

| | Now |
|---|---|
| LB | `PostAction` list + `PostActionButton` (download → `AndroidFiles.save` to Downloads/Leafbooru; copy link; open in browser; save fixture), context-menu entries incl. copy image (`ClipboardX.copyImage`), copy file URL. |
| KB | Copy image / copy file (`ClipboardX`); archive download per tile (dies with the tile); downloads portal + download manager designed (`docs/downloads-portal.md`), not built. |
| PX | Nothing. |

**Chosen:** LB's `PostAction` model (id, icon, label, priority, async task)
rendered by `LeafAsyncButton` in the bottom row, overflow by priority into a
⋯ menu (and the same list feeds the long-press context menu — one list, two
surfaces). Core actions: Save, Copy image, Copy link, Open in browser, Share
(Q6), Favorite (if cap). Apps append theirs (LB fixture, KB flag/archive).

Saving goes through a `DownloadManager` built from KB's design doc: per-URL
single-flight, queue honoring `HostRule` limits, progress signals that
survive leaving the screen, cancel, cache-aware (copy from the media cache
when the original is already there, which LB does via `getFile`). Save
target: `AndroidFiles` (streaming variant, 2.2) on Android, a chosen folder on
desktop. File naming: `{source}_{postId}_{index}.{ext}` default, source can
override (KB wants the API layout, Q6).

**Source-specific:** which URL is the "original" (PX `urls.original`, KB
`downloadUrl(hasFull)`, booru `fileUrl`), multi-file save for KB posts.

### 5.6 History, favorites, follows

| | Now |
|---|---|
| LB | Last search only (`booru_auth` box `last_search`). No favorites, no history. |
| PX | None. `bookmarkAdd` + CSRF in client, unwired; `isFollowed` parsed, follow button is a placeholder. |
| KB | Server favorites for creators and posts (`AnimatedFavoriteButton`), favorited id sets in `AppState`, "new posts since last check" per creator (`last_checked.json`), local flags store. |

**Chosen:**
- `FavoritesDelegate` / `FollowsDelegate` on the source (server truth), with
  the core holding the optimistic id set (KB `favoritedIds` pattern) and the
  `AnimatedFavoriteButton` from LW.
- `HistoryStore` (core, Hive): recently viewed posts (source + id + thumb +
  time, capped) and recent searches per source. New for every app; local only.
- `LastSeenStore` (core): per creator/feed timestamp → "new" badges. KB's
  `lastChecked` generalized; PX following-latest and Sankaku/Gelbooru saved
  searches can use it too.

**Source-specific:** the server calls, KB's local favorites tree / archive
(`PLANNED_FEATURES.md`, not built — stays a KB feature).

### 5.7 Search and filters

| | Now |
|---|---|
| LB | Tag query text field in the drawer, submit → new results; tag tap pushes a new `SearchView`; Gelbooru tag types resolved in batches of 100 into a permanent Hive box; both clients have `autocomplete()` — **not called from the UI**. |
| PX | Discovery mode segmented button (all/safe/r18). `searchArtworks` in the client, unused; tags not tappable; autocomplete endpoint unknown (roadmap research item). |
| KB | Local search over the 89K-creator index (`creator_store.dart`, `nfkc_map.dart`, `creator_alias_index.dart`, `creator_sort_service.dart`), sort + filter toggles (cached only, favorites only), per-creator post filters local. |

**Chosen:** `SearchBar` in the thumb zone: chips for committed terms (tap →
edit, swipe → remove, long-press → negate if `negativeTags`), suggestions
from `Source.suggest` (debounced, typed + counted), recent searches from
`HistoryStore`, PX `relatedTags` as chips under the bar. Filters (rating,
sort) as a sheet built from `caps` (`ratingFilter`, `sortMetaTags`).
Tag-kind resolution with a permanent cache (LB Gelbooru) becomes a core
helper `TagKindCache` any source can use.

**Source-specific:** query syntax (booru metatags, PX search params,
KB `q=`), KB's on-device creator search (stays app-side, plugged in as the
`suggest` implementation for creators and as KB's home screen).

### 5.8 Auth and session storage

| | Now |
|---|---|
| LB | `BooruClient.login/restoreAuth` in `manager.dart`: per-booru user/key in Hive `booru_auth`; Sankaku re-logs in with the stored password on every launch, token never refreshed; token printed to the log. |
| PX | `web_session.dart`: pasted `PHPSESSID`, interceptor merges every `Set-Cookie` into a jar (sliding ~30 d renewal), cookie values never logged. |
| KB | `auth_state.dart` + `AuthInterceptor`: form login, 302 outcome check (success vs bounce), session cookie + username + password in Hive, re-login on 401/302 for auth paths (plain `Interceptor`, not queued — the queued one deadlocked), `restoreSession` blocks `runApp`. |

**Chosen:** `AuthDelegate` (3.4) + core `SessionStore` (one Hive box
`sessions`, per-source map) + core `CookieJar` (PX merge logic) + core
`AuthRecoveryInterceptor` (KB logic, generalized to "source says 401/302/403
means expired"). Restore runs after `runApp` with an `AuthState.restoring`
state the UI shows as a thin indicator; requests that need auth wait for it.
Generic login form from `AuthDelegate.fields`; PX keeps its paste dialog as
the form (one field, `pastedCookie`).

**Source-specific:** the login exchange itself, KB's 302 discrimination and
flash parsing, PX's CSRF token for writes.

### 5.9 Settings

| | Now |
|---|---|
| LB | `settings.dart` `_persistedSignal(box, key, default)` with an `effect` writing back; settings sheet: posts per page slider, prefer sample, frosted tags, cache stats + clear. |
| PX | `WebSession` setters per value (clamp + put), Display dialog (tile width, minimap tile size, reverse details), cookie dialog. |
| KB | `kemono_settings` box, settings popover with one toggle; full settings screen planned (`TODO_SETTINGS.md`: per-class cache stats, purge stale, storage path). |

**Chosen:** LB's persisted-signal primitive (plus PX's clamp) as
`PersistedSignal<T>(box, key, default, {clamp})`, and one `SettingsSheet`
with sections contributed by the core (Display: tile width, minimap size;
Playback: volume, autoplay; Cache: per-class stats/clear/purge as KB planned
on PX's buckets; Diagnostics) and by sources (Account; source options like
LB preferSample, PX discovery mode default). Opened from the shell's bottom
bar.

### 5.10 Networking

| | Now |
|---|---|
| LB | `Dio` per client, UA header, no timeouts, no interceptors, `validateStatus` default; Gelbooru auth in query. |
| PX | One `Dio` in `WebSession` (timeouts 10/15 s, browser UA required, per-call Referer, cookie jar interceptor); `ApiCache` Hive TTL (7 d immutable, 1 h artist, never for samples) with `deepStringKeys`; in-memory work cache (500). |
| KB | One `Dio` (timeouts 15/30 s, `validateStatus < 500`, no redirects), interceptors: cookie, `AuthInterceptor`, `ErrorDescriptorInterceptor`, `RetryInterceptor` (broken, finding 5). Identity UA required on download hosts. Server limits unimplemented. |

**Chosen:** `HttpStack.build(source)`:

```
Dio(BaseOptions(timeouts 10 s connect / 30 s receive, validateStatus < 500))
  interceptors, in order:
  1. HostHeaders      UA / Referer from HostPolicy (+ per-call override)
  2. CookieJar        attach + merge Set-Cookie (PX)
  3. AuthRecovery     401/302 on auth paths → AuthDelegate.recover() → replay once (KB)
  4. RateLimiter      per-host token bucket + concurrency cap; 429 → Retry-After or
                      exponential backoff, max 3, then NetError.rateLimited
  5. Retry            transient (timeouts, connection, 5xx) on idempotent GET only,
                      replayed through THIS dio (fixes KB), jittered backoff
  6. ErrorLog         every ≥ 400 / transport error → AppErrors (KB), redacted
```

`ApiCache` (PX) moves to the core as an opt-in per call
(`cache: ApiTtl.immutable | .short | none`). The media download path
(`FileService`) shares the same `Dio`, so images get UA, cookies and limits
for free (PX already does this: `PxFileService` uses `WebSession.dio`).

**Source-specific:** host rules, which paths are auth paths, body
classification for 403s (KB `classifyBody`: link expired / bad signature /
bot block — only the first two are retryable via `refreshMedia`).

### 5.11 Errors and logging

| | Now |
|---|---|
| LB | `debugPrint('[tag] … ${e.runtimeType}\n$st')` — content-safe by habit; error text shown raw (`e.toString()`) in the grid. Sankaku token leak. |
| PX | `debugPrint('… $e\n$stack')`; error strings from `response.message` or `e.toString()`; Retry buttons. |
| KB | `AppErrors` bounded log with `safeUri`, `classifyBody`, 1 KB body capture, Diagnostics sheet with "Copy all", reachable from the UI. |

**Chosen:** KB's `AppErrors` + diagnostics sheet in the core, plus:

- `NetError` (typed: offline, timeout, rateLimited(retryAfter), unauthorized,
  notFound, blocked, expired, server(status), parse) with `userMessage`
  (short, for the UI) and `debugText` (for the log). Replaces FU
  `dio_exceptions.dart` and the raw `e.toString()` shown to users.
- One `log(tag, error, stack)` helper: prints `runtimeType`, status, host +
  path only (KB `safeUri`), never query strings, never response bodies from
  API hosts (they contain tags/titles), never cookies/tokens. Bodies are kept
  only for non-JSON error bodies ≤ 120 chars (KB rule), which are the server's
  own messages. This is the content-safety rule as code.
- One `ErrorView` (message + Retry) and one inline `ErrorPill` for tiles and
  media (PX "Retry next to broken image"; wishlist asks it for thumbs too).

### 5.12 Navigation shell

| | Now |
|---|---|
| LB | One `SearchView` scaffold: full-screen grid, drawer opened by edge drag (half the width), drawer content anchored at the **bottom** (search bar, booru selector, auth, settings); tag searches push new `SearchView`s; back closes drawer first. |
| PX | `FeedScreen` with AppBar (refresh, display, settings) + mode segmented button at the top; artist screen pushed; dialogs for settings. |
| KB | Auth router → `HomeScreen` with separate desktop/mobile layouts, tabs, popovers for sort/filter/settings/account; creator → posts screen → dialog → viewer. |

**Chosen (sketch first, Q1):** `BrowserShell`:
- Full-bleed grid; a bottom bar in the thumb zone with: feed switcher
  (named feeds + favorites + history), search entry, settings. Scrolling down
  hides it, up shows it.
- Source switcher only where an app has several (LB) — in the feed switcher
  sheet.
- New contexts (tag search, creator, related) push routes; the predictive
  back gesture pops them. A back long-press "trail" (PX contexts gap 5) stays
  an idea.
- Desktop (KB targets Windows; PX desktop): same shell, wider grid, bottom
  bar becomes a left rail. KB's separate desktop layout goes.

---

## 6. App-specific parts (stay in the apps)

**leafbooru**
- `GelbooruSource` (dapi, `@attributes.count`, query-string auth, permanent
  tag-type cache feeding `TagKindCache`, cookie for restricted content),
  `SankakuSource` (keyset, bearer token, AVIF `preview_url` → sample fallback,
  CDN auth headers on thumbnails, author object → `Creator`).
- AVIF decode path (`flutter_avif`) as a `MediaDecoder` hook for the image
  provider.
- Fixtures source + `saveFixture` action (debug), playback lab + stats
  overlay (debug), media_kit fork pin and decoder budget.
- Android-only (no desktop target; CLAUDE.md).

**pixiv_app**
- `PixivSource` over `PixivWebClient` (pure-Dart, keeps `tool/check_*`),
  DTOs → core models, per-call Referer, browser UA, CSRF for writes.
- `gridThumbUrl` aspect-true rewrite, `minTileAspect`.
- Ugoira renderer + `UgoiraSessionStore` + its zip cache class.
- Artist windows: `IdQueueCursor` over `userWorksAll` ids, hydrated in 50s
  via `userProfileWorks` (the window walking moves into a cursor, not the
  screen).
- Discovery sampling semantics (`SampleCursor`).

**kemono_browser_project**
- `PawchiveSource`: file states (`temp_url` / stored / unavailable) →
  `MediaAvailability`, `refreshMedia` = re-fetch post and match by `path`,
  identity UA rule, server limits as `HostRule`s, scraped post count,
  302-based login discrimination.
- On-device creator index (89K, NFKC + alias index + sort service) — the KB
  home screen.
- Archives: download, LRU cache, browse, entries in the viewer (via the core
  `MediaRenderer` for `MediaKind.archive`); password-protected archives later.
- HTML body renderer choice (`flutter_widget_from_html`), size gate
  (20 MB default) as a source policy, flags store, `ImageMetaStore`
  per-creator cache stats.
- Windows + Android targets.

---

## 7. Migration

Order: LB first (it's the sketch app and closest to the target), then PX,
then KB. Each step ends with the app working; nothing waits for "the whole
core".

### Step 0 — prerequisites (leaf_widgets)
1. Merge `controls-kit` into `master` (LB already depends on the branch; PX and
   KB on master). Run its tests; on-device check per the kit's own DESIGN §8.
2. Move into LW: `LeafMinimap` (+ teleport as `jumpToPage`), `LeafPinchLift`,
   `LeafAsyncButton` (merge with `LeafAsyncChip`), `LeafLoadMoreFooter`,
   `leaf_format.dart`, waterfall follow math. LB switches to them in the same
   step (they came from LB, so behaviour is identical).
- Risk: the kit is ~11 k lines and phase 4 is open; merge only phases 1–3 and
  keep the legacy controls default (the kit's own rule).

### Step 1 — `leaf_browser` skeleton, LB as the only consumer
1. New repo; models, `Source`, `FeedController`, `HttpStack`, `AppErrors`,
   `SessionStore`, `PersistedSignal`.
2. Wrap LB's two clients as sources (`BooruClient` → `Source`; parsing stays).
   `Search` → `FeedController`.
3. Move `CachedBooruImage` / `DioFileService` / `ImageCacheService` to the
   core's media cache — **rebuilt on PX's design** (request-seq guard, no disk
   delete on decode error, per-class managers: thumbs / fulls / large),
   with an AVIF decoder hook.
4. Move the sheet-sketch viewer (`PostView`, `PostPage`, `PostDetails`,
   `PostActionRow`) into the core as `PostViewer`. LB becomes: sources,
   fixtures, lab, `main.dart`.
- Risks: sheet-sketch is still moving (another agent is on it) — wait for it
  to land on `main`, then extract. Hero + teleport + pull-close interplay
  needs on-device re-check after the move. Cache rebuild changes cache keys
  → one-time cache miss (acceptable, say so in the release).

### Step 2 — pixiv_app
1. `PixivSource` adapter over the existing client; `FeedStore` →
   `FeedController` (`SampleCursor`); grid → `BrowserGrid`.
2. Viewer: replace `DetailScreen`/`DetailPage` with `PostViewer`. Port the
   inner pager + handoff (`resolveEndVelocity`, lazy held drag) into the
   core's multi-media slot, bringing PX's tests with it
   (`inner_edge_drag_test`, `detail_loading_pager_test`,
   `detail_viewer_cap_test`, `inner_viewport_height_test`).
3. `PxFileService` / `PxImageProvider` / `ApiCache` become the core
   implementations (they were the template in step 1).
4. Ugoira as an app `MediaRenderer`.
5. Wire what the client already has (section 8): search, ranking, follow
   feed, bookmarks, follow, comments.
- Risks: the nested pager is PX's most tested and most fragile code; the
  conditional keep-alive OOM and the keep-alive-notification deadlock must
  survive the move (their tests must pass unchanged). Reversed layout becomes
  the only layout — PX's `reverseDetails = false` mode goes (Q2).

### Step 3 — kemono_browser_project
1. `PawchiveSource`; fix `RetryInterceptor` by deleting it (core `Retry`).
   Implement the server limits via `HostRule` (closes its `Now` TODO).
2. Creator posts → `BrowserGrid` (cards) + `PostViewer`; `PostDetailDialog`
   goes. Files of a post become the multi-media inner pager; the size gate,
   preview fallback and signed-URL refresh move to `Media` +
   `refreshMedia`.
3. Diagnostics/`AppErrors` already match the core (it came from KB).
4. Downloads portal = core `DownloadManager`.
5. Delete dead viewers (`image_viewer_screen.dart`, the `_ZoomableMixin`
   left-overs) — with the user's OK.
- Risks: KB has the most app-only surface (creator index, archives, desktop
  layout). Its viewer handles four page kinds; archive pages must keep
  working through the renderer hook. `restoreSession` moving after `runApp`
  changes cold-start behaviour (intended).

### Cross-cutting risks
- Three apps on one core means a core bug hits all three. Pin the core by
  commit per app (as they pin `leaf_widgets` today) and bump deliberately.
- The core must stay usable without media_kit (PX) and without desktop (LB).
- `signals` version must be one across core and apps (all on ^7.1 today).

---

## 8. What the APIs offer that the apps don't use

From the clients and docs in the repos. Items marked *(unverified)* come from
general knowledge of the API, not from repo code or docs; verify before
building.

### Gelbooru (LB `booru/gelbooru.dart`)
- **Autocomplete** — `autocomplete()` implemented, never called from the UI.
- **Total count** — `@attributes.count` parsed into `totalCount`, never shown
  ("N results" in the search bar).
- **Tag kinds for suggestions** — the tag-type cache could type the
  suggestions too (they come back untyped).
- **Family** — `parent_id` / `has_children` → used in sheet-sketch related
  row; not on `main`.
- **Comments** — dapi has a comment index (`s=comment`) *(unverified)*.
- **Sort/filter metatags** in the query (`sort:score`, `rating:`, `-tag`)
  *(unverified syntax per site)* → filter sheet + negation chips.
- **Saved searches as feeds** — no API needed; local.

### Sankaku (LB `booru/sankaku.dart`)
- **Autocomplete** with types and counts — implemented, unused.
- **Author object** (name, display name, avatar) parsed, no creator page
  (search by artist tag works today; a creator header would use the avatar).
- **Stats** — `fav_count`, `vote_count`, `comment_count` parsed; only shown
  as facts.
- **Token lifetime** — the login response likely carries a refresh token
  *(unverified)*; the client re-logs in with the password instead.
- **Favorites, votes, comments, pools/books, recommendations** endpoints
  exist on this API *(unverified)*.

### pixiv (PX `web/pixiv_web_client.dart`, `docs/api_map.md`)
- **Search** — `searchArtworks` (word, mode, sMode, order, page; `total`,
  `lastPage`, `relatedTags`, `tagTranslation`) — in the client, no UI. Tags
  aren't tappable yet.
- **Ranking** — `ranking(mode, content, p)` incl. r18 — no UI.
- **Following feed** — `followLatest(mode, p)` — no UI.
- **Bookmarks** — `bookmarkAdd` + CSRF (POST never exercised live);
  `bookmarkData` on items tells whether it's already bookmarked → filled
  heart without an extra call. Remove-bookmark endpoint not in client.
- **Follow** — `userFull.isFollowed` parsed, button is a placeholder; follow
  endpoint not in client; following list (`/ajax/user/{id}/following`) on the
  roadmap.
- **Comments** — `comments(id, offset, limit)` with `hasNext` — no UI.
- **Stats** — `bookmarkCount`, `likeCount`, `viewCount`, `commentCount` in
  detail — not shown.
- **Originals** — `urls.original` per page → Save. App has no save at all.
- **AI flag / restriction** — `aiType`, `xRestrict` → filter and badge.
- **Recommend seeds** — `recommendMethods`, `recommendSeedIllustIds` on
  discovery items → "because you viewed …" grouping *(idea)*.
- Autocomplete endpoint: unknown (roadmap research item).

### kemono-style (KB `api/pawchive_client.dart`, `docs/pawchive-api-spec.json`, `docs/server-contract.md`)
- **Recent posts feed + search** — `GET /posts?q=&o=` — not in the client.
  A "latest" feed and full-text post search.
- **Creator profile** — `GET /{service}/user/{id}/profile` — not used (app
  uses the 89K list entry).
- **Linked accounts** — `GET /{service}/user/{id}/links` — would merge the
  same creator across services into one creator page.
- **Single post prev/next** — the single-post response has next/prev fields
  (AGENTS.md) → page past the loaded list without a list call.
- **Comments** — `…/post/{id}/comments` — no UI.
- **Revisions** — `…/post/{id}/revisions` — "edited" history, no UI.
- **Announcements, fancards** (fanbox) — no UI.
- **File hash lookup** — `GET /search_hash/{hash}` → "also posted in …",
  duplicate detection.
- **Server-side flag** — `POST/GET …/flag` — the app's flags are local notes
  only.
- **Favorite posts list** — fetched into an id set; no favorites feed screen.
- **Range requests** on download hosts → archive listing by range (verified
  possible in `docs/server-contract.md`), resumable downloads.

---

## 9. Open questions for the user

1. **Shell.** Bottom bar (feed switcher + search + settings) vs LB's
   bottom-anchored drawer for every app? I propose sketching the bottom bar in
   LB first and keeping the drawer until you've felt both.
2. **One details layout.** Make the reversed page (media bottom, details
   above, pull-up close) the only layout in all apps, and drop PX's
   non-reversed mode? I propose yes — it's the thumb-zone design and two
   layouts double the viewer tests.
3. **Package home.** New `leaf_browser` repo (my proposal, keeps
   `leaf_widgets` zero-dep), or relax `leaf_widgets`' zero-dep rule and put it
   all there?
4. **KB paging.** Keep numbered pages for KB creators (its state doc says "for
   now"), or switch to load-more like the others? Load-more gives one paging
   system; numbered pages keep "page 4 of 12" for big creators.
5. **KB post unit.** Should a KB post open in the same viewer as boorus
   (swipe between posts, files as inner pages), replacing the dialog? I
   propose yes; it's the biggest UX change for KB.
6. **Saving.** Share sheet (needs a plugin like share_plus) — wanted? Save
   naming and layout: flat `App/` folder, or per source/creator/post folders
   (KB's downloads doc prefers the API layout)?
7. **Credentials.** Keep plain Hive for passwords/keys/cookies (PX's
   "personal app" call), or move to secure storage for all three?
8. **Local history.** A viewed-posts history in every app — wanted, and how
   long to keep it?
9. **Desktop.** LB is mobile-only by rule; KB is Windows-first; PX both. The
   core supports desktop either way — confirm KB stays Windows-first so the
   rail layout gets priority there.
10. **fox_utils leftovers.** `random_utils.dart` (gradient text, clippers,
    color/date extensions): keep in FU, move to LW, or delete unused parts?
11. **Fixes outside the core** (finding 5): fix the Sankaku token log and KB
    `RetryInterceptor` now in the apps, or let the migration replace them?
    The token log is a one-liner I'd fix now.
