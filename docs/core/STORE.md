# Media store: cache + downloads on one transfer engine (working doc)

Status: proposal, nothing built. Companion to `DESIGN.md` (sections 5.5,
5.10, 7). Written 2026-11-09 from code and repo docs only: no live calls, no
content viewed (leafbooru `CLAUDE.md` rule). Where code disagrees with this
doc, the doc is stale.

Abbreviations as in `DESIGN.md`: **LB** leafbooru, **PX** pixiv_app, **KB**
kemono_browser_project, **FU** fox_utils, **VA** video_adapter_media_kit.

---

## 0. Summary

Two systems that the user sees as separate, on one engine they share:

| | **Cache** | **Downloads** |
|---|---|---|
| Owner | the app | the user |
| Where | app-private dir | public storage (or a user-chosen folder) |
| Addressing | content-addressed blobs (sha256) | human-readable paths from templates |
| Lifetime | size-limited, LRU-evicted, can be cleared any time | never evicted by the app; deleted only by the user |
| Index | `cache.db` | `downloads.db`, rebuildable from the files (+ sidecars for KB) |

Shared underneath, in the package **`leaf_store`**:

- **one transfer per resource** (the transfer registry, section 2): a grid
  tile, the viewer, the video proxy and a download job all subscribe to the
  same in-flight fetch, see the same progress, and the fetch is cancelled
  only when the last interested party is gone;
- the **chunked partial-range machinery** (videos and large files);
- the **lane-aware rate limiter** and the source's dio stack (UA, cookies,
  auth recovery, signed-URL refresh, 429 / Retry-After).

Two bridges, both narrow:

1. **A download completes from cached bytes** (same variant only, 2.2): a
   finished cache blob is copied out; a partial one has only its missing
   ranges fetched.
2. **The viewer reads downloaded files** (read-only, 2.3): a resource that is
   in the downloads index is displayed from the user's file, so it is never
   duplicated into the cache. No bytes move from downloads into the cache.

The engine (registry, limiter, disk I/O, hashing, video proxy) runs in a
**store isolate**, never on the UI isolate (2.7).

`leaf_store` replaces `flutter_cache_manager` in all three apps, KB's
`ImageMetaStore` + `ArchiveCache`, PX's three managers, and KB's planned
`DownloadManager` (`docs/downloads-portal.md`). It depends on dio, drift and
path_provider only and knows nothing about `Source`, `Post` or UI, so
comfy_client (and maybe Starsync) can use it without the post-browser core.
`leaf_browser` adds the screens and the `Source` → `MediaRequest` glue.

---

## 1. What the apps do now (and why the user is unhappy)

| | LB | PX | KB |
|---|---|---|---|
| Package | `flutter_cache_manager`, 1 manager | `flutter_cache_manager`, 3 managers (`px_thumbs` 1000 / `px_fulls` 100 / `px_ugoira` 30) | `flutter_cache_manager`, 1 manager + `ImageMetaStore` JSON + `ArchiveCache` (LRU of 10, own manifest) |
| Limit | 1000 objects, 30 d | object counts per class ("the split IS the balloon protection", `docs/caching.md`) | 1000 objects, 30 d; archives 10 |
| Byte cap | none | none | none |
| Location | temp dir | temp dir | temp dir; archives in documents dir |
| Usage view | dir walk (count, MB) | none | dir walk + per-creator / per-post bytes from `ImageMetaStore` |
| Clear | all | none | all; per creator; per post |
| Decode error | **deletes the disk file** | keeps disk file, evicts memory (documented trap) | **deletes the disk file** |
| Shared fetch cancel | last listener of one provider cancels the URL's download for everyone | same callback; a request-seq guard keeps a new token from being evicted | same as LB |
| Video | not cached (URL + headers to mpv) | no video | not cached (URL + headers to mpv) |
| Downloads | reads the whole file into memory → `AndroidFiles.save` | none | archive preview download dies with the tile; portal designed, not built |
| Rate limits | none | none | none (`TODO.md`: "1 req/s, 5 concurrent, cancel must dequeue") |

**KB's cache controls, and why they're "half-assed":** the per-creator view
is the right idea (usage grouped by who it came from, clear by group), but
the numbers come from a side JSON (`ImageMetaStore`) that isn't the cache's
own index:

1. Only thumbnails are attributed: `_postUrls` builds keys from
   `imgThumbBase` only. Full images and videos opened in the viewer are in
   the cache but in no creator's total, so "clear creator" leaves them.
2. Two sources of truth drift: `flutter_cache_manager` evicts by count
   without telling `ImageMetaStore`, and `ImageMetaStore` drops entries older
   than 30 days on load without deleting the files. `TODO_SETTINGS.md` plans
   to show both numbers ("Tracked" vs "Disk").
3. No byte budget anywhere, so the only control is "clear".
4. Stats are a recursive directory walk on every open.
5. Temp dir: the OS may clear it behind the index's back.

The design keeps KB's idea (owner tags on every cache entry, usage and clear
by creator / post) inside the one index that also evicts, so it can't drift.

---

## 2. The transfer registry: one in-flight transfer per resource

### 2.1 Resource key: source-defined, never a raw URL

**Decision:** `key = source + mediaId + variant`, built by the source
(`MediaRequest.key`). Variant ∈ `thumb | sample | original` (sources may add,
e.g. PX `regular`, `ugoira_zip`).

| Source | mediaId | Notes |
|---|---|---|
| Gelbooru | post id (+ md5 hint) | |
| Sankaku | post id (+ md5 hint) | CDN URLs are **signed and expire**: the URL is never part of the key and must be re-resolvable (below). |
| pixiv | illust id + page | `ugoira_zip` is its own variant: a zip of frames, plain file caching, not video. |
| kemono | **sha256 from the file path** (`/data/<aa>/<bb>/<sha256>.<ext>`, `t1.…/f/{hash}/…`) | The key *is* the content hash: stable across the temporary → stored flip (`server-contract.md`), and the downloaded original is verified against it. A mismatch is a corrupt download. Thumbs are `…:<sha>:thumb`. |
| comfy_client / others without ids | URL with volatile parts removed | Fallback only. |

Headers are not part of the key (no current source varies bytes by header;
one that does must fold it into the mediaId).

**Re-resolving URLs.** A `MediaRequest` carries `resolve()`: an async
callback into the source that returns a fresh URL for the same
`mediaId + variant` (Sankaku: re-fetch the post's signed `file_url`; KB:
re-fetch the post, match by path, as `refreshMedia` does). It's called:

- on `403 expired / bad signature`,
- before resuming a transfer whose URL is older than the source's
  `signedUrlTtl` (`DESIGN.md` 3.2), e.g. a download paused for hours or
  resumed after a restart,
- for persisted jobs, which store `source + mediaRef` (post id, page/index,
  variant), not just a URL, so the source can rebuild the request.

A re-resolved URL must serve the **same content**: resumes send `If-Range`
with the stored `ETag` / `Last-Modified`, and the total size from
`Content-Range` must match the recorded size. Any mismatch → discard the
partial and restart; for KB the final sha256 check catches the rest.

### 2.2 Variants

- **Cache → download reuse only when the variants match.** A booru viewer
  usually shows `sample` (LB `preferSample`); a download wants `original`.
  The cached sample is never exported as the download.
- **A download always fetches `original`** (source's definition: PX
  `urls.original`, KB `downloadUrl(hasFull)`, booru `file_url`).
- **The viewer upgrades.** For the displayed post it checks `original` before
  `sample`: a complete original (downloads index or cache) is shown instead
  of the sample, with no fetch. If an original transfer is in flight (a
  download running), the viewer shows the sample/thumb, attaches to the
  original's transfer as a watcher with `visible` priority, and swaps when it
  completes.
- It never *starts* an original fetch just to upgrade; that's the user's
  choice (download, or a "view original" action).

### 2.3 How cache entries, transfers and download records relate

```
                         resource key
          ┌──────────────────┼─────────────────────────┐
          ▼                  ▼                         ▼
   cache_entries        Transfer (runtime)       download_files (downloads.db)
   key → blob sha256    one per key, in memory    job/file → key, dest path,
   (cache.db)           subscribers, progress,    state, exported path, sha256
          │             priority = max(subs)
          ▼                  │ writes into
   blobs (sha256)            ▼
   complete files      partials (cache.db)   key → staging dir, chunk bitmap,
   in c/<sha>          size, validators, owner_cache, owner_download
          ▲                  │
          └── on completion: │ adopt into blobs (move) if owner_cache
                             └ export to destination (copy) if owner_download
```

- **`Transfer`** (in memory): the one fetch for a key. It owns the network
  request(s) and writes into a **partial** (app-private staging, chunked or
  whole, section 3.3). Subscribers: grid tile, viewer, video-proxy handle,
  download job. Each subscriber declares a **sink** (`cache`, `download`, or
  just `watch`) and a **priority**.
- **`partials`** (persisted): the bytes in progress. `owner_cache` /
  `owner_download` say who will take them. Partials owned by the cache
  count against the cache budget and are evictable when unleased;
  partials owned by a download are never evicted and not in any budget.
- **`blobs` / `cache_entries`**: the content-addressed cache (section 3).
- **`download_files`**: the user's files (section 6).
- On completion: verify (size, sniff, hash), compute sha256, then: if a
  download sink is attached, **copy** to the destination; if the cache sink
  is attached, **move** the staging file into `c/<sha>` (dedup if that blob
  exists); if neither, delete the staging. When both are attached, the
  cache sink is dropped once the download's file exists (the file is the
  read source from then on, below), so the bytes aren't kept twice.

**Read order** for a key (`store.open(key)`, used by `StoreImage`, the proxy
and exports):

1. memory (`ImageCache`),
2. **downloads index** (`download_files` by key, `done`): validate the file
   still exists and has the recorded size (a `stat`; result memoized per
   session, re-checked on failure). A user-deleted or modified file → the
   row is marked `missing` and lookup falls through,
3. cache blob,
4. partial / in-flight transfer (attach),
5. new transfer.

The downloads index as a read source is the second bridge (section 0). It
never copies a downloaded file into the cache; it only avoids fetching what
the user already has.

### 2.4 The four cases the user named

| Situation | What happens |
|---|---|
| Image already in cache (same variant), user taps Download | No transfer. The job copies `c/<sha>` to the destination (streaming), then the cache entry is released early (D4: drop or keep). Nothing is re-downloaded. |
| Image still fetching (viewer or tile subscribed, same variant), user taps Download | The job **attaches** to the running transfer with a `download` sink. Same request, same progress. On completion it's written to the destination; the viewer reads it from there. |
| Download started first (grid action or a queued KB bulk job), user opens the post | The viewer **attaches** to the job's transfer with `visible` priority (the transfer jumps the host queue, 7.2), shows the transfer's progress over the thumb/sample, and displays the image on completion. If the job was still queued (no transfer yet), the viewer creates the transfer and the job joins it when the scheduler reaches it (or immediately: it sees a transfer for its key). |
| Viewer shows `sample`, user taps Download | Different variant: the job fetches `original` in its own transfer; the viewer attaches as a watcher and upgrades when it lands (2.2). |
| Video | Same registry, ranges instead of whole files: the proxy's handles and the download job are subscribers of one `ChunkFetcher` over one partial. Chunks fetched for playback count for the download and vice versa (section 5.5). |

### 2.5 Rules

- **Single flight:** `registry.attach(request, sink, priority)` returns a
  subscription to the existing transfer for the key, or starts one. Never two
  transfers for one key.
- **Observable progress:** a transfer exposes `received`, `total`, `state`
  (queued / waiting-for-slot / running / waiting-retry / done / failed) as
  signals and a stream; the tile, the viewer and the download list all bind
  to the same object.
- **Cancel only when the last interested party is gone**, after the class's
  abandon policy:
  - thumbs: 500 ms grace (a hero flight or rebuild removes and re-adds
    listeners within frames),
  - fulls: also keep going if > 50 % done or < 2 MB left,
  - a `download` subscriber never leaves on its own; it leaves when its job
    is paused or cancelled.
  Fixes LB/KB's "one listener going away cancels the shared download" and
  makes PX's request-seq guard unnecessary (one cancel token per transfer,
  owned by it).
- **Priority classes:** `visible` > `prefetch` (neighbours) > `download`
  (a user-started save) > `bulk` (creator/group jobs). Transfer priority =
  max over subscribers. A raised priority re-sorts the transfer in the
  limiter's queue, so a post the user opens jumps ahead of queued downloads
  on the same host. Host slots are reserved and bulk work is preemptible so
  the visible post never starves (7.2).
- **One slot per transfer:** a transfer shared by a viewer and a download
  counts once against the host's concurrency.
- **Pausing a download that a viewer also watches:** the job detaches; the
  transfer continues at the viewer's priority. The partial stays
  `owner_download` so the job resumes from it.

### 2.6 Progressive display

**Decision:** not progressive decoding. Show the best lower variant already
available (grid thumb or sample) with the transfer's progress ring, swap in
the full on completion. That's what "attach and show its progress" looks
like. Decoding a partial file (progressive JPEG/PNG) isn't realistic in
Flutter: the codecs want the whole buffer, and truncated input fails or
renders inconsistently per format and platform.

### 2.7 Isolates

**Decision:** the engine runs in one long-lived **store isolate**; the UI
isolate only holds thin clients.

| Store isolate | UI isolate |
|---|---|
| transfer registry, rate limiter, transfers' dio instances | `StoreImage` (attaches over a port; gets progress + final file path; decodes via `ImmutableBuffer.fromFilePath`, which loads off the Dart thread) |
| drift DBs (`cache.db`, `downloads.db`) | signals mirrored from store events (usage, queue, transfer progress) |
| disk I/O: staging writes, chunk renames, exports, rescans | `Source` logic: parsing, `resolve()`, `AuthDelegate.recover()` (answered over RPC) |
| **video proxy** (`HttpServer`) | the player (gets only the proxy URL) |
| hashing: `Isolate.run` per large file, so a 2 GB hash never stalls the proxy's event loop | |

Why: on Android, a busy UI isolate drops video frames, and a proxy on the UI
isolate would stall playback on every GC pause, layout spike or scroll.
Streaming 10+ MB/s of chunks through the UI isolate's event loop is also
what makes grids hitch today.

Cost (the real one): the source's `HttpStack` lives on the UI isolate
(cookie jar, auth state, signals). The store isolate builds **mirror dio
stacks** from a serializable `SourceNetConfig` (host rules, UA, Referer
rules, static headers) and syncs state over ports:

- cookies: the UI jar pushes snapshots on change; `Set-Cookie` seen in the
  store isolate is forwarded to the UI jar (PX's sliding renewal keeps
  working);
- `resolve()` and auth recovery are RPCs to the UI isolate (rare: expiries,
  401s);
- API (JSON) calls stay on the UI isolate's dio; when they hit a host with a
  `HostRule`, their interceptor asks the store isolate's limiter for a permit
  over the port, so there is one limiter per app.

`path_provider` and platform channels (FU file ops) are resolved on the UI
isolate and passed in, or called through `BackgroundIsolateBinaryMessenger`.

---

## 3. Cache

### 3.1 Layout

```
<appSupport>/leaf_store/
  cache.db                 drift/SQLite, WAL
  c/<aa>/<sha256>          complete whole blobs
  c/<aa>/<sha256>.d/<n>    complete chunked blobs (1 MiB chunks)
  p/<partialId>[.part|/]   partials (staging), whole or chunked
```

- **Decision: files dir (application support), not `getCacheDir()`.**
  Android may wipe the cache dir under storage pressure, behind the index's
  back (KB problem 5): partial videos, pins and cache-owned partials would
  vanish while the index still counts them. The alternative, cache dir with
  tolerance for wipes, is workable (reconcile on every start, treat every
  missing file as a miss, no pins), but it makes pins meaningless and usage
  numbers wrong until the next reconcile. With our own hard budgets the OS
  has no reason to clear for us. Cost: Android's system "Clear cache" button
  no longer clears it; the in-app storage screen does. Open to override
  (D2).
- Startup reconcile (background isolate): files without rows are deleted,
  rows without files are dropped.

### 3.2 Content addressing

- Complete blobs are named by **sha256 of their content**. Whole blobs are
  hashed incrementally while they stream into staging (large ones in a
  worker isolate); chunked blobs are hashed after completion in a worker
  isolate, then their dir is renamed into `c/`.
- **Dedup:** a cache entry points at a blob; two keys with the same bytes
  share one blob (refcounted; a blob without entries is deleted).
- **Dedup before network:** a request may carry hash hints. KB's file paths
  *are* the sha256 (`/data/<aa>/<bb>/<sha256>.<ext>`, `t1.…/f/{hash}/…`), so a
  KB file already cached under another URL (temporary → stored flip,
  `server-contract.md`) is found without a request. Booru `md5` hints go in
  a `hints(algo, value → sha256)` table and are verified when the bytes
  arrive.
- **Integrity:** a hint that doesn't match the bytes = bad download →
  discard, refetch once (3.6).
- Cost: hashing every byte fetched. Cheap for images; for a 2 GB video a few
  seconds in a worker isolate after completion. Partials are not hashed.

### 3.3 Whole vs chunked staging

| | Whole | Chunked |
|---|---|---|
| Used for | images, ugoira zips, small files | videos, big archives, anything fetched by Range or > 32 MiB |
| On disk | `p/<id>.part`, renamed on completion | dir of 1 MiB chunk files `<n>` (bytes `[n·1MiB,(n+1)·1MiB)`), each written as `<n>.part` and renamed when full (last chunk: at EOF) |
| Range map | complete or not | present chunks = directory listing, mirrored as a bitmap in `partials` |
| Read by | `ImmutableBuffer.fromFilePath` | the store's `RangeReader` (proxy, archive reader, export) |

Why chunks, not one sparse file + byte-range map:

- **Windows** (KB's main target) doesn't make files sparse by default:
  writing at offset 2 GB in a new file zero-fills the gap first (slow, full
  allocation). Needs `FSCTL_SET_SPARSE` via FFI. exFAT SD cards: same.
- **Crash safety for free:** a chunk exists only after its rename, so the
  range map can never claim bytes the disk doesn't have.
- **Partial eviction later:** cold chunks of a huge partial video could be
  evicted alone.

Cost: a 2 GB video is 2048 files (fine on ext4/f2fs/NTFS); fetches align to
chunk starts (a seek mid-chunk fetches ≤ 1 MiB extra). 1 MiB is a guess, a
constant to tune (D3). Completed chunked blobs stay chunked; export streams
the chunks (a copy either way).

### 3.4 Index schema (`cache.db`, drift)

```
blobs          sha256 PK, layout (whole|chunked), size, mime, width, height,
               bad_until, bad_count, created_at
hints          algo, value, sha256 FK                       (md5, kemono sha path…)
cache_entries  key PK, sha256 FK, source, class, owner_creator, owner_post,
               url (last known, never logged), last_access, created_at
partials       key PK, id, layout, size, chunk_bitmap, etag, last_modified,
               mime, owner_cache, owner_download, updated_at
pins           sha256 FK, reason (user|offline_post), ref, created_at
budgets        bucket (class | source:class | total), bytes
```

- `class`: `thumb | full | video | ugoira | archive | file`; sources may add.
- `owner_*`: ids from the request (KB creator/post, PX user/illust, booru
  post). Usage and clear by owner are `GROUP BY`s. Covers every class, not
  just thumbs.
- `width/height`: filled at first decode or header parse (KB
  `ImageSizeParser`); replaces `ImageMetaStore` dims for justified layouts.
- `last_access` touches are batched in memory, flushed every 30 s and on
  pause.

Why SQLite, not Hive: eviction is "oldest unpinned entries in bucket X until
under budget", usage is "sum by class / source / creator", and eviction +
pin + partial updates must be atomic. Hive keeps every row in memory, has no
aggregates or transactions; we'd rebuild KB's drift by hand. drift runs the
DB in a background isolate and has migrations; raw `sqlite3` is the no-codegen
alternative (D1). Hive stays for settings and sessions.

### 3.5 Budgets, LRU, pins, leases

- **Decision: class budgets are hard partitions.** A class only ever evicts
  its own entries, so a video can never evict thumbnails. Optional
  per-source sub-budgets inside a class (LB: Gelbooru vs Sankaku) partition
  further. There's no independent total cap; the total shown is the sum of
  the class budgets. Defaults to confirm (D6): thumbs 500 MB, fulls 2 GB,
  video 4 GB, ugoira 1 GB, archives 4 GB (sum 11.5 GB). "Per app" is
  automatic: each app has its own sandbox and store.
- **Eviction:** after each adoption, on budget change, at startup, every
  10 min while running. For each bucket over budget (source sub-budget
  first, then class), delete unpinned, unleased entries by oldest
  `last_access`, down to 90 % (hysteresis). Cache-owned partials are
  evictable the same way.
- **Pins** (persisted, cache-side "keep offline in the app"): excluded from
  eviction, shown as their own usage line, outside class budgets. Reasons:
  `user`, `offline_post`. Pins are not downloads; they never leave the app
  dir.
- **Leases** (runtime): "in use right now" (decode, video playing through
  the proxy, a download reading the blob for export). Never evicted while
  leased; eviction re-runs after release.
- **Per-entry cap** `maxEntryBytes` per class (KB's 20 MB size gate is one).
  A video bigger than the video budget plays through a partial that is not
  `owner_cache` and is deleted when the last handle leaves.

### 3.6 Corrupt files: verify, retry, then quarantine

Prevention first: staging is atomic (rename on completion), and completion
checks `Content-Length` / expected size, sniffs for HTML/JSON error bodies
served with 200 (KB `classifyBody`), and checks hash hints. A killed app
never leaves a "complete" truncated file, the main source of decode errors
today.

On a decode failure, never delete on the spot:

| Check | Verdict | Action |
|---|---|---|
| size ≠ recorded, magic is HTML/JSON/empty, or sha256 ≠ name | bad bytes | delete blob, refetch once |
| size, magic and hash fine, decode fails | unsupported format (AVIF without decoder, CMYK JPEG…) | keep, show `ErrorPill`, no refetch |
| refetched blob fails again | persistently bad | `bad_until = now + 6 h`, `bad_count++`; no automatic refetch until then; Retry forces one |

The memory `ImageCache` entry is always evicted on failure (PX). Removes
LB/KB's delete-on-any-error loop and PX's keep-truncated-forever gap.

---

## 4. Image path

```dart
final class MediaRequest {
  final String key;                  // canonical resource key (2.1)
  final Uri uri;
  final Dio dio;                     // the source's HttpStack
  final Map<String, String> headers; // per-request extras (PX Referer); the stack adds UA/cookies
  final String source, cls;
  final String? ownerCreator, ownerPost;
  final List<HashHint> hashes;       // sha256 (KB path), md5 (booru)
  final int? expectedSize;
  final Future<Uri> Function()? resolve; // fresh URL for the same mediaId+variant (2.1)
  final MediaRef? ref;               // source + post id + index + variant, for persisted jobs
}
```

`StoreImage(request, {decoder})` is PX's `PxImageProvider` generalized:

- Key `(resource key, scale)`; `ResizeImage` wraps it (LB grid).
- Hit: synchronous lookup of `cache_entries` (an in-memory key → sha map is
  kept warm), no progress events (PX: no phantom progress on hits).
- Miss: `registry.attach(request, sink: cache, priority: visible)` (`prefetch` for neighbours);
  transfer progress → `ImageChunkEvent`, so existing `loadingBuilder`s keep
  working.
- Decode from the file path (`ImmutableBuffer.fromFilePath`), never
  `readAsBytes` (LB does today). `decoder` hook for AVIF (LB `flutter_avif`).
- `addOnLastListenerRemovedCallback` → `subscription.release()`, never a
  direct cancel (2.5).
- `reloadToken` for manual Retry (PX).

---

## 5. Video path

### 5.1 The proxy

Players (mpv via media_kit; ExoPlayer via `video_adapter_native`) open URLs.
VA already takes any URL + headers (`playableForUrl`). So:

```
player ──GET /v/<token>/<handle>  Range: bytes=N-──► LocalMediaServer (dart:io HttpServer, 127.0.0.1:random)
                                                        │ present chunks: read from the partial / blob
                                                        │ missing chunk: the resource's ChunkFetcher
                                                        ▼ (source dio, Range, registry priority)
                                                     origin
```

- `store.playbackUri(request)` registers a **handle** (in memory: the
  `MediaRequest`, with its `resolve`) as a subscriber of the
  resource's transfer, and returns
  `http://127.0.0.1:<port>/v/<sessionToken>/<handle>`. The player gets **no
  headers**: UA, Referer, cookies, auth recovery, limits and signed-URL
  re-resolving all happen in the proxy (in the store isolate, 2.7, never
  the UI isolate: a UI-isolate proxy would stall playback on every frame
  spike). Bonus: credentials and signed URLs never reach mpv's logs or error
  messages. KB's expiring `temp_url` stops being the player's problem: on `403 link expired` the fetcher calls `resolve` and
  continues with the new URL under the same key.
- **Loopback only** (`127.0.0.1`, never `0.0.0.0`) with a random per-session
  secret in every URL: other apps on an Android device can reach loopback
  ports, and the proxy fetches with the user's cookies and auth headers, so
  without the secret any local app could read through the user's session.
  Unknown token or handle → `404`, nothing logged beyond the count.
- The handle **pins (leases)** the blob/partial while the player has it open
  (+ 30 s), so eviction never deletes chunks mid-play.
- Not for ugoira: PX ugoira is a zip of frames, cached as a plain whole file
  (`ugoira_zip` variant) and read by the ugoira renderer; it never touches the
  proxy.

### 5.2 Serving a request

1. Unknown size: the fetcher opens the origin with `Range: bytes=<chunk>-`
   and records total (`Content-Range`, or `Content-Length` on a 200), `ETag`,
   `Last-Modified`, `Content-Type` in `partials`.
2. Response: `206`, `Accept-Ranges: bytes`, `Content-Range: bytes N-M/total`,
   `Content-Length`, the origin's `Content-Type`. ffmpeg only marks a stream
   seekable with these; a 200 without a length makes mpv treat it as
   unseekable.
3. Body loop from `p` to `M`: present chunk → stream its file; missing →
   ask the `ChunkFetcher` and stream the bytes **from memory as they
   arrive**, while the fetcher writes the chunk file.
4. Client disconnect is normal (mpv drops the old connection on every seek):
   catch the socket error, release; the fetcher finishes its current chunk
   and stops if nobody wants the next.
5. **Crash-safe range map:** data first, map second. A chunk is written to
   `<n>.part`, flushed, renamed to `<n>`, and only then set in the bitmap in
   `partials`. On startup the bitmap is rebuilt from the directory listing, so
   a crash between the rename and the DB update loses nothing and a crash
   before the rename loses at most one chunk.

### 5.3 Fetchers and concurrency

- One `ChunkFetcher` per resource (it is the video form of a `Transfer`),
  owning a set of **origin streams**, each fetching one run of missing chunks
  with one Range request (`bytes=a-b`, `b` = the next present chunk).
- **Coalescing:** concurrent requests for overlapping or nearby ranges share
  streams. mpv probing the file end for the MP4 `moov` atom while the head is
  still loading is two streams, not one per request; a repeat probe of the
  same tail joins the existing one. A reader whose next missing chunk is
  within 2 chunks of an active stream's cursor waits on it; otherwise a new stream starts at its chunk (a seek).
  Streams nobody waits on stop after their current chunk, unless a download
  subscriber wants the whole file (then they continue at the job's `download`/`bulk`
  priority).
- No read-ahead beyond what the player asks (mpv has its own demuxer
  cache), unless "cache whole video while watching" is on.
- One writer per chunk; readers open their own handles.

### 5.4 Pitfalls

| Pitfall | Handling |
|---|---|
| MP4 with `moov` at the end: head, seek to tail, seek back | three streams in a second; on KB's download host each is a request under **1 req/s**. Up to ~1 s extra start latency there; seeks queue behind the limiter instead of bursting. |
| Scrubbing → many seeks | streams still queued when their reader leaves are dropped before they start. |
| Origin ignores Range (200 to a Range request) | mark `rangeless`; serve only sequentially from 0; if the player seeks past what's present, fall back to today's path (origin URL + headers straight to the player) for that file. |
| Unknown length (no `Content-Length`, chunked transfer encoding) | can't answer Range correctly: serve a plain `200` stream (unseekable) and cache sequentially; when the stream ends the size is known and later plays are seekable from cache. If the user seeks during that first play, fall back to direct origin playback. |
| File changed under a partial | every resume sends `If-Range: <etag or last-modified>`; a 200 instead of 206 → discard chunks, restart. |
| Redirects (CDN, signed hops) | the fetcher follows them (KB's API dio has `followRedirects: false`; file fetches must not). |
| HLS / DASH | out of scope for v1 (would need playlist rewriting + segments as whole blobs). KB's rare `master.m3u8`: prefer `temp_download_url` (progressive) as today, else the playlist URL straight to mpv with headers, uncached. PX has no video; boorus are progressive mp4/webm. |
| ExoPlayer cleartext | Android blocks cleartext HTTP for Java/OkHttp stacks (API 28+). With `video_adapter_native`, a network security config must allow `127.0.0.1`. libmpv's sockets aren't affected. |
| Android background | not needed: the proxy lives in the store isolate and video pauses when the app leaves. The server stops on detach and restarts on resume (new port + token; open handles re-register). |
| Windows loopback | bind `127.0.0.1`, not `0.0.0.0`; shouldn't trigger the firewall prompt. Verify on the KB box. |
| mpv probing (`Icy-MetaData`, HEAD) | ignore unknown headers; answer HEAD with headers, no body. |

Verdict: **feasible**, and the only approach that caches video for both
adapters *and* shares bytes with downloads. The risk is ffmpeg's HTTP
behaviour under seeks, testable offline: a local Range-capable origin +
synthetic media + scripted seeks. Setting "stream directly (no video
cache)" keeps today's path as an escape hatch.

Rejected: mpv's disk cache (per session, not reusable or exportable),
ExoPlayer `SimpleCache` (one adapter, own index and eviction), "download
first, then play" (no streaming start).

### 5.5 Downloading a partly cached video

The job attaches to the resource's `ChunkFetcher` with a `download` sink.
The partial gains `owner_download` (no longer evictable), the fetcher
computes the missing runs from the bitmap and fetches them at the job's
priority (or higher while a viewer is attached). Present chunks are never
refetched. When the bitmap is full: verify size (+ hash hint), hash, copy
out to the destination streaming the chunks, adopt into the cache if it's
`owner_cache`. The same path resumes a paused or crashed download, so
"partial reuse" isn't a special case.

---

## 6. Downloads

### 6.1 Model (`downloads.db`)

```
roots     id, kind (mediastore|saf_tree|path), uri_or_path, label
groups    id, label, source, kind (post|creator|selection), expander_id,
          cursor, filters, state, created_at
jobs      id, group_id, key, request_json, template, root_id, rendered_path,
          state, attempts, next_attempt_at, last_error (NetError kind+status,
          no URL), priority, created_at, finished_at
creators  source, service, id, name, folder                 (KB; from sidecars)
posts     source, creator_id, id, title, published, tags, url, folder, sidecar_mtime
files     id, root_id, path_or_uri, post_id, index, origin_name, kind, size,
          sha256, mtime, missing, job_id
```

Job states: `queued → running → done`, `paused`, `waiting` (retry-at, host
paused, no network, needs auth, host blocked), `failed` (permanent),
`canceled`. Persisted; a restart resumes from the partials.
`request_json` rebuilds the `MediaRequest`; the dio comes from the source
registered under `source` at startup. Stored signed URLs are expected to be
stale; jobs carry a `MediaRef`, and `resolve` runs before resuming past
the source's `signedUrlTtl` or on the first `403 expired` (2.1).

`creators` / `posts` / `files` are the **browsable index** (6.9). For KB
they're rebuildable from sidecars; for LB/PX from file names.

### 6.2 Scheduling and limits

- The scheduler picks runnable jobs by priority, then age, and attaches each
  to the registry (`sink: download`, priority `download` for user saves, `bulk` for group
  jobs). If the
  resource is a complete cache blob, there's no transfer: it copies (2.4).
- The **shared limiter** (7.2) enforces host rules across browsing, video
  and downloads: KB's 1 req/s and 5 concurrent hold for the whole app.
- User settings can lower a host's concurrency, never raise it above the
  source's `HostRule`. Global cap (default 3 active jobs), optional Wi-Fi
  only.

### 6.3 Errors and retries

| Outcome | Action |
|---|---|
| timeout, reset, 5xx, 408 | backoff + jitter (2 s, 4 s, 8 s … cap 5 min), max 8 attempts, resuming from the partial |
| 429, or 503 with `Retry-After` | wait `Retry-After` (cap 1 h); the limiter **pauses the whole host** for every lane and halves its rate for 10 min |
| 403 link expired / bad signature (KB `classifyBody`) | `resolve` → new URL → retry (same size / `If-Range` validator, 2.1) |
| 403 bot block (KB DDoS-Guard) | stop the host's queue, jobs `waiting(blocked)`, tell the user; never hammer |
| 401 / auth bounce | `AuthDelegate.recover()` via the stack; if it fails, `waiting(needs auth)` |
| 404, 410 | `failed`, no retry |
| size or hash mismatch | discard, one full retry, then `failed` |

Retries happen at the transfer level, resuming from the partial. The dio
`Retry` interceptor (`DESIGN.md` 5.10) only covers the header phase; a body
dying mid-stream would restart from byte 0 there.

### 6.4 Bulk creator downloads (KB) and groups

- A `creator` group has an **expander**: an app-registered
  `(cursor) → Future<(List<JobSpec>, nextCursor)>` walking the creator's posts
  through the source (paced by the API host's rule), yielding file jobs and
  the post's metadata for the sidecar. The cursor is persisted; expansion
  resumes after a restart. Registered by id at startup (`'kb.creator'`).
- Filters: file kinds (images / video / archives / other), date range, skip
  previews-only (`MediaAvailability`).
- **Sync** re-runs the expander and enqueues only files not already in
  `files` (matched by post id + index, or by sha256 hint). "Download new posts
  from this creator" is a sync.
- Group progress aggregates its jobs; pause / resume / cancel act on all.
- The same shape covers "save this post" for every source and "save
  selection" later.

### 6.5 Layouts

**Roots (user decision, the defaults):**

| App | Root | Layout | Why |
|---|---|---|---|
| LB | `Pictures/Leafbooru/` | flat | images and videos only; Pictures is where galleries look |
| PX | `Pictures/pixiv/` | flat | images only (ugoira saves as the zip; see below) |
| KB | `Download/Kemono/` | structured | posts carry zips, PSDs, PDFs and `post.json`; under scoped storage non-media files may only live in `Download/` or `Documents/` (6.8). With all files access KB *could* use `Pictures/`, but `Download/` keeps the same path under both permission models and doesn't put archives in a media folder. |

PX ugoira: the zip is not media, so under MediaStore-only it can't go into
`Pictures/` (6.8). Default: export ugoira as the zip into `Pictures/pixiv/`
under all files access, or into `Download/pixiv/` under MediaStore-only.
(Encoding to GIF/WebP/MP4 is a feature for later.)

**LB and PX: flat.** One folder per app, information in the file name:

| App | Default template |
|---|---|
| LB | `{source}_{post_id}.{ext}` |
| PX | `{creator_id}_{post_id}_p{index}.{ext}` |

Names carry the source and ids, so the index is rebuildable by parsing them
(6.8) and a file explorer sorts them sensibly. Creator names and titles stay
out of flat names by default (renames, length, and they're in the index
anyway); the template is editable per source.

**KB: structured** (the user's proposal, evaluated):

```
Download/Kemono/<service>/<creator name> [<creator id>]/<YYYY-MM-DD> <title> [<post id>]/
    post.json
    01 <origin filename>
    02 <origin filename>
    …
```

Assessment: good, with these rules.

- **Ids in brackets are the identity, names are cosmetic.** Folders are
  matched by `[id]`, never by name. When a creator renames, the existing
  folder is kept (found by id); a "rename folders to current names" action
  can be offered (D10).
- **Empty title** → `<YYYY-MM-DD> [<post id>]`. Date = published date, UTC,
  so it doesn't shift by time zone.
- **`NN ` prefix** keeps the post's file order and makes duplicate origin
  names (two `1.png` in one post, common) unique without a suffix.
- `service` level stays: the same person on two services is two creators in
  the API. Linked accounts (`DESIGN.md` §8) could merge them in the browse
  view, not on disk.
- Optional `creator.json` in the creator folder (id, service, name, name
  history, avatar file name) so a creator folder is self-describing too.

### 6.6 Sidecars and the index

`post.json` per KB post folder is the **source of truth** for metadata:

```json
{
  "schema": 1,
  "source": "pawchive", "service": "…",
  "creator": { "id": "…", "name": "…" },
  "post": { "id": "…", "title": "…", "published": "…", "edited": "…",
            "tags": ["…"], "url": "…" },
  "files": [
    { "name": "01 origin.ext", "origin_name": "origin.ext", "index": 1,
      "kind": "image|video|archive|other", "size": 0, "sha256": "…",
      "remote_path": "/aa/bb/<sha>.ext" }
  ],
  "downloaded_at": "…", "app": "kemono_browser_project <version>"
}
```

- Written atomically (`post.json.tmp` → rename) after each file lands, so a
  half-downloaded post is still described.
- The `downloads.db` index is a **cache of the sidecars**: built from them,
  rebuildable by rescanning the root. It survives reinstalls (rescan) and
  picks up folders moved in by hand.
- **Rescan:** walk `Download/Kemono`, read each `post.json` whose mtime changed,
  upsert `creators`/`posts`/`files`, mark files listed but absent as
  `missing` (the browse view offers re-download), index files present but
  unlisted as extra files of that post. Folders without a sidecar are
  indexed by parsing `[id]` from folder names; anything else goes to
  "Unsorted".
- Rescan runs on first start after install, on "Rescan" in the downloads
  screen, and incrementally (mtime) on app start.

**EXIF/XMP instead of sidecars:** not as the source of truth.

- EXIF/XMP exists only for some formats (JPEG, PNG, WebP, TIFF, partly
  GIF/MP4). KB attachments are often videos, zips, PSDs, PDFs, CLIP files;
  those would have no metadata at all.
- Android's share/edit paths, gallery apps, messengers and some cloud sync
  strip or rewrite EXIF; a moved file can lose its metadata silently.
- Post-level data (title, tags, file order, sibling files) doesn't belong in
  each file; reading it back means opening every file on rescan.
- Writing it means rewriting image bytes (we copy at export anyway, so it's
  doable, but it's byte surgery per format).

Bonus, later (D12): write an XMP packet (`dc:title`, `dc:subject` = tags,
`dc:source` = post URL, creator) into JPEG/PNG/WebP at export, for OS-level
search (Windows Explorer reads XMP tags in JPEGs). Android's MediaStore
doesn't index XMP keywords, so the benefit is mostly desktop.

### 6.7 File names: sanitising, length, duplicates

- **Sanitise:** NFC-normalise; strip control chars, bidi overrides
  (U+202A–202E, U+2066–2069) and zero-width chars; replace
  `<>:"/\|?*` with `_`; trim leading/trailing spaces and dots; never `.`/`..`;
  avoid Windows reserved names case-insensitively, with or without an
  extension (`CON`, `PRN`, `AUX`, `NUL`, `COM1-9`, `LPT1-9`); collapse runs of
  whitespace.
  The character set is the union of Windows and **FAT/exFAT** (SD cards)
  rules, so a folder copied to any of them survives.
- **Length:** the limit is **255 bytes per name** (ext4/f2fs/FAT/exFAT), and
  Japanese is 3 bytes per char in UTF-8, so a 90-char title is already over.
  Each segment is capped at 200 bytes (margin for ` (2)` and `.part`),
  truncated on a grapheme boundary with `…` before the bracketed id; **the
  `[id]` suffix and extension are never truncated**. Windows: whole path
  ≤ 240 chars (`MAX_PATH` 260 minus margin) unless long paths are enabled;
  shorten the title segment first, then the creator name.
- **Case-insensitive collisions:** Android's shared storage and NTFS are
  case-insensitive; compare case-folded.
- **Same name, different file:** suffix ` (2)`. **Same file (sha256):** mark
  done without writing.
- **Duplicate files across posts** (KB creators often re-attach the same file
  to several posts) are detected by sha256 (the KB key). Setting (D11):
  **copy** (default: each post folder is complete in a file explorer, which
  is the point of the layout) or **skip and reference**, listing it in
  `post.json` as `"same_as": "<relative path>"` for the browse view to
  resolve. Hardlinks aren't available through MediaStore/SAF, and Dart has no
  hardlink API.
- **Atomic writes:** path and SAF roots write `<name>.part` and rename when
  complete and verified; MediaStore inserts with `IS_PENDING = 1` and flips it
  to 0 at the end. A killed app never leaves a half file under its real name.
  Startup removes stale `.part` files the downloads DB doesn't own.

### 6.8 Android storage: the permission model

This decides what works, so the facts first.

**Verified (Android docs + MediaProvider behaviour):**

1. Through MediaStore, `Pictures/` and `DCIM/` take **images and videos
   only**; `Movies/` takes video. **Non-media files** (zip, psd, pdf, json,
   and a `.nomedia` file, which has no media MIME) can only be created in
   **`Download/` or `Documents/`**. MediaProvider rejects other paths with
   "Primary directory … not allowed … allowed directories are [Download,
   Documents]". So **an app without all files access cannot create
   `Pictures/<app>/.nomedia`**.
2. After a reinstall, the previous install's files are no longer "owned".
   Reading back media needs `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` (on
   target SDK 33+); **non-media files in `Download/` made by the previous
   install are readable only through SAF** (docs: "Storage Access Framework
   required for accessing other apps' downloads").
3. A `.nomedia` in a **top-level** standard folder (`Pictures/`, `Music/` …)
   is ignored or removed on Android 11+; in an **app subfolder**
   (`Pictures/<app>/.nomedia`) it works, except in protected camera folders
   (Android 12+).
4. `MANAGE_EXTERNAL_STORAGE` (all files access) gives plain `dart:io` access to
   shared storage, any file type, any folder. The Play Store only allows it
   for file-manager-type apps; these apps are sideloaded, so it's available.

**Not verified, must be tested on a device before relying on it:** whether
a file inserted *through MediaStore* into a folder that holds a `.nomedia`
stays out of `MediaStore.Images` / `.Video` queries on Android 11–16.
MediaProvider's scanner marks files under a `.nomedia` directory as hidden
(media type none) so gallery queries skip them, but whether an explicit
`insert` into such a folder follows the same rule, and whether every
gallery app queries MediaStore rather than walking folders, is unproven.
Test: insert an image via `MediaStore.Images` into `Download/<app>/` that
holds a `.nomedia`, then query `MediaStore.Images` and open two gallery apps;
repeat on the oldest and newest Android version at hand.

**What works under each option:**

| | (a) All files access | (b) MediaStore only |
|---|---|---|
| LB/PX save to `Pictures/<app>/` | yes, plain file writes + media scan | yes (`IS_PENDING` insert) |
| "Hide from gallery" switch | `.nomedia` in `Pictures/<app>/` (or `Download/Kemono/`), then rescan the folder with `MediaScannerConnection.scanFile` so existing files drop out (or come back when switched off) | can't create `.nomedia` in `Pictures/`. Hidden mode must save into `Download/<app>/` with a `.nomedia` there, so the switch **moves** the folder (RELATIVE_PATH update per file); and whether MediaStore-inserted files are really hidden is the unverified point above |
| KB structured `Download/Kemono/…` with zips/psd/pdf/`post.json` | yes | yes for writing (Download takes any type) |
| KB index rebuild after reinstall (read `post.json`) | yes, `dart:io` rescan, no prompt | **no** with MediaStore alone (non-media from the old install is unreadable). Needs a one-time SAF pick of `Download/Kemono` after reinstall (allowed: a subfolder of Download, not its root), then rescans go through slow SAF listings |
| LB/PX index rebuild after reinstall | yes | yes with `READ_MEDIA_IMAGES/VIDEO` (names carry ids) |
| Folders moved in by hand | yes | KB: only via the SAF grant |
| Rescan speed (thousands of files) | `dart:io`, fast | SAF `ContentResolver` queries, slow (query `DocumentsContract` children with a projection; never `DocumentFile` per file) |
| Platform code in FU | none for I/O; one "request all files access" intent; media-scan call | streaming `saveFromPath` into MediaStore, RELATIVE_PATH moves, SAF tree ops (create, write stream, list, read) |

**Recommendation (D7): (a) all files access** for all three apps on
Android. It's one settings grant per app, makes the hide switch a
`.nomedia` toggle in place, keeps KB's sidecar rebuild trivial after a
reinstall, and keeps the I/O in `dart:io` in the store isolate. Fallback if
the user declines the grant: (b) for LB/PX (visible mode in `Pictures/<app>/`,
hidden mode in `Download/<app>/`, pending the device test), and for KB the
writes still work but rebuilding after a reinstall needs the SAF pick.

**Privacy switch:** "Hide downloads from gallery", **per app, off by default**
(user decision). On: `.nomedia` in the app's download root + rescan. Off:
remove it + rescan. KB's root is a separate switch from LB/PX by nature (each
app has its own).

Desktop (KB Windows, PX): a chosen folder, plain paths; no gallery concern.

### 6.9 Browse downloads (in the app)

A view over `downloads.db`, not over the network:

- **KB:** creators → posts → files, the same grid/viewer widgets as online
  browsing, fed from local files. Filter by creator, post, date range, file
  kind (images / video / archives / other), tags; sort by post date,
  download date, size, name. Search by title.
- **LB / PX:** a flat grid of saved files, filter by source / creator (PX) /
  kind, sort by date or size.
- Per item: open in viewer (local), open folder (desktop) / share (Android),
  go to the online post, delete (files + sidecar entry, with confirm),
  re-download missing files, "sync new" (KB creator).
- "Saved" state on online posts/files comes from the same index (by post id
  / sha256), so the viewer can show a filled save icon.

### 6.10 Android background work

Options:

1. **Own Dart downloader + a foreground service while jobs are active.**
   The service only keeps the process (and the Dart isolate) alive; the work
   stays in Dart with the source's dio, the registry, the limiter and the
   chunk fetchers. Its required notification is the progress notification.
   Android 14+: `foregroundServiceType="dataSync"` +
   `FOREGROUND_SERVICE_DATA_SYNC`; Android 15 caps `dataSync` at 6 h per
   24 h, after which the queue pauses until the app is foreground again.
   Android 13+ needs `POST_NOTIFICATIONS`. Via `flutter_foreground_task` or
   a ~100-line native service in FU.
2. **`background_downloader`** (native WorkManager / URLSession transfers,
   survives app death, notifications and pause/resume built in). Doesn't fit:
   requests leave the dio stack (no cookie merge, auth recovery, signed-URL
   refresh, shared limiter, Retry-After host pause); it writes its own files,
   so it can't share a transfer with the viewer or fill a partial video; its
   task DB would be a third index. Its Dart-side per-host queue only runs
   while the app is alive anyway.
3. Android 14 user-initiated data transfer jobs: the right OS API, native
   only; a later replacement for option 1's service if the 6 h cap bites.

Recommendation: **option 1** (D5). Desktop needs nothing.

The trade-off, stated plainly: option 1 keeps every rule in one place (Dart:
registry, range cache, limiter, sidecars) but **only runs while the process
lives**. If the user swipes the app away or the OS kills it (OEM battery
managers, the 6 h cap), transfers stop and resume from their partials on the
next launch. `background_downloader` would keep native transfers going after
a kill, at the price of a second network stack and none of the sharing this
design is built on.

Notifications: one ongoing "N downloading · X MB/s", one per finished group
("Saved 34 files"), one for host blocks / auth needed. Tap → downloads.

---

## 7. Networking integration

### 7.1 One stack per source

Every transfer uses `MediaRequest.dio`, the source's `HttpStack`
(`DESIGN.md` 5.10). KB's identity UA on file hosts, PX's Referer and cookie
jar, KB's cookie + auth recovery, Sankaku's CDN auth headers all apply to
thumbnails, the video proxy and downloads with no extra code.
`Source.requestFor(uri)` (`DESIGN.md` §3) builds the `MediaRequest`.
Apps outside the browser core (comfy_client) build `MediaRequest`s with
their own dio.

### 7.2 The rate limiter is shared, per host, priority-ordered

- One limiter registry per app, keyed by **host** (not by dio): two sources
  on one CDN share its budget. Rules from `HostRule` (rps, maxConcurrent).
- The `RateLimiter` interceptor reads the transfer's priority from
  `Options.extra`; the queue is ordered by priority, then age, and re-sorted
  when a transfer's priority is bumped (2.5).
- **Starvation guard (decision): reserve + preempt.** If KB's 5 slots were
  all held by bulk downloads, the visible post would wait for a whole file.
  - **Reserve:** `download` + `bulk` together may hold at most
    `maxConcurrent − 1` slots on a host (KB: 4 of 5); the last slot is only
    used by `visible` / `prefetch`. Hosts with `maxConcurrent` 1 have nothing
    to reserve and rely on preemption.
  - **Preempt:** if a `visible` transfer has waited > 300 ms with no free
    slot, the newest `bulk` transfer on that host is paused: request
    cancelled, partial kept, requeued to resume via `Range`. `download`
    (user-started) is preempted only when no `bulk` is running; `prefetch`
    never preempts.
  - **rps tokens** go to the highest-priority waiter first, so on a 1 req/s
    host a visible request is next in line, not behind queued bulk starts.
  - A transfer preempted 3 times in a minute is held for 30 s, so flicking
    through posts doesn't thrash it.
- A slot is held until the **response body ends**, not when headers arrive
  (dio interceptors see the response at headers; the registry releases the
  slot when the stream closes). Otherwise "5 concurrent downloads" would
  count header exchanges.
- 429 / `Retry-After` pauses the host for every priority and surfaces
  `NetError.rateLimited(retryAfter)` to callers that can't wait (a tile shows
  a retry pill instead of hanging).
- KB: download hosts 1 req/s + 5 concurrent; thumbnail host unpaced
  (`server-contract.md`). PX, boorus: no stated limits; default 6 concurrent
  per host, no rps, 429-aware.

### 7.3 Logging

Logs carry a short hash of the resource key, class, host, status and
`NetError` kind. Never URLs, file names, template output, owner ids or
sidecar fields (`DESIGN.md` 5.11). The indexes hold URLs and names on device
because refetch, export and browse need them; diagnostics never print them.

---

## 8. Settings and UI

All in `leaf_browser` (the store exposes signals and queries only).

**Storage (cache) screen**
- Stacked bar per class, plus "Pinned". Downloads are **not** on this
  screen's bar (they're the user's files), only a link to them.
- Per class: used / budget, budget slider (eviction runs at once), Clear.
- Per source rows when an app has several (LB).
- "By creator" / "By post" drill-in (KB's existing sheet, now every class):
  sorted by size, clear and pin per row.
- Pinned list with unpin; partial videos: count + bytes, "Clear partials".
- "Clear all except pinned". Location shown read-only.

**Downloads**
- Root overlay button, bottom-left, badge = active count (KB portal §5),
  opening the queue sheet; a full screen for long lists.
- Queue: groups with aggregate progress, expandable to files; per job state
  chip, progress, speed; pause / resume / retry / cancel / open / go to post.
  Pause all / resume all; filter active / finished / failed.
- Host status lines: "file host: rate limited, resuming in 40 s",
  "blocked: check user agent".
- Browse tab (6.9).
- Settings: "Hide from gallery" switch (per app, off by default, 6.8),
  root folder / storage mode, per-host concurrency (≤ source max),
  Wi-Fi only, naming template per source with a preview on synthetic sample
  data, duplicate policy (KB), Rescan.

**In the viewer / grid**
- Save = `LeafAsyncButton` bound to the job; shows the shared transfer's
  progress; filled when the index has the file. Long-press → "Save post".
- A tile or viewer page whose resource is being downloaded shows the
  download's progress (it's the same transfer).
- Video: "cached 82 %" in the controls' info; Download fills the gaps (5.5).
- KB creator page: "Download all" / "Sync new" → creator group.

---

## 9. Packages: reuse vs build

| Package | Verdict |
|---|---|
| `flutter_cache_manager` | **Drop.** Count-only eviction, no byte cap, whole files only, temp dir, an index we can't query by class/owner, and it deletes behind side-stores' backs (KB drift). Its in-flight dedup is the only part we need; the registry replaces it. |
| `cached_network_image` | **No.** Built on flutter_cache_manager; no app uses it; `StoreImage` replaces it. |
| `dio_cache_interceptor` | **No for media** (HTTP-semantics response cache, buffers bodies, no ranges or class budgets). **No for API JSON either:** these APIs send no useful cache headers; PX's TTL `ApiCache` (moving to the core) fits better. |
| `background_downloader` | **No as the base** (6.10: bypasses the dio stack, can't share transfers or fill partials, a third task DB). Revisit only if "survives app kill" becomes a must. |
| `extended_image` | **No.** Own cache, same issues. |
| `drift` (+ `sqlite3_flutter_libs`) | **Use** for `cache.db` / `downloads.db`. Alternative: raw `sqlite3` (D1). |
| `flutter_foreground_task` | **Use** for the Android service, or a tiny native service in FU (D5). |
| `flutter_local_notifications` | **Maybe**, for completion notifications if the service's own isn't enough. |
| `crypto` | **Use** (already transitive): sha256 / md5 in a worker isolate. |
| `shelf` | **No.** `dart:io` `HttpServer` is enough for one Range route. |
| `connectivity_plus` | **Optional**, only for "Wi-Fi only". |
| `native_exif` / XMP writers | **Not now.** If D12 is a yes, write the XMP packet ourselves at export (JPEG APP1 / PNG iTXt / WebP XMP chunk); plugins mostly cover EXIF on JPEG only. |
| mpv cache / ExoPlayer `SimpleCache` | **No** (5.4). |

---

## 10. Phased plan

**Phase 1: registry + image cache + flat downloads (LB, PX)**
1. `leaf_store`: store isolate, `cache.db`, content-addressed blobs,
   whole-file staging, atomic adoption, class budgets, LRU, pins, leases,
   reconcile, usage/clear queries, corrupt-file policy.
2. Transfer registry: source-defined keys + variants, `resolve`, single
   flight, sinks, refcounted cancel with abandon policies, priority classes;
   `StoreImage` with the read order (downloads → cache → transfer).
3. Shared limiter: priority order, slot reservation, bulk preemption,
   Retry-After host pause (lands with `DESIGN.md` step 1).
4. Downloader core: `downloads.db`, jobs, scheduler, retries, Range resume,
   templates + sanitising, flat layouts in `Pictures/<app>/`, name-parsed
   rescan, hide-from-gallery switch, all-files-access grant (D7) or
   MediaStore fallback.
5. Storage screen + downloads overlay/queue.
6. Migration in `DESIGN.md` order (LB, PX): first run deletes the old
   `flutter_cache_manager` dirs (one-time cache miss; say so in the release).
   Single-post saves are short, so no foreground service yet.

**Phase 2: KB structured downloads, index, foreground service**
1. `Download/Kemono/` structured layout, `post.json` sidecars,
   sidecar-built index + rescan, duplicate policy.
2. Creator bulk download + sync (expanders), groups. Closes KB's rate-limit
   TODO. KB cache migration (drops `ImageMetaStore` / `ArchiveCache`).
3. Android foreground service + notifications (bulk jobs are what need it).
4. Browse downloads view (KB tree; LB/PX flat grid).

**Phase 3: video cache (the proxy)**
1. Chunked staging + crash-safe bitmap, `RangeReader`, `ChunkFetcher` as the
   video transfer.
2. `LocalMediaServer` in the store isolate; VA gets `playbackUri`; leases;
   `resolve` in the proxy; fallbacks (rangeless, unknown length);
   `maxEntryBytes`.
3. Offline test harness (Range origin + synthetic media + scripted seeks:
   moov-at-end, scrub, disconnect). "Stream directly" escape hatch.
4. Bonus: `RangeReader` serves `koni_archive` range reads, so KB archive
   listings and PX ugoira zips read from partials (`server-contract.md`).

**Phase 4: completing downloads from partial video ranges**
1. Download jobs attach to `ChunkFetcher`s; gap runs; `If-Range`
   validation; export from chunks.
2. "Download" on a playing or partly cached video completes from cache.

**Could phase 3 start simpler? (open question, D15)** A "3a" without range
machinery: keep today's playback (origin URL + headers straight to mpv); when
a video has been played to the end (or past 80 %), enqueue a whole-file cache
fill at `bulk` priority; replays play the cached file via `file://`.

- For: ships video caching without touching the player path; reuses phase 1
  whole-file staging and the downloader unchanged; zero proxy risk.
- Against: every first play downloads the file **twice** (mpv's stream + the
  fill), which on KB's 1 req/s / 5-concurrent hosts doubles the load; no
  benefit while watching (seeks still go to the origin); credentials still go
  to mpv; nothing for phase 4 (a fill is all-or-nothing). And the eventual
  proxy needs the chunked staging anyway, so 3a is throwaway except for the
  `file://` replay path.

My view: worth it only as a stopgap if phase 3 slips; otherwise go straight
to the proxy, since its risk is testable offline.

**Later:** HLS via playlist rewrite; cold-chunk eviction; XMP at export
(D12); hardlink export on desktop; UIDT jobs on Android 14+; ugoira → GIF/MP4
export.

**Risks**
- ffmpeg/mpv HTTP behaviour against the proxy (seeks, reconnects,
  seekability) is the biggest unknown; mitigated by the harness and the
  escape hatch. ExoPlayer adds the cleartext config.
- KB's 1 req/s makes every seek a queued request: video start and seeks on KB
  file hosts get slower than today's direct mpv (which ignores the limit).
  That's the price of obeying the server.
- Mirror dio stacks in the store isolate (2.7) are new complexity: cookie
  sync and RPC for `resolve`/auth must be right or transfers run logged out.
- Android 15's 6 h `dataSync` cap and OEM battery killers stop long bulk
  downloads in the background; jobs resume, but not unattended overnight on
  every phone.
- Scoped storage: the MediaStore fallback can't hide `Pictures/` folders
  and can't read KB sidecars after a reinstall without a SAF pick; whether
  MediaStore inserts into a `.nomedia` folder stay hidden is untested.
- Sidecar/index drift when the user edits folders by hand: rescan fixes it,
  but the index is only as fresh as the last rescan.
- Hashing everything costs CPU (worker isolate) and adds seconds after a big
  video completes.
- Migration drops every existing cache once. New native dep (SQLite) in all
  apps; Hive stays for settings.
- Chunk size 1 MiB is a guess.

---

## 11. Decisions

**Settled by the user** (defaults in this doc): cache and downloads are
separate systems; one transfer per resource shared by display and download;
LB/PX save flat to `Pictures/<app>/`; KB saves structured with `post.json`
sidecars (to `Download/Kemono/`, justified in 6.5); a browse-downloads view;
"Hide from gallery" is a per-app switch, off by default.

**Decided in this doc** (override if wrong): keys = source + mediaId +
variant, KB keyed by sha256 and verified (2.1); downloads always fetch
`original`, viewer upgrades (2.2); downloads index is a read source (2.3);
priority classes with slot reservation + bulk preemption (7.2); engine and
proxy in a store isolate (2.7); class budgets as hard partitions (3.5); no
progressive decoding (2.6).

**Open for the user:**

1. **D1 Index:** drift (recommended: background isolate, migrations) or raw
   `sqlite3` (no codegen)? Hive isn't proposed (no aggregates/transactions).
2. **D2 Cache location:** files dir (recommended; pins and partials survive,
   system "Clear cache" won't touch it) or the OS cache dir (tolerate wipes,
   no meaningful pins)?
3. **D3 Partial storage:** 1 MiB chunk files (recommended, Windows- and
   crash-safe) or one sparse file + range map?
4. **D4 Bridges:** you said the only bridge is "complete a download from
   cached bytes". This doc adds a second, read-only one (the viewer shows a
   downloaded file instead of fetching, 2.3) because the review asked for
   it and it avoids duplicates. Keep it? And after copying a cached blob out,
   drop the cache copy (recommended, the file is the read source now) or keep
   it until LRU evicts it?
5. **D5 Android background:** own downloader + foreground service
   (recommended) or `background_downloader`? Plugin or native in FU?
6. **D6 Budgets:** thumbs 500 MB, fulls 2 GB, video 4 GB, ugoira 1 GB,
   archives 4 GB? Per-source sub-budgets exposed (only LB has two sources)?
7. **D7 Android permission model:** (a) all files access for all three apps
   (recommended; sideloaded), with (b) MediaStore as the fallback if a user
   declines. Will any of these apps ever go to the Play Store? (That would
   rule out (a).)
8. **D8 Video:** every video through the proxy (uniform headers, resolve,
   no credentials in mpv) or only when video caching is on?
9. **D9 Abandon policy:** thumbs cancel after 500 ms grace, fulls keep going
   past 50 %: right defaults?
10. **D10 Creator renames (KB):** keep folders found by `[id]` (recommended)
    with a manual "rename to current names", or rename automatically?
11. **D11 Duplicate files across KB posts:** copy (recommended default) or
    skip with a `same_as` reference? (It's a setting either way.)
12. **D12 XMP:** write XMP into images at export as a desktop-search bonus,
    later?
13. **D13 Flat names:** LB `{source}_{post_id}.{ext}`, PX
    `{creator_id}_{post_id}_p{index}.{ext}`: good, or include creator names?
14. **D14 Package:** separate `leaf_store` (recommended, usable by
    comfy_client without the browser core) or inside `leaf_browser`? What
    would Starsync need (not read here)?
15. **D15 Video stopgap:** "3a" (cache after full playback, no proxy) as a
    first step, or straight to the proxy (recommended)?
16. **D16 Device test:** run the `.nomedia` + MediaStore-insert test (6.8)
    before committing to the fallback's hidden mode.
