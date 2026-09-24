# Anime Watcher

A Flutter desktop app that indexes the anime you already have on disk,
matches it against MyAnimeList, plays it in a built-in player, and
remembers exactly where you stopped. Everything except the initial
metadata lookup works offline.

Point it at a show's folder → it parses the title/season, matches it on
MyAnimeList (cover, genres, synopsis, score), lists every episode on disk,
and plays them with resume support.

### Status

Linux and Windows desktop are the supported targets (no mobile/web build).
The core flows — library scanning, adding shows, browsing, playback and
progress tracking, search/sort, bulk import, cover caching, startup rescan
— are implemented and covered by `flutter test`, and the Linux build has
been built and smoke-tested end to end (launches, initializes GTK/Impeller
and the mpv-backed player plugin cleanly). See [ROADMAP.md](ROADMAP.md) for
the phase-by-phase breakdown of what's done and what's still open (movies
and TV series support, a few settings, packaging polish).

### Features
- Add a show folder → title/season parsed from the folder name → matched on
  MyAnimeList (cover, genres, synopsis, score).
- Episodes grouped by season (with specials), parsed from file names like
  `S01E05`, `Show - 05`, `EP05`, `[05]`.
- Built-in player (media_kit / mpv): resumes where you left off, marks an
  episode watched at 90 %, auto-plays the next one.
- "Continue" button picks the next episode to watch.
- Rescan a folder to pick up new downloads; mark episodes watched/unwatched.
- Home view with a "Continue watching" shelf across all shows.
- Search and sort the library (title, recently watched, recently added).
- Bulk import: point at a folder of show folders, review the MAL matches,
  add them all.
- New episodes are picked up automatically at startup (unplugged drives are
  skipped).
- Covers are cached locally for offline use.
- Settings: MyAnimeList client ID, watched threshold, clear watch history.
- Player shortcuts: space, J / I, arrows, F, plus N / P for next/previous
  episode and Esc to go back.

## Running from source

Requires the Flutter SDK (stable channel) with Linux desktop support
enabled (`flutter config --enable-linux-desktop`).

**Runtime/build libraries** — the built-in player links against mpv, and
the database uses sqlite3 at runtime:

```sh
# Arch
sudo pacman -S --needed mpv sqlite gtk3 base-devel cmake ninja clang pkgconf

# Debian / Ubuntu
sudo apt install libmpv-dev libsqlite3-dev libgtk-3-dev cmake ninja-build clang pkg-config
```

Then:

```sh
git clone <this repo>
cd anime-watcher
flutter pub get
flutter run -d linux   # or -d windows
```

A built-in MyAnimeList client ID is included so it works out of the box;
use your own with `--dart-define=MAL_CLIENT_ID=<id>`, or set one later in
Settings.

The library database and cached covers live in the app-support directory
(`anime_watcher.db`, `covers/`).

## Building a release / installing it

```sh
flutter build linux --release
```

produces a self-contained bundle at `build/linux/x64/release/bundle/`
(the Flutter engine, app code and assets are all in there — the only
things it still needs from the host are the system libraries above, which
`ldd` shows are otherwise universal desktop-Linux libraries, not anything
specific to this app). To install it as a normal application:

```sh
./packaging/linux/install.sh          # installs to ~/.local, adds a launcher
                                       # + app-menu entry, then installs
                                       # mpv/sqlite3/gtk3 via pacman/apt/dnf/
                                       # zypper if they're missing
./packaging/linux/install.sh --system # installs to /opt instead (needs sudo)
./packaging/linux/uninstall.sh        # removes it again
```

Run `install.sh --no-deps` to skip the package-manager step if you'd
rather manage those libraries yourself.

## Tests

```sh
flutter analyze
flutter test
```
