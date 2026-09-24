# Anime Watcher — Roadmap

Goal: a desktop app that indexes the anime/series/movies you already have on
disk, enriches them with metadata (MyAnimeList, later TMDB/OMDB), plays them in
a built-in player, and remembers exactly where you left off.

Status legend: ✅ done · 🚧 in progress · ⬜ not started

> Phases 1–6 are implemented and covered by unit/widget tests
> (`flutter test`, run in CI). The Linux build now compiles
> (`flutter build linux --release`) and has been smoke-tested: it launches,
> initializes GTK/Impeller and the mpv-backed player plugin without errors.
> Still needing a manual, interactive check on Windows/Linux: actually
> playing a video and the player shortcuts, the native folder pickers
> (single and bulk import), the acrylic window, real MyAnimeList requests
> and cover downloads, and the startup rescan against real drives.

---

## Phase 1 — Foundation (data layer) ✅

- ✅ Rename models to Dart conventions (`item.dart`, `MediaType` instead of
  shadowing `dart:core`'s `Type`).
- ✅ One central SQLite database in the app-support directory
  (`anime_watcher.db`), opened once through `AppDatabase`, versioned
  migrations.
- ✅ Schema:
  - `items` — one row per show/movie (MAL id, title, type, root path,
    genres, synopsis, images, airing status, episode count, score).
  - `episodes` — every video file found on disk (season, episode number,
    path).
  - `watch_progress` — position/duration/completed per episode.
- ✅ `LibraryRepository` with CRUD + progress queries; `ChangeNotifier` so the
  UI refreshes when the library changes.
- ✅ MAL client ID moved to `lib/config.dart`, overridable with
  `--dart-define=MAL_CLIENT_ID=...`.

## Phase 2 — Folder scanning & title parsing ✅

- ✅ Rewrite `TitleExtractor`: strip `[Group]`/`(2019)` tags, stop at the
  first season/quality token, case-insensitive technical-tag list, support
  `S01`, `S01-S03`, `Season 2`, `S02P01` (parts).
- ✅ `LibraryScanner`: walk a show folder, detect season sub-folders, find
  video files, parse episode numbers from file names (`S01E05`, `E05`,
  ` - 05`, `[05]`, fallback to sort order).
- ✅ Unit tests for the parser and scanner.

## Phase 3 — Add to library flow ✅

- ✅ Fix the add dialog: await MAL details, preview name/type/genres/
  episodes/seasons-on-disk before saving, real "Add To Library" button,
  loading and error states.
- ✅ Save item + scanned episodes in one transaction; reject duplicates
  (same root folder).
- ✅ Fallback: add with the typed title when MAL is unreachable / has no match
  (also used for movies and TV series until Phase 7).

## Phase 4 — Library browsing UI ✅

- ✅ Sidebar lists the real library (cover thumbnail, title, progress).
- ✅ Header: cover, title, genres, airing status, score, watched count,
  "Continue watching" button.
- ✅ Main content: episodes grouped by season, watched/partial indicators,
  click to play.
- ✅ Item actions: rescan folder, remove from library.

## Phase 5 — Playback & progress tracking ✅

- ✅ Player screen opens an episode, resumes from saved position.
- ✅ Save position periodically and on exit; mark completed at ≥ 90 %.
- ✅ Auto-advance to the next episode; back button returns to library.
- ✅ Manual "mark watched / unwatched" on episodes.

## Phase 6 — Quality of life 🚧

- ✅ "Continue watching" shelf on the home screen across all shows: shown
  when no show is selected (the new Home button in the title block), most
  recently watched first; click a card to resume, ⓘ to open the show.
- ✅ Search / filter / sort in the sidebar (title filter; sort by title,
  recently watched or recently added — the sort choice is remembered).
- 🚧 Settings page (gear button in the title block):
  - ✅ MAL client ID (stored in `settings`, overrides the built-in /
    `--dart-define` one), watched threshold (50–100 %), clear watch history.
  - ⬜ Default library folder, theme, player defaults (subtitle/audio
    language).
- ✅ Bulk import: pick a parent folder; every sub-folder not already in the
  library is scanned and matched on MAL (top result), then reviewed (keep,
  change match, search again, add without metadata, or skip) and added.
- ✅ Cache cover images locally for offline use (`<app-support>/covers/`,
  schema v2 adds `items.cover_path`; downloaded after adding and at startup
  for any item missing one; falls back to the network URL).
- ✅ Detect new episodes on disk at startup (auto-rescan in the background;
  missing folders — e.g. an unplugged drive — and folders that suddenly have
  no videos are skipped so their history is kept; one summary snackbar if
  anything changed).
- ✅ Keyboard shortcuts in the player. media_kit's desktop controls already
  handle space, J / I (±10 s), ← → (±2 s), ↑ ↓ (volume), F (fullscreen).
  Added: N / P (and Shift+N / Shift+P, media next/previous keys) for the
  next / previous episode, Esc to go back to the library (still leaves
  fullscreen first).

## Phase 7 — Movies & TV series ⬜

- ⬜ TMDB (or OMDB) client for `MediaType.movie` / `MediaType.series`.
- ⬜ Metadata-provider abstraction so the add flow is source-agnostic.

## Phase 8 — Polish & release ⬜

- ✅ Bump `win32` / `archive` in `pubspec.lock` — the previously locked
  versions do not compile on Dart ≥ 3.5.
- ✅ Remove unused dependencies (`play_video`, `json_theme`, `toastification`,
  `fullscreen_window`, `filesystem_picker`).
- ⬜ Clear remaining lints, add widget tests.
- ⬜ Toolchain floor: `pubspec.yaml` allows Dart ≥ 3.2.2 (Flutter 3.16), but
  `sqflite_common_ffi ^2.3.3` needs Dart ≥ 3.3 (Flutter ≥ 3.19), so
  `pub get` fails on 3.16. The code itself analyzes and passes all tests on
  3.16.9 when that constraint is loosened to `>=2.3.0 <2.3.3`; decide
  whether to lower the constraint or raise the SDK floor.
- ✅ CI (format + analyze + test) via GitHub Actions on ubuntu-latest.
- ✅ Linux bundle + installer: `flutter build linux --release` produces a
  self-contained `bundle/`; `packaging/linux/install.sh` installs it
  per-user or system-wide, adds a launcher and app-menu entry, and installs
  the mpv/sqlite3/gtk3 runtime libraries via pacman/apt/dnf/zypper.
- ✅ Windows installer: `.github/workflows/release.yml` builds
  `flutter build windows --release` on `windows-latest` and packages it
  with Inno Setup (`packaging/windows/installer.iss`) into
  `anime-watcher-setup_x64.exe`, which installs the app and the VC++
  runtime redistributable if it's missing, then attaches it to the GitHub
  Release for tags matching `v*.*.*`. Not yet run for real (needs a tag
  push or a manual Actions run on a Windows runner to confirm the .iss
  script works end to end).
- ⬜ App icon for the Linux `.desktop` entry beyond the placeholder
  `assets/logo.png`.

---

### Design notes

- **Central DB vs. per-folder DB.** The original sketch wrote a DB inside each
  show's folder. A single DB in the app-support directory is simpler, lets the
  sidebar list everything with one query, and survives read-only drives. If a
  "portable library" is needed later, add an export/import of watch progress.
- **Episodes are rows, not strings.** The previous `Map<int, String>` of
  season → `|`-joined paths is replaced by an `episodes` table so progress can
  be tracked per file.
- **Offline first.** Everything except the initial metadata lookup works
  without network access.
