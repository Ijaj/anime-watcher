# anime_watcher

Anime Watcher Helper Software

## A Software to help me keep track of all the animes that i watch.

Point it at the folders where your shows live; it matches them on
MyAnimeList, lists every episode on disk, plays them in a built-in player,
and remembers where you stopped.

### Features
- Add a show folder → title/season parsed from the folder name → matched on
  MyAnimeList (cover, genres, synopsis, score).
- Episodes grouped by season (with specials), parsed from file names like
  `S01E05`, `Show - 05`, `EP05`, `[05]`.
- Built-in player (media_kit / mpv): resumes where you left off, marks an
  episode watched at 90 %, auto-plays the next one.
- "Continue" button picks the next episode to watch.
- Rescan a folder to pick up new downloads; mark episodes watched/unwatched.

See [ROADMAP.md](ROADMAP.md) for what's done and what's next.

### Running
```sh
flutter pub get
flutter run -d windows   # or -d linux
```
Use your own MyAnimeList client ID with
`--dart-define=MAL_CLIENT_ID=<id>`.

Linux needs `libmpv` and `libsqlite3` installed
(e.g. `sudo apt install libmpv-dev libsqlite3-dev`).

The library database lives in the app-support directory
(`anime_watcher.db`).

### Tests
```sh
flutter analyze
flutter test
```
